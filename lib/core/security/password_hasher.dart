import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class SenhaProtegida {
  final String hash;
  final String salt;

  const SenhaProtegida({required this.hash, required this.salt});
}

abstract final class PasswordHasher {
  static const int iteracoes = 80000;
  static const int tamanhoChave = 32;

  static SenhaProtegida criar(String senha) {
    if (senha.length < 6) {
      throw const FormatException('A senha deve ter pelo menos 6 caracteres.');
    }

    final aleatorio = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => aleatorio.nextInt(256)),
    );
    final hash = _pbkdf2(utf8.encode(senha), salt, iteracoes, tamanhoChave);
    return SenhaProtegida(
      hash: base64UrlEncode(hash),
      salt: base64UrlEncode(salt),
    );
  }

  static bool verificar(String senha, String hashSalvo, String saltSalvo) {
    try {
      final salt = base64Url.decode(saltSalvo);
      final esperado = base64Url.decode(hashSalvo);
      final calculado = _pbkdf2(
        utf8.encode(senha),
        salt,
        iteracoes,
        esperado.length,
      );
      var diferenca = calculado.length ^ esperado.length;
      for (var i = 0; i < calculado.length && i < esperado.length; i++) {
        diferenca |= calculado[i] ^ esperado[i];
      }
      return diferenca == 0;
    } on FormatException {
      return false;
    }
  }

  static Uint8List _pbkdf2(
    List<int> senha,
    List<int> salt,
    int repeticoes,
    int tamanho,
  ) {
    final hmac = Hmac(sha256, senha);
    final blocos = (tamanho / 32).ceil();
    final saida = BytesBuilder(copy: false);

    for (var bloco = 1; bloco <= blocos; bloco++) {
      final contador = ByteData(4)..setUint32(0, bloco, Endian.big);
      var u = hmac.convert([...salt, ...contador.buffer.asUint8List()]).bytes;
      final t = Uint8List.fromList(u);

      for (var rodada = 1; rodada < repeticoes; rodada++) {
        u = hmac.convert(u).bytes;
        for (var indice = 0; indice < t.length; indice++) {
          t[indice] ^= u[indice];
        }
      }
      saida.add(t);
    }

    return Uint8List.fromList(saida.takeBytes().sublist(0, tamanho));
  }
}
