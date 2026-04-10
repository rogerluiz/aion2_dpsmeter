"""
main.py — Servidor WebSocket do DPS Meter para AION 2

Inicia captura de pacotes + servidor WebSocket que envia
snapshots de DPS para o frontend Flutter a cada segundo.

Uso:
    python main.py                    # captura real (requer Npcap + admin)
    python main.py --mock             # modo simulado (para desenvolvimento)
    python main.py --iface "Ethernet" # especifica interface de rede
    python main.py --list-ifaces      # lista interfaces disponíveis
"""

import asyncio
import json
import logging
import argparse
import threading
import time
import sys

import websockets

from calculator import DPSCalculator
from packet_parser import PacketParser

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("aion2_dpsmeter")

WS_HOST = "localhost"
WS_PORT = 8765
TICK_INTERVAL = 1.0  # segundos entre snapshots enviados ao Flutter


class DPSMeterServer:
    def __init__(self, use_mock: bool = False, interface: str | None = None):
        self.use_mock = use_mock
        self.interface = interface
        self.calculator = DPSCalculator()
        self.parser = PacketParser(use_mock_format=use_mock)
        self._clients: set = set()
        self._running = False

    # ─── Captura ──────────────────────────────────────────────────────────────

    def _on_packet(self, payload: bytes, direction: str):
        event = self.parser.parse(payload, direction)
        if event:
            self.calculator.process_event(event)

    def _start_capture(self):
        if self.use_mock:
            from capture import MockCapture
            cap = MockCapture(self._on_packet)
        else:
            from capture import PacketCapture
            cap = PacketCapture(self._on_packet, interface=self.interface)
        cap.start()
        logger.info("Captura iniciada.")
        return cap

    # ─── Tick loop (thread auxiliar) ─────────────────────────────────────────

    def _tick_loop(self, loop: asyncio.AbstractEventLoop):
        """Chama calculator.tick() a cada segundo e despacha snapshot."""
        while self._running:
            time.sleep(TICK_INTERVAL)
            self.calculator.tick()
            snapshot = self.calculator.get_snapshot()
            msg = json.dumps({"type": "snapshot", "data": snapshot})
            asyncio.run_coroutine_threadsafe(self._broadcast(msg), loop)

    # ─── WebSocket ────────────────────────────────────────────────────────────

    async def _broadcast(self, message: str):
        if not self._clients:
            return
        dead = set()
        for ws in self._clients:
            try:
                await ws.send(message)
            except Exception:
                dead.add(ws)
        self._clients -= dead

    async def _handle_client(self, websocket):
        self._clients.add(websocket)
        client_addr = websocket.remote_address
        logger.info(f"Cliente conectado: {client_addr}")

        # Envia snapshot imediato ao conectar
        snapshot = self.calculator.get_snapshot()
        await websocket.send(json.dumps({"type": "snapshot", "data": snapshot}))

        try:
            async for message in websocket:
                await self._handle_command(message, websocket)
        except websockets.ConnectionClosed:
            pass
        finally:
            self._clients.discard(websocket)
            logger.info(f"Cliente desconectado: {client_addr}")

    async def _handle_command(self, message: str, websocket):
        """Processa comandos enviados pelo Flutter."""
        try:
            cmd = json.loads(message)
            action = cmd.get("action")

            if action == "reset":
                self.calculator.reset()
                await websocket.send(json.dumps({"type": "reset_ack"}))
                logger.info("Sessão resetada pelo cliente.")

            elif action == "ping":
                await websocket.send(json.dumps({"type": "pong"}))

        except json.JSONDecodeError:
            pass

    # ─── Entry point ──────────────────────────────────────────────────────────

    async def serve(self):
        self._running = True
        loop = asyncio.get_running_loop()

        # Inicia captura de pacotes
        cap = self._start_capture()

        # Inicia tick loop em thread auxiliar
        tick_thread = threading.Thread(
            target=self._tick_loop, args=(loop,), daemon=True)
        tick_thread.start()

        logger.info(f"Servidor WebSocket em ws://{WS_HOST}:{WS_PORT}")
        logger.info("Aguardando conexão do Flutter...")

        async with websockets.serve(self._handle_client, WS_HOST, WS_PORT):
            await asyncio.Future()  # roda para sempre

    def run(self):
        try:
            asyncio.run(self.serve())
        except KeyboardInterrupt:
            self._running = False
            logger.info("Servidor encerrado.")


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="AION 2 DPS Meter - Backend")
    parser.add_argument("--mock",         action="store_true",
                        help="Usar dados simulados (sem Npcap)")
    parser.add_argument("--iface",        type=str,
                        default=None, help="Interface de rede para captura")
    parser.add_argument("--list-ifaces",  action="store_true",
                        help="Listar interfaces disponíveis e sair")
    args = parser.parse_args()

    if args.list_ifaces:
        try:
            from capture import PacketCapture
            ifaces = PacketCapture(lambda p, d: None).list_interfaces()
            print("\nInterfaces disponíveis:")
            for i in ifaces:
                print(f"  • {i}")
        except Exception as e:
            print(f"Erro ao listar interfaces: {e}")
        sys.exit(0)

    if not args.mock:
        # Verifica se está rodando como administrador (necessário para Npcap)
        import ctypes
        if not ctypes.windll.shell32.IsUserAnAdmin():
            logger.warning(
                "⚠️  Execute como Administrador para captura real com Npcap!")
            logger.warning("    Dica: use --mock para modo de desenvolvimento")

    server = DPSMeterServer(use_mock=args.mock, interface=args.iface)
    server.run()


if __name__ == "__main__":
    main()
