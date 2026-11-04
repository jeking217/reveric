// 职责: 国密 SM2 公钥加密（GB/T 32918.4）与 SM3 摘要，供 Unione 平台账号密码登录使用。
// 关联文件:
//   lib/shared/services/unione/unione_auth_client.dart
//   lib/shared/providers/unione_auth_providers.dart
//   test/shared/services/unione/unione_sm2_test.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//
// Unione 平台登录接口不接受明文密码：它自己的前端用 sm-crypto 加密
// （`'04' + sm2.doEncrypt(plain, pubKey, 1)`，即 C1C3C2 布局），服务端用
// Hutool 的 SM2 实现解密。Dart 生态没有可直接引用的国密实现（PointyCastle
// 不含 SM2 曲线），因此这里按标准实现，与参考实现
// （agenticos 的 backend/app/core/sm2.py、frontend/src/lib/sm2.ts）逐行对应。
//
// 密文布局为 `04 || X1 || Y1 || C3 || C2` 的十六进制串：每个坐标定长 32 字节，
// C2 与明文等长；开头的 04 是非压缩点标记，属于协议的一部分（Hutool 解密前
// 会去掉它，sm-crypto 要求调用方自己加上）。
//
// 明文密码只在本地参与加密，不会被写进日志、也不会随请求发出去。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// 推荐曲线参数，GB/T 32918.5 第 5.2.1 节。
final BigInt _p = BigInt.parse(
  'fffffffeffffffffffffffffffffffffffffffff00000000ffffffffffffffff',
  radix: 16,
);
final BigInt _a = BigInt.parse(
  'fffffffeffffffffffffffffffffffffffffffff00000000fffffffffffffffc',
  radix: 16,
);
final BigInt _b = BigInt.parse(
  '28e9fa9e9d9f5e344d5a9e4bcf6509a7f39789f515ab8f92ddbcbd414d940e93',
  radix: 16,
);
final BigInt _n = BigInt.parse(
  'fffffffeffffffffffffffffffffffff7203df6b21c6052b53bbf40939d54123',
  radix: 16,
);
final BigInt _gx = BigInt.parse(
  '32c4ae2c1f1981195f9904466a39c9948fe30bbff2660be1715a4589334c74c7',
  radix: 16,
);
final BigInt _gy = BigInt.parse(
  'bc3736a2f4f6779c59bdcee36b692153d0a9877cc62a474002df32e52139f0a0',
  radix: 16,
);

final BigInt _zero = BigInt.zero;
final BigInt _one = BigInt.one;
final BigInt _two = BigInt.two;
final BigInt _three = BigInt.from(3);
const int _mask32 = 0xffffffff;

/// SM2 加解密拒绝继续使用的密钥或密文。
class UnioneSm2Exception implements Exception {
  UnioneSm2Exception(this.message);

  final String message;

  @override
  String toString() => 'UnioneSm2Exception: $message';
}

// ── SM3（GB/T 32905）：SM2 计算 C3 与密钥派生时使用的摘要 ──

const List<int> _sm3Iv = [
  0x7380166f,
  0x4914b2b9,
  0x172442d7,
  0xda8a0600,
  0xa96f30bc,
  0x163138aa,
  0xe38dee4d,
  0xb0fb0e4e,
];

int _rotl(int value, int bits) {
  final shift = bits & 31;
  if (shift == 0) {
    return value & _mask32;
  }
  return ((value << shift) | (value >>> (32 - shift))) & _mask32;
}

int _p0(int value) => (value ^ _rotl(value, 9) ^ _rotl(value, 17)) & _mask32;

int _p1(int value) => (value ^ _rotl(value, 15) ^ _rotl(value, 23)) & _mask32;

void _compress(List<int> state, Uint8List block, int offset) {
  final words = List<int>.filled(68, 0);
  for (var index = 0; index < 16; index += 1) {
    final at = offset + index * 4;
    words[index] =
        ((block[at] << 24) |
            (block[at + 1] << 16) |
            (block[at + 2] << 8) |
            block[at + 3]) &
        _mask32;
  }
  for (var index = 16; index < 68; index += 1) {
    final mixed =
        (words[index - 16] ^ words[index - 9] ^ _rotl(words[index - 3], 15)) &
        _mask32;
    words[index] =
        (_p1(mixed) ^ _rotl(words[index - 13], 7) ^ words[index - 6]) & _mask32;
  }

  var a = state[0];
  var b = state[1];
  var c = state[2];
  var d = state[3];
  var e = state[4];
  var f = state[5];
  var g = state[6];
  var h = state[7];

  for (var index = 0; index < 64; index += 1) {
    final word = words[index];
    final expanded = (word ^ words[index + 4]) & _mask32;
    final int ff;
    final int gg;
    final int constant;
    if (index < 16) {
      ff = (a ^ b ^ c) & _mask32;
      gg = (e ^ f ^ g) & _mask32;
      constant = 0x79cc4519;
    } else {
      ff = ((a & b) | (a & c) | (b & c)) & _mask32;
      gg = ((e & f) | (~e & g)) & _mask32;
      constant = 0x7a879d8a;
    }
    final ss1 = _rotl((_rotl(a, 12) + e + _rotl(constant, index)) & _mask32, 7);
    final ss2 = (ss1 ^ _rotl(a, 12)) & _mask32;
    final tt1 = (ff + d + ss2 + expanded) & _mask32;
    final tt2 = (gg + h + ss1 + word) & _mask32;

    d = c;
    c = _rotl(b, 9);
    b = a;
    a = tt1;
    h = g;
    g = _rotl(f, 19);
    f = e;
    e = _p0(tt2);
  }

  state[0] = (state[0] ^ a) & _mask32;
  state[1] = (state[1] ^ b) & _mask32;
  state[2] = (state[2] ^ c) & _mask32;
  state[3] = (state[3] ^ d) & _mask32;
  state[4] = (state[4] ^ e) & _mask32;
  state[5] = (state[5] ^ f) & _mask32;
  state[6] = (state[6] ^ g) & _mask32;
  state[7] = (state[7] ^ h) & _mask32;
}

