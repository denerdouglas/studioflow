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

  Future<void> _editarHorario([HorarioProfissional? atual]) async {
    if (_profissionais.isEmpty) {
      _mensagem('Cadastre um profissional ativo primeiro.');
      return;
    }
    var profissionalId =
        atual?.profissionalId ?? _profissionais.first['id'] as String;
    var dia = atual?.diaSemana ?? DateTime.monday;
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
                DropdownButtonFormField<int>(
                  initialValue: dia,
                  decoration: const InputDecoration(labelText: 'Dia'),
                  items: List.generate(
                    7,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(_dias[i + 1]),
                    ),
                  ),
                  onChanged: (v) => setLocal(() => dia = v!),
                ),
                TextField(
                  controller: inicio,
                  decoration: const InputDecoration(
                    labelText: 'Início (HH:mm)',
                  ),
                ),
                TextField(
                  controller: fim,
                  decoration: const InputDecoration(labelText: 'Fim (HH:mm)'),
                ),
                TextField(
                  controller: intervaloInicio,
                  decoration: const InputDecoration(
                    labelText: 'Intervalo início',
                  ),
                ),
                TextField(
                  controller: intervaloFim,
                  decoration: const InputDecoration(labelText: 'Intervalo fim'),
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
      await _repository.salvarHorario(
        HorarioProfissional(
          id: atual?.id ?? '',
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
      await _carregar();
    } catch (e) {
      _mensagem('$e');
    }
  }

  Future<void> _adicionarBloqueio() async {
    String? profissionalId;
    var tipo = 'bloqueio';
    var data = DateTime.now();
    var inicio = const TimeOfDay(hour: 9, minute: 0);
    var fim = const TimeOfDay(hour: 10, minute: 0);
    final motivo = TextEditingController();
    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Novo bloqueio ou folga'),
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
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
    if (salvar != true) return;
    try {
      await _repository.adicionarBloqueio(
        BloqueioAgenda(
          id: '',
          profissionalId: profissionalId,
          inicio: DateTime(
            data.year,
            data.month,
            data.day,
            inicio.hour,
            inicio.minute,
          ),
          fim: DateTime(data.year, data.month, data.day, fim.hour, fim.minute),
          tipo: tipo,
          motivo: motivo.text.trim(),
        ),
      );
      await _carregar();
    } catch (e) {
      _mensagem('$e');
    }
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
              if (_horarios.isEmpty)
                const Card(
                  child: ListTile(title: Text('Nenhuma jornada configurada.')),
                ),
              ..._horarios.map(
                (h) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(_dias[h.diaSemana])),
                    title: Text(h.profissionalNome),
                    subtitle: Text(
                      h.ativo
                          ? '${h.inicio}–${h.fim}${h.intervaloInicio == null ? '' : ' • intervalo ${h.intervaloInicio}–${h.intervaloFim}'}'
                          : 'Folga',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editarHorario(h),
                  ),
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
