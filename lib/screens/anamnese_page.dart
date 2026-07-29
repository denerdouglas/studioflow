import 'package:flutter/material.dart';

import '../models/domain/anamnese.dart';
import '../repositories/anamnese_repository.dart';

class AnamnesePage extends StatefulWidget {
  final String clienteId;
  final String nomeCliente;

  const AnamnesePage({
    super.key,
    required this.clienteId,
    required this.nomeCliente,
  });

  @override
  State<AnamnesePage> createState() => _AnamnesePageState();
}

class _AnamnesePageState extends State<AnamnesePage> {
  static const _rotulos = <String, String>{
    'possui_alergias': 'Possui alergias?',
    'usa_medicamentos': 'Usa medicamentos?',
    'possui_problemas_pele': 'Possui problemas de pele?',
    'possui_diabetes': 'Possui diabetes?',
    'possui_pressao_alta': 'Possui pressão alta?',
    'esta_gestante': 'Está gestante?',
    'fez_cirurgia_recente': 'Fez cirurgia recente?',
    'usa_anticoagulante': 'Usa anticoagulante?',
    'possui_sensibilidade': 'Possui sensibilidade?',
    'usa_acidos': 'Usa ácidos na pele?',
    'possui_micose': 'Possui micose?',
    'possui_unha_encravada': 'Possui unha encravada?',
    'roe_unhas': 'Rói unhas?',
    'usa_alongamento': 'Usa alongamento?',
    'possui_sensibilidade_ocular': 'Possui sensibilidade ocular?',
    'usa_lentes_contato': 'Usa lentes de contato?',
    'fez_cirurgia_ocular': 'Fez cirurgia ocular?',
    'possui_quimica_cabelo': 'Possui química no cabelo?',
    'possui_queda_cabelo': 'Possui queda de cabelo?',
  };

