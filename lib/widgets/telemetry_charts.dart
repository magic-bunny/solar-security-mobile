import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// MPPT + BME280 history charts from get_history data.
/// Fields: V, I, VPV, PPV (MPPT), temperature, humidity, pressure (BME280)
class TelemetryCharts extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const TelemetryCharts({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No history data'));
    return ListView(padding: const EdgeInsets.all(12), children: [
      _card('Battery Voltage (V)', _chart([_line('V', Colors.blue)])),
      _card('Battery Current (A)', _chart([_line('I', Colors.orange)])),
      _card('Panel Power (W)', _chart([_line('PPV', Colors.green)])),
      _card('Temperature (°C)', _chart([_line('temperature', Colors.red)])),
      _card('Humidity (%)', _chart([_line('humidity', Colors.cyan)])),
      _card('Pressure (hPa)', _chart([_line('pressure', Colors.purple)])),
    ]);
  }

  Widget _card(String title, Widget chart) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        SizedBox(height: 160, child: chart),
      ],
    )),
  );

  Widget _chart(List<LineChartBarData> lines) => LineChart(LineChartData(
    gridData: const FlGridData(show: true, drawVerticalLine: false),
    titlesData: const FlTitlesData(
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    lineBarsData: lines,
  ));

  LineChartBarData _line(String key, Color color) {
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final v = data[i][key];
      if (v != null) spots.add(FlSpot(i.toDouble(), (v as num).toDouble()));
    }
    return LineChartBarData(
      spots: spots, isCurved: true, color: color,
      dotData: const FlDotData(show: false), barWidth: 2,
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
    );
  }
}
