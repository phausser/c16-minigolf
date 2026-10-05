"""Exercise VICE's actual C16 joystick latch through its binary monitor.

Protocol: https://vice-emu.sourceforge.io/vice_13.html
Prepare, start xplus4 with build/vice-joystick.mon and -binarymonitoraddress
127.0.0.1:6503, then verify. No RAM injection of input or charging state.
"""
import argparse
import json
from pathlib import Path
import socket
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from check_build import symbols

class Monitor:
    def __init__(self):
        self.sock = socket.create_connection(('127.0.0.1',6503),timeout=10)
        self.sock.settimeout(10)
        self.serial = 0
        self.events = []

    def read(self,n):
        data = bytearray()
        while len(data) < n:
            part = self.sock.recv(n-len(data))
            if not part:
                raise EOFError('VICE disconnected')
            data.extend(part)
        return bytes(data)

    def response(self):
        header = self.read(12)
        assert header[:2] == bytes([2,2]),header
        size,kind,error,serial = struct.unpack('<IBBI',header[2:])
        data = self.read(size)
        assert error == 0,(kind,error)
        return kind,serial,data

    def command(self,kind,data=b''):
        self.serial += 1
        self.sock.sendall(bytes([2,2])+struct.pack('<II',len(data),self.serial)+bytes([kind])+data)
        while True:
            response,serial,body = self.response()
            if serial == self.serial:
                return body
            self.events.append((response,body))

    def memory(self,start,end):
        body = self.command(1,struct.pack('<BHHBH',0,start,end,0,0))
        assert int.from_bytes(body[:2],'little') == end-start+1
        return body[2:]

    def frame(self):
        self.events.clear()
        self.command(0xaa)
        while not any(kind == 0x62 for kind,_ in self.events):
            kind,_,data = self.response()
            self.events.append((kind,data))

    def joystick(self,value):
        self.command(0xa2,struct.pack('<HH',0,255 ^ value))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--prepare-only',action='store_true')
    group.add_argument('--verify-only',action='store_true')
    args = parser.parse_args()
    s = symbols()
    if args.prepare_only:
        (ROOT/'build/vice-joystick.mon').write_text('delete 1\nuntil $%04x\n' % s['frame_begin'])
        return
    m = Monitor()
    resource = b'JoyPort1Device'
    m.command(0x52,bytes([1,len(resource)])+resource+bytes([4])+struct.pack('<I',37))
    value = m.command(0x51,bytes([len(resource)])+resource)
    assert int.from_bytes(value[2:],'little') == 37,value
    address = s['frame_done']
    m.command(0x12,struct.pack('<HHBBBBB',address,address,1,1,4,0,0))
    def state():
        data = m.memory(s['STATE_BEGIN'],s['STATE_END']-1)
        return {name:data[s[name]-s['STATE_BEGIN']] for name in
                ('ANGLE','POWER','CHARGING','SHOTS','ROLLING','KEY_CURRENT','KEY_PREVIOUS')}
    def frames(count):
        for _ in range(count):
            m.frame()
        return state()
    m.joystick(0)
    assert frames(3)['POWER'] == 0
    m.joystick(4)  # left: actual joyport -> TED -> scan -> debounce -> rotate
    st = frames(2)
    assert st['KEY_CURRENT'] == 1 and st['ANGLE'] == 127,st
    m.joystick(0)
    frames(2)
    m.joystick(8)
    assert frames(2)['ANGLE'] == 0
    m.joystick(0)
    frames(2)
    m.joystick(16)
    st = frames(2)
    assert st['POWER'] == 1 and st['CHARGING'] == 1 and st['SHOTS'] == 0,st
    st = frames(62)
    assert st['POWER'] == 32 and st['SHOTS'] == 0,st
    # Filled HUD must be visible; rows 21-23 keep hidden black/black code.
    bitmap = m.memory(0x3b80,0x3f3f)
    hidden = m.memory(0x1800+21*40,0x1800+24*40-1)+m.memory(0x1c00+21*40,0x1c00+24*40-1)
    assert not any(hidden),'hidden code rows are visible'
    assert any(bitmap[0x3e78-0x3b80:0x3ef8-0x3b80]),'charge bar not filled'
    assert not any(bitmap[0x3f08-0x3b80:]),'status text remains'
    m.joystick(0)
    st = frames(2)
    assert st['SHOTS'] == 1 and st['ROLLING'] == 1 and st['POWER'] == 0,st
    result = dict(hardware='VICE C16 PAL 16 KB',port=1,
                  joystick_latch_verified=True,full_charge_frames=64,
                  fires_on_release=True,hidden_code_rows=True,status_empty=True)
    (ROOT/'build/joystick-smoke.json').write_text(json.dumps(result,indent=2)+'\n')
    # VICE 3.10 can exit before acknowledging Quit; do not wait for a reply.
    m.serial += 1
    m.sock.sendall(bytes([2,2])+struct.pack('<II',0,m.serial)+bytes([0xbb]))
    m.sock.close()
    print('VICE joystick port 1: latch, rotation, charge, release and HUD passed')

if __name__ == '__main__':
    main()
