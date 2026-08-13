import 'package:flutter/material.dart';

import '../core/helpers/app_formatters.dart';
import '../models/domain/centro_resultado.dart';
import '../repositories/centro_resultado_repository.dart';
import 'assistente_gestao_page.dart';
import '../services/management_insight_engine.dart';

class GestaoFinanceiraPage extends StatefulWidget {
  final CentroResultado centroInicial;
  final bool compacto;

  const GestaoFinanceiraPage({
    super.key,
    this.centroInicial = CentroResultado.geral,
    this.compacto = false,
  });

  @override
  State<GestaoFinanceiraPage> createState() => _GestaoFinanceiraPageState();
}

class _GestaoFinanceiraPageState extends State<GestaoFinanceiraPage> {
  final repository = CentroResultadoRepository();
  late CentroResultado centro = widget.centroInicial;
  var periodoTipo = PeriodoGestaoTipo.mes;
  PeriodoGestao? periodoPersonalizado;
  late Future<ResumoCentroResultado> future = _load();

  PeriodoGestao get periodo => periodoTipo == PeriodoGestaoTipo.personalizado
      ? periodoPersonalizado!
      : PeriodoGestao.doTipo(periodoTipo);
  Future<ResumoCentroResultado> _load() => repository.resumo(centro, periodo);
  void reload() => setState(() => future = _load());

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<ResumoCentroResultado>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Não foi possível carregar: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _content(snapshot.data!);
      },
    );
    if (widget.compacto) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão financeira'),
        actions: [
          IconButton(
            tooltip: 'Assistente de Gestão',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssistenteGestaoPage(contexto: centro),
              ),
            ),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _content(ResumoCentroResultado summary) => RefreshIndicator(
    onRefresh: () async => reload(),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<CentroResultado>(
          segments: const [
            ButtonSegment(value: CentroResultado.geral, label: Text('GERAL')),
            ButtonSegment(value: CentroResultado.salao, label: Text('SALÃO')),
            ButtonSegment(value: CentroResultado.loja, label: Text('LOJA')),
          ],
          selected: {centro},
          onSelectionChanged: (value) {
            centro = value.single;
            reload();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<PeriodoGestaoTipo>(
          initialValue: periodoTipo,
          decoration: const InputDecoration(labelText: 'Período'),
          items: const [
            DropdownMenuItem(
              value: PeriodoGestaoTipo.hoje,
              child: Text('Hoje'),
            ),
            DropdownMenuItem(
              value: PeriodoGestaoTipo.seteDias,
              child: Text('7 dias'),
            ),
            DropdownMenuItem(value: PeriodoGestaoTipo.mes, child: Text('Mês')),
            DropdownMenuItem(
              value: PeriodoGestaoTipo.mesAnterior,
              child: Text('Mês anterior'),
            ),
            DropdownMenuItem(
              value: PeriodoGestaoTipo.personalizado,
              child: Text('Personalizado'),
            ),
          ],
          onChanged: (value) async {
            if (value == null) return;
            if (value == PeriodoGestaoTipo.personalizado) {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(DateTime.now().year + 2),
              );
              if (range == null) return;
              periodoPersonalizado = PeriodoGestao.personalizado(
                range.start,
                range.end,
              );
            }
            periodoTipo = value;
            reload();
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric('Faturamento', summary.faturamento, summary, 'faturamento'),
            _metric('Recebido', summary.recebido, summary, 'recebido'),
            _metric('A receber', summary.aReceber, summary, 'a_receber'),
            _metric('Despesas', summary.despesas, summary, 'despesas'),
            _metric('Resultado', summary.resultado, summary, 'resultado'),
            _metric(
              'Saldo realizado',
              summary.saldoRealizado,
              summary,
              'saldo',
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Resultado considera faturamento, custos, comissões e despesas. '
          'Saldo realizado considera somente entradas recebidas e saídas pagas.',
        ),
        if (centro == CentroResultado.geral) ...[
          const SizedBox(height: 16),
          _composition('Salão', summary.salao, CentroResultado.salao),
          _composition('Loja', summary.loja, CentroResultado.loja),
          _composition(
            'Administrativo/Geral',
            summary.administrativo,
            CentroResultado.geral,
          ),
          _composition(
            'Não classificados',
            summary.naoClassificado,
            CentroResultado.naoClassificado,
          ),
        ],
        if (summary.dadosAusentes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Dados incompletos:\n${summary.dadosAusentes.map((e) => '• $e').join('\n')}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Insights',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        for (final insight in ManagementInsightEngine.gerar(atual: summary))
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(insight.titulo),
            subtitle: Text(
              '${insight.explicacao}\nCálculo: ${insight.formula}',
            ),
          ),
      ],
    ),
  );

  Widget _metric(
    String label,
    double value,
    ResumoCentroResultado summary,
    String type,
  ) => SizedBox(
    width: 164,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CentroResultadoDetalhePage(
              titulo: label,
              centro: centro,
              periodo: summary.periodo,
              tipo: type,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 6),
              Text(
                AppFormatters.moeda(value),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _composition(String label, double value, CentroResultado target) =>
      ListTile(
        title: Text(label),
        trailing: Text(AppFormatters.moeda(value)),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CentroResultadoDetalhePage(
              titulo: label,
              centro: target,
              periodo: periodo,
            ),
          ),
        ),
      );
}

class CentroResultadoDetalhePage extends StatefulWidget {
  final String titulo;
  final CentroResultado centro;
  final PeriodoGestao periodo;
  final String? tipo;

  const CentroResultadoDetalhePage({
    super.key,
    required this.titulo,
    required this.centro,
    required this.periodo,
    this.tipo,
  });

  @override
  State<CentroResultadoDetalhePage> createState() =>
      _CentroResultadoDetalhePageState();
}

class _CentroResultadoDetalhePageState
    extends State<CentroResultadoDetalhePage> {
  final repository = CentroResultadoRepository();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.titulo)),
    body: FutureBuilder<List<DetalheCentroResultado>>(
      future: repository.movimentos(
        centro: widget.centro,
        periodo: widget.periodo,
        tipo: widget.tipo,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text('Nenhum lançamento financeiro neste recorte.'),
          );
        }
        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final item = snapshot.data![index];
            return ListTile(
              title: Text(item.titulo),
              subtitle: Text(
                '${item.fonte} • ${item.status} • ${item.data.toLocal()}',
              ),
              trailing: Text(AppFormatters.moeda(item.valor)),
              onTap: widget.centro == CentroResultado.naoClassificado
                  ? () => _classify(item)
                  : null,
            );
          },
        );
      },
    ),
  );

  Future<void> _classify(DetalheCentroResultado item) async {
    final result = await showDialog<CentroResultado>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Classificar lançamento'),
        children: [
          for (final center in const [
            CentroResultado.salao,
            CentroResultado.loja,
            CentroResultado.geral,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, center),
              child: Text(center.name.toUpperCase()),
            ),
        ],
      ),
    );
    if (result == null) return;
    await repository.classificarMovimento(item.id, result);
    if (mounted) setState(() {});
  }
}
