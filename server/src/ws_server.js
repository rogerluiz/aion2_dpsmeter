'use strict';
/**
 * ws_server.js — Servidor WebSocket que transmite snapshots de DPS.
 * Porta: 8765 (mesma do backend Python para compatibilidade com o frontend Flutter).
 */

const {WebSocketServer, OPEN} = require('ws');
const EventEmitter = require('events');

class WsServer extends EventEmitter {
  constructor(port = 8765) {
    super();
    this._port = port;
    this._wss = null;
    this._clients = new Set();
    // Filter state (applied by index.js when calling calculator.getSnapshot)
    this._filterMode = 'all'; // 'all' | 'party' | 'target'
    this._filterTargetId = null; // pinned targetId (null = auto-detect)
  }

  get filterOptions() {
    return {filterMode: this._filterMode, filterTargetId: this._filterTargetId};
  }

  start() {
    this._wss = new WebSocketServer({host: '127.0.0.1', port: this._port});

    this._wss.on('connection', (ws, req) => {
      const addr = req.socket.remoteAddress;
      this._clients.add(ws);
      console.log(
        `[WS] Cliente conectado: ${addr} (total: ${this._clients.size})`,
      );

      ws.on('message', (raw) => {
        try {
          const msg = JSON.parse(raw.toString());
          if (msg.action === 'reset') {
            this.emit('reset');
            ws.send(JSON.stringify({type: 'reset_ack'}));
          } else if (msg.action === 'set_filter') {
            const mode = msg.mode;
            if (['all', 'party', 'target'].includes(mode)) {
              this._filterMode = mode;
              // When switching to 'target' with an explicit id, pin it
              this._filterTargetId =
                mode === 'target' ? msg.targetId || null : null;
              console.log(
                `[WS] Filtro: ${mode}${this._filterTargetId ? ` (target=${this._filterTargetId})` : ''}`,
              );
              this.emit('filterChanged');
            }
          }
        } catch (_) {}
      });

      ws.on('close', () => {
        this._clients.delete(ws);
        console.log(`[WS] Cliente desconectado (total: ${this._clients.size})`);
      });

      ws.on('error', () => this._clients.delete(ws));
    });

    this._wss.on('error', (err) => {
      console.error(`[WS] Erro: ${err.message}`);
    });

    console.log(`[WS] Servidor WebSocket em ws://localhost:${this._port}`);
  }

  /** Envia mensagem JSON a todos os clientes conectados. */
  broadcast(data) {
    if (this._clients.size === 0) return;
    const msg = JSON.stringify(data);
    for (const client of this._clients) {
      if (client.readyState === OPEN) {
        client.send(msg);
      }
    }
  }

  stop() {
    if (this._wss) {
      this._wss.close();
      this._wss = null;
    }
  }
}

module.exports = WsServer;
