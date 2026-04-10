from scapy.utils import rdpcap
path = r'A:\Projects\aion2_dspmeter\backend\pcaps\capture_auto_1775829582.pcap'
pkts = rdpcap(path)
idx = 2990 - 1
if idx < 0 or idx >= len(pkts):
    print('Index out of range', idx)
    raise SystemExit(2)
raw = bytes(pkts[idx])
print(f'Packet#{2990} len={len(raw)} offset_magic={raw.find(b"\x06\x00\x36")}')
print(raw.hex())
