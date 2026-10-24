#!/usr/bin/env python3
"""把某个版本的更新说明从 CHANGELOG.md 里取出来，给发布流程当正文。

用法：python3 tool/release_notes.py v0.0.5 > release_notes.md

CHANGELOG.md 里找不到这个版本就直接失败，免得发出去的包没有说明。
"""
import pathlib
import sys

TAIL = """
装好第一件事：设置页填模型地址和密钥，再回主机页加一台机器。
"""


def section(text, version):
    """取 `## [版本]` 那一段，到下一条 `## ` 为止。"""
    head = '## [%s]' % version
    lines = text.splitlines()
    out = []
    keep = False
    for line in lines:
        if line.startswith('## '):
            if keep:
                break
            if line.startswith(head):
                keep = True
                continue
        if keep:
            out.append(line)
    while out and not out[-1].strip():
        out.pop()
    return out


def main(argv):
    tag = argv[1] if len(argv) > 1 else ''
    version = tag.lstrip('vV')
    if not version:
        sys.stderr.write('用法：python3 tool/release_notes.py v0.0.5\n')
        return 2
    root = pathlib.Path(__file__).resolve().parent.parent
    text = (root / 'CHANGELOG.md').read_text(encoding='utf-8')
    body = section(text, version)
    if not body:
        sys.stderr.write('CHANGELOG.md 里没有 %s 这一段，先补上再发\n' % version)
        return 2
    print('Carbide Shell 碳壳 %s\n' % (tag or version))
    print('\n'.join(body).strip())
    print(TAIL)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
