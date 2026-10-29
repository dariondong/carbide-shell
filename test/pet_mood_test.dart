import 'dart:io';

import 'package:carbide_shell/ui/pet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每一态都有一张立绘，文件真的在', () {
    for (final PetMood mood in PetMood.values) {
      expect(mood.asset, 'assets/pet/${mood.name}.png');
      expect(File(mood.asset).existsSync(), isTrue, reason: mood.asset);
    }
  });

  test('assets/pet 里的图全被用上，不留没人用的', () {
    final Set<String> files = Directory('assets/pet')
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String n) => n.endsWith('.png'))
        .toSet();
    expect(files, PetMood.values.map((PetMood m) => '${m.name}.png').toSet());
  });

  test('空着的地方在招手，有活在跑才是工作中', () {
    expect(petMoodNow(running: false, waiting: false), PetMood.sleeping);
    expect(petMoodNow(running: false, waiting: false, greeting: true), PetMood.waving);
    expect(petMoodNow(running: true, waiting: false, greeting: true), PetMood.working);
    expect(petMoodNow(running: false, waiting: true, greeting: true), PetMood.thinking);
  });

  test('只有闲的那几态轮着换', () {
    expect(kPetResting.contains(PetMood.idle), isTrue);
    expect(kPetResting.contains(PetMood.waving), isTrue);
    expect(kPetResting.contains(PetMood.working), isFalse);
    expect(PetMood.sleeping.rests, isFalse);
  });
}
