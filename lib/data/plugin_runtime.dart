/// 代理机上跑的那个 Node 桥的源码。
///
/// 手机上跑不了 npm、跑不了 Node，也开不了子进程，所以「装插件」这件事
/// 只能交给一台用户指定的机器去做。这个桥就是那台机器上的全部东西：
/// 它不装 dsh、不起 agent、不联网，只做一件事——把 dsh 工具插件按 cordis
/// 的约定装配一遍，把工具掏出来，然后按名字调其中一个。
///
/// 之所以能这么干，是因为 `defineTool` 造出来的是一个普通对象：
/// `{name, description, parameters, output, execute}`，`execute` 收参数吐
/// JSON，它不关心调用者是模型还是一个命令行。核实于 @deepseek-ai/dsh-tools
/// 0.0.1-rc.1。
///
/// 桥的契约：stdout 只吐一个 JSON，出错写 stderr 并给非零退出码。
const String kPluginEngine = r'''#!/usr/bin/env node
/**
 * Carbide Shell 插件桥。
 *
 * 子命令：
 *   probe                              报告运行时能力
 *   list                               列出已装的包
 *   install <pkg> [--with-scripts]     装一个包
 *   remove  <pkg>                      删一个包
 *   harvest <pkg> [--config J]         列出插件注册的工具
 *   call <pkg> <tool> --args F [--config J] [--cwd D]   执行一个工具
 *
 * 环境变量 CARBIDE_ROOT 决定装到哪，默认 ~/.carbide/plugins。
 * stdout 只留一个 JSON 对象；装包时的 npm 输出被压到 stderr。
 */
import fs from 'node:fs'
import fsp from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'
import { spawn } from 'node:child_process'
import { pathToFileURL } from 'node:url'
import { createRequire } from 'node:module'

const MAX_BEFORE = 512 * 1024

function out(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

function boom(msg, code) {
  process.stderr.write(JSON.stringify({ ok: false, error: String(msg) }) + '\n')
  process.exit(code === undefined ? 1 : code)
}

function fsError(code, message) {
  const e = new Error(message)
  e.name = 'FsError'
  e.code = code
  return e
}

function versionOf(s) {
  return s.size + ':' + Math.round(s.mtimeMs)
}

/** 按 dsh-fs 的契约实现一份本地文件系统。插件里 ctx.fs.* 就是这里。 */
function makeFs(defaultCwd) {
  const api = {
    get sandboxMode() {
      return undefined
    },
    async resolve(p, opts) {
      const base = (opts && opts.cwd) || defaultCwd || process.cwd()
      const abs = path.isAbsolute(String(p)) ? String(p) : path.resolve(base, String(p))
      return { targetKey: abs, displayPath: abs }
    },
    async stat(t) {
      try {
        const s = await fsp.stat(t.targetKey)
        return {
          type: s.isFile() ? 'file' : s.isDirectory() ? 'directory' : 'other',
          size: s.size,
          version: versionOf(s),
        }
      } catch {
        return undefined
      }
    },
    async readText(t) {
      const buf = await fsp.readFile(t.targetKey)
      if (buf.includes(0)) throw fsError('FS_NOT_TEXT', '这个文件不是文本')
      return buf.toString('utf8').replace(/\r\n/g, '\n')
    },
    async *streamText(t) {
      const fh = await fsp.open(t.targetKey, 'r')
      try {
        const size = 64 * 1024
        const buf = Buffer.alloc(size)
        let pos = 0
        let carry = ''
        for (;;) {
          const r = await fh.read(buf, 0, size, pos)
          if (!r.bytesRead) break
          pos += r.bytesRead
          const text = carry + buf.subarray(0, r.bytesRead).toString('utf8')
          const cut = text.lastIndexOf('\n')
          if (cut === -1) {
            carry = text
            continue
          }
          carry = text.slice(cut + 1)
          yield text.slice(0, cut + 1)
        }
        if (carry.length) yield carry.endsWith('\n') ? carry : carry + '\n'
      } finally {
        await fh.close()
      }
    },
    async writeText(t, content, expected) {
      let operation = 'create'
      let before = null
      try {
        const s = await fsp.stat(t.targetKey)
        operation = 'update'
        if (s.size <= MAX_BEFORE) {
          try {
            before = (await fsp.readFile(t.targetKey)).toString('utf8').replace(/\r\n/g, '\n')
          } catch {
            before = null
          }
        }
        if (expected && expected.kind === 'replaceIfVersion' && versionOf(s) !== expected.version) {
          throw fsError('FS_STALE_VERSION', '文件在读过之后变过了')
        }
      } catch (e) {
        if (e && e.code && String(e.code).startsWith('FS_')) throw e
        if (expected && expected.kind === 'replaceIfVersion') throw fsError('FS_NOT_FOUND', '文件不在了')
      }
      await fsp.mkdir(path.dirname(t.targetKey), { recursive: true })
      await fsp.writeFile(t.targetKey, content, 'utf8')
      const s2 = await fsp.stat(t.targetKey)
      return { operation, version: versionOf(s2), before, after: content }
    },
    async editText(t, edit) {
      const raw = await fsp.readFile(t.targetKey, 'utf8')
      const before = raw.replace(/\r\n/g, '\n')
      const oldString = edit && edit.oldString
      const newString = (edit && edit.newString) || ''
      if (!oldString) throw fsError('FS_AMBIGUOUS_EDIT', 'oldString 是空的')
      const hits = before.split(oldString).length - 1
      if (hits === 0) throw fsError('FS_EDIT_NOT_FOUND', '找不到要替换的那段文字')
      if (hits > 1 && !edit.replaceAll) throw fsError('FS_AMBIGUOUS_EDIT', '匹配到 ' + hits + ' 处，要么写长一点，要么允许全换')
      const after = edit.replaceAll ? before.split(oldString).join(newString) : before.replace(oldString, newString)
      await fsp.writeFile(t.targetKey, after, 'utf8')
      const s = await fsp.stat(t.targetKey)
      return { version: versionOf(s), before, after }
    },
  }
  return api
}

/**
 * 造一个最小 ctx。插件 inject 声明的服务基本都在这里：
 * tools / systemPrompt / skills / fs 是真造的，其余第一次被碰到时才记一笔，
 * 真去调用才抛错——这样「差哪一项」能如实回报，而不是启动就崩。
 */
// ---------------------------------------------------------------- web 能力层
// dsh 的 ctx.web 是一层「接缝」：插件只管要结果，具体谁去抓由这里决定。
// 这里实现一个够用的版本：fetch 直接真抓，search 走 Bing 的结果页。
// 抓不到就抛带 code 的错，不假装成功。

const WEB_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
const WEB_TIMEOUT = 15000
const WEB_MAX_BYTES = 2 * 1024 * 1024

function webError(code, message) {
  const e = new Error(message)
  e.code = code
  return e
}

function decodeEntities(s) {
  return String(s)
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
}

function stripTags(s) {
  return decodeEntities(String(s).replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim()
}

/** 从 Bing 的结果页里抠出 url/title/snippet。抠不出来就是空数组，不编。 */
function parseBing(html) {
  const out = []
  const chunks = String(html).split('<li class="b_algo"').slice(1)
  for (const chunk of chunks) {
    const end = chunk.indexOf('</li>')
    const block = end === -1 ? chunk : chunk.slice(0, end)
    const m = /<h2[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(block)
    if (!m) continue
    const url = decodeEntities(m[1])
    if (!/^https?:/i.test(url)) continue
    const title = stripTags(m[2])
    if (!title) continue
    const p = /<p[^>]*>([\s\S]*?)<\/p>/.exec(block)
    const snippet = p ? stripTags(p[1]) : ''
    out.push(snippet ? { url, title, snippet } : { url, title })
  }
  return out
}

function makeWeb(opts) {
  const warnings = (opts && opts.warnings) || []

  async function request(url, signal) {
    if (typeof fetch !== 'function') {
      throw webError('WEB_UNAVAILABLE', '这个 node 没有全局 fetch，要 18 以上')
    }
    const ac = new AbortController()
    const timer = setTimeout(() => ac.abort(), WEB_TIMEOUT)
    const relay = () => ac.abort()
    if (signal && typeof signal.addEventListener === 'function') signal.addEventListener('abort', relay)
    try {
      return await fetch(url, {
        signal: ac.signal,
        redirect: 'follow',
        headers: {
          'user-agent': WEB_UA,
          'accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      })
    } catch (e) {
      const why = e && e.name === 'AbortError' ? '超时或被取消' : (e && e.message) || '网络错误'
      throw webError('WEB_PROVIDER_FAILED', '抓 ' + url + ' 失败：' + why)
    } finally {
      clearTimeout(timer)
      if (signal && typeof signal.removeEventListener === 'function') signal.removeEventListener('abort', relay)
    }
  }

  return {
    searchProviders: new Map(),
    fetchProviders: new Map(),
    registerSearchProvider(p) {
      if (p && p.id) this.searchProviders.set(p.id, p)
      return () => this.searchProviders.delete(p && p.id)
    },
    registerFetchProvider(p) {
      if (p && p.id) this.fetchProviders.set(p.id, p)
      return () => this.fetchProviders.delete(p && p.id)
    },
    /** 搜。只在真解析出结果时才算成功。 */
    async search(req, signal) {
      const query = String((req && req.query) || '').trim()
      if (!query) throw webError('WEB_EMPTY_QUERY', '搜索词是空的')
      const want = Number((req && req.maxResults) || 0) || 8
      const bound = Math.max(1, Math.min(20, want))
      const url = 'https://www.bing.com/search?q=' + encodeURIComponent(query) + '&count=' + bound
      const res = await request(url, signal)
      if (!res.ok) throw webError('WEB_PROVIDER_FAILED', '搜索服务回了 HTTP ' + res.status)
      const all = parseBing(await res.text())
      if (!all.length) {
        throw webError('WEB_PROVIDER_FAILED', '搜索页能打开，但一条结果都没解析出来（可能被要求验证）')
      }
      const sources = all.slice(0, bound)
      return { sources, truncated: all.length > bound }
    },
    /** 抓一页。非 2xx 不算失败，状态码原样带回去。 */
    async fetch(req, signal) {
      const url = String((req && req.url) || '').trim()
      if (!/^https?:\/\//i.test(url)) throw webError('WEB_INVALID_URL', '只抓 http/https：' + url)
      const res = await request(url, signal)
      const ct = String(res.headers.get('content-type') || '').toLowerCase()
      const buf = Buffer.from(await res.arrayBuffer())
      const truncated = buf.length > WEB_MAX_BYTES
      const body = truncated ? buf.subarray(0, WEB_MAX_BYTES) : buf
      const kind = ct.includes('html') ? 'html' : 'text'
      if (warnings.length < 50) warnings.push('web:' + url)
      return {
        url: res.url || url,
        statusCode: res.status,
        body: { kind, content: body.toString('utf8') },
        truncated,
      }
    },
  }
}

/** 未实现的服务访问到就记一笔，报给用户的是「缺哪一项」，不是假的「无」。 */
function missesOf(ctx) {
  if (!ctx || !ctx.__misses) return []
  return [...ctx.__misses]
    .map((n) => String(n))
    .filter((n) => !n.startsWith('__'))
    .sort()
}

function makeCtx(opts) {
  const cwd = opts.cwd || process.cwd()
  const warnings = opts.warnings
  const misses = new Set()
  const sections = []
  const services = Object.create(null)

  services.tools = {
    register(tool) {
      opts.onTool(tool)
      return () => {}
    },
    unregister() {},
    get() {
      return undefined
    },
    has() {
      return false
    },
    list() {
      return []
    },
    execute() {
      throw new Error('ctx.tools.execute 这里没实现，直接调工具的 execute 就行')
    },
  }

  // dsh 的段是 { name, order, text, complete }，按 order 升序拼。
  // 以前这里只记了个名字就把内容扔了，等于插件的引导语全丢——现在真收下来。
  services.systemPrompt = {
    section(s) {
      const sec = typeof s === 'string' ? { text: s } : s || {}
      const text = typeof sec.text === 'string' ? sec.text : ''
      sections.push({
        name: String(sec.name || ''),
        order: Number.isFinite(sec.order) ? sec.order : 100,
        text,
        complete: sec.complete === true,
      })
      return () => {}
    },
    text() {
      return sections
        .slice()
        .sort((a, b) => a.order - b.order)
        .map((x) => x.text)
        .filter(Boolean)
        .join('\n\n')
    },
  }

  services.skills = {
    register() {
      return () => {}
    },
    unregister() {},
    add() {
      return () => {}
    },
    list() {
      return []
    },
    get() {
      return undefined
    },
    of() {
      return []
    },
  }

  services.fs = makeFs(cwd)
  services.web = makeWeb({ warnings })

  // 会话投影登记表。dsh 里每个领域（比如 todo 列表）往这儿登记一段纯净的状态
  // 计算，读的时候由会话日志驱动。这里只做登记和自洽的查询，不编状态。
  const projections = new Map()
  services.sessionProjections = {
    register(def) {
      if (!def || typeof def.key !== 'string' || !def.key) {
        throw new Error('session projection 要一个非空字符串 key')
      }
      if (!Number.isSafeInteger(def.stateVersion) || def.stateVersion < 0) {
        throw new Error(
          'session projection ' + JSON.stringify(def.key) + ' 的 stateVersion 要是非负整数，给的是 ' + String(def.stateVersion),
        )
      }
      const prev = projections.get(def.key)
      if (prev && prev.stateVersion !== def.stateVersion) {
        throw new Error(
          'session projection ' + JSON.stringify(def.key) + ' 已经用 stateVersion ' + prev.stateVersion + ' 登记过了',
        )
      }
      projections.set(def.key, def)
      return () => projections.delete(def.key)
    },
    onChanged() {
      return () => {}
    },
    async snapshot() {
      return { values: {} }
    },
    async checkpoint() {
      return []
    },
    async view() {
      return []
    },
    async restore() {},
    keys() {
      return [...projections.keys()]
    },
  }

  // 沙箱：没人管的时候一律放行，跟没有这一层时一样。
  services.sandbox = {
    get mode() {
      return undefined
    },
    async resolvePolicy() {
      return undefined
    },
    mapError(err) {
      return err
    },
  }

  // 事件监听登记在这儿，waterfall 那一串中间件就从这张表里串起来。
  const listeners = new Map()

  const base = {
    get(name) {
      return services[name]
    },
    set(name, value) {
      services[name] = value
      return true
    },
    has(name) {
      return name in services
    },
    provide(name, value) {
      services[name] = value
    },
    emit() {},
    on(event, fn) {
      if (typeof event === 'string' && typeof fn === 'function') {
        const list = listeners.get(event) || []
        list.push(fn)
        listeners.set(event, list)
        return () => {
          const cur = listeners.get(event) || []
          const at = cur.indexOf(fn)
          if (at >= 0) cur.splice(at, 1)
        }
      }
      return () => {}
    },
    /**
     * 审批中间件链。dsh 里 fs/write-intent 这类事件就是这样挂上去的：
     * 注册一个处理函数就能改写这次写入的意图。这里没人注册就照原样放行，
     * 也就是把最后一个函数（默认实现）直接调掉。
     */
    async waterfall(...all) {
      const args = all.slice()
      while (args.length && typeof args[0] !== 'string') args.shift()
      const event = args.shift()
      const chain = (listeners.get(event) || []).slice()
      const next = typeof args[args.length - 1] === 'function' ? args.pop() : () => undefined
      let i = 0
      const step = async (...carried) => {
        if (i >= chain.length) return next(...carried)
        const fn = chain[i++]
        return fn(...carried, (...again) => step(...(again.length ? again : carried)))
      }
      return step(...args)
    },
    once() {
      return () => {}
    },
    off() {},
    /**
     * dsh 的 effect 是 generator：跑起来后 yield 出一个清理函数。
     * 以前这里直接 fn() 就当完了，generator 函数被调用只会返回一个迭代器、
     * 里面一行都不执行。现在真把它跑到第一个 yield，并把清理函数留住。
     */
    effect(fn) {
      if (typeof fn !== 'function') return () => {}
      try {
        const r = fn()
        if (r && typeof r.next === 'function') {
          const first = r.next()
          const cleanup = first && first.value
          return () => {
            try {
              if (typeof cleanup === 'function') cleanup()
            } catch {}
            try {
              if (typeof r.return === 'function') r.return()
            } catch {}
          }
        }
      } catch (e) {
        warnings.push('effect:' + ((e && e.message) || String(e)))
      }
      return () => {}
    },
    /**
     * cordis 的原文是「Run a callback once the requested services are available」，
     * 而且服务变了会卸载重跑。以前这里是无条件 fn(ctx)，等于告诉插件
     * 「你要的都齐了」——插件于是放心地用，一碰就抛，整个 apply 连带崩掉，
     * 连不依赖那项服务的工具都注册不上。
     *
     * 现在的规矩：没就绪就永不调用，并把这几个名字记进缺项。
     * 插件缺一段功能，而不是整个废掉——这才是作者写 inject 时的预期。
     *
     * 「服务变了重跑」在这个一次性进程模型里没有对应物：服务表在装配期是静态的。
     */
    inject(names, fn) {
      const list = Array.isArray(names)
        ? names
        : names && typeof names === 'object'
          ? Object.keys(names)
          : [names]
      const ready = list.every((n) => typeof n === 'string' && n && n in services && services[n] != null)
      if (!ready) {
        for (const n of list) {
          if (typeof n !== 'string' || !n) continue
          if (!(n in services) || services[n] == null) misses.add(n)
        }
        return () => {}
      }
      if (typeof fn !== 'function') return () => {}
      try {
        fn(ctx)
      } catch (e) {
        warnings.push('inject:' + ((e && e.message) || String(e)))
      }
      return () => {}
    },
    plugin() {
      return () => {}
    },
    dispose() {},
    logger: { debug() {}, info() {}, warn() {}, error() {} },
    baseDir: cwd,
  }

  function stub(name) {
    const trap = () => {
      misses.add(name)
      throw new Error('插件要 ctx.' + name + '，代理机上没有')
    }
    return new Proxy(trap, {
      get(_, prop) {
        if (prop === 'then') return undefined
        return trap
      },
      apply() {
        return trap()
      },
    })
  }

  const ctx = new Proxy(base, {
    get(target, prop) {
      if (prop === '__misses') return misses
      if (prop === '__sections') return sections
      if (prop === '__projections') return projections
      if (typeof prop === 'symbol') return undefined
      if (prop in target) return target[prop]
      if (prop in services) return services[prop]
      misses.add(prop)
      return stub(prop)
    },
    set(target, prop, value) {
      services[prop] = value
      return true
    },
    has(target, prop) {
      return prop in target || prop in services
    },
  })
  return ctx
}

/** 找到包入口。先按 node_modules 里的 package.json 走，不行再退回 CJS 解析。 */
function resolveEntry(root, pkg) {
  const dir = path.join(root, 'node_modules', pkg)
  const pkgFile = path.join(dir, 'package.json')
  if (fs.existsSync(pkgFile)) {
    let pj = {}
    try {
      pj = JSON.parse(fs.readFileSync(pkgFile, 'utf8'))
    } catch {}
    const ex = pj.exports
    let rel
    if (typeof ex === 'string') rel = ex
    else if (ex && typeof ex === 'object') {
      const dot = ex['.'] !== undefined ? ex['.'] : ex
      if (typeof dot === 'string') rel = dot
      else if (dot && typeof dot === 'object') rel = dot.import || dot.default || dot.node || dot.require
    }
    rel = rel || pj.module || pj.main || 'index.js'
    const abs = path.resolve(dir, rel)
    if (fs.existsSync(abs)) return { file: abs, pj }
  }
  const req = createRequire(path.join(root, 'package.json'))
  const file = req.resolve(pkg)
  let pj = {}
  try {
    pj = JSON.parse(fs.readFileSync(path.join(path.dirname(file), '..', 'package.json'), 'utf8'))
  } catch {}
  return { file, pj }
}

async function loadPlugin(root, pkg) {
  const found = resolveEntry(root, pkg)
  const mod = await import(pathToFileURL(found.file).href + '?t=' + Date.now())
  return { mod, pj: found.pj }
}

/** 插件可能是 `export const apply`，也可能是 `export default {apply}`，还可能就是个函数。 */
function pluginParts(mod) {
  const d = mod.default
  const pick = (k) => {
    if (mod[k] !== undefined) return mod[k]
    if (d && typeof d === 'object' && d[k] !== undefined) return d[k]
    return undefined
  }
  let apply = mod.apply
  if (typeof apply !== 'function') {
    if (typeof d === 'function') apply = d
    else if (d && typeof d === 'object' && typeof d.apply === 'function') apply = d.apply
  }
  return { name: pick('name') || 'unknown', inject: pick('inject') || [], Config: pick('Config'), apply }
}

/** dsh 的 loader 会用 Config 这个 schema 补默认值；脱离 dsh 得自己补。 */
function buildConfig(parts, raw) {
  const cfg = raw && typeof raw === 'object' ? raw : {}
  const C = parts.Config
  if (typeof C !== 'function') return cfg
  try {
    const resolved = C(cfg)
    return resolved && typeof resolved === 'object' ? resolved : cfg
  } catch (e) {
    throw new Error('插件配置不合法：' + (e && e.message ? e.message : e))
  }
}

async function collect(root, pkg, cfgRaw, opts) {
  const loaded = await loadPlugin(root, pkg)
  const parts = pluginParts(loaded.mod)
  if (typeof parts.apply !== 'function') throw new Error(pkg + ' 没有导出 apply，不是 dsh 插件')
  const tools = []
  const warnings = []
  const ctx = makeCtx({ cwd: opts.cwd || process.cwd(), onTool: (t) => tools.push(t), warnings })
  const config = buildConfig(parts, cfgRaw)
  const r = parts.apply(ctx, config)
  if (r && typeof r.then === 'function') await r
  return { parts, pj: loaded.pj, tools, warnings, ctx }
}

const READ_HINTS = /(^|_)(read|list|get|status|probe|check|inspect|find|search|show|view|stat|info)(_|$)/i

function specOf(tool) {
  const name = String(tool.name || '')
  return {
    name,
    description: String(tool.description || ''),
    schema: tool.parameters || { type: 'object', properties: {} },
    risk: READ_HINTS.test(name) ? 'read' : 'write',
    renders: !!(tool.output && typeof tool.output.render === 'function'),
  }
}

/**
 * 找 npm。不能直接跑 bin/npm —— 那个脚本的 shebang 是 `#!/usr/bin/env node`，
 * 会去找 PATH 上第一个 node，常常是个老版本，一跑就 MODULE_NOT_FOUND。
 * 拿我们自己这个 node 去跑 npm-cli.js 才稳。
 */
function npmInvocation() {
  const bin = path.dirname(process.execPath)
  const prefix = path.dirname(bin)
  const cli = path.join(prefix, 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js')
  if (fs.existsSync(cli)) return { cmd: process.execPath, pre: [cli] }
  const shell = path.join(bin, 'npm')
  if (fs.existsSync(shell)) return { cmd: shell, pre: [] }
  return { cmd: 'npm', pre: [] }
}

/**
 * 跑一个子进程，把 stderr 留着。npm 出错时只有它说得清为什么，
 * 光回一句「退出码 1」等于什么都没说。
 */
function run(cmd, args, opts) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, Object.assign({ stdio: ['ignore', 2, 'pipe'] }, opts || {}))
    let tail = ''
    if (p.stderr) {
      p.stderr.on('data', (b) => {
        const text = b.toString()
        process.stderr.write(text)
        tail = (tail + text).slice(-2000)
      })
    }
    p.on('error', (e) => reject(new Error('跑不起来 ' + cmd + '：' + e.message)))
    p.on('close', (code) => {
      if (code === 0) return resolve()
      const lines = tail
        .split('\n')
        .map((l) => l.replace(/^npm (error|ERR!)\s*/, '').trim())
        .filter((l) => l.length > 0 && l !== '404' && !l.startsWith('npm error'))
      reject(new Error(lines.slice(-4).join(' / ') || cmd + ' 退出码 ' + code))
    })
  })
}

async function cmdProbe(root) {
  let python = ''
  try {
    await new Promise((resolve, reject) => {
      const p = spawn('python3', ['-V'], { stdio: 'ignore' })
      p.on('error', reject)
      p.on('close', (c) => (c === 0 ? resolve() : reject(new Error('no'))))
    })
    python = 'python3'
  } catch {
    python = ''
  }
  const nm = path.join(root, 'node_modules')
  out({
    ok: true,
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    root,
    python,
    installed: fs.existsSync(nm),
    engine: import.meta.url,
  })
}

async function cmdList(root) {
  const nm = path.join(root, 'node_modules')
  const packages = []
  if (fs.existsSync(nm)) {
    for (const e of await fsp.readdir(nm)) {
      if (e.startsWith('.')) continue
      if (e.startsWith('@')) {
        for (const s of await fsp.readdir(path.join(nm, e))) packages.push(e + '/' + s)
        continue
      }
      packages.push(e)
    }
  }
  out({ ok: true, root, packages })
}

async function cmdInstall(root, pkg, withScripts) {
  if (!pkg) throw new Error('要装哪个包？')
  await fsp.mkdir(root, { recursive: true })
  const pjFile = path.join(root, 'package.json')
  if (!fs.existsSync(pjFile)) {
    await fsp.writeFile(pjFile, JSON.stringify({ name: 'carbide-plugins', private: true }, null, 2) + '\n')
  }
  const args = ['install', '--prefix', root, '--no-audit', '--no-fund', '--loglevel', 'error', pkg]
  if (!withScripts) args.push('--ignore-scripts')
  const npm = npmInvocation()
  await run(npm.cmd, npm.pre.concat(args), { env: Object.assign({}, process.env, { npm_config_yes: 'true' }) })
  out({ ok: true, package: pkg, root, ranScripts: !!withScripts })
}

async function cmdRemove(root, pkg) {
  if (!pkg) throw new Error('要删哪个包？')
  await fsp.rm(path.join(root, 'node_modules', pkg), { recursive: true, force: true })
  try {
    const pjFile = path.join(root, 'package.json')
    const pj = JSON.parse(await fsp.readFile(pjFile, 'utf8'))
    if (pj.dependencies) delete pj.dependencies[pkg]
    await fsp.writeFile(pjFile, JSON.stringify(pj, null, 2) + '\n')
  } catch {}
  out({ ok: true, removed: pkg })
}

async function cmdHarvest(root, pkg, cfgRaw, opts) {
  const c = await collect(root, pkg, cfgRaw, opts)
  const declared = Array.isArray(c.parts.inject) ? c.parts.inject : []
  const missing = new Set(missesOf(c.ctx))
  // 光看运行时不够：有些服务插件注明了要用、但装配阶段碰都不碰。
  // 以前这种一律报「缺的服务：无」，等于骗人。
  for (const n of declared) {
    let has = false
    try {
      has = !!c.ctx.has(n)
    } catch {
      has = false
    }
    if (!has) missing.add(n)
  }
  const sections = (c.ctx.__sections || [])
    .filter((x) => x && x.text)
    .slice()
    .sort((a, b) => a.order - b.order)
  out({
    ok: true,
    package: pkg,
    version: (c.pj && c.pj.version) || '',
    pluginName: c.parts.name,
    inject: declared,
    tools: c.tools.map(specOf),
    warnings: c.warnings,
    sections,
    missingSeams: [...missing].sort(),
    node: process.version,
  })
}

/** 一次读干净 stdin。参数走管道过来，就不用把 JSON 塞进 shell 引号里。 */
async function readStdin() {
  const chunks = []
  for await (const chunk of process.stdin) chunks.push(chunk)
  return Buffer.concat(chunks).toString('utf8')
}

/** 一次调用里给插件看到的 exec。dsh 里这是 agent 会话的执行 frame。 */
function makeExec(ctx, opts) {
  const cwd = opts.cwd || process.cwd()
  const events = []
  const state = new Map()
  const defs = ctx.__projections instanceof Map ? ctx.__projections : new Map()

  // 每来一个事件，把登记过的投影都往前推一步。这样 snapshot() 读到的是真的，
  // 而不是一个永远空的假表。
  function drive(event) {
    for (const [key, def] of defs) {
      const before = state.has(key) ? state.get(key) : typeof def.init === 'function' ? def.init() : undefined
      let after = before
      if (typeof def.apply === 'function') {
        try {
          after = def.apply(before, event)
        } catch (e) {
          after = before
        }
      }
      state.set(key, after)
    }
  }

  const session = {
    header: { cwd },
    events,
    append(type, data) {
      const event = { type, data }
      events.push(event)
      drive(event)
      return events.length
    },
    appendMany(list) {
      for (const e of Array.isArray(list) ? list : []) {
        if (e && e.type) this.append(e.type, e.data)
      }
      return events.length
    },
    state(key) {
      return state.get(key)
    },
  }

  return {
    signal: undefined,
    callId: 'carbide-' + Date.now(),
    cwd,
    agent: { session },
  }
}

async function cmdCall(root, pkg, toolName, argsFile, cfgRaw, opts) {
  let rawArgs = '{}'
  if (argsFile === '-') rawArgs = await readStdin()
  else if (argsFile) rawArgs = await fsp.readFile(argsFile, 'utf8')
  const args = JSON.parse(rawArgs)
  const c = await collect(root, pkg, cfgRaw, opts)
  const tool = c.tools.find((t) => t.name === toolName)
  if (!tool) {
    throw new Error('插件 ' + pkg + ' 里没有工具 ' + toolName + '，有的这些：' + c.tools.map((t) => t.name).join(', '))
  }
  const exec = makeExec(c.ctx, opts)
  const started = Date.now()
  const value = await tool.execute(args, exec)
  let text = ''
  try {
    if (tool.output && typeof tool.output.render === 'function') {
      const cards = tool.output.render(args, value)
      if (Array.isArray(cards)) {
        text = cards.map((c2) => (c2 && c2.text) || '').filter(Boolean).join('\n')
      }
    }
  } catch (e) {
    text = ''
  }
  out({
    ok: true,
    tool: toolName,
    ms: Date.now() - started,
    result: value,
    text,
    missingSeams: missesOf(c.ctx),
  })
}

const argv = process.argv.slice(2)
const cmd = argv[0]
const ROOT = process.env.CARBIDE_ROOT || path.join(process.env.HOME || process.env.USERPROFILE || '.', '.carbide', 'plugins')

function flag(name) {
  const i = argv.indexOf('--' + name)
  return i === -1 ? undefined : argv[i + 1]
}

function hasFlag(name) {
  return argv.includes('--' + name)
}

function parseCfg(v) {
  if (!v) return {}
  try {
    if (fs.existsSync(v)) return JSON.parse(fs.readFileSync(v, 'utf8'))
  } catch {}
  return JSON.parse(v)
}

function opts() {
  return { cwd: flag('cwd') }
}

async function main() {
  if (!cmd || cmd === 'help' || cmd === '--help') {
    out({ ok: true, commands: ['probe', 'list', 'install <pkg>', 'remove <pkg>', 'harvest <pkg>', 'call <pkg> <tool> --args <file>'] })
    return
  }
  if (cmd === 'probe') return cmdProbe(ROOT)
  if (cmd === 'list') return cmdList(ROOT)
  if (cmd === 'install') return cmdInstall(ROOT, argv[1], hasFlag('with-scripts'))
  if (cmd === 'remove') return cmdRemove(ROOT, argv[1])
  if (cmd === 'harvest') return cmdHarvest(ROOT, argv[1], parseCfg(flag('config')), opts())
  if (cmd === 'call') return cmdCall(ROOT, argv[1], argv[2], flag('args'), parseCfg(flag('config')), opts())
  throw new Error('不认识的子命令：' + cmd)
}

main().catch((e) => boom(e && e.message ? e.message : e, 1))
''';
