// main.dart — AION 2 DPS Meter
// Visual idêntico ao mockup: fundo #0c0d0f, titlebar com dots, overlay arrastável

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'ws_service.dart';
import 'models.dart';
import 'party_table.dart';
import 'dps_chart.dart';
import 'backend_service.dart';
import 'player_detail.dart';

// ─── Paleta (espelha o mockup) ────────────────────────────────────────────────
const kBg         = Color(0xFF0C0D0F);
const kBgBar      = Color(0xFF111215);
const kBorder     = Color(0x1AFFFFFF);
const kBorderFaint= Color(0x0AFFFFFF);
const kText       = Color(0xE6FFFFFF);
const kTextMuted  = Color(0x8CFFFFFF);
const kTextDim    = Color(0x40FFFFFF);
const kAccent     = Color(0xFF4FC3F7);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(500, 440),
    minimumSize: Size(400, 280),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setOpacity(0.92);
    await windowManager.show();
  });

  // Inicia o servidor Node.js empacotado automaticamente
  final backendService = BackendService();
  await backendService.start();

  runApp(
    ChangeNotifierProvider(
      create: (_) => WsService()..connect(),
      child: const DpsMeterApp(),
    ),
  );
}

class DpsMeterApp extends StatelessWidget {
  const DpsMeterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.transparent),
    home: const MeterWindow(),
  );
}

// ─── Janela principal ─────────────────────────────────────────────────────────
class MeterWindow extends StatefulWidget {
  const MeterWindow({super.key});
  @override
  State<MeterWindow> createState() => _MeterWindowState();
}

class _MeterWindowState extends State<MeterWindow> {
  bool _showChart = true;
  double _opacity = 0.92;
  int? _detailPlayerId;
  int _detailColorIndex = 0;
  Rect? _compactBounds;

  Future<void> _openDetail(PlayerStats player, int colorIndex) async {
    setState(() {
      _detailPlayerId = player.id;
      _detailColorIndex = colorIndex;
    });

    final currentBounds = await windowManager.getBounds();
    _compactBounds ??= currentBounds;

    const detailSize = Size(920, 680);
    final displays = await screenRetriever.getAllDisplays();
    final currentCenter = currentBounds.center;

    Display? activeDisplay;
    for (final display in displays) {
      final visibleRect = Rect.fromLTWH(
        display.visiblePosition?.dx ?? 0,
        display.visiblePosition?.dy ?? 0,
        display.visibleSize?.width ?? display.size.width,
        display.visibleSize?.height ?? display.size.height,
      );
      if (visibleRect.contains(currentCenter)) {
        activeDisplay = display;
        break;
      }
    }
    activeDisplay ??= displays.isNotEmpty ? displays.first : await screenRetriever.getPrimaryDisplay();

    final visibleRect = Rect.fromLTWH(
      activeDisplay.visiblePosition?.dx ?? 0,
      activeDisplay.visiblePosition?.dy ?? 0,
      activeDisplay.visibleSize?.width ?? activeDisplay.size.width,
      activeDisplay.visibleSize?.height ?? activeDisplay.size.height,
    );

    final targetWidth = detailSize.width.clamp(500.0, visibleRect.width).toDouble();
    final targetHeight = detailSize.height.clamp(440.0, visibleRect.height).toDouble();
    final extraWidth = targetWidth - currentBounds.width;
    final freeLeft = currentBounds.left - visibleRect.left;
    final freeRight = visibleRect.right - currentBounds.right;
    final expandRight = freeRight >= extraWidth || freeRight >= freeLeft;

    final targetLeft = (expandRight
        ? currentBounds.left.clamp(
          visibleRect.left,
                visibleRect.right - targetWidth,
          )
        : (currentBounds.left - extraWidth).clamp(
          visibleRect.left,
                visibleRect.right - targetWidth,
          ))
      .toDouble();
    final targetTop = currentBounds.top
        .clamp(visibleRect.top, visibleRect.bottom - targetHeight)
      .toDouble();

    await windowManager.setResizable(true);
    await windowManager.setBounds(
      Rect.fromLTWH(targetLeft, targetTop, targetWidth, targetHeight),
      animate: true,
    );
  }

  Future<void> _closeDetail() async {
    final compactBounds = _compactBounds;
    setState(() => _detailPlayerId = null);
    if (compactBounds != null) {
      await windowManager.setBounds(compactBounds, animate: true);
    } else {
      await windowManager.setSize(const Size(500, 440), animate: true);
    }
    _compactBounds = null;
  }

