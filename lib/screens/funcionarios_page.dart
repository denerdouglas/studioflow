import 'package:flutter/material.dart';

import '../repositories/funcionarios_repository.dart';

const Color kCorPrincipal = Color(0xFF70569A);
const Color kCorFundo = Color(0xFFF9F6FC);
const Color kTextoEscuro = Color(0xFF2D2140);
const Color kTextoClaro = Color(0xFF766A85);
const Color kVerde = Color(0xFF15996B);
const Color kVermelho = Color(0xFFD64D64);
const Color kLaranja = Color(0xFFE58A25);

class FuncionariosPage extends StatefulWidget {
  const FuncionariosPage({super.key});

  @override
  State<FuncionariosPage> createState() => _FuncionariosPageState();
}

class _FuncionariosPageState extends State<FuncionariosPage> {
  final FuncionariosRepository repository = FuncionariosRepository();

  final TextEditingController pesquisaController = TextEditingController();

  List<ProfissionalRegistro> funcionarios = [];

  bool carregando = true;
  bool mostrarInativos = true;

  String pesquisa = '';

  @override
  void initState() {
    super.initState();
    carregar();
  }

  @override
  void dispose() {
    pesquisaController.dispose();
    super.dispose();
  }

  Future<void> carregar() async {
    final lista = await repository.listar(incluirInativos: mostrarInativos);

    if (!mounted) return;

    setState(() {
      funcionarios = lista;
      carregando = false;
    });
  }

  List<ProfissionalRegistro> get lista {
    if (pesquisa.trim().isEmpty) {
      return funcionarios;
    }

    return funcionarios.where((f) {
      return f.nome.toLowerCase().contains(pesquisa.toLowerCase()) ||
          f.cargo.toLowerCase().contains(pesquisa.toLowerCase());
    }).toList();
  }

  Future<void> novoFuncionario() async {
    final resultado = await showModalBottomSheet<ProfissionalRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FuncionarioFormSheet(),
    );

    if (resultado == null) {
      return;
    }

    await repository.salvar(resultado);

