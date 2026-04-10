from scapy.utils import rdpcap
MAGIC = b'\x06\x00\x36'
path = r'A:\Projects\aion2_dspmeter\backend\pcaps\capture_auto_1775829582.pcap'
pkts = rdpcap(path)
found = 0
for i, p in enumerate(pkts, start=1):
    raw = bytes(p)
    idx = raw.find(MAGIC)
    if idx != -1:
        print(f'Packet#{i} offset={idx} len={len(raw)}')
        print(raw[idx:idx+96].hex())
        found += 1
        if found >= 5:
            break
print('DONE')
