#!/usr/bin/env python3
"""Make explicit iPad icon sizes from existing artwork with macOS sips."""
from pathlib import Path
import json,subprocess,sys
root=Path(__file__).resolve().parents[1]
sizes=[("20",1),("20",2),("29",1),("29",2),("40",1),("40",2),("76",1),("76",2),("83.5",2)]
folders=list((root/"Resources/Assets.xcassets").glob("AppIcon*.appiconset"))
if not folders: sys.exit("Missing AppIcon catalogs")
for folder in folders:
    original=folder/"AppIcon-1024.png"; contents=folder/"Contents.json"
    if not original.exists(): sys.exit(f"Missing source icon {original}")
    data=json.loads(contents.read_text()); images=[item for item in data.get('images',[]) if item.get('idiom')!='ipad']
    for size,scale in sizes:
        px=round(float(size)*scale)
        filename=f"AppIcon-iPad-{size}@{scale}x.png"
        subprocess.run(["sips","-z",str(px),str(px),str(original),"--out",str(folder/filename)],check=True,stdout=subprocess.DEVNULL)
        images.append({"filename":filename,"idiom":"ipad","scale":f"{scale}x","size":f"{size}x{size}"})
    data['images']=images
    contents.write_text(json.dumps(data,indent=2)+'\n')
print(f"Prepared iPad icons in {len(folders)} catalogs")
