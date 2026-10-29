/// 模型计价：用户手填优先，没填就用内置的那张表。
///
/// 内置表由本仓库维护，用户在界面上看不到编辑入口，只能用手填的那一套盖住它。
/// 单位统一成「每百万 token 多少元」，DeepSeek 的谷时按高峰的一半算。
library;

import 'deepseek.dart';

/// 一套价格。三种 token 各一个数，缓存命中那一档没有就跟着输入价走。
class ModelPrice {
  const ModelPrice({
    required this.input,
    this.cache = 0,
    required this.output,
    this.currency = '元',
    this.per = 1000000,
  });

  /// 每 [per] 个输入 token 的价格（没命中缓存的那部分）。
  final double input;

  /// 命中缓存的那部分输入。0 表示不单独计价，按 [input] 算。
  final double cache;

  /// 每个输出 token 的价格。
  final double output;

  final String currency;
  final int per;

  bool get empty => input <= 0 && output <= 0;

  double get cachePrice => cache > 0 ? cache : input;


  Map<String, Object?> toJson() => <String, Object?>{
        'input': input,
        if (cache > 0) 'cache': cache,
        'output': output,
        if (currency != '元') 'currency': currency,
      };

  /// 手填的报价读回来。缺项、负数一律当没填。
  static ModelPrice? fromJson(Map<String, Object?> json) {
    double read(String key) {
      final Object? v = json[key];
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? 0;
    }

    final double input = read('input');
    final double output = read('output');
    if (input <= 0 && output <= 0) return null;
    return ModelPrice(
      input: input < 0 ? 0 : input,
      cache: read('cache') < 0 ? 0 : read('cache'),
      output: output < 0 ? 0 : output,
      currency: '${json['currency'] ?? '元'}',
    );
  }

  /// `2 / 0.5 / 8` 这样写给人看：输入 / 缓存 / 输出。
  String get oneLine {
    final String c = cache > 0 ? '，缓存命中 $cache' : '';
    return '输入 $input$c，输出 $output（每百万 token，$currency）';
  }
}

/// 内置价目表的一条：按模型名里包含的关键字匹配。
class PriceEntry {
  const PriceEntry({
    required this.match,
    required this.input,
    required this.output,
    this.cache = 0,
    this.peakValley = false,
    required this.note,
  });

  /// 模型名里带这个字就算命中，小写比较。
  final String match;
  final double input;
  final double output;
  final double cache;

  /// 有峰谷价的那种。
  final bool peakValley;

  /// 表上的备注，界面上会说一句。
  final String note;

  ModelPrice get price =>
      ModelPrice(input: input, output: output, cache: cache);
}

/// 内置的价目表。改价只动这里，界面不用动。
///
/// 数字按各家公开的定价页抄的，单位是每百万 token 的人民币。
const List<PriceEntry> kPriceBook = <PriceEntry>[
  PriceEntry(
    match: 'deepseek-chat',
    input: 2,
    cache: 0.5,
    output: 8,
    peakValley: true,
    note: 'DeepSeek 对话模型，谷时半价',
  ),
  PriceEntry(
    match: 'deepseek-reasoner',
    input: 4,
    cache: 1,
    output: 16,
    peakValley: true,
    note: 'DeepSeek 推理模型，谷时半价',
  ),
  PriceEntry(
    match: 'deepseek',
    input: 2,
    cache: 0.5,
    output: 8,
    peakValley: true,
    note: 'DeepSeek 其它型号按对话模型算，谷时半价',
  ),
];

PriceEntry? builtinEntry(String model) {
  final String m = model.toLowerCase().trim();
  if (m.isEmpty) return null;
  for (final PriceEntry e in kPriceBook) {
    if (m.contains(e.match)) return e;
  }
  return null;
}

/// 这套配置的价钱从哪儿来。
enum PriceSource { none, manual, builtin }

/// 算出来的那一刻：谁给的价、要不要打折。
class PriceQuote {
  const PriceQuote({
    required this.price,
    required this.source,
    this.note = '',
    this.peakValley = false,
  });

  final ModelPrice? price;
  final PriceSource source;
  final String note;

  /// 这个价有峰谷之分。
  final bool peakValley;

  bool get known => price != null && !price!.empty;

  String get sourceLabel => switch (source) {
        PriceSource.manual => '手填',
        PriceSource.builtin => '内置',
        PriceSource.none => '没配',
      };
}

/// 先看手填，再查内置表。
PriceQuote quotePrice({
  required Map<String, Object?> manual,
  required String model,
}) {
  final ModelPrice? own = ModelPrice.fromJson(manual);
  if (own != null) {
    return PriceQuote(
      price: own,
      source: PriceSource.manual,
      note: '手填的价',
      peakValley: isDeepSeekModel(model),
    );
  }
  final PriceEntry? entry = builtinEntry(model);
  if (entry == null) {
    return const PriceQuote(price: null, source: PriceSource.none);
  }
  return PriceQuote(
    price: entry.price,
    source: PriceSource.builtin,
    note: entry.note,
    peakValley: entry.peakValley,
  );
}

/// 这一刻该乘几倍。DeepSeek 的谷时是高峰的一半，其余模型不打折。
double peakFactor({required bool peakValley, required DateTime at}) {
  if (!peakValley) return 1;
  const DeepSeekClock clock = DeepSeekClock();
  return clock.state(at).peak ? 1 : 0.5;
}

/// 一次调用值多少钱，输入与输出分开算。
class CostSplit {
  const CostSplit({this.input = 0, this.cached = 0, this.output = 0});

  /// 没命中缓存的输入那部分。
  final double input;

  /// 命中缓存的那部分（可能按缓存价算）。
  final double cached;

  final double output;

  double get total => input + cached + output;

  /// 输入一共花了多少，缓存那一档也算输入。
  double get promptTotal => input + cached;
}

CostSplit costSplitOf({
  required int prompt,
  required int completion,
  required int cached,
  required ModelPrice price,
  double factor = 1,
}) {
  if (prompt <= 0 && completion <= 0) return const CostSplit();
  final int hit = cached < 0 ? 0 : (cached > prompt ? prompt : cached);
  final int miss = prompt - hit;
  return CostSplit(
    input: miss / price.per * price.input * factor,
    cached: hit / price.per * price.cachePrice * factor,
    output: completion / price.per * price.output * factor,
  );
}

/// 一次调用值多少钱。
double costOf({
  required int prompt,
  required int completion,
  required int cached,
  required ModelPrice price,
  double factor = 1,
}) =>
    costSplitOf(
      prompt: prompt,
      completion: completion,
      cached: cached,
      price: price,
      factor: factor,
    ).total;

/// 钱怎么写：不到一分写四位小数，多的写两位。
String moneyText(double value, {String currency = '元'}) {
  if (value <= 0) return '¥0';
  if (value < 0.01) return '¥${value.toStringAsFixed(4)}';
  if (value < 1) return '¥${value.toStringAsFixed(3)}';
  return '¥${value.toStringAsFixed(2)}';
}
