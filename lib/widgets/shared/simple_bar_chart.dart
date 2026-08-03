import 'package:flutter/material.dart';

class BarChartData {
  final String label;
  final double value;

  BarChartData(this.label, this.value);
}

class SimpleBarChart extends StatelessWidget {
  final List<BarChartData> data;
  final double height;
  final Color color;

  const SimpleBarChart({
    super.key,
    required this.data,
    this.height = 150,
    this.color = const Color(0xFF6D4ACB),
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Sem dados suficientes para o gráfico',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final double maxValue = data
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);
    final double safeMaxValue = maxValue == 0 ? 1 : maxValue;

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final barHeight = (item.value / safeMaxValue) * (height - 40);
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                item.value.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Container(
                width: 24,
                height: barHeight > 0 ? barHeight : 2,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
