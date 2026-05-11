import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// MPPT charts: battery V/A, panel V/W, battery power, solar yield
class MpptCharts extends StatelessWidget {
  final List<Map<String, dynamic>> data; // time-series from Media-AI
  const MpptCharts({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No MPPT data'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _chartCard('Battery Voltage & Current', _batteryVAChart()),
        const SizedBox(height: 12),
        _chartCard('Panel Voltage & Power', _panelChart()),
        const SizedBox(height: 12),
        _chartCard('Battery Power', _batteryPowerChart()),
        const SizedBox(height: 12),
        _chartCard('Solar Yield', _solarYieldChart()),
      ],
    );
  }

  Widget _chartCard(String title, Widget chart) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            SizedBox(height: 180, child: chart),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _spots(String key) {
    final s = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final v = data[i][key];
      if (v != null) s.add(FlSpot(i.toDouble(), (v is num ? v : double.tryParse('$v') ?? 0).toDouble()));
    }
    return s;
  }

  Widget _batteryVAChart() {
    return LineChart(LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(axisNameWidget: Text('V', style: TextStyle(fontSize: 10)), sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        rightTitles: AxisTitles(axisNameWidget: Text('A', style: TextStyle(fontSize: 10)), sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        _line(_spots('battery_voltage'), Colors.blue, 'V'),
        _line(_spots('battery_current'), Colors.orange, 'A'),
      ],
    ));
  }

  Widget _panelChart() {
    return LineChart(LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(axisNameWidget: Text('V', style: TextStyle(fontSize: 10)), sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        rightTitles: AxisTitles(axisNameWidget: Text('W', style: TextStyle(fontSize: 10)), sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        _line(_spots('solar_voltage'), Colors.amber, 'V'),
        _line(_spots('solar_power'), Colors.green, 'W'),
      ],
    ));
  }

  Widget _batteryPowerChart() {
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final v = _d(data[i]['battery_voltage']) * _d(data[i]['battery_current']);
      spots.add(FlSpot(i.toDouble(), v));
    }
    return LineChart(LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(spots: spots, isCurved: true, color: Colors.teal, belowBarData: BarAreaData(show: true, color: Colors.teal.withValues(alpha: 0.15)), dotData: const FlDotData(show: false), barWidth: 2),
      ],
    ));
  }

  Widget _solarYieldChart() {
    final spots = _spots('solar_power');
    return BarChart(BarChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: spots.map((s) => BarChartGroupData(x: s.x.toInt(), barRods: [
        BarChartRodData(toY: s.y, color: Colors.amber, width: 6, borderRadius: BorderRadius.circular(2)),
      ])).toList(),
    ));
  }

  LineChartBarData _line(List<FlSpot> spots, Color color, String label) {
    return LineChartBarData(spots: spots, isCurved: true, color: color, dotData: const FlDotData(show: false), barWidth: 2);
  }

  double _d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
}
