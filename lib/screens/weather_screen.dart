import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/connection_provider.dart';
import 'package:provider/provider.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final _api = null; // unused
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<ConnectionProvider>().api;
    if (!api.isConnected) { setState(() => _loading = false); return; }
    try {
      final d = await api.getBme280(); // Use BME280 data instead of weather API
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weather')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null || _data!.containsKey('error')
              ? const Center(child: Text('Failed to load weather'))
              : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final hourly = _data!['hourly'] as Map<String, dynamic>?;
    final daily = _data!['daily'] as Map<String, dynamic>?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hourly != null) _hourlyChart(hourly),
        const SizedBox(height: 16),
        if (daily != null) _dailyForecast(daily),
      ],
    );
  }

  Widget _hourlyChart(Map<String, dynamic> hourly) {
    final temps = (hourly['temperature_2m'] as List?)?.cast<num>() ?? [];
    final times = (hourly['time'] as List?)?.cast<String>() ?? [];
    // Show next 48 hours
    final n = temps.length.clamp(0, 48);
    final spots = <FlSpot>[];
    for (var i = 0; i < n; i++) {
      spots.add(FlSpot(i.toDouble(), temps[i].toDouble()));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hourly Temperature', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: LineChart(LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 24, interval: 6,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= times.length) return const SizedBox();
                      return Text(times[i].substring(11, 16), style: const TextStyle(fontSize: 9));
                    },
                  )),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots, isCurved: true, color: Colors.orange,
                    dotData: const FlDotData(show: false), barWidth: 2,
                    belowBarData: BarAreaData(show: true, color: Colors.orange.withValues(alpha: 0.1)),
                  ),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyForecast(Map<String, dynamic> daily) {
    final dates = (daily['time'] as List?)?.cast<String>() ?? [];
    final maxT = (daily['temperature_2m_max'] as List?)?.cast<num>() ?? [];
    final minT = (daily['temperature_2m_min'] as List?)?.cast<num>() ?? [];
    final codes = (daily['weather_code'] as List?)?.cast<num>() ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('7-Day Forecast', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...List.generate(dates.length, (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text(dates[i].substring(5), style: const TextStyle(fontSize: 13))),
                  Icon(_weatherIcon(codes.length > i ? codes[i].toInt() : 0), size: 20),
                  const SizedBox(width: 8),
                  Text(_weatherLabel(codes.length > i ? codes[i].toInt() : 0), style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  Text('${minT.length > i ? minT[i] : "--"}°', style: const TextStyle(color: Colors.blue, fontSize: 13)),
                  const Text(' / ', style: TextStyle(fontSize: 12)),
                  Text('${maxT.length > i ? maxT[i] : "--"}°', style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code <= 3) return Icons.cloud;
    if (code <= 49) return Icons.foggy;
    if (code <= 69) return Icons.grain;
    if (code <= 79) return Icons.ac_unit;
    if (code <= 99) return Icons.thunderstorm;
    return Icons.cloud;
  }

  String _weatherLabel(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 49) return 'Fog';
    if (code <= 59) return 'Drizzle';
    if (code <= 69) return 'Rain';
    if (code <= 79) return 'Snow';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }
}
