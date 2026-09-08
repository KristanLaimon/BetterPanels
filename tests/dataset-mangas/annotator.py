#!/usr/bin/env python3
"""
Launcher script for PanelsPlus Manga Panel Annotator.

Usage:
    python3 tests/dataset-mangas/annotator.py
    python3 tests/dataset-mangas/annotator.py path/to/comic.cbz
    python3 tests/dataset-mangas/annotator.py path/to/comic.pdf --dataset-dir tests/dataset-mangas/dataset-private
"""

import os
import sys

# Ensure repository and annotator directory are on python path
cur_dir = os.path.dirname(os.path.abspath(__file__))
if cur_dir not in sys.path:
    sys.path.insert(0, cur_dir)

from annotator.app import main

if __name__ == "__main__":
    main()
