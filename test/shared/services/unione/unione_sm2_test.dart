// 职责: 验证 SM2 加密实现符合 GB/T 32918.4/32905 的公开向量与 C1C3C2 密文布局。
// 关联文件:
//   lib/shared/services/unione/unione_sm2.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/unione/unione_sm2.dart';

/// Unione 平台内置的 `secret.soft.sm2keys` 密钥对：公钥是平台的默认值，
/// 与 agenticos 的 `UNIONE_SM2_PUB_KEY` 相同，因此往返一次同时验证两半配套。
const _unionePrivateKey =
    '4389c4329a001df855d14ec204d25bf12d4d631bf61bb02d0586a653e199e0da';
const _unionePublicKey =
    '04a684d7140aebfc83515a2312dac7ab836f3adc484627971b6936ad7d5575048c'
    'aecf9c7eb07ed4dcee9d04cb3a7b1c514477b646b1ebe8245de215733baa5133';

String _hex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('SM3', () {
    test('GB/T 32905 公开向量', () {
      expect(
        _hex(sm3(Uint8List.fromList(utf8.encode('abc')))),
        '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0',
      );
      expect(
        _hex(sm3(Uint8List.fromList(utf8.encode('abcd' * 16)))),
        'debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732',
      );
      expect(
        _hex(sm3(Uint8List(0))),
        '1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b',
      );
    });

    test('64 字节边界两侧的填充不会互相污染', () {
      final a = sm3(Uint8List.fromList(utf8.encode('a' * 64)));
      final b = sm3(Uint8List.fromList(utf8.encode('a' * 65)));
      expect(_hex(a), isNot(_hex(b)));
    });
  });

  group('SM2 加密', () {
    test('密文往返可还原明文', () {
      final ciphertext = encryptSm2('Uni@12345', _unionePublicKey);
      expect(decryptSm2(ciphertext, _unionePrivateKey), 'Uni@12345');
    });

    test('中文密码同样可以往返', () {
      final ciphertext = encryptSm2('中文密码123', _unionePublicKey);
      expect(decryptSm2(ciphertext, _unionePrivateKey), '中文密码123');
    });

    test('布局是 04 开头的 C1C3C2，C2 与明文等长', () {
      const plaintext = 'Uni@12345';
      final ciphertext = encryptSm2(plaintext, _unionePublicKey);
      // 04 + C1(64B) + C3(32B) + C2(明文长度)
      expect(ciphertext.startsWith('04'), isTrue);
      expect(ciphertext.length, 2 + 128 + 64 + plaintext.length * 2);
      expect(RegExp(r'^04[0-9a-f]+$').hasMatch(ciphertext), isTrue);
    });

    test('同一次临时标量得到同一密文，换标量则不同', () {
      final first = encryptSm2(
        'Uni@12345',
        _unionePublicKey,
        scalar: BigInt.one,
      );
      final again = encryptSm2(
        'Uni@12345',
        _unionePublicKey,
        scalar: BigInt.one,
      );
      final other = encryptSm2(
        'Uni@12345',
        _unionePublicKey,
        scalar: BigInt.two,
      );
      expect(first, again);
      expect(first, isNot(other));
      expect(decryptSm2(first, _unionePrivateKey), 'Uni@12345');
    });

    test('与 Python 参考实现逐字节一致（固定临时标量）', () {
      // 由 agenticos 的 backend/app/core/sm2.py 生成，同一公钥、同一 k：
      // Dart 侧产出完全相同，才说明 C1/C3/C2 的字段顺序与宽度没有偏差。
      const asciiVector =
          '04f9ec83f1a19bb4cb30ace5c399d7b970d6e374a76c54c746c33ac4be3f8e3e64'
          '0126ba5f6d0216a097a7ad27883b62ab04fc54b6d6e91bf5d5fe785f20b1c00e2b6'
          'e23815683fd9eed80f688b26653c85e3710d9fc94134d7d93f9c0efceb2e23ee7fc'
          '4f50acc4b3ec';
      expect(
        encryptSm2(
          'Uni@12345',
          _unionePublicKey,
          scalar: BigInt.parse('12345678901234567890'),
        ),
        asciiVector,
      );
      expect(decryptSm2(asciiVector, _unionePrivateKey), 'Uni@12345');
    });

    test('可解密参考实现产出，含 C3 完整性校验', () {
      const vector =
          '04e7955af066035a35e7ee08adf72a4094f20aca015815926996fd83bf51802d50'
          'a2738533f7c32ecde25949d461e471f2cf66888afd7910e6953083b752106c1426'
          '5acf0dbadf76695778fc6a64e46bc9f30f1abebb7fee29e55665031c524794de2e8'
          'd38f7574081d783c6c45b5216';
      expect(decryptSm2(vector, _unionePrivateKey), '中文密码123');
      // 篡改最后一个字节：C3 校验必须拒绝。
      final tampered =
          '${vector.substring(0, vector.length - 2)}${vector.endsWith('16') ? '17' : '16'}';
      expect(
        () => decryptSm2(tampered, _unionePrivateKey),
        throwsA(isA<UnioneSm2Exception>()),
      );
    });

    test('拒绝不在曲线上的公钥', () {
      final bogus = '04${'11' * 64}';
      expect(() => encryptSm2('x', bogus), throwsA(isA<UnioneSm2Exception>()));
    });

    test('拒绝空明文与空公钥', () {
      expect(
        () => encryptSm2('', _unionePublicKey),
        throwsA(isA<UnioneSm2Exception>()),
      );
      expect(() => encryptSm2('x', '  '), throwsA(isA<UnioneSm2Exception>()));
    });
  });
}
