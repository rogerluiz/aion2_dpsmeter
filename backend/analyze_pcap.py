import sys
import os
from scapy.utils import rdpcap

MAGIC = b"\x06\x00\x36"


def analyze(path):
    if not os.path.exists(path):
        print('File not found:', path)
        return 2
    pkts = rdpcap(path)
    found = 0
    for i, p in enumerate(pkts, start=1):
        raw = bytes(p)
        idx = raw.find(MAGIC)
        if idx != -1:
            found += 1
            print(f'Packet #{i} contains magic at offset {idx}')
            snippet = raw[idx:idx+64]
            print(snippet.hex())
    if found == 0:
        print('No magic bytes found')
    else:
        print(f'{found} packets contain magic bytes')
    return 0


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: analyze_pcap.py <pcap_file>')
        sys.exit(2)
    # Optional second arg: packet index to dump full packet hex
    if len(sys.argv) >= 3:
        try:
            pkt_index = int(sys.argv[2])
        except ValueError:
            pkt_index = None
    else:
        pkt_index = None

    if pkt_index:
        # dump full packet bytes for given packet number
        path = sys.argv[1]
        if not os.path.exists(path):
            print('File not found:', path)
            sys.exit(2)
        pkts = rdpcap(path)
        if pkt_index < 1 or pkt_index > len(pkts):
            print('Packet index out of range')
            sys.exit(2)
        raw = bytes(pkts[pkt_index - 1])
        print(
            f'Packet#{pkt_index} len={len(raw)} magic_offset={raw.find(MAGIC)}')
        print(raw.hex())
        sys.exit(0)

    sys.exit(analyze(sys.argv[1]))
