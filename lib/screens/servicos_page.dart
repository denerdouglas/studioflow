import 'package:flutter/material.dart';

import '../repositories/servicos_repository.dart';
import '../repositories/unidades_repository.dart';
import '../repositories/funcionarios_repository.dart';
import '../repositories/estoque_repository.dart';
import '../models/domain/unidade.dart';
import '../database/database_service.dart';
import '../services/session_controller.dart';
import 'package:sqflite/sqflite.dart';
import 'assistente_gestao_page.dart';
import '../models/domain/centro_resultado.dart';

class ServicosPage extends StatefulWidget {
  const ServicosPage({super.key});

  @override
  State<ServicosPage> createState() => _ServicosPageState();
}

class _ServicosPageState extends State<ServicosPage> {
  static const Color _corPrincipal = Color(0xFF70569A);

  static const Color _corFundo = Color(0xFFF9F6FC);

  static const Color _textoEscuro = Color(0xFF2D2140);

  static const Color _textoClaro = Color(0xFF766A85);

  static const Color _vermelho = Color(0xFFD64D64);

  final ServicosRepository _repository = ServicosRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  List<ServicoRegistro> _servicos = [];

  bool _carregando = true;
  bool _mostrarInativos = true;

  String _pesquisa = '';
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarServicos();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregarServicos() async {
    try {
      final servicos = await _repository.listar(
        incluirInativos: _mostrarInativos,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _servicos = servicos;
        _carregando = false;
        _erro = null;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar os serviços.';
      });
    }
  }

  List<ServicoRegistro> get _servicosFiltrados {
    final texto = _pesquisa.trim().toLowerCase();

    if (texto.isEmpty) {
      return _servicos;
    }

    return _servicos.where((servico) {
      return servico.nome.toLowerCase().contains(texto) ||
          servico.categoria.toLowerCase().contains(texto) ||
          servico.descricao.toLowerCase().contains(texto);
    }).toList();
  }

  Future<void> _novoServico() async {
    final novo = await showModalBottomSheet<ServicoRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return const ServicoFormSheet();
      },
    );

    if (novo == null) {
      return;
    }

    try {
      await _repository.salvar(novo);

      setState(() {
        _carregando = true;
      });

      await _carregarServicos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Serviço cadastrado com sucesso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            erro is StateError
                ? erro.message
                : 'Não foi possível salvar o serviço.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editarServico(ServicoRegistro servico) async {
    final atualizado = await showModalBottomSheet<ServicoRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ServicoFormSheet(servicoInicial: servico);
      },
    );

    if (atualizado == null) {
      return;
    }

    try {
      await _repository.salvar(atualizado);

      setState(() {
        _carregando = true;
      });

      await _carregarServicos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Serviço atualizado com sucesso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            erro is StateError
                ? erro.message
                : 'Não foi possível atualizar o serviço.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _alterarStatus(ServicoRegistro servico) async {
    try {
      await _repository.alterarStatus(id: servico.id, ativo: !servico.ativo);

      setState(() {
        _carregando = true;
      });

      await _carregarServicos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            servico.ativo ? 'Serviço desativado.' : 'Serviço reativado.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível alterar o serviço.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _excluirServico(ServicoRegistro servico) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Desativar serviço?'),
          content: Text(
            'O serviço “${servico.nome}” '
            'não aparecerá mais nos novos agendamentos.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: FilledButton.styleFrom(backgroundColor: _vermelho),
              child: const Text('Desativar'),
            ),
          ],
        );
      },
    );

    if (confirmou != true) {
      return;
    }

    try {
      await _repository.excluir(servico.id);

      setState(() {
        _carregando = true;
      });

      await _carregarServicos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Serviço desativado.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível desativar o serviço.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _abrirOpcoes(ServicoRegistro servico) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return OpcoesServicoSheet(servico: servico);
      },
    );

    if (acao == 'editar') {
      await _editarServico(servico);
    }

    if (acao == 'status') {
      await _alterarStatus(servico);
    }

    if (acao == 'excluir') {
      await _excluirServico(servico);
    }

    if (acao == 'ficha') {
      _abrirFichaConsumo(servico);
    }
  }

  void _abrirFichaConsumo(ServicoRegistro servico) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FichaConsumoSheet(servico: servico);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _corFundo,
      body: SafeArea(
        child: Column(
          children: [
            _cabecalho(),
            _barraPesquisa(),
            const SizedBox(height: 12),
            Expanded(child: _conteudo()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _novoServico,
        backgroundColor: _corPrincipal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Novo serviço',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Serviços',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textoEscuro,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Preços, duração e categorias',
                  style: TextStyle(fontSize: 13, color: _textoClaro),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _corPrincipal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${_servicos.length}',
              style: const TextStyle(
                color: _corPrincipal,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Assistente de Gestão',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const AssistenteGestaoPage(contexto: CentroResultado.salao),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
    );
  }

  Widget _barraPesquisa() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          TextField(
            controller: _pesquisaController,
            onChanged: (valor) {
              setState(() {
                _pesquisa = valor;
              });
            },
            decoration: InputDecoration(
              hintText: 'Buscar serviço...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _pesquisa.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _pesquisaController.clear();

                        setState(() {
                          _pesquisa = '';
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _mostrarInativos,
            title: const Text(
              'Mostrar serviços inativos',
              style: TextStyle(fontSize: 13, color: _textoClaro),
            ),
            activeThumbColor: _corPrincipal,
            onChanged: (valor) {
              setState(() {
                _mostrarInativos = valor;
                _carregando = true;
              });

              _carregarServicos();
            },
          ),
        ],
      ),
    );
  }

  Widget _conteudo() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: _corPrincipal),
      );
    }

    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: _vermelho),
              const SizedBox(height: 14),
              Text(
                _erro!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textoEscuro, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _carregando = true;
                    _erro = null;
                  });

                  _carregarServicos();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_servicosFiltrados.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.content_cut_outlined,
                size: 70,
                color: Color(0xFFB6A9C3),
              ),
              const SizedBox(height: 16),
              Text(
                _pesquisa.isEmpty
                    ? 'Nenhum serviço cadastrado'
                    : 'Nenhum serviço encontrado',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _textoEscuro,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _pesquisa.isEmpty
                    ? 'Toque em “Novo serviço” para cadastrar o primeiro.'
                    : 'Altere a pesquisa e tente novamente.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textoClaro),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _corPrincipal,
      onRefresh: _carregarServicos,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        itemCount: _servicosFiltrados.length,
        separatorBuilder: (_, _) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final servico = _servicosFiltrados[index];

          return _ServicoCard(
            servico: servico,
            onTap: () {
              _abrirOpcoes(servico);
            },
          );
        },
      ),
    );
  }
}

