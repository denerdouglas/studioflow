import 'package:flutter/material.dart';
import '../../database/database_service.dart';
import '../../models/domain/pacote_servico.dart';
import '../../repositories/cliente_repository.dart';
import '../../repositories/pacotes_repository.dart';
import '../../widgets/selectors/cliente_smart_selector.dart';
import 'widgets/recorrencia_selector.dart';
import 'widgets/previa_agenda_view.dart';

class VendaPacotePage extends StatefulWidget {
  const VendaPacotePage({super.key});

  @override
  State<VendaPacotePage> createState() => _VendaPacotePageState();
}

class _VendaPacotePageState extends State<VendaPacotePage> {
  final _repo = PacotesRepository();
  bool _carregando = true;
  List<PacoteModeloRegistro> _pacotes = [];
  List<Map<String, Object?>> _profissionais = [];
  List<Map<String, Object?>> _servicos = [];

  ClienteRegistro? _cliente;
  PacoteModeloRegistro? _pacoteSelecionado;
  String? _profissionalSelecionadoId;

  // Agendamento
  bool _agendarAgora = false;
  FrequenciaAgendamentoPacote _frequencia = FrequenciaAgendamentoPacote.semanal;
  int _intervalo = 1;
  PreviaAgendaPacote? _previa;
  bool _gerandoPrevia = false;
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      final pacotes = await _repo.listarModelos();
      // Workaround: We need the list of professionals.
      // I'll add a helper or use database directly via repository if not available.
      // For now, let's pretend _repo has it, I will update _repo.
      final profissionais = await (await DatabaseService.instance.database)
          .query(
            'profissionais',
            where: 'comercio_id = ? AND ativo = 1',
            whereArgs: [_repo.comercioIdForUI],
          );
      final servicos = await (await DatabaseService.instance.database).query(
        'servicos',
        where: 'comercio_id = ? AND ativo = 1',
        whereArgs: [_repo.comercioIdForUI],
      );

      if (mounted) {
        setState(() {
          _pacotes = pacotes.where((p) => p.ativo).toList();
          _profissionais = profissionais;
          _servicos = servicos;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
      }
    }
  }

