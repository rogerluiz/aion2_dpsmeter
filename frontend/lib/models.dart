// models.dart — Modelos de dados do DPS Meter

class SkillStat {
  final int code;
  final String name;
  final int hits;
  final int crits;
  final int totalDmg;
  final int maxDmg;
  final double critRate;

  const SkillStat({
    required this.code,
    required this.name,
    required this.hits,
    required this.crits,
    required this.totalDmg,
    required this.maxDmg,
    required this.critRate,
  });

  factory SkillStat.fromJson(Map<String, dynamic> json) => SkillStat(
    code:     json['code']      as int,
    name:     json['name']      as String,
    hits:     json['hits']      as int,
    crits:    json['crits']     as int,
    totalDmg: json['total_dmg'] as int,
    maxDmg:   json['max_dmg']   as int,
    critRate: (json['crit_rate'] as num).toDouble(),
  );

  String get formattedTotalDmg {
    if (totalDmg >= 1000000) return '${(totalDmg / 1000000).toStringAsFixed(2)}M';
    if (totalDmg >= 1000)    return '${(totalDmg / 1000).toStringAsFixed(1)}k';
    return totalDmg.toString();
  }
}

class PlayerStats {
  final int id;
  final String name;
  final String className;
  final int totalDamage;
  final int totalHeal;
  final int totalHits;
  final int totalCrits;
  final int totalMisses;
  final int backAttacks;
  final int perfects;
  final int doubles;
  final int parries;
  final double currentDps;
  final double currentHps;
  final int maxHit;
  final double critRate;
  final List<SkillStat> skills;

  const PlayerStats({
    required this.id,
    required this.name,
    required this.className,
    required this.totalDamage,
    required this.totalHeal,
    required this.totalHits,
    required this.totalCrits,
    required this.totalMisses,
    required this.backAttacks,
    required this.perfects,
    required this.doubles,
    required this.parries,
    required this.currentDps,
    required this.currentHps,
    required this.maxHit,
    required this.critRate,
    required this.skills,
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
      backAttacks:  (json['back_attacks'] as int?) ?? 0,
      perfects:     (json['perfects']     as int?) ?? 0,
      doubles:      (json['doubles']      as int?) ?? 0,
      parries:      (json['parries']      as int?) ?? 0,
      currentDps:   (json['current_dps'] as num).toDouble(),
      currentHps:   (json['current_hps'] as num).toDouble(),
      maxHit:       json['max_hit']       as int,
      critRate:     (json['crit_rate']    as num).toDouble(),
      skills:       (json['skills'] as List? ?? [])
                      .map((s) => SkillStat.fromJson(s as Map<String, dynamic>))
                      .toList(),
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

  double get backAttackRate => totalHits > 0 ? backAttacks / totalHits : 0;
  double get perfectRate    => totalHits > 0 ? perfects    / totalHits : 0;
  double get doubleRate     => totalHits > 0 ? doubles     / totalHits : 0;
  double get parryRate      => totalHits > 0 ? parries     / totalHits : 0;
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
