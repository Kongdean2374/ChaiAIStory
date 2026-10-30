#!/usr/bin/env python3
"""Original geometric book mark. PNG created with standard library only."""
import json, struct, zlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent / "Resources/Assets.xcassets"
def png(path, size):
    rows=[]
    for y in range(size):
        row=bytearray()
        for x in range(size):
            u,v=x/size,y/size
            gold = ((.22<u<.48 or .52<u<.78) and .27<v<.70 and v > .27+abs(u-.5)*.12)
            spine = abs(u-.5)<.012 and .33<v<.75
            line = .30<u<.70 and abs(v-(.75-abs(u-.5)*.15))<.009
            rgb=(205,176,113) if gold or spine or line else (18,23,28)
            if gold and .34<v<.60 and any(abs(v-t)<.005 for t in [.39,.47,.55]) and (.28<u<.43 or .57<u<.72): rgb=(120,101,64)
            row.extend(rgb)
        rows.append(b'\0'+row)
    def chunk(tag, data): return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data)&0xffffffff)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b'IHDR',struct.pack(">IIBBBBB",size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b''))
icon=root/"AppIcon.appiconset"
icon.mkdir(parents=True,exist_ok=True)
png(icon/"AppIcon.png",1024)
(icon/"Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}))
(root/"Contents.json").write_text(json.dumps({"info":{"author":"xcode","version":1}}))
color=root/"LaunchBackground.colorset"
color.mkdir(exist_ok=True)
(color/"Contents.json").write_text(json.dumps({"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0.07","green":"0.09","blue":"0.11","alpha":"1.0"}}}],"info":{"author":"xcode","version":1}}))
