import 'package:flutter/material.dart';

import '../core/routes/app_routes.dart';

import '../services/preferencias_service.dart';
import '../core/theme/studioflow_theme.dart';
import 'cadastro_negocio_page.dart';
import 'dashboard_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  static const Color _roxoPrincipal = Color(0xFF70569A);

  static const Color _roxoVivo = Color(0xFF8B5CF6);

  static const Color _textoEscuro = Color(0xFF2D2140);

  static const Color _textoClaro = Color(0xFF766A85);

  bool _entrando = false;

  void _mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _abrirCadastro() {
    Navigator.push(
      context,
      AppRoutes.material(builder: (_) => const CadastroNegocioPage()),
    );
  }

  StudioFlowTheme _temaPelaChave(String chave) {
    for (final tema in StudioFlowTheme.values) {
      if (tema.chave == chave) {
        return tema;
      }
    }

    return StudioFlowTheme.elegante;
  }

  Future<void> _entrar() async {
    if (_entrando) {
      return;
    }

    setState(() {
      _entrando = true;
    });

    try {
      final possuiCadastro = await PreferenciasService.cadastroConcluido();

      if (!possuiCadastro) {
        if (!mounted) {
          return;
        }

        _mostrarMensagem('Nenhum negócio foi cadastrado ainda.');

        setState(() {
          _entrando = false;
        });

        return;
      }

      final cadastro = await PreferenciasService.carregarCadastro();

      final nomeResponsavel = cadastro['nomeResponsavel'] ?? '';

      final nomeNegocio = cadastro['nomeNegocio'] ?? '';

      final tipoNegocio = cadastro['tipoNegocio'] ?? '';

      final temaChave = cadastro['tema'] ?? 'elegante';

      if (nomeResponsavel.isEmpty || nomeNegocio.isEmpty) {
        if (!mounted) {
          return;
        }

        _mostrarMensagem('O cadastro salvo está incompleto.');

        setState(() {
          _entrando = false;
        });

        return;
      }

      final tema = _temaPelaChave(temaChave);

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        AppRoutes.material(
          builder: (_) => DashboardPage(
            nomeResponsavel: nomeResponsavel,
            nomeNegocio: nomeNegocio,
            tipoNegocio: tipoNegocio,
            tema: tema,
          ),
        ),
        (route) => false,
      );
    } catch (erro) {
      if (!mounted) {
        return;
      }

      _mostrarMensagem('Não foi possível entrar. Tente novamente.');

      setState(() {
        _entrando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height - 85,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),

                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9660F4), Color(0xFF7040D2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: _roxoVivo.withValues(alpha: 0.25),
                          blurRadius: 25,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 65),
                        SizedBox(height: 10),
                        Text(
                          'Gestão inteligente',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  const Text(
                    'StudioFlow',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: _textoEscuro,
                      letterSpacing: -1,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Gestão inteligente para todos os negócios da beleza',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      color: _textoClaro,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Salões • Barbearias • Nails • Estética • SPA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9A8EA7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const Spacer(),
                  FilledButton(
                    onPressed: _entrando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      backgroundColor: _roxoPrincipal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _entrando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Entrar',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),

                  const SizedBox(height: 14),

                  OutlinedButton(
                    onPressed: _entrando ? null : _abrirCadastro,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _roxoPrincipal,
                      minimumSize: const Size.fromHeight(60),
                      side: const BorderSide(color: _roxoVivo, width: 1.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Criar meu negócio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextButton.icon(
                    onPressed: _entrando
                        ? null
                        : () {
                            _mostrarMensagem(
                              'O agendamento online será conectado depois da versão interna.',
                            );
                          },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Sou cliente • Agendar horário'),
                    style: TextButton.styleFrom(
                      foregroundColor: _roxoPrincipal,
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Organize • Automatize • Cresça',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textoClaro, fontSize: 13),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Versão 1.0.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFA69BB3), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