  PlayerStats? _selectedPlayer(DpsSnapshot snapshot) {
    final detailPlayerId = _detailPlayerId;
    if (detailPlayerId == null) return null;
    for (final player in snapshot.players) {
      if (player.id == detailPlayerId) return player;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder, width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_detailPlayerId ?? 'main'),
                child: Column(children: [
                  _TitleBar(
                    showChart: _showChart,
                    opacity: _opacity,
                    onToggleChart: () => setState(() => _showChart = !_showChart),
                    onReset: () => context.read<WsService>().sendReset(),
                  ),
                  Expanded(
                    child: Consumer<WsService>(
                      builder: (_, ws, __) {
                        final selectedPlayer = _selectedPlayer(ws.snapshot);
                        if (selectedPlayer != null) {
                          return PlayerDetailScreen(
                            player: selectedPlayer,
                            colorIndex: _detailColorIndex,
                            onBack: () {
                              _closeDetail();
                            },
                          );
                        }

                        return _Body(
                          snapshot: ws.snapshot,
                          status: ws.status,
                          showChart: _showChart,
                          opacity: _opacity,
                          filterMode: ws.filterMode,
                          onOpacityChanged: (v) {
                            setState(() => _opacity = v);
                            windowManager.setOpacity(v);
                          },
                          onFilterChanged: (mode) => ws.sendFilter(mode),
                          onPlayerTap: (player, colorIndex) {
                            _openDetail(player, colorIndex);
                          },
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Barra de título ──────────────────────────────────────────────────────────
class _TitleBar extends StatelessWidget {
  final bool showChart;
  final double opacity;
  final VoidCallback onToggleChart;
  final VoidCallback onReset;
  const _TitleBar({
    required this.showChart, required this.opacity,
    required this.onToggleChart, required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<WsService>(
      builder: (_, ws, __) => Container(
        height: 34,
        decoration: const BoxDecoration(
          color: kBgBar,
          border: Border(bottom: BorderSide(color: kBorderFaint, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          // Dots estilo macOS
          _Dot(color: _statusColor(ws.status)),
          const SizedBox(width: 6),
          const _Dot(color: Color(0xFFFFBF00)),
          const SizedBox(width: 6),
          const _Dot(color: Color(0xFF00CA4E)),
          const SizedBox(width: 10),
          // Título
          const Expanded(
            child: Text(
              'AION 2  ·  DPS Meter',
              style: TextStyle(fontSize: 11, color: kTextDim, letterSpacing: 0.8),
            ),
          ),
          // Botão gráfico
          _TbBtn(
            label: showChart ? '▾' : '▸',
            tooltip: showChart ? 'Ocultar gráfico' : 'Mostrar gráfico',
            onTap: onToggleChart,
          ),
          _TbBtn(label: '⊞', tooltip: 'Sempre no topo', onTap: () {}),
          _TbBtn(label: '✕', tooltip: 'Fechar', onTap: () => windowManager.close(), danger: true),
        ]),
      ),
    );
  }

  Color _statusColor(WsStatus s) => switch (s) {
    WsStatus.connected    => const Color(0xFF4ADE80),
    WsStatus.connecting   => const Color(0xFFFBBF24),
    WsStatus.disconnected => const Color(0xFFF87171),
  };
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 6, height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _TbBtn extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  const _TbBtn({required this.label, required this.tooltip, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: danger ? const Color(0x99F87171) : const Color(0x4DFFFFFF),
          ),
        ),
      ),
    ),
  );
}

// ─── Corpo ────────────────────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  final DpsSnapshot snapshot;
  final WsStatus status;
  final bool showChart;
  final double opacity;
  final FilterMode filterMode;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<FilterMode> onFilterChanged;
  final void Function(PlayerStats, int)? onPlayerTap;

  const _Body({
    required this.snapshot, required this.status,
    required this.showChart, required this.opacity,
    required this.filterMode,
    required this.onOpacityChanged,
    required this.onFilterChanged,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    if (status != WsStatus.connected) {
      return _ConnectingScreen(status: status);
    }
    return Column(children: [
      // Stats rápidas
      _StatsRow(snapshot: snapshot),
      // Barra de filtro
      _FilterBar(current: filterMode, onChanged: onFilterChanged),
      // Gráfico colapsável
      if (showChart) ...[
        Container(
          height: 96,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: DpsChart(snapshot: snapshot),
        ),
        const Divider(height: 0.5, color: kBorderFaint),
      ],
      // Tabela
      Expanded(
        child: SingleChildScrollView(
          child: PartyTable(snapshot: snapshot, onPlayerTap: onPlayerTap),
        ),
      ),
      const Divider(height: 0.5, color: kBorderFaint),
      // Slider de opacidade
      _OpacityRow(opacity: opacity, onChanged: onOpacityChanged),
      // Footer
      _Footer(snapshot: snapshot),
    ]);
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final DpsSnapshot snapshot;
  const _StatsRow({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final top = snapshot.players.isEmpty ? null : snapshot.players.first;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0x0AFFFFFF),
        border: Border(bottom: BorderSide(color: kBorderFaint, width: 0.5)),
      ),
      child: Row(children: [
        _StatCell(label: 'Tempo',       value: snapshot.formattedDuration),
        _vLine(),
        _StatCell(label: 'Top DPS',     value: top?.formattedDps ?? '—', accent: true),
        _vLine(),
        _StatCell(label: 'Dano total',  value: _fmtTotal(snapshot.totalDamage)),
        _vLine(),
        _StatCell(label: 'Jogadores',   value: '${snapshot.players.length}'),
      ]),
    );
  }

  Widget _vLine() => Container(width: 0.5, height: 38, color: kBorderFaint);

  String _fmtTotal(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const _StatCell({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, color: kTextDim, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: accent ? kAccent : kText,
          ),
        ),
      ]),
    ),
  );
}

// ─── Barra de filtro ──────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final FilterMode current;
  final ValueChanged<FilterMode> onChanged;
  const _FilterBar({required this.current, required this.onChanged});

  static const _labels = {
    FilterMode.all:    'Todos',
    FilterMode.party:  'Party',
    FilterMode.target: 'Target',
  };

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    decoration: const BoxDecoration(
      color: Color(0x08FFFFFF),
      border: Border(bottom: BorderSide(color: kBorderFaint, width: 0.5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(children: [
      for (final mode in FilterMode.values) ...[
        _FilterPill(
          label: _labels[mode]!,
          active: current == mode,
          onTap: () => onChanged(mode),
        ),
        if (mode != FilterMode.values.last) const SizedBox(width: 4),
      ],
    ]),
  );
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? kAccent.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? kAccent.withOpacity(0.5) : const Color(0x22FFFFFF),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: active ? kAccent : kTextMuted,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          letterSpacing: 0.3,
        ),
      ),
    ),
  );
}