  final _repository = AnamneseRepository();
  final _formKey = GlobalKey<FormState>();
  final _alergias = TextEditingController();
  final _medicamentos = TextEditingController();
  final _pele = TextEditingController();
  final _formato = TextEditingController();
  final _comprimento = TextEditingController();
  final _restricoes = TextEditingController();
  final _observacoes = TextEditingController();
  final _assinatura = TextEditingController();
  final Map<String, bool> _respostas = {
    for (final campo in AnamneseRegistro.camposBooleanos) campo: false,
  };
  String _tipo = 'geral';
  bool _confirmou = false;
  bool _autorizou = false;
  bool _carregando = true;
  bool _salvando = false;
  int _versaoAtual = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final controller in [
      _alergias,
      _medicamentos,
      _pele,
      _formato,
      _comprimento,
      _restricoes,
      _observacoes,
      _assinatura,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final ficha = await _repository.atual(widget.clienteId);
      if (!mounted) return;
      if (ficha != null) {
        _tipo = ficha.tipoFicha;
        _respostas.addAll(ficha.respostas);
        _alergias.text = ficha.descricaoAlergias;
        _medicamentos.text = ficha.medicamentos;
        _pele.text = ficha.problemasPele;
        _formato.text = ficha.formatoPreferido;
        _comprimento.text = ficha.comprimentoPreferido;
        _restricoes.text = ficha.restricoes;
        _observacoes.text = ficha.observacoes;
        _assinatura.text = ficha.assinaturaCliente;
        _confirmou = ficha.clienteConfirmouInformacoes;
        _autorizou = ficha.autorizouProcedimento;
        _versaoAtual = ficha.versao;
      }
    } catch (_) {
      if (mounted) _mensagem('Não foi possível carregar a anamnese.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final agora = DateTime.now().toUtc();
      final salva = await _repository.salvar(
        AnamneseRegistro(
          id: '',
          clienteId: widget.clienteId,
          comercioId: '',
          tipoFicha: _tipo,
          versao: 0,
          ativa: true,
          respostas: Map.unmodifiable(_respostas),
          descricaoAlergias: _alergias.text,
          medicamentos: _medicamentos.text,
          problemasPele: _pele.text,
          formatoPreferido: _formato.text,
          comprimentoPreferido: _comprimento.text,
          restricoes: _restricoes.text,
          observacoes: _observacoes.text,
          clienteConfirmouInformacoes: _confirmou,
          autorizouProcedimento: _autorizou,
          assinaturaCliente: _assinatura.text,
          termoVersao: '1.0',
          dataCriacao: agora,
          dataAtualizacao: agora,
        ),
      );
      if (!mounted) return;
      setState(() => _versaoAtual = salva.versao);
      _mensagem('Anamnese versão ${salva.versao} salva com segurança.');
    } catch (erro) {
      if (mounted) _mensagem(erro.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _historico() async {
    final fichas = await _repository.historico(widget.clienteId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Histórico de versões',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (fichas.isEmpty) const Text('Nenhuma anamnese registrada.'),
            for (final ficha in fichas)
              ListTile(
                leading: Icon(
                  ficha.ativa ? Icons.verified_outlined : Icons.history,
                ),
                title: Text(
                  'Versão ${ficha.versao}${ficha.ativa ? ' • atual' : ''}',
                ),
                subtitle: Text(
                  '${_data(ficha.dataAtualizacao)} • ${ficha.assinaturaCliente}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _mensagem(String texto) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Anamnese • ${widget.nomeCliente}'),
        actions: [
          IconButton(
            onPressed: _historico,
            tooltip: 'Histórico',
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_versaoAtual > 0)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined),
                        title: Text('Versão atual: $_versaoAtual'),
                        subtitle: const Text(
                          'Ao salvar, uma nova versão será criada.',
                        ),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _tipo,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de ficha',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'geral', child: Text('Geral')),
                      DropdownMenuItem(value: 'cabelo', child: Text('Cabelo')),
                      DropdownMenuItem(
                        value: 'unhas',
                        child: Text('Unhas / podologia'),
                      ),
                      DropdownMenuItem(
                        value: 'facial',
                        child: Text('Facial / estética'),
                      ),
                      DropdownMenuItem(
                        value: 'olhos',
                        child: Text('Olhos / cílios'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _tipo = v ?? 'geral'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Saúde e segurança',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  for (final campo in AnamneseRegistro.camposBooleanos)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_rotulos[campo]!),
                      value: _respostas[campo]!,
                      onChanged: (v) => setState(() => _respostas[campo] = v),
                    ),
                  if (_respostas['possui_alergias']!)
                    _campo(
                      _alergias,
                      'Descreva as alergias',
                      obrigatorio: true,
                    ),
                  if (_respostas['usa_medicamentos']!)
                    _campo(
                      _medicamentos,
                      'Medicamentos utilizados',
                      obrigatorio: true,
                    ),
                  if (_respostas['possui_problemas_pele']!)
                    _campo(
                      _pele,
                      'Descreva os problemas de pele',
                      obrigatorio: true,
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Preferências e observações',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  _campo(_formato, 'Formato preferido'),
                  _campo(_comprimento, 'Comprimento preferido'),
                  _campo(
                    _restricoes,
                    'Restrições e contraindicações',
                    linhas: 3,
                  ),
                  _campo(_observacoes, 'Observações profissionais', linhas: 3),
                  const Divider(height: 32),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmou,
                    onChanged: (v) => setState(() => _confirmou = v ?? false),
                    title: const Text(
                      'A cliente confirma que as informações são verdadeiras e completas.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _autorizou,
                    onChanged: (v) => setState(() => _autorizou = v ?? false),
                    title: const Text(
                      'A cliente autoriza o procedimento, ciente dos riscos e orientações.',
                    ),
                  ),
                  _campo(
                    _assinatura,
                    'Nome completo da cliente (assinatura declaratória)',
                    obrigatorio: true,
                  ),
                  const Text(
                    'Termo v1.0 • data, usuário e histórico serão registrados.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _versaoAtual == 0
                          ? 'Salvar anamnese'
                          : 'Salvar nova versão',
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _campo(
    TextEditingController controller,
    String label, {
    bool obrigatorio = false,
    int linhas = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        maxLines: linhas,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: obrigatorio
            ? (v) => (v ?? '').trim().length < 3 ? 'Campo obrigatório.' : null
            : null,
      ),
    );
  }

  static String _data(DateTime value) =>
      '${value.toLocal().day.toString().padLeft(2, '0')}/${value.toLocal().month.toString().padLeft(2, '0')}/${value.toLocal().year} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}
