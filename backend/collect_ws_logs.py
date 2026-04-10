import asyncio
import time
import sys

try:
    import websockets
except Exception as e:
    print('Missing websockets package:', e, file=sys.stderr)
    sys.exit(2)


async def main():
    uri = 'ws://localhost:8765'
    try:
        async with websockets.connect(uri) as ws:
            print('CONNECTED to', uri)
            t0 = time.time()
            while time.time() - t0 < 30:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=5)
                    print(msg)
                except asyncio.TimeoutError:
                    print('NO_MSG_TIMEOUT')
            print('DONE')
    except Exception as e:
        print('ERROR connecting to websocket:', e, file=sys.stderr)

if __name__ == '__main__':
    asyncio.run(main())
