// models.dart — Modelos de dados do DPS Meter

class PlayerStats {
  final int id;
  final String name;
  final String className;
  final int totalDamage;
  final int totalHeal;
  final int totalHits;
  final int totalCrits;
  final int totalMisses;
  final double currentDps;
  final double currentHps;
  final int maxHit;
  final double critRate;

  const PlayerStats({
    required this.id,
    required this.name,
    required this.className,
    required this.totalDamage,
    required this.totalHeal,
    required this.totalHits,
    required this.totalCrits,
    required this.totalMisses,
    required this.currentDps,
    required this.currentHps,
    required this.maxHit,
    required this.critRate,
  });

  factory PlayerStats.fromJson(Map<String, dynamic> json) {
    return PlayerStats(
      id:           json['id']            as int,
      name:         json['name']          as String,
      className:    (json['class_name']    as String?) ?? '',
      totalDamage:  json['total_damage']  as int,
      totalHeal:    json['total_heal']    as int,
      totalHits:    json['total_hits']    as int,
      totalCrits:   json['total_crits']   as int,
      totalMisses:  json['total_misses']  as int,
      currentDps:   (json['current_dps'] as num).toDouble(),
      currentHps:   (json['current_hps'] as num).toDouble(),
      maxHit:       json['max_hit']       as int,
      critRate:     (json['crit_rate']    as num).toDouble(),
    );
  }

  String get formattedDps {
    if (currentDps >= 1000) return '${(currentDps / 1000).toStringAsFixed(1)}k';
    return currentDps.toStringAsFixed(0);
  }

  String get formattedDamage {
    if (totalDamage >= 1000000) return '${(totalDamage / 1000000).toStringAsFixed(2)}M';
    if (totalDamage >= 1000)    return '${(totalDamage / 1000).toStringAsFixed(1)}k';
    return totalDamage.toString();
  }
}

class DpsSnapshot {
  final double sessionDuration;
  final int totalDamage;
  final List<PlayerStats> players;
  final Map<int, List<DpsPoint>> dpsHistory;

  const DpsSnapshot({
    required this.sessionDuration,
    required this.totalDamage,
    required this.players,
    required this.dpsHistory,
  });

  factory DpsSnapshot.fromJson(Map<String, dynamic> json) {
    final players = (json['players'] as List)
        .map((p) => PlayerStats.fromJson(p as Map<String, dynamic>))
        .toList();

    final histRaw = json['dps_history'] as Map<String, dynamic>? ?? {};
    final history = <int, List<DpsPoint>>{};
    for (final entry in histRaw.entries) {
      final pid = int.tryParse(entry.key) ?? 0;
      history[pid] = (entry.value as List)
          .map((e) => DpsPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return DpsSnapshot(
      sessionDuration: (json['session_duration'] as num).toDouble(),
      totalDamage:     json['total_damage'] as int,
      players:         players,
      dpsHistory:      history,
    );
  }

  static DpsSnapshot empty() => const DpsSnapshot(
    sessionDuration: 0,
    totalDamage: 0,
    players: [],
    dpsHistory: {},
  );

  String get formattedDuration {
    final m = (sessionDuration / 60).floor();
    final s = (sessionDuration % 60).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class DpsPoint {
  final double time;
  final double dps;
  final double hps;

  const DpsPoint({required this.time, required this.dps, required this.hps});

  factory DpsPoint.fromJson(Map<String, dynamic> json) => DpsPoint(
    time: (json['t']   as num).toDouble(),
    dps:  (json['dps'] as num).toDouble(),
    hps:  (json['hps'] as num).toDouble(),
  );
}
