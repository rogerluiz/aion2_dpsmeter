// dps_chart.dart — Gráfico de DPS igual ao mockup

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'models.dart';

const _playerColors = [
  Color(0xFF4FC3F7),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFE57373),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
];

class DpsChart extends StatelessWidget {
  final DpsSnapshot snapshot;
  const DpsChart({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final history = snapshot.dpsHistory;
    final players = snapshot.players;

    if (history.isEmpty || players.isEmpty) {
      return const Center(
        child: Text('Sem dados', style: TextStyle(color: Color(0x33FFFFFF), fontSize: 11)),
      );
    }

    final lines = <LineChartBarData>[];
    double maxY = 100;

    for (var i = 0; i < players.length; i++) {
      final pid = players[i].id;
      final pts = history[pid] ?? [];
      if (pts.isEmpty) continue;
      final spots = pts.map((p) => FlSpot(p.time, p.dps)).toList();
      final color = _playerColors[i % _playerColors.length];
      final peak = pts.map((p) => p.dps).fold(0.0, (a, b) => a > b ? a : b);
      if (peak > maxY) maxY = peak;
      lines.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.4,
        color: color,
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: color.withOpacity(0.07)),
      ));
    }

    maxY = maxY * 1.2;

    return LineChart(
      duration: const Duration(milliseconds: 200),
      LineChartData(
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => const FlLine(color: Color(0x0DFFFFFF), strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: maxY / 4,
              getTitlesWidget: (v, _) => Text(
                _fmtDps(v),
                style: const TextStyle(color: Color(0x33FFFFFF), fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}s',
                style: const TextStyle(color: Color(0x26FFFFFF), fontSize: 9),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: lines,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A1C20),
            tooltipBorder: const BorderSide(color: Color(0x1AFFFFFF)),
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final idx = lines.indexOf(s.bar);
              final name = (idx >= 0 && idx < players.length) ? players[idx].name : '';
              return LineTooltipItem(
                '$name\n${_fmtDps(s.y)} DPS',
                TextStyle(color: s.bar.color, fontSize: 10, fontWeight: FontWeight.w500),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _fmtDps(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}
