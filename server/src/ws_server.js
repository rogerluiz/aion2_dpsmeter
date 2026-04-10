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
