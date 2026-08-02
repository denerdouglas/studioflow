import 'package:flutter/material.dart';

import '../core/routes/app_routes.dart';

import '../services/preferencias_service.dart';
import '../core/theme/studioflow_theme.dart';
import 'dashboard_premium_page.dart';

class CadastroNegocioPage extends StatefulWidget {
  const CadastroNegocioPage({super.key});

  @override
  State<CadastroNegocioPage> createState() => _CadastroNegocioPageState();
}

class _CadastroNegocioPageState extends State<CadastroNegocioPage> {
  final TextEditingController _nomeNegocioController = TextEditingController();

  final TextEditingController _responsavelController = TextEditingController();

  final TextEditingController _whatsappController = TextEditingController();

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _cidadeController = TextEditingController();

  String _estadoSelecionado = 'SP';
  String _categoriaSelecionada = 'Salão de beleza';

  StudioFlowTheme _temaSelecionado = StudioFlowTheme.elegante;

  bool _salvando = false;

  final List<String> _categorias = const [
    'Salão de beleza',
    'Barbearia',
    'Nail Designer / Manicure',
    'Clínica de estética',
    'Cílios e sobrancelhas',
    'Cabeleireiro',
    'SPA',
    'Espaço infantil',
    'Maquiagem',
    'Massagem',
    'Outro',
  ];

  final List<String> _estados = const [
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO',
  ];

  @override
  void dispose() {
    _nomeNegocioController.dispose();
    _responsavelController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _cidadeController.dispose();
    super.dispose();
  }

  void _alterarCategoria(String categoria) {
    setState(() {
      _categoriaSelecionada = categoria;
      _temaSelecionado = StudioFlowThemeData.sugeridoParaCategoria(categoria);
    });
  }

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), behavior: SnackBarBehavior.floating),
    );
  }

  bool _validarCadastro() {
    if (_nomeNegocioController.text.trim().isEmpty) {
      _mostrarMensagem('Digite o nome do seu negócio.');
      return false;
    }

    if (_responsavelController.text.trim().isEmpty) {
      _mostrarMensagem('Digite o nome do responsável.');
      return false;
    }

    if (_whatsappController.text.trim().isEmpty) {
      _mostrarMensagem('Digite o WhatsApp profissional.');
      return false;
    }

    return true;
  }

  Future<void> _salvarEContinuar() async {
    if (!_validarCadastro() || _salvando) {
      return;
    }

    setState(() {
      _salvando = true;
    });

    final nomeNegocio = _nomeNegocioController.text.trim();

    final nomeResponsavel = _responsavelController.text.trim();

    try {
      await PreferenciasService.salvarCadastro(
        nomeResponsavel: nomeResponsavel,
        nomeNegocio: nomeNegocio,
        tipoNegocio: _categoriaSelecionada,
        tema: _temaSelecionado.chave,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        AppRoutes.material(
          builder: (_) => DashboardPremiumPage(
            nomeResponsavel: nomeResponsavel,
            nomeNegocio: nomeNegocio,
            tipoNegocio: _categoriaSelecionada,
            tema: _temaSelecionado,
          ),
        ),
        (route) => false,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem('Não foi possível salvar o cadastro. Tente novamente.');

      setState(() {
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final corPrincipal = _temaSelecionado.corPrincipal;

    final corSecundaria = _temaSelecionado.corSecundaria;

    return Scaffold(
      backgroundColor: _temaSelecionado.fundo,
      appBar: AppBar(
        backgroundColor: _temaSelecionado.fundo,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Criar meu negócio',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2140),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure seu StudioFlow',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  color: corPrincipal,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Preencha os dados principais e escolha o estilo que mais combina com seu negócio.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Color(0xFF766A85),
                ),
              ),

              const SizedBox(height: 26),

              TextField(
                controller: _nomeNegocioController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: const InputDecoration(
                  labelText: 'Nome do negócio',
                  hintText: 'Exemplo: Rafa Rodrigues Beauty',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: _responsavelController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: const InputDecoration(
                  labelText: 'Nome do responsável',
                  hintText: 'Exemplo: Rafa',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp profissional',
                  hintText: '(11) 99999-9999',
                  prefixIcon: Icon(Icons.chat_outlined),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  hintText: 'contato@seunegocio.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: _cidadeController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Cidade',
                  hintText: 'Exemplo: Barueri',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
              ),

              const SizedBox(height: 15),

              DropdownButtonFormField<String>(
                initialValue: _estadoSelecionado,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                items: _estados.map((estado) {
                  return DropdownMenuItem(value: estado, child: Text(estado));
                }).toList(),
                onChanged: (valor) {
                  if (valor == null) {
                    return;
                  }

                  setState(() {
                    _estadoSelecionado = valor;
                  });
                },
              ),

              const SizedBox(height: 15),

              DropdownButtonFormField<String>(
                initialValue: _categoriaSelecionada,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Categoria do negócio',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categorias.map((categoria) {
                  return DropdownMenuItem(
                    value: categoria,
                    child: Text(categoria, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (valor) {
                  if (valor != null) {
                    _alterarCategoria(valor);
                  }
                },
              ),

              const SizedBox(height: 26),

              const Text(
                'Tema do aplicativo',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2140),
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'A categoria sugere um tema, mas você pode escolher qualquer um.',
                style: TextStyle(fontSize: 13, color: Color(0xFF766A85)),
              ),

              const SizedBox(height: 14),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: StudioFlowTheme.values.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (context, index) {
                  final tema = StudioFlowTheme.values[index];

                  final selecionado = tema == _temaSelecionado;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        setState(() {
                          _temaSelecionado = tema;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selecionado
                              ? tema.corPrincipal.withValues(alpha: 0.13)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selecionado
                                ? tema.corPrincipal
                                : const Color(0xFFE4DDEB),
                            width: selecionado ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              tema.icone,
                              color: tema.corPrincipal,
                              size: 31,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tema.nome,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: selecionado
                                    ? tema.corPrincipal
                                    : const Color(0xFF2D2140),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 28),

              const Text(
                'Prévia',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2140),
                ),
              ),

              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [corPrincipal, corSecundaria],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: corPrincipal.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(_temaSelecionado.icone, color: Colors.white, size: 43),

                    const SizedBox(height: 11),

                    Text(
                      _nomeNegocioController.text.trim().isEmpty
                          ? 'Nome do seu negócio'
                          : _nomeNegocioController.text.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '$_categoriaSelecionada • ${_temaSelecionado.nome}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),

                    if (_responsavelController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Responsável: ${_responsavelController.text.trim()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 28),

              FilledButton.icon(
                onPressed: _salvando ? null : _salvarEContinuar,
                icon: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward),
                label: Text(
                  _salvando ? 'Salvando...' : 'Criar negócio e continuar',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: corPrincipal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(58),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
