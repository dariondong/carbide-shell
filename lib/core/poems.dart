/// 等待的时候读一首古诗。
///
/// 每次只给一首，随机挑，不连着重复同一首。古诗库放在这里，界面只管每隔多久换一次。
library;

/// 一首诗：题目、作者、一句正文。
class Poem {
  const Poem({required this.title, required this.author, required this.line});

  final String title;
  final String author;

  /// 展示的那一句。多半是名句，不是全诗。
  final String line;

  /// 逗号前一行，用于分成两行写。
  String get head {
    final int cut = line.indexOf('，');
    return cut < 0 ? line : line.substring(0, cut);
  }

  String get tail {
    final int cut = line.indexOf('，');
    return cut < 0 ? '' : line.substring(cut + 1);
  }

  /// 标题与作者，弱化着写的那一行。
  String get byline => author.isEmpty ? '《$title》' : '《$title》 $author';
}

/// 内置的古诗库。想加就在这儿加，界面不用动。
const List<Poem> kPoems = <Poem>[
  Poem(title: '行路难', author: '李白', line: '长风破浪会有时，直挂云帆济沧海'),
  Poem(title: '游山西村', author: '陆游', line: '山重水复疑无路，柳暗花明又一村'),
  Poem(title: '浪淘沙', author: '刘禹锡', line: '千淘万漉虽辛苦，吹尽狂沙始到金'),
  Poem(title: '别董大', author: '高适', line: '莫愁前路无知己，天下谁人不识君'),
  Poem(title: '望岳', author: '杜甫', line: '会当凌绝顶，一览众山小'),
  Poem(title: '登鹳雀楼', author: '王之涣', line: '欲穷千里目，更上一层楼'),
  Poem(title: '竹石', author: '郑燮', line: '千磨万击还坚劲，任尔东西南北风'),
  Poem(title: '观书有感', author: '朱熹', line: '问渠那得清如许，为有源头活水来'),
  Poem(title: '山居秋暝', author: '王维', line: '明月松间照，清泉石上流'),
  Poem(title: '使至塞上', author: '王维', line: '大漠孤烟直，长河落日圆'),
  Poem(title: '早发白帝城', author: '李白', line: '两岸猿声啼不住，轻舟已过万重山'),
  Poem(title: '酬乐天扬州初逢席上见赠', author: '刘禹锡', line: '沉舟侧畔千帆过，病树前头万木春'),
];

/// 一轮接一轮地抽：随机、不连着重复、抽不到就没有。
class PoemWheel {
  PoemWheel({List<Poem>? poems, int? seed}) : poems = poems ?? kPoems {
    _rand = _Rng(seed ?? DateTime.now().microsecondsSinceEpoch);
  }

  final List<Poem> poems;
  late final _Rng _rand;
  int _last = -1;

  bool get isEmpty => poems.isEmpty;

  /// 现在这一首。还没抽过就是第一首。
  Poem? get current => _last < 0 ? (poems.isEmpty ? null : poems.first) : poems[_last];

  /// 抽下一首。库空着就返回 null。
  Poem? next() {
    if (poems.isEmpty) return null;
    if (poems.length == 1) {
      _last = 0;
      return poems[0];
    }
    int pick = _rand.next(poems.length);
    if (pick == _last) pick = (pick + 1 + _rand.next(poems.length - 1)) % poems.length;
    if (pick == _last) pick = (pick + 1) % poems.length;
    _last = pick;
    return poems[pick];
  }
}

/// 一个够用的伪随机，固定种子就能重放，测试里用得上。
class _Rng {
  _Rng(int seed) : _state = (seed & 0x7fffffff) | 1;

  int _state;

  int next(int bound) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return bound <= 0 ? 0 : _state % bound;
  }
}

/// 换诗的最小与最大间隔，秒。
const int kPoemEveryMin = 10;
const int kPoemEveryMax = 60;
const int kPoemEveryDefault = 20;

int clampPoemEvery(int seconds) =>
    seconds < kPoemEveryMin ? kPoemEveryMin : (seconds > kPoemEveryMax ? kPoemEveryMax : seconds);
