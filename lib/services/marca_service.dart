import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ResultadoMarca {
  final String caminho;
  final List<String> cores;

  const ResultadoMarca({required this.caminho, required this.cores});
}

class MarcaService {
  final ImagePicker _picker;
  final ImageCropper _cropper;

  MarcaService({ImagePicker? picker, ImageCropper? cropper})
    : _picker = picker ?? ImagePicker(),
      _cropper = cropper ?? ImageCropper();

  Future<ResultadoMarca?> selecionar({required bool camera}) async {
    final arquivo = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (arquivo == null) return null;
    final recortado = await _cropper.cropImage(
      sourcePath: arquivo.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.png,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar logomarca',
          toolbarColor: const Color(0xFF70569A),
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Recortar logomarca',
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (recortado == null) return null;
    final bytes = await File(recortado.path).readAsBytes();
    final documento = await getApplicationDocumentsDirectory();
    final pasta = Directory(p.join(documento.path, 'marcas'));
    if (!await pasta.exists()) await pasta.create(recursive: true);
    final destino = File(
      p.join(pasta.path, 'logo_${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    await destino.writeAsBytes(bytes, flush: true);
    return ResultadoMarca(caminho: destino.path, cores: _extrairCores(bytes));
  }

  Future<List<String>> coresDoArquivo(String caminho) async {
    return _extrairCores(await File(caminho).readAsBytes());
  }

  List<String> _extrairCores(Uint8List bytes) {
    final original = img.decodeImage(bytes);
    if (original == null) return const ['#70569A', '#8B5CF6', '#D9C7F2'];
    final reduzida = img.copyResize(
      original,
      width: math.min(72, original.width),
    );
    final frequencias = <int, int>{};
    for (var y = 0; y < reduzida.height; y += 2) {
      for (var x = 0; x < reduzida.width; x += 2) {
        final pixel = reduzida.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final maximo = math.max(r, math.max(g, b));
        final minimo = math.min(r, math.min(g, b));
        if (maximo > 244 || maximo < 24 || maximo - minimo < 18) continue;
        final chave = ((r ~/ 32) << 10) | ((g ~/ 32) << 5) | (b ~/ 32);
        frequencias[chave] = (frequencias[chave] ?? 0) + 1;
      }
    }
    final ordenadas = frequencias.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cores = ordenadas.take(3).map((item) {
      final r = (((item.key >> 10) & 31) * 32 + 16).clamp(0, 255);
      final g = (((item.key >> 5) & 31) * 32 + 16).clamp(0, 255);
      final b = ((item.key & 31) * 32 + 16).clamp(0, 255);
      return '#${r.toRadixString(16).padLeft(2, '0')}'
              '${g.toRadixString(16).padLeft(2, '0')}'
              '${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
    }).toList();
    while (cores.length < 3) {
      cores.add(const ['#70569A', '#8B5CF6', '#D9C7F2'][cores.length]);
    }
    return cores;
  }
}
