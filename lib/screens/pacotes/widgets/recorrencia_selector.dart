import 'package:flutter/material.dart';
import '../../../models/domain/pacote_servico.dart';

class RecorrenciaSelector extends StatefulWidget {
  final ValueChanged<FrequenciaAgendamentoPacote> onFrequenciaChanged;
  final ValueChanged<int> onIntervaloChanged;

  const RecorrenciaSelector({
    super.key,
    required this.onFrequenciaChanged,
    required this.onIntervaloChanged,
  });

  @override
  State<RecorrenciaSelector> createState() => _RecorrenciaSelectorState();
}

class _RecorrenciaSelectorState extends State<RecorrenciaSelector> {
  FrequenciaAgendamentoPacote _frequencia = FrequenciaAgendamentoPacote.semanal;
  int _intervalo = 1;

  void _notify() {
    widget.onFrequenciaChanged(_frequencia);
    widget.onIntervaloChanged(_intervalo);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Recorrência',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<FrequenciaAgendamentoPacote>(
          initialValue: _frequencia,
          decoration: const InputDecoration(
            labelText: 'Frequência',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: FrequenciaAgendamentoPacote.dias,
              child: Text('Dias'),
            ),
            DropdownMenuItem(
              value: FrequenciaAgendamentoPacote.semanal,
              child: Text('Semanal'),
            ),
            DropdownMenuItem(
              value: FrequenciaAgendamentoPacote.mensal,
              child: Text('Mensal'),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _frequencia = val);
              _notify();
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: _intervalo.toString(),
          decoration: const InputDecoration(
            labelText: 'Intervalo',
            border: OutlineInputBorder(),
            suffixText: 'vez(es)',
          ),
          keyboardType: TextInputType.number,
          onChanged: (val) {
            final parsed = int.tryParse(val);
            if (parsed != null && parsed > 0) {
              _intervalo = parsed;
              _notify();
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          _frequencia == FrequenciaAgendamentoPacote.dias
              ? 'A cada $_intervalo dia(s)'
              : _frequencia == FrequenciaAgendamentoPacote.semanal
              ? 'A cada $_intervalo semana(s)'
              : 'A cada $_intervalo mês(es)',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ],
    );
  }
}