class _ServicoCard extends StatelessWidget {
  final ServicoRegistro servico;
  final VoidCallback onTap;

  const _ServicoCard({required this.servico, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cor = servico.ativo
        ? const Color(0xFF70569A)
        : const Color(0xFF968AA5);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8E1EE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.content_cut, color: cor),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            servico.nome,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2140),
                            ),
                          ),
                        ),
                        if (!servico.ativo)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFD64D64,
                              ).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Inativo',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD64D64),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      servico.categoria,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF766A85),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ServicoInformacao(
                          icone: Icons.attach_money,
                          texto: 'R\$ ${servico.preco.toStringAsFixed(2)}',
                        ),
                        _ServicoInformacao(
                          icone: Icons.schedule_outlined,
                          texto: '${servico.duracaoMinutos} min',
                        ),
                        if (servico.custoEstimado > 0)
                          _ServicoInformacao(
                            icone: Icons.inventory_2_outlined,
                            texto:
                                'Custo R\$ ${servico.custoEstimado.toStringAsFixed(2)}',
                          ),
                      ],
                    ),
                    if (servico.descricao.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        servico.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF968AA5),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.more_vert, color: Color(0xFF968AA5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServicoInformacao extends StatelessWidget {
  final IconData icone;
  final String texto;

  const _ServicoInformacao({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EDF8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: const Color(0xFF70569A)),
          const SizedBox(width: 4),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF70569A),
            ),
          ),
        ],
      ),
    );
  }
}

