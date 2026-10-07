import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

void main() {
  test('MegaPlay AES-256-CBC decrypt test', () async {
    const keyStr = 'i?LMTAx0Q6,:}50U';
    const ivStr = "W0;27ToaUpl_P%'c";

    final keyBytes = Uint8List(32);
    final keyRaw = utf8.encode(keyStr);
    keyBytes.setRange(0, keyRaw.length.clamp(0, 32), keyRaw);

    final ivBytes = Uint8List(16);
    final ivRaw = utf8.encode(ivStr);
    ivBytes.setRange(0, ivRaw.length.clamp(0, 16), ivRaw);

    // Let's encrypt a sample JSON payload using AesCbc and decrypt it
    final algorithm = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(keyBytes);

    final plaintext = utf8.encode(
      '{"file":"https://fetch.nexabloom.top/test.m3u8"}',
    );
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: ivBytes,
    );

    final decryptedBytes = await algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    final decryptedText = utf8.decode(decryptedBytes);
    expect(decryptedText, '{"file":"https://fetch.nexabloom.top/test.m3u8"}');
  });
}
