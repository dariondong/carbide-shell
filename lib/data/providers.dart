/// Known-good OpenAI-compatible endpoints. Picking one fills the address and a
/// couple of model names on the settings page. Nothing is prefilled by default,
/// and every field stays editable.
class LlmPreset {
  const LlmPreset({
    required this.name,
    required this.baseUrl,
    this.models = const <String>[],
    this.note = '',
  });

  final String name;
  final String baseUrl;
  final List<String> models;
  final String note;
}

const List<LlmPreset> kLlmPresets = <LlmPreset>[
  LlmPreset(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: <String>['gpt-4.1', 'gpt-4.1-mini', 'o4-mini'],
  ),
  LlmPreset(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    models: <String>['deepseek-chat', 'deepseek-reasoner'],
  ),
  LlmPreset(
    name: '阿里百炼',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: <String>['qwen-max', 'qwen-plus', 'qwen-turbo'],
  ),
  LlmPreset(
    name: '月之暗面',
    baseUrl: 'https://api.moonshot.cn/v1',
    models: <String>['moonshot-v1-8k', 'moonshot-v1-32k'],
  ),
  LlmPreset(
    name: '智谱',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: <String>['glm-4-plus', 'glm-4-flash'],
  ),
  LlmPreset(
    name: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: <String>['Qwen/Qwen2.5-72B-Instruct', 'deepseek-ai/DeepSeek-V3'],
  ),
  LlmPreset(
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    models: <String>['openai/gpt-4.1', 'deepseek/deepseek-chat'],
    note: '模型名带厂商前缀',
  ),
  LlmPreset(
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    models: <String>['llama-3.3-70b-versatile'],
  ),
  LlmPreset(
    name: 'Together',
    baseUrl: 'https://api.together.xyz/v1',
    models: <String>['meta-llama/Llama-3.3-70B-Instruct-Turbo'],
  ),
  LlmPreset(
    name: 'xAI',
    baseUrl: 'https://api.x.ai/v1',
    note: '模型名去控制台抄',
  ),
  LlmPreset(
    name: 'Mistral',
    baseUrl: 'https://api.mistral.ai/v1',
    models: <String>['mistral-large-latest'],
  ),
  LlmPreset(
    name: '火山方舟',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    note: '模型名填接入点 ID，形如 ep-',
  ),
  LlmPreset(
    name: '百度千帆',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    note: '模型名填千帆的模型 ID',
  ),
  LlmPreset(
    name: '腾讯混元',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    models: <String>['hunyuan-turbos-latest'],
  ),
  LlmPreset(
    name: 'Ollama（本机）',
    baseUrl: 'http://localhost:11434/v1',
    models: <String>['qwen2.5', 'llama3.2'],
    note: '跑在本机，密钥随便填',
  ),
  LlmPreset(
    name: 'LM Studio（本机）',
    baseUrl: 'http://localhost:1234/v1',
    note: '跑在本机，密钥随便填',
  ),
];