class OpcoesServicoSheet extends StatelessWidget {
  final ServicoRegistro servico;

  const OpcoesServicoSheet({super.key, required this.servico});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD6CDDD),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            servico.nome,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2140),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${servico.categoria} • '
            'R\$ ${servico.preco.toStringAsFixed(2)}',
            style: const TextStyle(color: Color(0xFF766A85)),
          ),
          const SizedBox(height: 22),
          _OpcaoServico(
            titulo: 'Editar serviço',
            icone: Icons.edit_outlined,
            cor: const Color(0xFF70569A),
            onTap: () {
              Navigator.pop(context, 'editar');
            },
          ),
          _OpcaoServico(
            titulo: servico.ativo ? 'Desativar serviço' : 'Reativar serviço',
            icone: servico.ativo
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            cor: servico.ativo
                ? const Color(0xFFE58A25)
                : const Color(0xFF15996B),
            onTap: () {
              Navigator.pop(context, 'status');
            },
          ),
          if (servico.ativo)
            _OpcaoServico(
              titulo: 'Desativar e remover da agenda',
              icone: Icons.delete_outline,
              cor: const Color(0xFFD64D64),
              onTap: () {
                Navigator.pop(context, 'excluir');
              },
            ),
          _OpcaoServico(
            titulo: 'Ficha de consumo (Materiais)',
            icone: Icons.inventory_2_outlined,
            cor: const Color(0xFF15996B),
            onTap: () {
              Navigator.pop(context, 'ficha');
            },
          ),
        ],
      ),
    );
  }
}

class _OpcaoServico extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final Color cor;
  final VoidCallback onTap;

  const _OpcaoServico({
    required this.titulo,
    required this.icone,
    required this.cor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icone, color: cor),
      ),
      title: Text(
        titulo,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF2D2140),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class ServicoFormSheet extends StatefulWidget {
  final ServicoRegistro? servicoInicial;

  const ServicoFormSheet({super.key, this.servicoInicial});

  @override
  State<ServicoFormSheet> createState() => _ServicoFormSheetState();
}

class _ServicoFormSheetState extends State<ServicoFormSheet> {
  static const Color _corPrincipal = Color(0xFF70569A);

  static const Color _corFundo = Color(0xFFF9F6FC);

  final TextEditingController _nomeController = TextEditingController();

  final TextEditingController _precoController = TextEditingController();

  final TextEditingController _duracaoController = TextEditingController();

  final TextEditingController _custoController = TextEditingController();

  final TextEditingController _descricaoController = TextEditingController();

  String _categoria = 'Manicure';
  bool _ativo = true;

  final List<String> _categorias = const [
    'Manicure',
    'Pedicure',
    'Combo',
    'Alongamento',
    'Blindagem',
    'Gel',
    'Fibra',
    'Spa dos pés',
    'Cílios',
    'Sobrancelhas',
    'Cabelo',
    'Estética',
    'Outros',
  ];

  final List<String> _coresHex = const [
    '#70569A',
    '#D64D64',
    '#E58A25',
    '#15996B',
    '#2D2140',
    '#0000FF',
    '#008000',
    '#FF00FF',
    '#FF0000',
    '#FFFF00',
    '#00FFFF',
  ];

  final UnidadesRepository _unidadesRepository = UnidadesRepository();
  final FuncionariosRepository _funcionariosRepository =
      FuncionariosRepository();

