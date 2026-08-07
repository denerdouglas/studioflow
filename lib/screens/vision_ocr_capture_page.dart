import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class VisionOcrCapturePage extends StatefulWidget {
  const VisionOcrCapturePage({super.key});

  @override
  State<VisionOcrCapturePage> createState() => _VisionOcrCapturePageState();
}

class _VisionOcrCapturePageState extends State<VisionOcrCapturePage> {
  String? _frontPath;
  String? _backPath;
  final _picker = ImagePicker();

  Future<void> _pickImage(bool isFront, ImageSource source) async {
    final xfile = await _picker.pickImage(source: source);
    if (xfile == null) return;
    setState(() {
      if (isFront) {
        _frontPath = xfile.path;
      } else {
        _backPath = xfile.path;
      }
    });
  }

  void _remove(bool isFront) {
    setState(() {
      if (isFront) _frontPath = null;
      else _backPath = null;
    });
  }

  Widget _buildPhotoSlot(String label, bool isFront, String? path) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (path != null) ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _pickImage(isFront, ImageSource.camera),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refazer'),
                  ),
                  TextButton.icon(
                    onPressed: () => _remove(isFront),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text('Remover', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(isFront, ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Câmera'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickImage(isFront, ImageSource.gallery),
                    icon: const Icon(Icons.photo),
                    label: const Text('Galeria'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capturar Etiqueta OCR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Capture a foto da frente (obrigatório) e do verso (opcional). Ambas as imagens serão analisadas para preencher o rascunho.', style: TextStyle(fontSize: 15)),
          const SizedBox(height: 24),
          _buildPhotoSlot('Frente (Principal)', true, _frontPath),
          const SizedBox(height: 16),
          _buildPhotoSlot('Verso (Ingredientes, código, etc)', false, _backPath),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _frontPath == null
                      ? null
                      : () => Navigator.pop(context, {'front': _frontPath, 'back': _backPath}),
                  child: const Text('Analisar Imagens'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
