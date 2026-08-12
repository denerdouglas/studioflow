import 'package:flutter/material.dart';

import '../models/domain/atendimento.dart';
import '../repositories/agenda_completa_repository.dart';

class DisponibilidadePage extends StatefulWidget {
  const DisponibilidadePage({super.key});
  @override
  State<DisponibilidadePage> createState() => _DisponibilidadePageState();
}

class _DisponibilidadePageState extends State<DisponibilidadePage> {
  final _repository = AgendaCompletaRepository();
  List<HorarioProfissional> _horarios = [];
  List<BloqueioAgenda> _bloqueios = [];
  List<Map<String, Object?>> _profissionais = [];
  bool _carregando = true;

  static const _dias = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      _profissionais = await _repository.listarProfissionais();
      _horarios = await _repository.listarHorarios();
      if (_horarios.isEmpty && _profissionais.isNotEmpty) {
        await _repository.criarHorariosPadrao();
        _horarios = await _repository.listarHorarios();
      }
      _bloqueios = await _repository.listarBloqueios();
    } catch (e) {
      if (mounted) _mensagem('$e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _selecionarHorario(TextEditingController controller) async {
    final partes = controller.text.split(':');
    final inicial = partes.length == 2
        ? TimeOfDay(
            hour: int.tryParse(partes[0]) ?? 8,
            minute: int.tryParse(partes[1]) ?? 0,
          )
        : const TimeOfDay(hour: 8, minute: 0);
    final escolhido = await showTimePicker(
      context: context,
      initialTime: inicial,
    );
    if (escolhido != null) {
      controller.text =
          '${escolhido.hour.toString().padLeft(2, '0')}:${escolhido.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _editarHorario([HorarioProfissional? atual]) async {
    if (_profissionais.isEmpty) {
      _mensagem('Cadastre um profissional ativo primeiro.');
      return;
    }
    var profissionalId =
        atual?.profissionalId ?? _profissionais.first['id'] as String;
    final diasSelecionados = atual == null
        ? <int>{DateTime.monday}
        : _horarios
              .where((h) => h.profissionalId == atual.profissionalId && h.ativo)
              .map((h) => h.diaSemana)
              .toSet();
    if (diasSelecionados.isEmpty) {
      diasSelecionados.add(atual?.diaSemana ?? DateTime.monday);
    }
    var aplicarAosSelecionados = atual == null;
    final inicio = TextEditingController(text: atual?.inicio ?? '08:00');
    final fim = TextEditingController(text: atual?.fim ?? '18:00');
    final intervaloInicio = TextEditingController(
      text: atual?.intervaloInicio ?? '12:00',
    );
    final intervaloFim = TextEditingController(
      text: atual?.intervaloFim ?? '13:00',
    );
    var ativo = atual?.ativo ?? true;
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Adicionar jornada' : 'Editar jornada'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: profissionalId,
                  decoration: const InputDecoration(labelText: 'Profissional'),
                  items: _profissionais
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(p['nome'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => profissionalId = v!),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 6),
                    child: Text('Aplicar aos dias'),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    final dia = i + 1;
                    return FilterChip(
                      label: Text(_dias[dia]),
                      selected: diasSelecionados.contains(dia),
                      onSelected: (selected) => setLocal(() {
                        if (selected) {
                          diasSelecionados.add(dia);
                        } else if (diasSelecionados.length > 1) {
                          diasSelecionados.remove(dia);
                        }
                      }),
                    );
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: aplicarAosSelecionados,
                  title: const Text(
                    'Aplicar este horário a todos os dias selecionados',
                  ),
                  subtitle: const Text(
                    'Desative para personalizar somente o dia em edição.',
                  ),
                  onChanged: (value) =>
                      setLocal(() => aplicarAosSelecionados = value),
                ),
                TextField(
                  controller: inicio,
                  decoration: InputDecoration(
                    labelText: 'Início',
                    suffixIcon: IconButton(
                      tooltip: 'Escolher horário',
                      onPressed: () => _selecionarHorario(inicio),
                      icon: const Icon(Icons.schedule),
                    ),
                  ),
                ),
                TextField(
                  controller: fim,
                  decoration: InputDecoration(
                    labelText: 'Fim',
                    suffixIcon: IconButton(
                      onPressed: () => _selecionarHorario(fim),
                      icon: const Icon(Icons.schedule),
                    ),
                  ),
                ),
                TextField(
                  controller: intervaloInicio,
                  decoration: InputDecoration(
                    labelText: 'Intervalo início',
                    suffixIcon: IconButton(
                      onPressed: () => _selecionarHorario(intervaloInicio),
                      icon: const Icon(Icons.schedule),
                    ),
                  ),
                ),
                TextField(
                  controller: intervaloFim,
                  decoration: InputDecoration(
                    labelText: 'Intervalo fim',
                    suffixIcon: IconButton(
                      onPressed: () => _selecionarHorario(intervaloFim),
                      icon: const Icon(Icons.schedule),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: ativo,
                  title: const Text('Trabalha neste dia'),
                  onChanged: (v) => setLocal(() => ativo = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (salvar != true) return;
    try {
      for (final dia in diasSelecionados) {
        if (!aplicarAosSelecionados &&
            atual != null &&
            dia != atual.diaSemana) {
          continue;
        }
        await _repository.salvarHorario(
          HorarioProfissional(
            id: dia == atual?.diaSemana ? atual?.id ?? '' : '',
            profissionalId: profissionalId,
            diaSemana: dia,
            inicio: inicio.text.trim(),
            fim: fim.text.trim(),
            intervaloInicio: intervaloInicio.text.trim().isEmpty
                ? null
                : intervaloInicio.text.trim(),
            intervaloFim: intervaloFim.text.trim().isEmpty
                ? null
                : intervaloFim.text.trim(),
            ativo: ativo,
          ),
        );
      }
      await _carregar();
    } catch (e) {
      _mensagem('$e');
    }
  }

  Future<void> _adicionarBloqueio([BloqueioAgenda? atual]) async {
    String? profissionalId = atual?.profissionalId;
    var tipo = atual?.tipo ?? 'bloqueio';
    var data = atual?.inicio ?? DateTime.now();
    var inicio = atual == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay.fromDateTime(atual.inicio);
    var fim = atual == null
        ? const TimeOfDay(hour: 10, minute: 0)
        : TimeOfDay.fromDateTime(atual.fim);
    var diaInteiro =
        atual != null &&
        atual.inicio.hour == 0 &&
        atual.inicio.minute == 0 &&
        atual.fim.difference(atual.inicio).inHours >= 24;
    final motivo = TextEditingController(text: atual?.motivo ?? '');
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(atual == null ? 'Novo bloqueio' : 'Editar bloqueio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: profissionalId,
                  decoration: const InputDecoration(labelText: 'Profissional'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Toda a equipe'),
                    ),
                    ..._profissionais.map(
                      (p) => DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text(p['nome'] as String),
                      ),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => profissionalId = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'bloqueio',
                      child: Text('Bloqueio'),
                    ),
                    DropdownMenuItem(value: 'folga', child: Text('Folga')),
                    DropdownMenuItem(
                      value: 'intervalo',
                      child: Text('Intervalo extra'),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => tipo = v!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data'),
                  subtitle: Text('${data.day}/${data.month}/${data.year}'),
                  onTap: () async {
                    final v = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                      initialDate: data,
                    );
                    if (v != null) setLocal(() => data = v);
                  },
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Dia inteiro')),
                    ButtonSegment(value: false, label: Text('Por horário')),
                  ],
                  selected: {diaInteiro},
                  onSelectionChanged: (valor) =>
                      setLocal(() => diaInteiro = valor.first),
                ),
                if (!diaInteiro) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Início: ${inicio.format(context)}'),
                    onTap: () async {
                      final v = await showTimePicker(
                        context: context,
                        initialTime: inicio,
                      );
                      if (v != null) setLocal(() => inicio = v);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Fim: ${fim.format(context)}'),
                    onTap: () async {
                      final v = await showTimePicker(
                        context: context,
                        initialTime: fim,
                      );
                      if (v != null) setLocal(() => fim = v);
                    },
                  ),
                ],
                TextField(
                  controller: motivo,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(atual == null ? 'Adicionar' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
    if (salvar != true) return;
    try {
      await _repository.adicionarBloqueio(
        BloqueioAgenda(
          id: atual?.id ?? '',
          profissionalId: profissionalId,
          inicio: diaInteiro
              ? DateTime(data.year, data.month, data.day)
              : DateTime(
                  data.year,
                  data.month,
                  data.day,
                  inicio.hour,
                  inicio.minute,
                ),
          fim: diaInteiro
              ? DateTime(
                  data.year,
                  data.month,
                  data.day,
                ).add(const Duration(days: 1))
              : DateTime(data.year, data.month, data.day, fim.hour, fim.minute),
          tipo: tipo,
          motivo: motivo.text.trim(),
        ),
      );
      await _carregar();
    } catch (e) {
      _mensagem('$e');
    }
  }

  List<HorarioProfissional> _doProfissional(String id) =>
      _horarios.where((h) => h.profissionalId == id).toList()
        ..sort((a, b) => a.diaSemana.compareTo(b.diaSemana));

  String _resumoProfissional(String id) {
    final dias = _doProfissional(id);
    if (dias.isEmpty) return 'Jornada ainda não configurada';
    return dias
        .map((h) {
          if (!h.ativo) return '${_dias[h.diaSemana]}: folga';
          final intervalo = h.intervaloInicio == null
              ? ''
              : ' · intervalo ${h.intervaloInicio}–${h.intervaloFim}';
          return '${_dias[h.diaSemana]}: ${h.inicio}–${h.fim}$intervalo';
        })
        .join('\n');
  }

  void _mensagem(String texto) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(texto)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Disponibilidade'),
      actions: [
        IconButton(onPressed: _carregar, icon: const Icon(Icons.refresh)),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      onPressed: _adicionarBloqueio,
      icon: const Icon(Icons.block),
      label: const Text('Bloqueio'),
    ),
    body: _carregando
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Jornadas',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _editarHorario,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_profissionais.isEmpty)
                const Card(
                  child: ListTile(title: Text('Nenhum profissional ativo.')),
                ),
              ..._profissionais.map((p) {
                final id = p['id'] as String;
                final jornadas = _doProfissional(id);
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(p['nome'] as String),
                    subtitle: Text(_resumoProfissional(id)),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () => _editarHorario(
                      jornadas.isEmpty ? null : jornadas.first,
                    ),
                  ),
                );
              }),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Toque no profissional para ajustar a jornada. Use + para adicionar uma exceção por dia.',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Próximos bloqueios e folgas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (_bloqueios.isEmpty)
                const Card(
                  child: ListTile(title: Text('Nenhum bloqueio futuro.')),
                ),
              ..._bloqueios.map(
                (b) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_busy),
                    title: Text('${b.tipo} • ${b.profissionalNome}'),
                    subtitle: Text(
                      '${b.inicio.day}/${b.inicio.month} ${b.inicio.hour.toString().padLeft(2, '0')}:${b.inicio.minute.toString().padLeft(2, '0')}–${b.fim.hour.toString().padLeft(2, '0')}:${b.fim.minute.toString().padLeft(2, '0')}\n${b.motivo}',
                    ),
                    isThreeLine: b.motivo.isNotEmpty,
                    onTap: () => _adicionarBloqueio(b),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await _repository.removerBloqueio(b.id);
                        await _carregar();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