  List<Unidade> _unidades = [];
  List<ProfissionalRegistro> _profissionais = [];

  String? _unidadeId;
  String? _corIdentificacao;
  final TextEditingController _comissaoPercentualController =
      TextEditingController();
  List<String> _profissionaisAutorizados = [];

  bool _carregandoDependencias = true;

  @override
  void initState() {
    super.initState();

    final servico = widget.servicoInicial;

    if (servico != null) {
      _nomeController.text = servico.nome;

      _precoController.text = servico.preco.toStringAsFixed(2);

      _duracaoController.text = servico.duracaoMinutos.toString();

      _custoController.text = servico.custoEstimado.toStringAsFixed(2);

      _descricaoController.text = servico.descricao;

      _categoria = servico.categoria;
      _ativo = servico.ativo;

      _unidadeId = servico.unidadeId;
      _corIdentificacao = servico.corIdentificacao;
      _comissaoPercentualController.text =
          servico.comissaoPercentual?.toStringAsFixed(2) ?? '';
      _profissionaisAutorizados = List.from(servico.profissionaisAutorizados);

      if (!_categorias.contains(_categoria)) {
        _categoria = 'Outros';
      }
    }

    _carregarDependencias();
  }

  Future<void> _carregarDependencias() async {
    try {
      final unidades = await _unidadesRepository.listar();
      final profissionais = await _funcionariosRepository.listar(
        incluirInativos: false,
      );
      if (mounted) {
        setState(() {
          _unidades = unidades;
          _profissionais = profissionais;
          _carregandoDependencias = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _carregandoDependencias = false);
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _precoController.dispose();
    _duracaoController.dispose();
    _custoController.dispose();
    _descricaoController.dispose();
    _comissaoPercentualController.dispose();
    super.dispose();
  }

  void _salvar() {
    final nome = _nomeController.text.trim();

    final preco = double.tryParse(
      _precoController.text.trim().replaceAll(',', '.'),
    );

    final duracao = int.tryParse(_duracaoController.text.trim());

    final custo =
        double.tryParse(_custoController.text.trim().replaceAll(',', '.')) ?? 0;

    final comissaoPercentual = double.tryParse(
      _comissaoPercentualController.text.trim().replaceAll(',', '.'),
    );

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome do serviço.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (preco == null || preco < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um preço válido.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (duracao == null || duracao <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma duração válida.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (custo < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um custo válido.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final agora = DateTime.now();
    final existente = widget.servicoInicial;

    final servico = ServicoRegistro(
      id: existente?.id ?? agora.microsecondsSinceEpoch.toString(),
      nome: nome,
      categoria: _categoria,
      descricao: _descricaoController.text.trim(),
      preco: preco,
      duracaoMinutos: duracao,
      ativo: _ativo,
      custoEstimado: custo,
      dataCadastro: existente?.dataCadastro ?? agora,
      unidadeId: _unidadeId,
      corIdentificacao: _corIdentificacao,
      comissaoPercentual: comissaoPercentual,
      profissionaisAutorizados: _profissionaisAutorizados,
    );

    Navigator.pop(context, servico);
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    final editando = widget.servicoInicial != null;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      decoration: const BoxDecoration(
        color: _corFundo,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6CDDD),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              editando ? 'Editar serviço' : 'Novo serviço',
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              editando
                  ? 'Atualize os dados do serviço.'
                  : 'Cadastre um novo serviço para usar na agenda.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF766A85)),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome do serviço',
                prefixIcon: Icon(Icons.content_cut),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _categoria,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categorias.map((categoria) {
                return DropdownMenuItem(
                  value: categoria,
                  child: Text(categoria),
                );
              }).toList(),
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _categoria = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _precoController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Preço',
                      prefixText: 'R\$ ',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _duracaoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duração',
                      suffixText: 'min',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _custoController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Custo estimado',
                prefixText: 'R\$ ',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descricaoController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _unidadeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Unidade',
                prefixIcon: Icon(Icons.store_outlined),
              ),
              items: _unidades.map((unidade) {
                return DropdownMenuItem(
                  value: unidade.id,
                  child: Text(unidade.nome),
                );
              }).toList(),
              onChanged: (valor) {
                setState(() {
                  _unidadeId = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _comissaoPercentualController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Comissão (%)',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Cor de Identificação',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _coresHex.length,
                itemBuilder: (context, index) {
                  final hex = _coresHex[index];
                  final color = Color(int.parse(hex.replaceFirst('#', '0xff')));
                  final selected = _corIdentificacao == hex;
                  return GestureDetector(
                    onTap: () => setState(() => _corIdentificacao = hex),
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: Colors.black, width: 3)
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Profissionais Autorizados',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 8),
            if (_carregandoDependencias)
              const CircularProgressIndicator()
            else
              ..._profissionais.map((p) {
                return CheckboxListTile(
                  title: Text(p.nome),
                  value: _profissionaisAutorizados.contains(p.id),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _profissionaisAutorizados.add(p.id);
                      } else {
                        _profissionaisAutorizados.remove(p.id);
                      }
                    });
                  },
                );
              }),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ativo,
              title: const Text(
                'Serviço ativo',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D2140),
                ),
              ),
              subtitle: const Text(
                'Serviços inativos não aparecem em novos agendamentos.',
                style: TextStyle(fontSize: 12, color: Color(0xFF766A85)),
              ),
              activeThumbColor: _corPrincipal,
              onChanged: (valor) {
                setState(() {
                  _ativo = valor;
                });
              },
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                editando ? 'Salvar alterações' : 'Salvar serviço',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _corPrincipal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(57),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ServicoMaterialRegistro {
  final String id;
  final String servicoId;
  final String itemEstoqueId;
  final double quantidade;
  final String? unidadeMedida;
  final String comercioId;

  const ServicoMaterialRegistro({
    required this.id,
    required this.servicoId,
    required this.itemEstoqueId,
    required this.quantidade,
    this.unidadeMedida,
    required this.comercioId,
  });

  Map<String, Object?> paraMapa() {
    return {
      'id': id,
      'servico_id': servicoId,
      'item_estoque_id': itemEstoqueId,
      'quantidade': quantidade,
      'unidade_medida': unidadeMedida,
      'comercio_id': comercioId,
    };
  }

  factory ServicoMaterialRegistro.doMapa(Map<String, Object?> mapa) {
    return ServicoMaterialRegistro(
      id: mapa['id'] as String,
      servicoId: mapa['servico_id'] as String,
      itemEstoqueId: mapa['item_estoque_id'] as String,
      quantidade: (mapa['quantidade'] as num).toDouble(),
      unidadeMedida: mapa['unidade_medida'] as String?,
      comercioId: mapa['comercio_id'] as String,
    );
  }
}

class ServicoMateriaisRepository {
  final DatabaseService _databaseService;

  ServicoMateriaisRepository({DatabaseService? databaseService})
    : _databaseService = databaseService ?? DatabaseService.instance;

  String get _comercioId => SessionController.instance.usuario!.comercioId;

  Future<void> criarTabelaSeNecessario() async {
    final db = await _databaseService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS servico_materiais (
        id TEXT PRIMARY KEY,
        servico_id TEXT NOT NULL,
        item_estoque_id TEXT NOT NULL,
        quantidade REAL NOT NULL,
        unidade_medida TEXT,
        comercio_id TEXT NOT NULL,
        FOREIGN KEY (servico_id) REFERENCES servicos(id) ON DELETE CASCADE,
        FOREIGN KEY (item_estoque_id) REFERENCES estoque(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<List<ServicoMaterialRegistro>> listar(String servicoId) async {
    await criarTabelaSeNecessario();
    final db = await _databaseService.database;
    final resultado = await db.query(
      'servico_materiais',
      where: 'servico_id = ? AND comercio_id = ?',
      whereArgs: [servicoId, _comercioId],
    );
    return resultado.map(ServicoMaterialRegistro.doMapa).toList();
  }

  Future<void> adicionar(ServicoMaterialRegistro material) async {
    await criarTabelaSeNecessario();
    final db = await _databaseService.database;
    await db.insert(
      'servico_materiais',
      material.paraMapa(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remover(String id) async {
    await criarTabelaSeNecessario();
    final db = await _databaseService.database;
    await db.delete(
      'servico_materiais',
      where: 'id = ? AND comercio_id = ?',
      whereArgs: [id, _comercioId],
    );
  }
}

class FichaConsumoSheet extends StatefulWidget {
  final ServicoRegistro servico;

  const FichaConsumoSheet({super.key, required this.servico});

  @override
  State<FichaConsumoSheet> createState() => _FichaConsumoSheetState();
}

class _FichaConsumoSheetState extends State<FichaConsumoSheet> {
  final ServicoMateriaisRepository _repoMateriais =
      ServicoMateriaisRepository();
  final EstoqueRepository _repoEstoque = EstoqueRepository();

  List<ServicoMaterialRegistro> _materiais = [];
  List<ItemEstoqueRegistro> _estoque = [];
  bool _carregando = true;

  String? _itemSelecionado;
  final TextEditingController _qtdController = TextEditingController();
  final TextEditingController _unidadeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);
    try {
      final estoque = await _repoEstoque.listar(incluirInativos: false);
      final materiais = await _repoMateriais.listar(widget.servico.id);
      if (mounted) {
        setState(() {
          _estoque = estoque;
          _materiais = materiais;
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionarItem() async {
    if (_itemSelecionado == null) return;
    final qtd = double.tryParse(_qtdController.text.replaceAll(',', '.'));
    if (qtd == null || qtd <= 0) return;

    final novoItem = ServicoMaterialRegistro(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      servicoId: widget.servico.id,
      itemEstoqueId: _itemSelecionado!,
      quantidade: qtd,
      unidadeMedida: _unidadeController.text,
      comercioId: SessionController.instance.usuario!.comercioId,
    );

    await _repoMateriais.adicionar(novoItem);
    _itemSelecionado = null;
    _qtdController.clear();
    _unidadeController.clear();
    await _carregarDados();
  }

  Future<void> _removerItem(String id) async {
    await _repoMateriais.remover(id);
    await _carregarDados();
  }

  @override
  void dispose() {
    _qtdController.dispose();
    _unidadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 25),
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD6CDDD),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ficha de Consumo',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2140),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Materiais usados no serviço: ${widget.servico.nome}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF766A85)),
          ),
          const SizedBox(height: 22),
          DropdownButtonFormField<String>(
            initialValue: _itemSelecionado,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Item de Estoque'),
            items: _estoque.map((item) {
              return DropdownMenuItem(value: item.id, child: Text(item.nome));
            }).toList(),
            onChanged: (v) => setState(() => _itemSelecionado = v),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtdController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantidade'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _unidadeController,
                  decoration: const InputDecoration(
                    labelText: 'Unidade de medida',
                  ),
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  color: Color(0xFF70569A),
                  size: 36,
                ),
                onPressed: _adicionarItem,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _materiais.length,
                    itemBuilder: (context, index) {
                      final material = _materiais[index];
                      final itemEstoque = _estoque.firstWhere(
                        (e) => e.id == material.itemEstoqueId,
                        orElse: () => ItemEstoqueRegistro.doMapa({
                          'id': '',
                          'nome': 'Desconhecido',
                        }),
                      );
                      return ListTile(
                        title: Text(itemEstoque.nome),
                        subtitle: Text(
                          '${material.quantidade} ${material.unidadeMedida ?? ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removerItem(material.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