/// [data] 的 32 字节 SM3 摘要。
Uint8List sm3(Uint8List data) {
  final paddedLength = ((data.length + 9) / 64).ceil() * 64;
  final message = Uint8List(paddedLength)..setRange(0, data.length, data);
  message[data.length] = 0x80;

  final bits = data.length * 8;
  final view = ByteData.view(message.buffer);
  view.setUint32(paddedLength - 8, bits ~/ 0x100000000);
  view.setUint32(paddedLength - 4, bits & _mask32);

  final state = List<int>.from(_sm3Iv);
  for (var offset = 0; offset < paddedLength; offset += 64) {
    _compress(state, message, offset);
  }

  final digest = Uint8List(32);
  final out = ByteData.view(digest.buffer);
  for (var index = 0; index < state.length; index += 1) {
    out.setUint32(index * 4, state[index]);
  }
  return digest;
}

// ── 曲线运算：仿射坐标，与参考实现同构（登录只加密一次短密码，
//    Jacobian 乘法省下的常数因子不如"能对照标准逐行读"重要）──

BigInt _mod(BigInt value) {
  final rest = value % _p;
  return rest.isNegative ? rest + _p : rest;
}

BigInt _inverse(BigInt value) => _mod(value).modPow(_p - _two, _p);

/// 曲线上的点。无穷远点用 null 表示。
class _Point {
  const _Point(this.x, this.y);

  final BigInt x;
  final BigInt y;
}

_Point? _add(_Point? left, _Point? right) {
  if (left == null) return right;
  if (right == null) return left;
  if (left.x == right.x) {
    if (_mod(left.y + right.y) == _zero) return null;
    return _double(left);
  }
  final slope = _mod((right.y - left.y) * _inverse(right.x - left.x));
  final x = _mod(slope * slope - left.x - right.x);
  return _Point(x, _mod(slope * (left.x - x) - left.y));
}

_Point? _double(_Point point) {
  if (point.y == _zero) return null;
  final slope = _mod(
    (_three * point.x * point.x + _a) * _inverse(_two * point.y),
  );
  final x = _mod(slope * slope - _two * point.x);
  return _Point(x, _mod(slope * (point.x - x) - point.y));
}

_Point? _multiply(BigInt scalar, _Point point) {
  _Point? result;
  _Point? addend = point;
  var remaining = scalar;
  while (remaining > _zero) {
    if ((remaining & _one) == _one) {
      result = _add(result, addend);
    }
    addend = addend == null ? null : _double(addend);
    remaining >>= 1;
  }
  return result;
}

bool _onCurve(_Point point) =>
    _mod(
      point.y * point.y - (point.x * point.x * point.x + _a * point.x + _b),
    ) ==
    _zero;

_Point _parsePublicKey(String publicKeyHex) {
  var raw = publicKeyHex.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (raw.startsWith('04')) {
    raw = raw.substring(2);
  }
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(raw) || raw.length != 128) {
    throw UnioneSm2Exception('平台公钥不是 64 字节的十六进制串');
  }
  final point = _Point(
    BigInt.parse(raw.substring(0, 64), radix: 16),
    BigInt.parse(raw.substring(64), radix: 16),
  );
  if (!_onCurve(point)) {
    throw UnioneSm2Exception('平台公钥不是曲线上的点');
  }
  return point;
}

Uint8List _kdf(Uint8List source, int length) {
  final out = Uint8List(length);
  var counter = 1;
  var written = 0;
  while (written < length) {
    final input = Uint8List(source.length + 4)
      ..setRange(0, source.length, source);
    ByteData.view(input.buffer).setUint32(source.length, counter);
    final digest = sm3(input);
    final take = min(digest.length, length - written);
    out.setRange(written, written + take, digest);
    written += take;
    counter += 1;
  }
  return out;
}

