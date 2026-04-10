// party_table.dart — Tabela de ranking idêntica ao mockup

import 'package:flutter/material.dart';
import 'models.dart';

const _playerColors = [
  Color(0xFF4FC3F7),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFE57373),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
];

const _classNames = ['Warrior', 'Scout', 'Mage', 'Priest', 'Chanter', 'Templar'];

class PartyTable extends StatelessWidget {
  final DpsSnapshot snapshot;
  const PartyTable({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final players = snapshot.players;
    final maxDmg = players.isEmpty ? 1 : players.first.totalDamage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TableHeader(),
        ...players.asMap().entries.map((e) => _PlayerRow(
          rank: e.key + 1,
          player: e.value,
          maxDamage: maxDmg,
          color: _playerColors[e.key % _playerColors.length],
          className: _classNames[e.value.id % _classNames.length],
        )),
        if (players.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Aguardando combate...',
                style: TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(10, 5, 10, 5),
    child: Row(children: [
      SizedBox(width: 20),
      Expanded(flex: 3, child: _H('Jogador')),
      Expanded(flex: 2, child: _H('DPS', right: true)),
      Expanded(flex: 2, child: _H('Dano', right: true)),
      Expanded(flex: 1, child: _H('Crit%', right: true)),
      Expanded(flex: 2, child: _H('Max hit', right: true)),
    ]),
  );
}

class _H extends StatelessWidget {
  final String text;
  final bool right;
  const _H(this.text, {this.right = false});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: const TextStyle(fontSize: 9, color: Color(0x40FFFFFF), letterSpacing: 0.5),
  );
}

class _PlayerRow extends StatelessWidget {
  final int rank;
  final PlayerStats player;
  final int maxDamage;
  final Color color;
  final String className;
  const _PlayerRow({
    required this.rank, required this.player,
    required this.maxDamage, required this.color, required this.className,
  });

  @override
  Widget build(BuildContext context) {
    final pct = maxDamage > 0 ? player.totalDamage / maxDamage : 0.0;
    final critHot = player.critRate > 20;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x0AFFFFFF), width: 0.5)),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(color: color.withOpacity(0.09)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(children: [
            SizedBox(
              width: 16,
              child: Text('$rank', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
            ),
            const SizedBox(width: 4),
            Expanded(flex: 3, child: Row(children: [
              Container(
                width: 3, height: 14,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Flexible(child: Text(
                player.name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xE6FFFFFF)),
                overflow: TextOverflow.ellipsis,
              )),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(className, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: color)),
              ),
            ])),
            Expanded(flex: 2, child: Text(
              player.formattedDps, textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
            )),
            Expanded(flex: 2, child: Text(
              player.formattedDamage, textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Color(0x8CFFFFFF)),
            )),
            Expanded(flex: 1, child: Text(
              '${player.critRate.toStringAsFixed(0)}%', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: critHot ? const Color(0xFFFFB74D) : const Color(0x66FFFFFF)),
            )),
            Expanded(flex: 2, child: Text(
              _fmt(player.maxHit), textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Color(0x66FFFFFF)),
            )),
          ]),
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
