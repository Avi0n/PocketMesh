"""MeshCore Enum Sync Generator

This script downloads the latest MeshCore Python library from GitHub,
extracts enum definitions from Python source files using AST parsing,
and generates Swift enums by extending the existing protocol enums in
PocketMeshKit/Protocol/ProtocolFrame.swift.
"""

# Import sys and run the main script as the main entry point
import sys
import subprocess
from pathlib import Path

def main():
    """Main entry point that delegates to the script"""
    script_path = Path(__file__).parent.parent.parent / "meshcore_enum_generator.py"
    result = subprocess.run([sys.executable, str(script_path)] + sys.argv[1:])
    return result.returncode

# Make the main function available at package level
__all__ = ['main']