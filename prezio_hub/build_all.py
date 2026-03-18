"""
Build-Script fuer PrezioHub Distribution
Baut alle Tools als .exe und erstellt einen sauberen Ordner fuer den Installer.

Usage: python build_all.py
"""

import os
import shutil
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DIST_DIR = os.path.join(SCRIPT_DIR, "dist", "PrezioHub")

BUILDS = [
    {
        "name": "PrezioHub",
        "script": os.path.join(SCRIPT_DIR, "prezio_hub.py"),
        "icon": os.path.join(SCRIPT_DIR, "prezio_hub.ico"),
        "version": os.path.join(SCRIPT_DIR, "version_info.py"),
        "windowed": True,
        "uac_admin": False,
        "hidden_imports": ["paramiko", "bcrypt", "nacl", "cryptography"],
        "add_data": [(os.path.join(SCRIPT_DIR, "prezio_hub.ico"), ".")],
    },
    {
        "name": "PrezioImager",
        "script": os.path.join(PROJECT_ROOT, "pi_recorder", "prezio_imager.py"),
        "icon": os.path.join(PROJECT_ROOT, "pi_recorder", "prezio_imager.ico"),
        "version": os.path.join(PROJECT_ROOT, "pi_recorder", "version_info.py"),
        "windowed": True,
        "uac_admin": True,
    },
    {
        "name": "PrezioRecorder",
        "script": os.path.join(PROJECT_ROOT, "pc_recorder", "prezio_recorder.py"),
        "icon": os.path.join(SCRIPT_DIR, "prezio_tool.ico"),
        "version": None,
        "windowed": True,
        "uac_admin": False,
        "hidden_imports": ["serial", "serial.tools", "serial.tools.list_ports"],
    },
    {
        "name": "PrezioDummy",
        "script": os.path.join(PROJECT_ROOT, "dummy_server", "server.py"),
        "icon": os.path.join(SCRIPT_DIR, "prezio_tool.ico"),
        "version": None,
        "windowed": False,
        "uac_admin": False,
    },
]

DOCS = [
    ("README.md",                                "Projekt_Uebersicht.md"),
    ("DOKUMENTATION.md",                         "Technische_Dokumentation.md"),
    ("ANLEITUNG_APPSTORE_CONNECT_CODEMAGIC.md",  "App_Store_und_Google_Play.md"),
    ("ANLEITUNG_PI_KLONEN.md",                   "Pi_Image_klonen.md"),
    ("pi_recorder/howto.txt",                    "Raspberry_Pi_Ersteinrichtung.md"),
    ("pc_recorder/README.md",                    "PC_Recorder_Handbuch.md"),
    ("dummy_server/README.md",                   "Dummy_Server_Anleitung.md"),
    ("PrezioHub_Anleitung.md",                   "PrezioHub_Anleitung.md"),
]


def log(msg):
    print(f"\n{'='*60}\n  {msg}\n{'='*60}")


def build_exe(cfg):
    name = cfg["name"]
    log(f"Building {name}...")

    if not os.path.exists(cfg["script"]):
        print(f"  SKIP: {cfg['script']} not found")
        return False

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm", "--onefile",
        "--name", name,
    ]

    if cfg["windowed"]:
        cmd.append("--windowed")
    else:
        cmd.append("--console")

    if cfg.get("icon") and os.path.exists(cfg["icon"]):
        cmd.extend(["--icon", cfg["icon"]])

    if cfg.get("version") and os.path.exists(cfg["version"]):
        cmd.extend(["--version-file", cfg["version"]])

    if cfg.get("uac_admin"):
        cmd.append("--uac-admin")

    for imp in cfg.get("hidden_imports", []):
        cmd.extend(["--hidden-import", imp])

    for src, dst in cfg.get("add_data", []):
        cmd.extend(["--add-data", f"{src};{dst}"])

    cmd.extend(["--distpath", DIST_DIR])
    cmd.extend(["--workpath", os.path.join(SCRIPT_DIR, "build", name)])
    cmd.extend(["--specpath", os.path.join(SCRIPT_DIR, "build")])

    cmd.append(cfg["script"])

    result = subprocess.run(cmd, cwd=SCRIPT_DIR)
    if result.returncode != 0:
        print(f"  FAILED: {name}")
        return False

    print(f"  OK: {name}.exe")
    return True


def copy_docs():
    log("Copying documentation...")
    docs_dir = os.path.join(DIST_DIR, "docs")
    os.makedirs(docs_dir, exist_ok=True)

    for src_rel, dst_name in DOCS:
        src = os.path.join(PROJECT_ROOT, src_rel)
        dst = os.path.join(docs_dir, dst_name)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            print(f"  OK: {dst_name}")
        else:
            print(f"  SKIP: {src_rel} not found")

    ico_src = os.path.join(SCRIPT_DIR, "prezio_hub.ico")
    if os.path.exists(ico_src):
        shutil.copy2(ico_src, os.path.join(DIST_DIR, "prezio_hub.ico"))
        print(f"  OK: prezio_hub.ico")



def cleanup():
    build_dir = os.path.join(SCRIPT_DIR, "build")
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir, ignore_errors=True)


def main():
    start = time.time()
    log("PrezioHub Distribution Builder")
    print(f"  Project root: {PROJECT_ROOT}")
    print(f"  Output:       {DIST_DIR}")

    if os.path.exists(DIST_DIR):
        shutil.rmtree(DIST_DIR, ignore_errors=True)
        time.sleep(1)
        if os.path.exists(DIST_DIR):
            for f in os.listdir(DIST_DIR):
                fp = os.path.join(DIST_DIR, f)
                try:
                    if os.path.isfile(fp):
                        os.remove(fp)
                    elif os.path.isdir(fp):
                        shutil.rmtree(fp, ignore_errors=True)
                except OSError:
                    pass
    os.makedirs(DIST_DIR, exist_ok=True)

    ok = 0
    fail = 0
    for cfg in BUILDS:
        if build_exe(cfg):
            ok += 1
        else:
            fail += 1

    copy_docs()
    cleanup()

    elapsed = time.time() - start
    log(f"Done! {ok} built, {fail} failed ({elapsed:.0f}s)")
    print(f"\n  Distribution: {DIST_DIR}")
    print(f"  Contents:")
    for f in sorted(os.listdir(DIST_DIR)):
        full = os.path.join(DIST_DIR, f)
        if os.path.isdir(full):
            print(f"    {f}/")
            for sf in sorted(os.listdir(full)):
                print(f"      {sf}")
        else:
            size_mb = os.path.getsize(full) / (1024 * 1024)
            print(f"    {f}  ({size_mb:.1f} MB)")

    if fail > 0:
        print(f"\n  WARNING: {fail} build(s) failed!")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
