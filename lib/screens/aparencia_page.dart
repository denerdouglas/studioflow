import 'dart:io';

import 'package:flutter/material.dart';

import '../models/domain/aparencia.dart';
import '../repositories/aparencia_repository.dart';
import '../services/marca_service.dart';
import '../services/session_controller.dart';

class AparenciaPage extends StatefulWidget {
  const AparenciaPage({super.key});

  @override
  State<AparenciaPage> createState() => _AparenciaPageState();
}

class _AparenciaPageState extends State<AparenciaPage> {
  final _repository = AparenciaRepository();
  final _marca = MarcaService();
  final _principal = TextEditingController();
  final _secundaria = TextEditingController();
  final _destaque = TextEditingController();
  bool _carregando = true;
  bool _salvando = false;
  bool _automatico = true;
  String _modo = 'claro';
  String _logoPath = '';

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final config = await _repository.carregar(_comercioId);
      _principal.text = config.corPrincipal;
      _secundaria.text = config.corSecundaria;
      _destaque.text = config.corDestaque;
      _automatico = config.temaAutomatico;
      _modo = config.temaModo;
      _logoPath = config.logoPath;
    } catch (_) {
      _snack('Não foi possível carregar a aparência.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _selecionarLogo(bool camera) async {
    try {
      final resultado = await _marca.selecionar(camera: camera);
      if (resultado == null || !mounted) return;
      setState(() {
        _logoPath = resultado.caminho;
        _principal.text = resultado.cores[0];
        _secundaria.text = resultado.cores[1];
        _destaque.text = resultado.cores[2];
        _automatico = true;
      });
      _snack('Logo recortada e paleta extraída. Salve para aplicar.');
    } catch (_) {
      _snack('Não foi possível selecionar ou recortar a logo.');
    }
  }

  Future<void> _restaurarDaLogo() async {
    if (_logoPath.isEmpty || !File(_logoPath).existsSync()) {
      _snack('Selecione uma logo antes de restaurar sua paleta.');
      return;
    }
    final cores = await _marca.coresDoArquivo(_logoPath);
    if (!mounted) return;
    setState(() {
      _principal.text = cores[0];
      _secundaria.text = cores[1];
      _destaque.text = cores[2];
      _automatico = true;
    });
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await _repository.salvar(
        ConfiguracaoAparencia(
          comercioId: _comercioId,
          logoPath: _logoPath,
          corPrincipal: _principal.text,
          corSecundaria: _secundaria.text,
          corDestaque: _destaque.text,
          temaModo: _modo,
          temaAutomatico: _automatico,
        ),
      );
      await SessionController.instance.atualizarUsuario();
      _snack('Aparência salva e aplicada.');
    } catch (erro) {
      _snack(erro.toString().replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _snack(String texto) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(texto)));
    }
  }

  @override
  void dispose() {
    _principal.dispose();
    _secundaria.dispose();
    _destaque.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aparência')),
    body: _carregando
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 54,
                  backgroundImage:
                      _logoPath.isNotEmpty && File(_logoPath).existsSync()
                      ? FileImage(File(_logoPath))
                      : null,
                  child: _logoPath.isEmpty
                      ? const Icon(Icons.storefront, size: 42)
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selecionarLogo(false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galeria'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selecionarLogo(true),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Câmera'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _automatico,
                title: const Text('Tema automático pela logo'),
                subtitle: const Text(
                  'Extrai três cores localmente, sem enviar a imagem.',
                ),
                onChanged: (valor) => setState(() => _automatico = valor),
              ),
              _campo(_principal, 'Cor principal'),
              _campo(_secundaria, 'Cor secundária'),
              _campo(_destaque, 'Cor de destaque'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'claro',
                    label: Text('Claro'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: 'escuro',
                    label: Text('Escuro'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: 'sistema',
                    label: Text('Sistema'),
                    icon: Icon(Icons.settings_brightness_outlined),
                  ),
                ],
                selected: {_modo},
                onSelectionChanged: (valor) =>
                    setState(() => _modo = valor.first),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _restaurarDaLogo,
                icon: const Icon(Icons.palette_outlined),
                label: const Text('Restaurar tema da logo'),
              ),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: const Icon(Icons.save_outlined),
                label: Text(_salvando ? 'Salvando...' : 'Salvar aparência'),
              ),
            ],
          ),
  );

  Widget _campo(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: '$label (#RRGGBB)',
        prefixIcon: const Icon(Icons.color_lens_outlined),
      ),
    ),
  );
}