String _hexOf(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _fieldHex(BigInt value) => value.toRadixString(16).padLeft(64, '0');

/// 256 位无符号大端字节。
Uint8List _bytesOf(BigInt value) {
  final out = Uint8List(32);
  var remaining = value;
  for (var index = 31; index >= 0; index -= 1) {
    out[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return out;
}

BigInt _randomScalar() {
  final random = Random.secure();
  final bytes = Uint8List(32);
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = random.nextInt(256);
  }
  var value = _zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return (value % (_n - _one)) + _one;
}

/// 用 [publicKeyHex] 加密 [plaintext]，返回十六进制 `04||C1||C3||C2`。
///
/// [scalar] 是临时私钥 k，仅供测试用于得到固定密文；真实调用从系统随机源取值。
/// 平台公钥不是曲线上的点时抛 [UnioneSm2Exception]——这比登录时被回一句
/// "密码错误"更早指出配置问题。
String encryptSm2(String plaintext, String publicKeyHex, {BigInt? scalar}) {
  final message = utf8.encode(plaintext);
  if (message.isEmpty) {
    throw UnioneSm2Exception('没有可加密的内容');
  }
  if (publicKeyHex.trim().isEmpty) {
    throw UnioneSm2Exception('缺少平台公钥，无法加密密码');
  }
  final publicKey = _parsePublicKey(publicKeyHex);

  while (true) {
    final k = scalar ?? _randomScalar();
    if (k < _one || k > _n - _one) {
      throw UnioneSm2Exception('临时标量必须落在 [1, n-1] 区间');
    }

    final c1 = _multiply(k, _Point(_gx, _gy));
    final shared = _multiply(k, publicKey);
    if (c1 == null || shared == null) {
      if (scalar != null) throw UnioneSm2Exception('临时标量不可用');
      continue;
    }

    final x2 = _bytesOf(shared.x);
    final y2 = _bytesOf(shared.y);
    final source = Uint8List(64)
      ..setRange(0, 32, x2)
      ..setRange(32, 64, y2);

    final stream = _kdf(source, message.length);
    if (!stream.any((byte) => byte != 0)) {
      // GB/T 32918.4 第 6.1 节步骤 A5：全零密钥流说明这个 k 不可用。
      if (scalar != null) throw UnioneSm2Exception('临时标量不可用');
      continue;
    }

    final c2 = Uint8List(message.length);
    for (var index = 0; index < message.length; index += 1) {
      c2[index] = message[index] ^ stream[index];
    }

    // C3 是 SM3(x2 || M || y2)：两个坐标夹着明文，而不是坐标拼接后再接明文。
    final digestInput = Uint8List(64 + message.length)
      ..setRange(0, 32, x2)
      ..setRange(32, 32 + message.length, message)
      ..setRange(32 + message.length, 64 + message.length, y2);
    final c3 = sm3(digestInput);

    return '04${_fieldHex(c1.x)}${_fieldHex(c1.y)}${_hexOf(c3)}${_hexOf(c2)}';
  }
}

/// 用 [privateKeyHex] 解密十六进制 `04||C1||C3||C2`。
///
/// 只用于测试与自检：应用本身不持有任何私钥，只负责把密文发给平台。
String decryptSm2(String ciphertextHex, String privateKeyHex) {
  final raw = _decodeHex(ciphertextHex.trim());
  final body = (raw.isNotEmpty && raw[0] == 0x04)
      ? Uint8List.sublistView(raw, 1)
      : raw;
  if (body.length < 96) {
    throw UnioneSm2Exception('SM2 密文长度不足');
  }
  final c1 = _Point(
    BigInt.parse(_hexOf(Uint8List.sublistView(body, 0, 32)), radix: 16),
    BigInt.parse(_hexOf(Uint8List.sublistView(body, 32, 64)), radix: 16),
  );
  if (!_onCurve(c1)) {
    throw UnioneSm2Exception('SM2 密文的 C1 不是曲线上的点');
  }
  final c3 = Uint8List.sublistView(body, 64, 96);
  final c2 = Uint8List.sublistView(body, 96);

  final privateKey = BigInt.parse(privateKeyHex.trim(), radix: 16);
  if (privateKey < _one || privateKey > _n - _one) {
    throw UnioneSm2Exception('SM2 私钥超出取值范围');
  }
  final shared = _multiply(privateKey, c1);
  if (shared == null) {
    throw UnioneSm2Exception('共享点为无穷远点');
  }
  final x2 = _bytesOf(shared.x);
  final y2 = _bytesOf(shared.y);
  final stream = _kdf(
    Uint8List(64)
      ..setRange(0, 32, x2)
      ..setRange(32, 64, y2),
    c2.length,
  );
  final plaintext = Uint8List(c2.length);
  for (var index = 0; index < c2.length; index += 1) {
    plaintext[index] = c2[index] ^ stream[index];
  }
  final expected = sm3(
    Uint8List(64 + plaintext.length)
      ..setRange(0, 32, x2)
      ..setRange(32, 32 + plaintext.length, plaintext)
      ..setRange(32 + plaintext.length, 64 + plaintext.length, y2),
  );
  if (_hexOf(expected) != _hexOf(c3)) {
    throw UnioneSm2Exception('SM2 密文未通过 C3 完整性校验');
  }
  return utf8.decode(plaintext);
}

Uint8List _decodeHex(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    throw UnioneSm2Exception('密文不是合法的十六进制串');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var index = 0; index < out.length; index += 1) {
    out[index] = int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16);
  }
  return out;
}
