#!/usr/bin/env python3
"""Copies ffmpeg and every non-system dylib it needs into the .app.

The DASH/ClearKey and HEVC-in-TS channels are repackaged by ffmpeg at runtime,
so a machine without Homebrew would otherwise lose them. Dependencies are
rewritten to load from Contents/Frameworks, making the bundle self-contained.
"""
import os
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def deps(binary):
    out = subprocess.run(["otool", "-L", binary], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines()[1:]:
        path = line.strip().split(" (")[0]
        if not path or path.startswith("@"):
            continue
        if path.startswith(SYSTEM_PREFIXES):
            continue
        found.append(path)
    return found


def main():
    app = sys.argv[1]
    # ffprobe comes along because the remuxer counts audio tracks before it
    # can tell the HLS muxer how many renditions to write.
    tools = {}
    for name in ("ffmpeg", "ffprobe"):
        path = shutil.which(name) or f"/opt/homebrew/bin/{name}"
        if os.path.exists(path):
            tools[name] = path
    if "ffmpeg" not in tools:
        print("ffmpeg não encontrado — DMG sairá sem suporte a DASH/HEVC")
        return 0

    resources = os.path.join(app, "Contents", "Resources")
    frameworks = os.path.join(app, "Contents", "Frameworks")
    os.makedirs(resources, exist_ok=True)
    os.makedirs(frameworks, exist_ok=True)

    targets = []
    for name, path in tools.items():
        target = os.path.join(resources, name)
        shutil.copy2(os.path.realpath(path), target)
        os.chmod(target, 0o755)
        targets.append(target)

    # Breadth-first over the dependency graph, copying each library once.
    copied = {}
    queue = list(targets)
    while queue:
        binary = queue.pop()
        for dep in deps(binary):
            name = os.path.basename(dep)
            if name not in copied:
                real = os.path.realpath(dep)
                if not os.path.exists(real):
                    continue
                dest = os.path.join(frameworks, name)
                shutil.copy2(real, dest)
                os.chmod(dest, 0o755)
                subprocess.run(["install_name_tool", "-id",
                                f"@loader_path/{name}", dest], capture_output=True)
                copied[name] = dest
                queue.append(dest)

            # ffmpeg sits in Resources, the libraries next to each other.
            new = (f"@executable_path/../Frameworks/{name}"
                   if binary in targets else f"@loader_path/{name}")
            subprocess.run(["install_name_tool", "-change", dep, new, binary],
                           capture_output=True)

    for path in list(copied.values()) + targets:
        subprocess.run(["codesign", "--force", "--sign", "-", path], capture_output=True)

    print(f"{'+'.join(sorted(tools))} embutidos com {len(copied)} bibliotecas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
