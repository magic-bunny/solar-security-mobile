import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class SolarChart extends StatelessWidget {
  final List<FlSpot> voltageData;
  final List<FlSpot> currentData;
  final List<FlSpot> powerData;

  const SolarChart({super.key, this.voltageData = const [], this.currentData = const [], this.powerData = const []});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solar Power', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: LineChart(LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: const FlTitlesData(show: true),
                lineBarsData: [
                  _line(voltageData, Colors.blue),
                  _line(currentData, Colors.orange),
                  _line(powerData, Colors.green),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
    isCurved: true,
    color: color,
    dotData: const FlDotData(show: false),
    barWidth: 2,
  );
}
