'use strict';
/**
 * index.js — Entry point do servidor AION 2 DPS Meter (Node.js)
 *
 * Uso:
 *   node src/index.js                       # captura real (requer Admin + Npcap)
 *   node src/index.js --mock                # dados simulados (sem Npcap)
 *   node src/index.js --list-interfaces     # lista interfaces de rede
 *   node src/index.js --iface=<nome>        # interface específica
 *   DEBUG=1 node src/index.js               # logs detalhados de pacotes brutos
 */

// PacketCapture carregado lazily — evita que require('cap') falhe no modo --mock
const {StreamParser} = require('./packet_parser');
const DpsCalculator = require('./calculator');
const WsServer = require('./ws_server');

const args = process.argv.slice(2);
const isMock = args.includes('--mock');
const listInterfaces = args.includes('--list-interfaces');
const ifaceArg =
  (args.find((a) => a.startsWith('--iface=')) || '').split('=')[1] || null;
const portArg =
  parseInt((args.find((a) => a.startsWith('--port=')) || '').split('=')[1]) ||
  null;
const WS_PORT = 8765;

// --- Listar interfaces e sair ---
if (listInterfaces) {
  const PacketCapture = require('./capture');
  let devices;
  try {
    devices = PacketCapture.listInterfaces();
  } catch (e) {
    console.error('[ERROR] Não foi possível listar interfaces:', e.message);
    console.error('Verifique se Npcap está instalado.');
    process.exit(1);
  }
  console.log('\nInterfaces de rede disponíveis:\n');
  devices.forEach((dev, i) => {
    console.log(`  [${i}] ${dev.description || dev.name}`);
    console.log(`       Nome: ${dev.name}`);
    dev.addresses.forEach(
      (a) => a.addr && console.log(`       Addr: ${a.addr}`),
    );
  });
  console.log(
    '\nUse: node src/index.js --iface=<Nome> para selecionar uma interface específica.',
  );
  process.exit(0);
}

// --- Inicia WebSocket e calculadora ---
const wsServer = new WsServer(WS_PORT);
const calculator = new DpsCalculator();
const streamParser = new StreamParser();

wsServer.start();

// Handle reset from Flutter frontend
wsServer.on('reset', () => {
  calculator.reset();
  streamParser.reset();
  console.log('[INFO] Sessão resetada pelo cliente.');
});

// Broadcast imediato quando nome de jogador é resolvido
calculator.on('nameUpdated', () => broadcastNow());

// Broadcast imediato quando filtro muda
wsServer.on('filterChanged', () => broadcastNow());

// Broadcast snapshot a cada 100ms para UI responsiva
const snapshotInterval = setInterval(() => {
  wsServer.broadcast(calculator.getSnapshot(wsServer.filterOptions));
}, 100);

// Throttle helper: garante no máximo 1 broadcast por tick de event loop
let _broadcastPending = false;
function broadcastNow() {
  if (_broadcastPending) return;
  _broadcastPending = true;
  setImmediate(() => {
    _broadcastPending = false;
    wsServer.broadcast(calculator.getSnapshot(wsServer.filterOptions));
  });
}

// --- Modo MOCK ---
if (isMock) {
  console.log('[MOCK] Gerando eventos de dano simulados...');
  const mockPlayers = ['player_1', 'player_2'];
  let tick = 0;

  setInterval(() => {
    tick++;
    const actorId = tick % 2 === 0 ? 1 : 2;
    const damage = Math.floor(Math.random() * 8000) + 500;
    const isCrit = Math.random() > 0.65;
    const isDot = Math.random() > 0.85;

    const event = {actorId, damage, isCrit, isDot, skillCode: 0x1234};
    calculator.addEvent(event);

    console.log(
      `[MOCK] actor=${mockPlayers[actorId - 1]} dmg=${damage} crit=${isCrit} dot=${isDot}`,
    );
  }, 500);

  // --- Modo REAL ---
} else {
  const PacketCapture = require('./capture');
  const capture = new PacketCapture();

  capture.on('magic', ({connKey}) => {
    console.log(
      `\n[INFO] AION 2 detectado em ${connKey} — capturando combate...\n`,
    );
  });

  capture.on('packet', (pkt) => {
    // Feed bytes into per-connection stream parser
    const events = streamParser.consume(pkt.connKey, pkt.payload);
    events.forEach((ev) => {
      if (ev.type === 'nickname') {
        calculator.setNickname(ev.actorId, ev.name);
        console.log(`[NICK] actor=${ev.actorId} name="${ev.name}"`);
        return;
      }
      calculator.addEvent(ev);
      console.log(
        `[EVENT] ${ev.isDot ? 'DoT' : 'DMG'} actor=${ev.actorId} target=${ev.targetId} ` +
          `dmg=${ev.damage} skill=${ev.skillCode} crit=${ev.isCrit}`,
      );
    });

    // Real-time broadcast on combat events (throttled to 1 per event loop tick)
    if (events.length > 0) {
      broadcastNow();
    }
  });

  try {
    capture.start(ifaceArg);
  } catch (err) {
    console.error('[ERROR] Falha ao iniciar captura:', err.message);
    console.error('[WARN] Iniciando em modo MOCK — instale o Npcap para captura real.');

    // Cai em mock para o WS server continuar funcionando
    const mockPlayers = ['player_1', 'player_2'];
    let tick = 0;
    setInterval(() => {
      tick++;
      const actorId = tick % 2 === 0 ? 1 : 2;
      const damage = Math.floor(Math.random() * 8000) + 500;
      calculator.addEvent({actorId, damage, isCrit: Math.random() > 0.65, isDot: false, skillCode: 0x1234});
    }, 500);
  }

  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n[INFO] Encerrando...');
    clearInterval(snapshotInterval);
    capture.stop();
    wsServer.stop();
    process.exit(0);
  });

  process.on('SIGTERM', () => {
    capture.stop();
    wsServer.stop();
    process.exit(0);
  });
}