    carregar();
  }

  Future<void> _abrirOpcoes(ProfissionalRegistro funcionario) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => OpcoesFuncionarioSheet(funcionario: funcionario),
    );

    if (!mounted || acao == null) {
      return;
    }

    if (acao == 'editar') {
      final atualizado = await showModalBottomSheet<ProfissionalRegistro>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FuncionarioFormSheet(funcionarioInicial: funcionario),
      );

      if (atualizado != null) {
        await repository.salvar(atualizado);
        await carregar();
      }

      return;
    }

    if (acao == 'status') {
      await repository.alterarStatus(
        id: funcionario.id,
        ativo: !funcionario.ativo,
      );
      await carregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCorFundo,
      appBar: AppBar(
        backgroundColor: kCorFundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Funcionários',
          style: TextStyle(color: kTextoEscuro, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: carregar,
            icon: const Icon(Icons.refresh, color: kCorPrincipal),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: kCorPrincipal,
        foregroundColor: Colors.white,
        onPressed: novoFuncionario,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo'),
      ),
      body: Column(
        children: [
          _cabecalho(),
          _pesquisa(),
          Expanded(
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : _lista(),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho() {
    final ativos = funcionarios.where((e) => e.ativo).length;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF70569A), Color(0xFF9A78C5)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Equipe', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(
              '$ativos funcionário(s)',
              style: const TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pesquisa() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          TextField(
            controller: pesquisaController,
            decoration: InputDecoration(
              hintText: 'Pesquisar...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: pesquisa.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        pesquisaController.clear();

                        setState(() {
                          pesquisa = '';
                        });
                      },
                    ),
            ),
            onChanged: (texto) {
              setState(() {
                pesquisa = texto;
              });
            },
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: mostrarInativos,
            activeThumbColor: kCorPrincipal,
            title: const Text('Mostrar funcionários inativos'),
            onChanged: (valor) async {
              setState(() {
                mostrarInativos = valor;
                carregando = true;
              });

              await carregar();
            },
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    if (lista.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 70, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Nenhum funcionário cadastrado.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kCorPrincipal,
      onRefresh: carregar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
        itemCount: lista.length,
        itemBuilder: (_, index) {
          final funcionario = lista[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFE6DFF0)),
              ),
              child: ListTile(
                onTap: () {
                  _abrirOpcoes(funcionario);
                },

                leading: CircleAvatar(
                  backgroundColor: funcionario.ativo
                      ? kVerde.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.20),
                  child: Text(
                    funcionario.nome[0].toUpperCase(),
                    style: TextStyle(
                      color: funcionario.ativo ? kVerde : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  funcionario.nome,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${funcionario.cargo}\n'
                  '${funcionario.percentualComissao.toStringAsFixed(0)}% comissão',
                ),
                isThreeLine: true,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: funcionario.ativo
                        ? kVerde.withValues(alpha: 0.12)
                        : kLaranja.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    funcionario.ativo ? 'Ativo' : 'Inativo',
                    style: TextStyle(
                      color: funcionario.ativo ? kVerde : kLaranja,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OpcoesFuncionarioSheet extends StatelessWidget {
  final ProfissionalRegistro funcionario;

  const OpcoesFuncionarioSheet({super.key, required this.funcionario});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      decoration: const BoxDecoration(
        color: kCorFundo,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD6CDDD),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 36,
            backgroundColor: kCorPrincipal.withValues(alpha: 0.15),
            child: Text(
              funcionario.nome[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                color: kCorPrincipal,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            funcionario.nome,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(funcionario.cargo, style: const TextStyle(color: kTextoClaro)),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: kCorPrincipal),
            title: const Text('Editar funcionário'),
            onTap: () {
              Navigator.pop(context, 'editar');
            },
          ),
          ListTile(
            leading: Icon(
              funcionario.ativo ? Icons.person_off : Icons.person,
              color: funcionario.ativo ? kLaranja : kVerde,
            ),
            title: Text(
              funcionario.ativo
                  ? 'Desativar funcionário'
                  : 'Reativar funcionário',
            ),
            onTap: () {
              Navigator.pop(context, 'status');
            },
          ),
        ],
      ),
    );
  }
}

class FuncionarioFormSheet extends StatefulWidget {
  final ProfissionalRegistro? funcionarioInicial;

  const FuncionarioFormSheet({super.key, this.funcionarioInicial});

  @override
  State<FuncionarioFormSheet> createState() => _FuncionarioFormSheetState();
}

class _FuncionarioFormSheetState extends State<FuncionarioFormSheet> {
  final TextEditingController nomeController = TextEditingController();

  final TextEditingController whatsappController = TextEditingController();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController comissaoController = TextEditingController();

  final TextEditingController metaController = TextEditingController();

  String cargo = 'Profissional';
  bool ativo = true;

  final cargos = const [
    'Proprietário',
    'Administrador',
    'Recepcionista',
    'Manicure',
    'Pedicure',
    'Cabeleireiro',
    'Barbeiro',
    'Esteticista',
    'Lash Designer',
    'Designer de sobrancelhas',
    'Profissional',
  ];

  @override
  void initState() {
    super.initState();

    final f = widget.funcionarioInicial;

    if (f == null) {
      comissaoController.text = '50';
      metaController.text = '0';
      return;
    }

    nomeController.text = f.nome;
    whatsappController.text = f.whatsapp;
    emailController.text = f.email;
    comissaoController.text = f.percentualComissao.toStringAsFixed(0);
    metaController.text = f.metaMensal.toStringAsFixed(2);

    cargo = f.cargo;
    ativo = f.ativo;
  }

  @override
  void dispose() {
    nomeController.dispose();
    whatsappController.dispose();
    emailController.dispose();
    comissaoController.dispose();
    metaController.dispose();
    super.dispose();
  }

  void salvar() {
    final nome = nomeController.text.trim();

    if (nome.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe o nome.')));
      return;
    }

    final funcionario = ProfissionalRegistro(
      id:
          widget.funcionarioInicial?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      nome: nome,
      whatsapp: whatsappController.text.trim(),
      email: emailController.text.trim(),
      cargo: cargo,
      fotoPerfil: widget.funcionarioInicial?.fotoPerfil ?? '',
      ativo: ativo,
      percentualComissao:
          double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 50,
      metaMensal:
          double.tryParse(metaController.text.replaceAll(',', '.')) ?? 0,
      faturamentoMes: widget.funcionarioInicial?.faturamentoMes ?? 0,
      dataCadastro: widget.funcionarioInicial?.dataCadastro ?? DateTime.now(),
    );

    Navigator.pop(context, funcionario);
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(22, 22, 22, teclado + 22),
      decoration: const BoxDecoration(
        color: kCorFundo,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: whatsappController,
              decoration: const InputDecoration(labelText: 'WhatsApp'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: cargo,
              decoration: const InputDecoration(labelText: 'Cargo'),
              items: cargos
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;

                setState(() {
                  cargo = v;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: comissaoController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Comissão (%)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: metaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Meta mensal',
                prefixText: 'R\$ ',
              ),
            ),
            SwitchListTile(
              value: ativo,
              title: const Text('Funcionário ativo'),
              onChanged: (v) {
                setState(() {
                  ativo = v;
                });
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: salvar,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(55),
                backgroundColor: kCorPrincipal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Salvar funcionário'),
            ),
          ],
        ),
      ),
    );
  }
}