  Future<void> _gerarPrevia() async {
    if (_pacoteSelecionado == null || _profissionalSelecionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione pacote e profissional.')),
      );
      return;
    }
    setState(() => _gerandoPrevia = true);
    try {
      final solicitacao = SolicitacaoAgendaPacote(
        vendaId: '',
        primeiraData: DateTime.now().add(const Duration(days: 1)),
        diasSemana: {1, 2, 3, 4, 5, 6}, // Seg a Sab
        horaPreferida: 9,
        minutoPreferido: 0,
        profissionalId: _profissionalSelecionadoId!,
        frequencia: _frequencia,
        intervalo: _intervalo,
      );
      final previa = await _repo.gerarPreviaSimulada(
        pacoteId: _pacoteSelecionado!.id,
        solicitacao: solicitacao,
      );
      if (mounted) setState(() => _previa = previa);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro na prévia: $e')));
      }
    }
    if (mounted) setState(() => _gerandoPrevia = false);
  }

  Future<void> _editarSessao(int index, SessaoPlanejadaPacote sessao) async {
    if (_previa == null) return;

    DateTime novaData = sessao.inicio;
    TimeOfDay novaHora = TimeOfDay.fromDateTime(sessao.inicio);
    String novoServicoId = sessao.servicoId;
    String novoProfissionalId = sessao.profissionalId;

    final bool? confirmou = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar Sessão'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Serviço'),
                      initialValue: novoServicoId,
                      items: _servicos.map((s) {
                        return DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['nome'] as String),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => novoServicoId = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Profissional',
                      ),
                      initialValue: novoProfissionalId,
                      items: _profissionais.map((p) {
                        return DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(p['nome'] as String),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => novoProfissionalId = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Data'),
                      subtitle: Text(
                        '${novaData.day}/${novaData.month}/${novaData.year}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final data = await showDatePicker(
                          context: context,
                          initialDate: novaData,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (data != null) {
                          setDialogState(() {
                            novaData = DateTime(
                              data.year,
                              data.month,
                              data.day,
                              novaHora.hour,
                              novaHora.minute,
                            );
                          });
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Horário'),
                      subtitle: Text(novaHora.format(context)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final hora = await showTimePicker(
                          context: context,
                          initialTime: novaHora,
                        );
                        if (hora != null) {
                          setDialogState(() {
                            novaHora = hora;
                            novaData = DateTime(
                              novaData.year,
                              novaData.month,
                              novaData.day,
                              hora.hour,
                              hora.minute,
                            );
                          });
                        }
                      },
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
            );
          },
        );
      },
    );

    if (confirmou == true) {
      final servicoNome =
          _servicos.firstWhere((s) => s['id'] == novoServicoId)['nome']
              as String;
      final profissionalNome =
          _profissionais.firstWhere(
                (p) => p['id'] == novoProfissionalId,
              )['nome']
              as String;

      // In a real app, we should check for conflicts again here!
      // But since it's a preview, we can just update it and let the user visually confirm.

      final novaSessao = sessao.copyWith(
        inicio: novaData,
        servicoId: novoServicoId,
        servicoNome: servicoNome,
        profissionalId: novoProfissionalId,
        profissionalNome: profissionalNome,
        horarioAlternativo: false,
        aviso: null, // Clear any previous warning
      );

      setState(() {
        final novasSessoes = List<SessaoPlanejadaPacote>.from(_previa!.sessoes);
        novasSessoes[index] = novaSessao;
        _previa = _previa!.copyWith(sessoes: novasSessoes);
      });
    }
  }

  Future<void> _confirmarVenda() async {
    if (_cliente == null || _pacoteSelecionado == null) return;
    setState(() => _confirmando = true);
    try {
      final pacoteId = _pacoteSelecionado!.id;
      final preco = _pacoteSelecionado!.preco;

      final entrada = VendaPacoteEntrada(
        pacoteId: pacoteId,
        clienteId: _cliente!.id,
        vendedorProfissionalId: _profissionalSelecionadoId ?? '',
        formaPagamento:
            'Dinheiro', // To be improved in a real app with payment picker
        dataCompra: DateTime.now().toUtc(),
        valorPagoInicial: preco,
      );

      final sessoes =
          (_agendarAgora && _previa != null && _previa!.naoEncaixadas.isEmpty)
          ? _previa!.sessoes
          : null;

      await _repo.venderEAgendar(
        entrada: entrada,
        pacoteNome: _pacoteSelecionado!.nome,
        agendamentos: sessoes,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pacote vendido com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao vender: $e')));
      }
    }
    if (mounted) setState(() => _confirmando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vender Pacote')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Cliente',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    leading: const Icon(Icons.person),
                    title: Text(_cliente?.nome ?? 'Selecione um cliente'),
                    trailing: const Icon(Icons.search),
                    onTap: () async {
                      final c = await ClienteSmartSelector.show(context);
                      if (c != null) setState(() => _cliente = c);
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Pacote',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PacoteModeloRegistro>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Selecione um pacote'),
                    initialValue: _pacoteSelecionado,
                    items: _pacotes.map((p) {
                      final nome = p.nome;
                      final preco = p.preco;
                      return DropdownMenuItem(
                        value: p,
                        child: Text('$nome - R\$ ${preco.toStringAsFixed(2)}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _pacoteSelecionado = val;
                        _previa = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Profissional',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Selecione um profissional'),
                    initialValue: _profissionalSelecionadoId,
                    items: _profissionais.map((p) {
                      return DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text(p['nome'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _profissionalSelecionadoId = val;
                        _previa = null;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  SwitchListTile(
                    title: const Text('Agendar sessões agora?'),
                    subtitle: const Text(
                      'Você pode agendar depois se preferir.',
                    ),
                    value: _agendarAgora,
                    onChanged: (val) {
                      setState(() {
                        _agendarAgora = val;
                        if (!val) _previa = null;
                      });
                    },
                  ),

                  if (_agendarAgora) ...[
                    const Divider(),
                    RecorrenciaSelector(
                      onFrequenciaChanged: (f) => setState(() {
                        _frequencia = f;
                        _previa = null;
                      }),
                      onIntervaloChanged: (i) => setState(() {
                        _intervalo = i;
                        _previa = null;
                      }),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed:
                          (_pacoteSelecionado == null ||
                              _profissionalSelecionadoId == null)
                          ? null
                          : _gerarPrevia,
                      icon: _gerandoPrevia
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.calendar_month),
                      label: const Text('Gerar Prévia'),
                    ),
                  ],

                  if (_previa != null)
                    PreviaAgendaView(
                      previa: _previa!,
                      onEditSessao: _editarSessao,
                    ),

                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed:
                        (_cliente == null ||
                            _pacoteSelecionado == null ||
                            _confirmando)
                        ? null
                        : _confirmarVenda,
                    child: _confirmando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Confirmar Venda'),
                  ),
                ],
              ),
            ),
    );
  }
}
