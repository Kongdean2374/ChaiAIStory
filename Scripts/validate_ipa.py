#!/usr/bin/env python3
import plistlib, stat, struct, sys, zipfile, re
from pathlib import Path
from pathlib import PurePosixPath
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, "Corrupt ZIP"
    names = archive.namelist()
    prefix = "Payload/ChaiAIStory.app/"
    assert all(n == "Payload/" or n.startswith(prefix) for n in names), "Unexpected root contents"
    assert not any(".." in PurePosixPath(n).parts or n.startswith("/") for n in names)
    assert not any("_CodeSignature" in n or n.endswith((".mobileprovision", ".p12", ".pem", ".key")) for n in names)
    info = plistlib.loads(archive.read(prefix+"Info.plist"))
    assert info["CFBundleIdentifier"] == "com.kongdean.ChaiAIStory"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    assert info["DTPlatformName"] == "iphoneos"
    source = (Path(__file__).parent / "generate_project.py").read_text()
    version = re.search(r'"MARKETING_VERSION":"([^"]+)"', source).group(1)
    build = re.search(r'"CURRENT_PROJECT_VERSION":"([^"]+)"', source).group(1)
    assert info["CFBundleShortVersionString"] == version, "Wrong marketing version"
    assert info["CFBundleVersion"] == build, "Wrong build number"
    print("Version verified: " + version + " (Build " + build + ")")
    binary = archive.read(prefix+info["CFBundleExecutable"])
    assert len(binary)>4096
    assert struct.unpack_from("<I",binary)[0] == 0xfeedfacf
    assert struct.unpack_from("<I",binary,4)[0] == 0x0100000c
    ncmds=struct.unpack_from("<I",binary,16)[0]
    offset=32
    for _ in range(ncmds):
        cmd,length=struct.unpack_from("<II",binary,offset)
        assert cmd != 0x1d, "Mach-O contains LC_CODE_SIGNATURE"
        assert length >= 8
        offset += length
    mode=archive.getinfo(prefix+info["CFBundleExecutable"]).external_attr>>16
    assert mode & stat.S_IXUSR, "Executable bit missing"
    assert prefix+"Assets.car" in names, "Missing app resources"
print("Verified: unique Payload/ChaiAIStory.app, unsigned arm64 iPhoneOS executable, plist and resources")
