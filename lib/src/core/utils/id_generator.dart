import 'dart:math';

final _random = Random.secure();
final _writerId = List.generate(
        4, (_) => _random.nextInt(1 << 24).toRadixString(16).padLeft(6, '0'))
    .join();
int _sequence = 0;

String buildId(String prefix) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final serial = (_sequence++).toRadixString(36).padLeft(8, '0');
  return '${prefix}_${micros}_${serial}_$_writerId';
}
