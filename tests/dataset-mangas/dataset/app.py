#!/usr/bin/env python3
"""
Launcher inside tests/dataset-mangas/dataset for the Manga Panel Annotator.
"""

import os
import sys

parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from annotator.app import main

if __name__ == "__main__":
    main()
