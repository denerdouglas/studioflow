import 'package:flutter/material.dart';

import '../models/domain/configuracao_comercial.dart';
import '../models/domain/configuracao_comercio.dart';
import '../repositories/configuracao_comercial_repository.dart';
import '../repositories/configuracoes_repository.dart';
import '../services/external_action_service.dart';
import '../services/session_controller.dart';

class ConfiguracaoComercialPage extends StatefulWidget {
  const ConfiguracaoComercialPage({super.key});

  @override
  State<ConfiguracaoComercialPage> createState() =>
      _ConfiguracaoComercialPageState();
}

class _ConfiguracaoComercialPageState extends State<ConfiguracaoComercialPage> {
  final _repository = ConfiguracaoComercialRepository();
  final _configuracoes = ConfiguracoesRepository();
  final _externo = const ExternalActionService();
  final _campos = <String, TextEditingController>{
    for (final chave in const [
      'cep',
      'rua',
      'numero',
      'complemento',
      'bairro',
      'cidade',
      'estado',
      'ponto',
      'link',
      'latitude',
      'longitude',
    ])
      chave: TextEditingController(),
  };
  bool _carregando = true;
  bool _salvando = false;
  String _nome = '';
  String _telefone = '';

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _repository.carregar(_comercioId),
        _configuracoes.carregar(_comercioId),
      ]);
      final config = resultados[0] as ConfiguracaoComercial;
      final comercio = resultados[1] as ConfiguracaoComercio;
      _campos['cep']!.text = config.cep;
      _campos['rua']!.text = config.rua;
      _campos['numero']!.text = config.numero;
      _campos['complemento']!.text = config.complemento;
      _campos['bairro']!.text = config.bairro;
      _campos['cidade']!.text = config.cidade;
      _campos['estado']!.text = config.estado;
      _campos['ponto']!.text = config.pontoReferencia;
      _campos['link']!.text = config.linkLocalizacao;
      _campos['latitude']!.text = config.latitude;
      _campos['longitude']!.text = config.longitude;
      _nome = comercio.nomeExibicao;
      _telefone = comercio.telefone;
    } catch (_) {
      _snack('Não foi possível carregar o endereço.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  ConfiguracaoComercial _valor() => ConfiguracaoComercial(
    comercioId: _comercioId,
    cep: _campos['cep']!.text,
    rua: _campos['rua']!.text,
    numero: _campos['numero']!.text,
    complemento: _campos['complemento']!.text,
    bairro: _campos['bairro']!.text,
    cidade: _campos['cidade']!.text,
    estado: _campos['estado']!.text,
    pontoReferencia: _campos['ponto']!.text,
    linkLocalizacao: _campos['link']!.text,
    latitude: _campos['latitude']!.text,
    longitude: _campos['longitude']!.text,
  );

  Future<void> _salvar() async {
    final config = _valor();
    if (config.rua.trim().isEmpty ||
        config.cidade.trim().isEmpty ||
        config.estado.trim().isEmpty) {
      _snack('Preencha ao menos rua, cidade e estado.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await _repository.salvar(config);
      _snack('Endereço e localização salvos.');
    } catch (_) {
      _snack('Não foi possível salvar o endereço.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _abrirRota() async {
    final config = _valor();
    if (config.destinoRota.trim().isEmpty &&
        config.linkLocalizacao.trim().isEmpty) {
      _snack('Cadastre o endereço ou as coordenadas antes de abrir a rota.');
      return;
    }
    if (!await _externo.abrirRota(config.uriRota)) {
      _snack('Não foi possível abrir o aplicativo de mapas.');
    }
  }

  Future<void> _compartilhar() async {
    final config = _valor();
    if (config.enderecoCompleto.isEmpty) {
      _snack('Cadastre o endereço antes de compartilhar.');
      return;
    }
    final texto =
        'Olá!\n\nEste é o endereço do $_nome:\n\n${config.enderecoCompleto}\n\n'
        '${config.pontoReferencia.trim().isEmpty ? '' : 'Ponto de referência:\n${config.pontoReferencia}\n\n'}'
        'Rota:\n${config.uriRota}\n\nQualquer dúvida, fale conosco pelo número $_telefone.';
    await _externo.compartilhar(texto);
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
    for (final controller in _campos.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Endereço e localização')),
    body: _carregando
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('Localização fixa do salão'),
                  subtitle: Text(
                    'A rota usa apenas o endereço cadastrado. O StudioFlow não acessa sua localização atual.',
                  ),
                ),
              ),
              _campo(
                'cep',
                'CEP',
                Icons.markunread_mailbox_outlined,
                teclado: TextInputType.number,
              ),
              _campo('rua', 'Rua *', Icons.route_outlined),
              Row(
                children: [
                  Expanded(child: _campo('numero', 'Número', Icons.numbers)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campo(
                      'complemento',
                      'Complemento',
                      Icons.apartment_outlined,
                    ),
                  ),
                ],
              ),
              _campo('bairro', 'Bairro', Icons.location_city_outlined),
              Row(
                children: [
                  Expanded(
                    child: _campo('cidade', 'Cidade *', Icons.location_city),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 95,
                    child: _campo('estado', 'UF *', Icons.map_outlined),
                  ),
                ],
              ),
              _campo('ponto', 'Ponto de referência', Icons.near_me_outlined),
              _campo('link', 'Link de localização (opcional)', Icons.link),
              Row(
                children: [
                  Expanded(
                    child: _campo(
                      'latitude',
                      'Latitude (opcional)',
                      Icons.my_location,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campo(
                      'longitude',
                      'Longitude (opcional)',
                      Icons.my_location,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: const Icon(Icons.save_outlined),
                label: Text(_salvando ? 'Salvando...' : 'Salvar endereço'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _abrirRota,
                icon: const Icon(Icons.directions_outlined),
                label: const Text('ABRIR ROTA'),
              ),
              OutlinedButton.icon(
                onPressed: _compartilhar,
                icon: const Icon(Icons.share_outlined),
                label: const Text('COMPARTILHAR LOCALIZAÇÃO'),
              ),
            ],
          ),
  );

  Widget _campo(
    String chave,
    String label,
    IconData icone, {
    TextInputType? teclado,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _campos[chave],
      keyboardType: teclado,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icone)),
    ),
  );
}
