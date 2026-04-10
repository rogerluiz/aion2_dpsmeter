// player_detail.dart — Tela de detalhes por jogador

import 'package:flutter/material.dart';
import 'models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paleta (reutiliza as constantes do main.dart)
const _kBg        = Color(0xFF0C0D0F);
const _kBgBar     = Color(0xFF111215);
const _kBorder    = Color(0x1AFFFFFF);
const _kFaint     = Color(0x0AFFFFFF);
const _kText      = Color(0xE6FFFFFF);
const _kMuted     = Color(0x8CFFFFFF);
const _kDim       = Color(0x40FFFFFF);

const _playerColors = [
  Color(0xFF4FC3F7),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFE57373),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
];

// ─────────────────────────────────────────────────────────────────────────────

class PlayerDetailScreen extends StatelessWidget {
  final PlayerStats player;
  final int colorIndex;
  final VoidCallback onBack;

  const PlayerDetailScreen({
    super.key,
    required this.player,
    required this.colorIndex,
    required this.onBack,
  });

  Color get _color => _playerColors[colorIndex % _playerColors.length];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Header bar ─────────────────────────────────────────────
      _DetailHeader(player: player, color: _color, onBack: onBack),
      // ── Scrollable body ────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top stats
              _TopStats(player: player, color: _color),
              const SizedBox(height: 8),
              // Combat flags row
              _FlagsRow(player: player, color: _color),
              const SizedBox(height: 10),
              // Skill breakdown
              if (player.skills.isNotEmpty) ...[
                _SectionLabel('Skills'),
                const SizedBox(height: 4),
                _SkillTable(player: player, color: _color),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Sem dados de skill ainda...',
                      style: TextStyle(color: _kDim, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ─── Detail header bar ─────────────────────────────────────────────────────
class _DetailHeader extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  final VoidCallback onBack;
  const _DetailHeader({required this.player, required this.color, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: _kBgBar,
        border: Border(bottom: BorderSide(color: _kFaint, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        // Botão voltar
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(3),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('‹', style: TextStyle(fontSize: 16, color: _kMuted)),
          ),
        ),
        const SizedBox(width: 6),
        // Barra de cor + nome
        Container(width: 3, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            player.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Badge de classe
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            player.className.isEmpty ? '?' : player.className,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ]),
    );
  }
}

// ─── Top stats grid ────────────────────────────────────────────────────────
class _TopStats extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  const _TopStats({required this.player, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _StatCard(label: 'DPS',      value: player.formattedDps,    color: color),
      const SizedBox(width: 6),
      _StatCard(label: 'Dano Total', value: player.formattedDamage, color: color),
      const SizedBox(width: 6),
      _StatCard(label: 'Max Hit',  value: _fmt(player.maxHit),    color: color),
      const SizedBox(width: 6),
      _StatCard(label: 'Hits',     value: '${player.totalHits}',  color: color),
    ]);
  }

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.12), width: 0.5),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 8, color: _kDim, letterSpacing: 0.4)),
      ]),
    ),
  );
}

// ─── Combat flags row ──────────────────────────────────────────────────────
class _FlagsRow extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  const _FlagsRow({required this.player, required this.color});

  @override
  Widget build(BuildContext context) {
    final critPct = player.critRate * 100;
    final baPct   = player.backAttackRate * 100;
    final perfPct = player.perfectRate * 100;
    final dblPct  = player.doubleRate * 100;
    final paryPct = player.parryRate * 100;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _kFaint, width: 0.5),
      ),
      child: Row(children: [
        _FlagStat(label: 'Crit',        value: critPct, color: const Color(0xFFFFB74D)),
        _FlagStat(label: 'Back Atk',    value: baPct,   color: const Color(0xFF4FC3F7)),
        _FlagStat(label: 'Perfect',     value: perfPct, color: const Color(0xFF81C784)),
        _FlagStat(label: 'Double',      value: dblPct,  color: const Color(0xFFBA68C8)),
        _FlagStat(label: 'Parry',       value: paryPct, color: const Color(0xFFE57373)),
      ]),
    );
  }
}

class _FlagStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _FlagStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(
        '${value.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: value > 0.1 ? color : _kDim,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 8, color: _kDim, letterSpacing: 0.4)),
    ]),
  );
}

// ─── Section label ─────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 9, color: _kDim, letterSpacing: 1.0),
  );
}

// ─── Skill breakdown table ─────────────────────────────────────────────────
class _SkillTable extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  const _SkillTable({required this.player, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        child: Row(children: const [
          Expanded(flex: 5, child: _SH('Skill')),
          Expanded(flex: 2, child: _SH('Hits', right: true)),
          Expanded(flex: 2, child: _SH('Crit%', right: true)),
          Expanded(flex: 3, child: _SH('Total', right: true)),
          Expanded(flex: 3, child: _SH('Max', right: true)),
        ]),
      ),
      // Rows
      ...player.skills.map((sk) => _SkillRow(skill: sk, color: color)),
    ]);
  }
}

class _SH extends StatelessWidget {
  final String text;
  final bool right;
  const _SH(this.text, {this.right = false});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: const TextStyle(fontSize: 8, color: _kDim, letterSpacing: 0.4),
  );
}

class _SkillRow extends StatelessWidget {
  final SkillStat skill;
  final Color color;
  const _SkillRow({required this.skill, required this.color});

  @override
  Widget build(BuildContext context) {
    final critHot = skill.critRate > 0.25;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kFaint, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Text(
            skill.name,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(flex: 2, child: Text(
          '${skill.hits}',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11, color: _kMuted),
        )),
        Expanded(flex: 2, child: Text(
          '${(skill.critRate * 100).toStringAsFixed(0)}%',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            color: critHot ? const Color(0xFFFFB74D) : _kDim,
          ),
        )),
        Expanded(flex: 3, child: Text(
          skill.formattedTotalDmg,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11, color: _kMuted),
        )),
        Expanded(flex: 3, child: Text(
          _fmt(skill.maxDmg),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 11, color: _kDim),
        )),
      ]),
    );
  }

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}
