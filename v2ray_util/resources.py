"""Locate unpacked package data without a setuptools runtime dependency.

The distribution is zip_safe=False and contains mutable legacy cache files.
Keep the same paths as resource_filename, including module-relative resources.
"""
import importlib
from pathlib import Path


def resource_filename(package_or_module, name):
    module = importlib.import_module(package_or_module)
    return str(Path(module.__file__).resolve().parent / name)
