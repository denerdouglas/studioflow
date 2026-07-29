import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../core/routes/app_routes.dart';
import '../widgets/shared/sheet_handle.dart';
import '../core/utils/phone_normalizer.dart';
import '../models/domain/mensagem_modelo.dart';
import '../models/domain/configuracao_comercial.dart';
import '../models/domain/configuracao_comercio.dart';
import '../models/domain/atendimento.dart';
import '../repositories/configuracao_comercial_repository.dart';
import '../repositories/configuracoes_repository.dart';
import '../repositories/modelos_mensagens_repository.dart';
import '../repositories/pagamento_repository.dart';
import '../services/mensagem_service.dart';
import '../services/session_controller.dart';
import '../widgets/mensagem_revisao_dialog.dart';

import '../repositories/cliente_repository.dart';
import 'agenda_page.dart';
import 'anamnese_page.dart';
import 'clientes_360_page.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  static const Color _corPrincipal = Color(0xFF70569A);
  static const Color _corFundo = Color(0xFFF9F6FC);
  static const Color _textoEscuro = Color(0xFF2D2140);
  static const Color _textoClaro = Color(0xFF766A85);

  final ClienteRepository _repository = ClienteRepository();

  final TextEditingController _pesquisaController = TextEditingController();

  List<ClienteRegistro> _clientes = [];

  bool _carregando = true;
  String _pesquisa = '';
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    super.dispose();
  }

  Future<void> _carregarClientes() async {
    try {
      final clientes = await _repository.listar();

      if (!mounted) {
        return;
      }

      setState(() {
        _clientes = clientes;
        _carregando = false;
        _erro = null;
      });
    } catch (erro) {
      if (!mounted) {
        return;
      }

      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar os clientes.';
      });
    }
  }

  List<ClienteRegistro> get _clientesFiltrados {
    final texto = _pesquisa.trim().toLowerCase();

    if (texto.isEmpty) {
      return _clientes;
    }

    return _clientes.where((cliente) {
      return cliente.nome.toLowerCase().contains(texto) ||
          cliente.whatsapp.contains(texto) ||
          cliente.profissional.toLowerCase().contains(texto);
    }).toList();
  }

  Future<void> _abrirCadastroCliente() async {
    final novoCliente = await showModalBottomSheet<ClienteRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return const CadastroClienteSheet();
      },
    );

    if (novoCliente == null) {
      return;
    }

    try {
      final whatsappExiste = await _repository.existeWhatsapp(
        novoCliente.whatsapp,
      );

      if (whatsappExiste) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Já existe um cliente ativo com esse WhatsApp.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

        return;
      }

      await _repository.inserir(novoCliente);
      await _carregarClientes();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${novoCliente.nome} foi cadastrado com sucesso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar o cliente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _abrirCliente(ClienteRegistro cliente) async {
    final resultado = await Navigator.push<String>(
      context,
      AppRoutes.material(
        builder: (_) =>
            DetalhesClientePage(cliente: cliente, repository: _repository),
      ),
    );

    if (resultado == 'atualizado' || resultado == 'excluido') {
      await _carregarClientes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _corFundo,
      body: SafeArea(
        child: Column(
          children: [
            _construirCabecalho(),
            _construirPesquisa(),
            const SizedBox(height: 14),
            Expanded(child: _construirConteudo()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirCadastroCliente,
        backgroundColor: _corPrincipal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text(
          'Novo cliente',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _construirCabecalho() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clientes',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textoEscuro,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Cadastros, histórico e anamnese',
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
              '${_clientes.length}',
              style: const TextStyle(
                color: _corPrincipal,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPesquisa() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _pesquisaController,
        onChanged: (valor) {
          setState(() {
            _pesquisa = valor;
          });
        },
        decoration: InputDecoration(
          hintText: 'Buscar cliente...',
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
    );
  }

  Widget _construirConteudo() {
    if (_carregando) {
      return const Center(
        child: CircularProgressIndicator(color: _corPrincipal),
      );
    }

    if (_erro != null) {
      return _ErroClientes(
        mensagem: _erro!,
        onTentarNovamente: () {
          setState(() {
            _carregando = true;
            _erro = null;
          });

          _carregarClientes();
        },
      );
    }

    if (_clientesFiltrados.isEmpty) {
      return _ClientesVazio(possuiPesquisa: _pesquisa.isNotEmpty);
    }

    return RefreshIndicator(
      color: _corPrincipal,
      onRefresh: _carregarClientes,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        itemCount: _clientesFiltrados.length,
        separatorBuilder: (_, _) {
          return const SizedBox(height: 10);
        },
        itemBuilder: (context, index) {
          final cliente = _clientesFiltrados[index];

          return _ClienteCard(
            cliente: cliente,
            onTap: () {
              _abrirCliente(cliente);
            },
          );
        },
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  final ClienteRegistro cliente;
  final VoidCallback onTap;

  const _ClienteCard({required this.cliente, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const corPrincipal = Color(0xFF70569A);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: const Color(0xFFE8E1EE)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: corPrincipal.withValues(alpha: 0.12),
                child: Text(
                  _iniciais(cliente.nome),
                  style: const TextStyle(
                    color: corPrincipal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente.nome,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D2140),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Profissional: ${cliente.profissional}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF766A85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cliente.totalAtendimentos} atendimentos • '
                      'R\$ ${cliente.totalGasto.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF968AA5),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF968AA5)),
            ],
          ),
        ),
      ),
    );
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(' ')
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) {
      return '?';
    }

    if (partes.length == 1) {
      return partes.first[0].toUpperCase();
    }

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }
}

DateTime? _dataCliente(String texto) {
  final partes = texto.trim().split('/');
  if (partes.length != 3) return null;
  return DateTime.tryParse(
    '${partes[2]}-${partes[1].padLeft(2, '0')}-${partes[0].padLeft(2, '0')}',
  );
}

class CadastroClienteSheet extends StatefulWidget {
  const CadastroClienteSheet({super.key});

  @override
  State<CadastroClienteSheet> createState() => _CadastroClienteSheetState();
}

class _CadastroClienteSheetState extends State<CadastroClienteSheet> {
  static const Color _corPrincipal = Color(0xFF70569A);
  static const Color _corFundo = Color(0xFFF9F6FC);
  static const Color _textoEscuro = Color(0xFF2D2140);
  static const Color _textoClaro = Color(0xFF766A85);

  final TextEditingController _nomeController = TextEditingController();

  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _telefoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _aniversarioController = TextEditingController();
  bool _consentimentoWhatsapp = false;
  bool _consentimentoMarketing = false;

  final TextEditingController _observacoesController = TextEditingController();

  String _profissionalSelecionada = 'Rafa';

  final List<String> _profissionais = const [
    'Rafa',
    'Ana',
    'Sem profissional definida',
  ];

  @override
  void dispose() {
    _nomeController.dispose();
    _whatsappController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _aniversarioController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _importarContato() async {
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permissão negada. Você pode continuar o cadastro manualmente.',
              ),
            ),
          );
        }
        return;
      }
      final contato = await FlutterContacts.native.showPicker(
        properties: const {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
        },
      );
      if (contato == null || !mounted) return;
      if (contato.phones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O contato selecionado não possui telefone.'),
          ),
        );
        return;
      }
      var telefone = contato.phones.first.number;
      if (contato.phones.length > 1) {
        final escolhido = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Escolha o telefone'),
            children: contato.phones
                .map(
                  (item) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, item.number),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(item.number),
                    ),
                  ),
                )
                .toList(),
          ),
        );
        if (escolhido == null) return;
        telefone = escolhido;
        if (!mounted) return;
      }
      setState(() {
        final nomeContato = contato.displayName?.trim() ?? '';
        if (nomeContato.isNotEmpty) {
          _nomeController.text = nomeContato;
        }
        _whatsappController.text = telefone;
        _telefoneController.text = telefone;
        if (contato.emails.isNotEmpty) {
          _emailController.text = contato.emails.first.address;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contato importado. Revise os dados antes de salvar.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível abrir os contatos. Continue manualmente.',
            ),
          ),
        );
      }
    }
  }

  void _salvar() {
    final nome = _nomeController.text.trim();
    final whatsapp = _whatsappController.text.trim();

    if (nome.isEmpty || whatsapp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha o nome e o WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final agora = DateTime.now();

    Navigator.pop(
      context,
      ClienteRegistro(
        id: agora.microsecondsSinceEpoch.toString(),
        nome: nome,
        whatsapp: whatsapp,
        telefone: _telefoneController.text.trim(),
        email: _emailController.text.trim(),
        dataNascimento: _dataCliente(_aniversarioController.text),
        consentimentoWhatsapp: _consentimentoWhatsapp,
        consentimentoMarketing: _consentimentoMarketing,
        profissional: _profissionalSelecionada,
        ultimoServico: 'Nenhum atendimento',
        totalGasto: 0,
        totalAtendimentos: 0,
        observacoes: _observacoesController.text.trim(),
        dataCadastro: agora,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

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
            const SheetHandle(),
            const SizedBox(height: 20),
            const Text(
              'Cadastrar cliente',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: _textoEscuro,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Preencha os dados principais da cliente.',
              style: TextStyle(fontSize: 13, height: 1.4, color: _textoClaro),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _importarContato,
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('IMPORTAR DOS CONTATOS'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Opcional: somente o contato escolhido será usado para preencher este formulário.',
              style: TextStyle(fontSize: 12, color: _textoClaro),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _whatsappController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                hintText: '(11) 99999-9999',
                prefixIcon: Icon(Icons.chat_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _telefoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail (opcional)',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _aniversarioController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Aniversário (dd/mm/aaaa)',
                prefixIcon: Icon(Icons.cake_outlined),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _consentimentoWhatsapp,
              title: const Text('Aceita contato operacional por WhatsApp'),
              onChanged: (v) => setState(() => _consentimentoWhatsapp = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _consentimentoMarketing,
              title: const Text('Aceita mensagens promocionais'),
              onChanged: (v) => setState(() => _consentimentoMarketing = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _profissionalSelecionada,
              decoration: const InputDecoration(
                labelText: 'Profissional principal',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: _profissionais.map((profissional) {
                return DropdownMenuItem(
                  value: profissional,
                  child: Text(profissional),
                );
              }).toList(),
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _profissionalSelecionada = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _observacoesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Salvar cliente',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

class EditarClienteSheet extends StatefulWidget {
  final ClienteRegistro cliente;

  const EditarClienteSheet({super.key, required this.cliente});

  @override
  State<EditarClienteSheet> createState() => _EditarClienteSheetState();
}

class _EditarClienteSheetState extends State<EditarClienteSheet> {
  static const Color _corPrincipal = Color(0xFF70569A);
  static const Color _corFundo = Color(0xFFF9F6FC);

  late final TextEditingController _nomeController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _aniversarioController;
  late bool _consentimentoWhatsapp;
  late bool _consentimentoMarketing;
  late final TextEditingController _observacoesController;

  late String _profissionalSelecionada;

  final List<String> _profissionais = const [
    'Rafa',
    'Ana',
    'Sem profissional definida',
  ];

  @override
  void initState() {
    super.initState();

    _nomeController = TextEditingController(text: widget.cliente.nome);

    _whatsappController = TextEditingController(text: widget.cliente.whatsapp);
    _telefoneController = TextEditingController(text: widget.cliente.telefone);
    _emailController = TextEditingController(text: widget.cliente.email);
    final nascimento = widget.cliente.dataNascimento;
    _aniversarioController = TextEditingController(
      text: nascimento == null
          ? ''
          : '${nascimento.day.toString().padLeft(2, '0')}/${nascimento.month.toString().padLeft(2, '0')}/${nascimento.year}',
    );
    _consentimentoWhatsapp = widget.cliente.consentimentoWhatsapp;
    _consentimentoMarketing = widget.cliente.consentimentoMarketing;

    _observacoesController = TextEditingController(
      text: widget.cliente.observacoes,
    );

    _profissionalSelecionada = widget.cliente.profissional;

    if (!_profissionais.contains(_profissionalSelecionada)) {
      _profissionalSelecionada = 'Sem profissional definida';
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _whatsappController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _aniversarioController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  void _salvar() {
    final nome = _nomeController.text.trim();
    final whatsapp = _whatsappController.text.trim();

    if (nome.isEmpty || whatsapp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha o nome e o WhatsApp.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    Navigator.pop(
      context,
      widget.cliente.copiarCom(
        nome: nome,
        whatsapp: whatsapp,
        telefone: _telefoneController.text.trim(),
        email: _emailController.text.trim(),
        dataNascimento: _dataCliente(_aniversarioController.text),
        consentimentoWhatsapp: _consentimentoWhatsapp,
        consentimentoMarketing: _consentimentoMarketing,
        profissional: _profissionalSelecionada,
        observacoes: _observacoesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

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
            const SheetHandle(),
            const SizedBox(height: 20),
            const Text(
              'Editar cliente',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _whatsappController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                prefixIcon: Icon(Icons.chat_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _telefoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail (opcional)',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _aniversarioController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Aniversário (dd/mm/aaaa)',
                prefixIcon: Icon(Icons.cake_outlined),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _consentimentoWhatsapp,
              title: const Text('Aceita contato operacional por WhatsApp'),
              onChanged: (v) => setState(() => _consentimentoWhatsapp = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _consentimentoMarketing,
              title: const Text('Aceita mensagens promocionais'),
              onChanged: (v) => setState(() => _consentimentoMarketing = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _profissionalSelecionada,
              decoration: const InputDecoration(
                labelText: 'Profissional principal',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: _profissionais.map((profissional) {
                return DropdownMenuItem(
                  value: profissional,
                  child: Text(profissional),
                );
              }).toList(),
              onChanged: (valor) {
                if (valor == null) {
                  return;
                }

                setState(() {
                  _profissionalSelecionada = valor;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _observacoesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observações',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: const Text(
                'Salvar alterações',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

class DetalhesClientePage extends StatefulWidget {
  final ClienteRegistro cliente;
  final ClienteRepository repository;

  const DetalhesClientePage({
    super.key,
    required this.cliente,
    required this.repository,
  });

  @override
  State<DetalhesClientePage> createState() => _DetalhesClientePageState();
}

class _DetalhesClientePageState extends State<DetalhesClientePage> {
  static const Color _corPrincipal = Color(0xFF70569A);

  static const Color _corFundo = Color(0xFFF9F6FC);

  static const Color _textoEscuro = Color(0xFF2D2140);

  static const Color _textoClaro = Color(0xFF766A85);

  late ClienteRegistro _cliente;

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
  }

  Future<void> _editarCliente() async {
    final clienteAtualizado = await showModalBottomSheet<ClienteRegistro>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return EditarClienteSheet(cliente: _cliente);
      },
    );

    if (clienteAtualizado == null) {
      return;
    }

    try {
      await widget.repository.atualizar(clienteAtualizado);

      if (!mounted) {
        return;
      }

      setState(() {
        _cliente = clienteAtualizado;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliente atualizado com sucesso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar o cliente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _excluirCliente() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir cliente?'),
          content: Text(
            'Deseja excluir ${_cliente.nome}? '
            'Essa cliente não aparecerá mais na lista.',
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
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD64D64),
              ),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    try {
      await widget.repository.excluir(_cliente.id);

      if (!mounted) {
        return;
      }

      Navigator.pop(context, 'excluido');
    } catch (erro) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível excluir o cliente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _abrirWhatsApp() => _abrirModelo('agradecimento');

  Future<void> _abrirModelo(String chave) async {
    if (PhoneNormalizer.paraWhatsapp(_cliente.whatsapp) == null) {
      if (!mounted) return;
      final editar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('WhatsApp inválido'),
          content: const Text(
            'Esta cliente ainda não possui um número de WhatsApp válido.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Editar número'),
            ),
          ],
        ),
      );
      if (editar == true) await _editarCliente();
      return;
    }
    try {
      final comercioId = SessionController.instance.usuario!.comercioId;
      final resultados = await Future.wait([
        ModelosMensagensRepository().porChave(comercioId, chave),
        ConfiguracoesRepository().carregar(comercioId),
        ConfiguracaoComercialRepository().carregar(comercioId),
        PagamentoRepository().carregarConfiguracao(),
      ]);
      final modelo = resultados[0] as ModeloMensagem;
      final comercio = resultados[1] as ConfiguracaoComercio;
      final local = resultados[2] as ConfiguracaoComercial;
      final pagamento = resultados[3] as ConfiguracaoPagamento;
      final agora = DateTime.now();
      final dados = DadosMensagem(
        cliente: _cliente.nome,
        salao: comercio.nomeExibicao,
        data:
            '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year}',
        hora:
            '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}',
        profissional: _cliente.profissional,
        pix: pagamento.chavePix,
        nomeRecebedor: pagamento.nomeRecebedor,
        banco: pagamento.banco,
        endereco: local.enderecoCompleto,
        pontoReferencia: local.pontoReferencia,
        linkRota: local.uriRota.toString(),
        telefoneSalao: comercio.telefone,
      );
      final mensagem = const MensagemService().montar(modelo.texto, dados);
      if (!mounted) return;
      await mostrarRevisaoMensagem(
        context,
        titulo: modelo.nome,
        mensagem: mensagem,
        telefone: _cliente.whatsapp,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível preparar a mensagem.'),
          ),
        );
      }
    }
  }

  Future<void> _abrirAgenda() async {
    await Navigator.push(
      context,
      AppRoutes.material(builder: (_) => AgendaPage(clienteInicial: _cliente)),
    );
  }

  Future<void> _abrirCliente360() async {
    await Navigator.push(
      context,
      AppRoutes.material(
        builder: (_) => Cliente360DetalhePage(clienteId: _cliente.id),
      ),
    );
  }

  Future<void> _abrirAnamnese() async {
    await Navigator.push(
      context,
      AppRoutes.material(
        builder: (_) =>
            AnamnesePage(clienteId: _cliente.id, nomeCliente: _cliente.nome),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _corFundo,
      appBar: AppBar(
        backgroundColor: _corFundo,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _cliente.nome,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: _textoEscuro,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Editar cliente',
            onPressed: _editarCliente,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (valor) {
              if (valor == 'excluir') {
                _excluirCliente();
              }
            },
            itemBuilder: (_) {
              return const [
                PopupMenuItem(
                  value: 'excluir',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Color(0xFFD64D64)),
                      SizedBox(width: 10),
                      Text('Excluir cliente'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        child: Column(
          children: [
            CircleAvatar(
              radius: 45,
              backgroundColor: _corPrincipal.withValues(alpha: 0.12),
              child: Text(
                _iniciais(_cliente.nome),
                style: const TextStyle(
                  fontSize: 25,
                  color: _corPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 13),
            Text(
              _cliente.nome,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: _textoEscuro,
              ),
            ),
            const SizedBox(height: 5),
            Text(_cliente.whatsapp, style: const TextStyle(color: _textoClaro)),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'AÇÕES DA CLIENTE',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AcaoCliente(
                    titulo: 'WhatsApp',
                    icone: Icons.chat_outlined,
                    onTap: _abrirWhatsApp,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AcaoCliente(
                    titulo: 'Agendar',
                    icone: Icons.calendar_month_outlined,
                    onTap: _abrirAgenda,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(
                        Icons.event_available_outlined,
                        size: 18,
                      ),
                      label: const Text('Confirmar horário'),
                      onPressed: () => _abrirModelo('confirmacao_agendamento'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.alarm_outlined, size: 18),
                      label: const Text('Lembrete'),
                      onPressed: () => _abrirModelo('lembrete_horario'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.pix, size: 18),
                      label: const Text('Enviar Pix'),
                      onPressed: () => _abrirModelo('envio_pix'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Enviar endereço'),
                      onPressed: () => _abrirModelo('envio_endereco'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.favorite_outline, size: 18),
                      label: const Text('Agradecimento'),
                      onPressed: () => _abrirModelo('agradecimento'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.event_repeat_outlined, size: 18),
                      label: const Text('Novo agendamento'),
                      onPressed: () => _abrirModelo('convite_novo_agendamento'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _AcaoCliente(
              titulo: 'Visão 360°',
              icone: Icons.contact_page_outlined,
              onTap: _abrirCliente360,
            ),
            const SizedBox(height: 10),
            _InfoClienteCard(
              titulo: 'Contato e aniversário',
              valor:
                  [
                    if (_cliente.telefone.isNotEmpty) _cliente.telefone,
                    if (_cliente.email.isNotEmpty) _cliente.email,
                    if (_cliente.dataNascimento != null)
                      'Aniversário: ${_cliente.dataNascimento!.day.toString().padLeft(2, '0')}/${_cliente.dataNascimento!.month.toString().padLeft(2, '0')}',
                  ].isEmpty
                  ? 'Nenhum dado adicional'
                  : [
                      if (_cliente.telefone.isNotEmpty) _cliente.telefone,
                      if (_cliente.email.isNotEmpty) _cliente.email,
                      if (_cliente.dataNascimento != null)
                        'Aniversário: ${_cliente.dataNascimento!.day.toString().padLeft(2, '0')}/${_cliente.dataNascimento!.month.toString().padLeft(2, '0')}',
                    ].join(' • '),
              icone: Icons.contact_phone_outlined,
            ),
            const SizedBox(height: 10),
            _InfoClienteCard(
              titulo: 'Consentimentos',
              valor:
                  'WhatsApp: ${_cliente.consentimentoWhatsapp ? 'sim' : 'não'} • Marketing: ${_cliente.consentimentoMarketing ? 'sim' : 'não'}',
              icone: Icons.verified_user_outlined,
            ),
            const SizedBox(height: 10),
            _InfoClienteCard(
              titulo: 'Profissional principal',
              valor: _cliente.profissional,
              icone: Icons.badge_outlined,
            ),
            const SizedBox(height: 10),
            _InfoClienteCard(
              titulo: 'Último serviço',
              valor: _cliente.ultimoServico,
              icone: Icons.content_cut,
            ),
            const SizedBox(height: 10),
            _InfoClienteCard(
              titulo: 'Histórico',
              valor:
                  '${_cliente.totalAtendimentos} atendimentos • '
                  'R\$ ${_cliente.totalGasto.toStringAsFixed(2)} gastos',
              icone: Icons.history,
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _abrirAnamnese,
              child: const _InfoClienteCard(
                titulo: 'Ficha de anamnese',
                valor: 'Abrir ou preencher ficha',
                icone: Icons.assignment_outlined,
                alerta: true,
              ),
            ),
            const SizedBox(height: 10),
            _InfoClienteCard(
              titulo: 'Observações',
              valor: _cliente.observacoes.isEmpty
                  ? 'Nenhuma observação cadastrada'
                  : _cliente.observacoes,
              icone: Icons.notes_outlined,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _excluirCliente,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir cliente'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD64D64),
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: Color(0xFFE7A7B2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(' ')
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) {
      return '?';
    }

    if (partes.length == 1) {
      return partes.first[0].toUpperCase();
    }

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }
}

class _AcaoCliente extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final VoidCallback onTap;

  const _AcaoCliente({
    required this.titulo,
    required this.icone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const corPrincipal = Color(0xFF70569A);

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icone),
      label: Text(titulo),
      style: OutlinedButton.styleFrom(
        foregroundColor: corPrincipal,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Color(0xFFB69ED1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _InfoClienteCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final bool alerta;

  const _InfoClienteCard({
    required this.titulo,
    required this.valor,
    required this.icone,
    this.alerta = false,
  });

  @override
  Widget build(BuildContext context) {
    final cor = alerta ? const Color(0xFFE58A25) : const Color(0xFF70569A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8E1EE)),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icone, color: cor),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF766A85),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2140),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF968AA5)),
        ],
      ),
    );
  }
}

class _ClientesVazio extends StatelessWidget {
  final bool possuiPesquisa;

  const _ClientesVazio({required this.possuiPesquisa});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.people_outline,
              size: 70,
              color: Color(0xFFB6A9C3),
            ),
            const SizedBox(height: 16),
            Text(
              possuiPesquisa
                  ? 'Nenhum cliente encontrado'
                  : 'Nenhum cliente cadastrado',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2140),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              possuiPesquisa
                  ? 'Altere a pesquisa e tente novamente.'
                  : 'Toque em “Novo cliente” para cadastrar o primeiro.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF766A85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroClientes extends StatelessWidget {
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const _ErroClientes({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 65, color: Color(0xFFD64D64)),
            const SizedBox(height: 14),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF2D2140)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF70569A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
