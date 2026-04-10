"""
build_backend.py - Empacota backend Python em executável standalone

Uso:
    python build_backend.py
    
Gera: dist/aion2_backend.exe
"""

import PyInstaller.__main__
import os
import shutil
from pathlib import Path


def build_backend():
    """Compila backend Python para executável usando PyInstaller"""

    backend_dir = Path(__file__).parent
    dist_dir = backend_dir / "dist"
    build_dir = backend_dir / "build"

    # Limpa builds anteriores
    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    if build_dir.exists():
        shutil.rmtree(build_dir)

    print("[BUILD] Compilando backend Python com PyInstaller...")

    PyInstaller.__main__.run([
        str(backend_dir / "main.py"),
        "--name=aion2_backend",
        "--onefile",
        "--clean",
        "--noconfirm",
        "--console",  # Manter console para logs
        "--add-data", f"{backend_dir / 'packet_parser.py'};.",
        "--add-data", f"{backend_dir / 'calculator.py'};.",
        "--add-data", f"{backend_dir / 'capture.py'};.",
        "--hidden-import=scapy",
        "--hidden-import=websockets",
        "--collect-all=scapy",
        f"--distpath={dist_dir}",
        f"--workpath={build_dir}",
        f"--specpath={backend_dir}",
    ])

    backend_exe = dist_dir / "aion2_backend.exe"

    if backend_exe.exists():
        print(f"[SUCCESS] Backend compilado: {backend_exe}")
        print(
            f"          Tamanho: {backend_exe.stat().st_size / 1024 / 1024:.1f} MB")
        return True
    else:
        print("[ERROR] Erro ao compilar backend")
        return False


if __name__ == "__main__":
    success = build_backend()
    exit(0 if success else 1)