// ─── Slider de opacidade ──────────────────────────────────────────────────────
class _OpacityRow extends StatelessWidget {
  final double opacity;
  final ValueChanged<double> onChanged;
  const _OpacityRow({required this.opacity, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
    child: Row(children: [
      const Text('Opacidade', style: TextStyle(fontSize: 9, color: kTextDim)),
      const SizedBox(width: 8),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: const Color(0x66FFFFFF),
            inactiveTrackColor: const Color(0x1AFFFFFF),
            thumbColor: const Color(0x8CFFFFFF),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: opacity,
            min: 0.3,
            max: 1.0,
            onChanged: onChanged,
          ),
        ),
      ),
      const SizedBox(width: 6),
      SizedBox(
        width: 30,
        child: Text(
          '${(opacity * 100).round()}%',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 9, color: kTextDim),
        ),
      ),
    ]),
  );
}

// ─── Footer ───────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final DpsSnapshot snapshot;
  const _Footer({required this.snapshot});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
    child: Row(children: [
      const Text(
        'ws://localhost:8765  ·  janela 10s',
        style: TextStyle(fontSize: 9, color: kTextDim),
      ),
      const Spacer(),
      InkWell(
        onTap: () => context.read<WsService>().sendReset(),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x1AFFFFFF), width: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Resetar sessão',
            style: TextStyle(fontSize: 10, color: kTextMuted),
          ),
        ),
      ),
    ]),
  );
}

// ─── Tela de conexão ──────────────────────────────────────────────────────────
class _ConnectingScreen extends StatelessWidget {
  final WsStatus status;
  const _ConnectingScreen({required this.status});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0x33FFFFFF)),
      ),
      const SizedBox(height: 12),
      Text(
        status == WsStatus.connecting
            ? 'Conectando ao backend...'
            : 'Backend desconectado\nReconectando em 3s...',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
      ),
      const SizedBox(height: 8),
      const Text(
        'python main.py --mock',
        style: TextStyle(fontSize: 10, color: Color(0x33FFFFFF), fontFamily: 'monospace'),
      ),
    ]),
  );
}
