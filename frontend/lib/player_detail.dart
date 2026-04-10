// player_detail.dart — Janela de detalhes por jogador (920×680)

import 'package:flutter/material.dart';
import 'models.dart';

// ─── Paleta ────────────────────────────────────────────────────────────────────
const _kBg     = Color(0xFF0C0D0F);
const _kBgBar  = Color(0xFF111215);
const _kBgCard = Color(0xFF14161A);
const _kBorder = Color(0x1AFFFFFF);
const _kFaint  = Color(0x0AFFFFFF);
const _kText   = Color(0xE6FFFFFF);
const _kMuted  = Color(0x8CFFFFFF);
const _kDim    = Color(0x40FFFFFF);

const _playerColors = [
  Color(0xFF4FC3F7),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFE57373),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
];

// ─── Tela principal ────────────────────────────────────────────────────────────
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
      _DetailHeader(player: player, color: _color, onBack: onBack),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Painel esquerdo: resumo de stats
            SizedBox(width: 270, child: _LeftPanel(player: player, color: _color)),
            Container(width: 0.5, color: _kFaint),
            // Painel direito: lista de skills
            Expanded(child: _SkillPanel(player: player, color: _color)),
          ],
        ),
      ),
    ]);
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────
class _DetailHeader extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  final VoidCallback onBack;
  const _DetailHeader({required this.player, required this.color, required this.onBack});

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    decoration: const BoxDecoration(
      color: _kBgBar,
      border: Border(bottom: BorderSide(color: _kFaint, width: 0.5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(children: [
      InkWell(
        onTap: onBack,
        borderRadius: BorderRadius.circular(3),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text('‹', style: TextStyle(fontSize: 18, color: _kMuted)),
        ),
      ),
      const SizedBox(width: 8),
      Container(
        width: 3, height: 16,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          player.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (player.className.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            player.className,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ),
    ]),
  );
}

// ─── Painel esquerdo ───────────────────────────────────────────────────────────
class _LeftPanel extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  const _LeftPanel({required this.player, required this.color});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // DPS hero
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.18), width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DPS', style: TextStyle(fontSize: 9, color: color.withOpacity(0.65), letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(player.formattedDps, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
      const SizedBox(height: 10),
      // Grid 2×2
      Row(children: [
        _GridCell(label: 'DANO TOTAL', value: player.formattedDamage),
        const SizedBox(width: 6),
        _GridCell(label: 'MAX HIT',    value: _fmt(player.maxHit)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        _GridCell(label: 'HITS', value: '${player.totalHits}'),
        const SizedBox(width: 6),
        _GridCell(label: 'CRITS', value: '${player.totalCrits}'),
      ]),
      const SizedBox(height: 16),
      // Flags
      const _SectionLabel('Flags de Combate'),
      const SizedBox(height: 8),
      _FlagRow(label: 'Crítico',      value: player.critRate,        color: const Color(0xFFFFB74D)),
      _FlagRow(label: 'Back Attack',  value: player.backAttackRate,  color: const Color(0xFF4FC3F7)),
      _FlagRow(label: 'Perfect',      value: player.perfectRate,     color: const Color(0xFF81C784)),
      _FlagRow(label: 'Double Hit',   value: player.doubleRate,      color: const Color(0xFFBA68C8)),
      _FlagRow(label: 'Parry receb.', value: player.parryRate,       color: const Color(0xFFE57373)),
    ]),
  );

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}

class _GridCell extends StatelessWidget {
  final String label, value;
  const _GridCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: BoxDecoration(
        color: _kBgCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kFaint, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 8, color: _kDim, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
      ]),
    ),
  );
}

class _FlagRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _FlagRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(
        width: 90,
        child: Text(label, style: const TextStyle(fontSize: 10, color: _kMuted)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: color.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color.withOpacity(value > 0 ? 0.65 : 0.15)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 40,
        child: Text(
          '${(value * 100).toStringAsFixed(1)}%',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: value > 0 ? color : _kDim),
        ),
      ),
    ]),
  );
}

// ─── Painel direito: skills ─────────────────────────────────────────────────
class _SkillPanel extends StatelessWidget {
  final PlayerStats player;
  final Color color;
  const _SkillPanel({required this.player, required this.color});

  @override
  Widget build(BuildContext context) {
    final skills = player.skills;
    final topDmg = skills.isEmpty ? 1 : skills.first.totalDmg;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const _SectionLabel('Skills'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${skills.length}', style: TextStyle(fontSize: 9, color: color)),
          ),
        ]),
      ),
      Container(height: 0.5, color: _kFaint),
      // Lista
      if (skills.isEmpty)
        const Expanded(
          child: Center(
            child: Text('Sem dados de skill ainda...', style: TextStyle(color: _kDim, fontSize: 12)),
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: skills.length,
            itemBuilder: (_, i) => _SkillCard(
              skill: skills[i],
              color: color,
              topDmg: topDmg,
            ),
          ),
        ),
    ]);
  }
}

class _SkillCard extends StatelessWidget {
  final SkillStat skill;
  final Color color;
  final int topDmg;
  const _SkillCard({required this.skill, required this.color, required this.topDmg});

  @override
  Widget build(BuildContext context) {
    final frac = topDmg > 0 ? (skill.totalDmg / topDmg).clamp(0.0, 1.0) : 0.0;
    final critHot = skill.critRate > 0.25;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: _kBgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kFaint, width: 0.5),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        // Ícone da skill
        _SkillIcon(code: skill.code, name: skill.name, color: color),
        const SizedBox(width: 12),
        // Nome + barra de progresso
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              skill.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 3,
                backgroundColor: color.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation(color.withOpacity(0.5)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        // Estatísticas
        _MetaStat(label: 'TOTAL',  value: skill.formattedTotalDmg, color: color),
        const SizedBox(width: 14),
        _MetaStat(label: 'MAX',    value: _fmt(skill.maxDmg),      color: _kMuted),
        const SizedBox(width: 14),
        _MetaStat(label: 'HITS',   value: '${skill.hits}',         color: _kMuted),
        const SizedBox(width: 14),
        _MetaStat(
          label: 'CRIT',
          value: '${(skill.critRate * 100).toStringAsFixed(0)}%',
          color: critHot ? const Color(0xFFFFB74D) : _kDim,
        ),
      ]),
    );
  }

  String _fmt(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}

class _MetaStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MetaStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
      const SizedBox(height: 1),
      Text(label, style: const TextStyle(fontSize: 8, color: _kDim, letterSpacing: 0.3)),
    ],
  );
}

// ─── Ícone da skill ────────────────────────────────────────────────────────────
class _SkillIcon extends StatelessWidget {
  final int code;
  final String name;
  final Color color;
  const _SkillIcon({required this.code, required this.name, required this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 44, height: 44,
      child: Image.asset(
        'assets/skills/$code.png',
        width: 44, height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _FallbackIcon(name: name, color: color),
      ),
    ),
  );
}

class _FallbackIcon extends StatelessWidget {
  final String name;
  final Color color;
  const _FallbackIcon({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(' ');
    final initials = words.take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22), width: 0.5),
      ),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color.withOpacity(0.75)),
        ),
      ),
    );
  }
}

// ─── Helper ────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 9, color: _kDim, letterSpacing: 1.0),
  );
}

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
