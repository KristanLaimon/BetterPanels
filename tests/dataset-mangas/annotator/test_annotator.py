"""
Automated unit and integration tests for the Manga Panel Annotator.
Verifies document loading, panel manipulation, full-page shortcuts,
and Lua PanelsPlus schema compatibility.
"""

import io
import json
import os
import shutil
import tempfile
import unittest
import zipfile
from PIL import Image

# Ensure PyQt6 runs headless
os.environ["QT_QPA_PLATFORM"] = "offscreen"

import sys
pkg_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if pkg_dir not in sys.path:
    sys.path.insert(0, pkg_dir)

import fitz  # PyMuPDF
from PyQt6.QtWidgets import QApplication

from annotator.document_reader import DocumentReader, natural_sort_key
from annotator.dataset_manager import DatasetManager, Panel, PageAnnotation
from annotator.canvas import MangaCanvas
from annotator.app import AnnotatorMainWindow


class TestAnnotator(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="annotator_test_")

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _create_dummy_image(self, width=400, height=600, color=(255, 255, 255)) -> Image.Image:
        img = Image.new("RGB", (width, height), color=color)
        return img

    def test_natural_sort_key(self):
        items = ["page_10.jpg", "page_1.jpg", "page_2.jpg", "page_20.jpg"]
        sorted_items = sorted(items, key=natural_sort_key)
        self.assertEqual(sorted_items, ["page_1.jpg", "page_2.jpg", "page_10.jpg", "page_20.jpg"])

    def test_document_reader_cbz(self):
        cbz_path = os.path.join(self.test_dir, "test_manga.cbz")
        with zipfile.ZipFile(cbz_path, "w") as zf:
            for i in range(1, 4):
                img = self._create_dummy_image(200, 300)
                buf = io.BytesIO()
                img.save(buf, format="PNG")
                zf.writestr(f"page_{i:02d}.png", buf.getvalue())

        reader = DocumentReader(cbz_path)
        self.assertEqual(reader.total_pages, 3)
        self.assertEqual(reader.book_title, "test_manga")

        page1 = reader.get_page(1)
        self.assertIsNotNone(page1)
        self.assertEqual(page1.native_w, 200)
        self.assertEqual(page1.native_h, 300)

        pil_im = page1.get_pil_image()
        self.assertEqual(pil_im.size, (200, 300))
        reader.close()

    def test_document_reader_pdf(self):
        pdf_path = os.path.join(self.test_dir, "sample.pdf")
        doc = fitz.open()
        for i in range(2):
            page = doc.new_page(width=300, height=450)
            page.draw_rect(fitz.Rect(10, 10, 100, 100), color=(0, 0, 0), fill=(0.5, 0.5, 0.5))
        doc.save(pdf_path)
        doc.close()

        reader = DocumentReader(pdf_path, render_dpi=150)
        self.assertEqual(reader.total_pages, 2)
        page1 = reader.get_page(1)
        self.assertIsNotNone(page1)
        pil_im = page1.get_pil_image()
        self.assertGreater(pil_im.width, 0)
        self.assertGreater(pil_im.height, 0)
        reader.close()

    def test_dataset_manager_export_and_compatibility(self):
        ds_dir = os.path.join(self.test_dir, "dataset")
        mgr = DatasetManager(ds_dir)

        book_title = "custom_series"
        p1 = Panel(10, 20, 200, 300)
        p2 = Panel(10, 340, 200, 250)
        mgr.set_page_frames(book_title, page_index=1, frames=[p1, p2])

        dummy_img = self._create_dummy_image(300, 600)
        mgr.export_page_image(book_title, 1, dummy_img, ext="png")

        json_file = mgr.save_dataset()
        self.assertTrue(os.path.exists(json_file))

        with open(json_file, "r") as f:
            data = json.load(f)

        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["book_title"], book_title)
        self.assertEqual(len(data[0]["pages"]), 1)
        self.assertEqual(len(data[0]["pages"][0]["frame"]), 2)
        self.assertEqual(data[0]["pages"][0]["frame"][0]["x"], 10)
        self.assertEqual(data[0]["pages"][0]["frame"][0]["y"], 20)

    def test_canvas_panel_operations(self):
        canvas = MangaCanvas()
        canvas.native_w = 800
        canvas.native_h = 1200

        # Full page panel
        canvas.add_full_page_panel()
        self.assertEqual(len(canvas.panels), 1)
        self.assertEqual(canvas.panels[0].x, 0)
        self.assertEqual(canvas.panels[0].y, 0)
        self.assertEqual(canvas.panels[0].w, 800)
        self.assertEqual(canvas.panels[0].h, 1200)

        # Add second panel
        p2 = Panel(50, 50, 300, 400)
        canvas.panels.append(p2)
        self.assertEqual(len(canvas.panels), 2)

        # Move panel up (swap order)
        canvas.move_panel_up(1)
        self.assertEqual(canvas.panels[0].x, 50)
        self.assertEqual(canvas.panels[1].x, 0)

        # Move panel down
        canvas.move_panel_down(0)
        self.assertEqual(canvas.panels[0].x, 0)
        self.assertEqual(canvas.panels[1].x, 50)

        # Delete selected
        canvas.select_panel(0)
        canvas.delete_selected_panel()
        self.assertEqual(len(canvas.panels), 1)
        self.assertEqual(canvas.panels[0].x, 50)

        # Clear
        canvas.clear_panels()
        self.assertEqual(len(canvas.panels), 0)

    def test_extract_all_pages_ordered(self):
        cbz_path = os.path.join(self.test_dir, "manga_extract.cbz")
        with zipfile.ZipFile(cbz_path, "w") as zf:
            for i in range(5):
                img = self._create_dummy_image(200, 300)
                buf = io.BytesIO()
                img.save(buf, format="PNG")
                zf.writestr(f"p_{i}.png", buf.getvalue())

        reader = DocumentReader(cbz_path)
        out_dir = os.path.join(self.test_dir, "dataset", "manga_extract")
        extracted = reader.extract_all_pages(out_dir)
        self.assertEqual(len(extracted), 5)
        self.assertTrue(os.path.exists(os.path.join(out_dir, "00.png")))
        self.assertTrue(os.path.exists(os.path.join(out_dir, "01.png")))
        self.assertTrue(os.path.exists(os.path.join(out_dir, "04.png")))
        reader.close()

    def test_extract_all_pages_cancellation(self):
        cbz_path = os.path.join(self.test_dir, "manga_cancel.cbz")
        with zipfile.ZipFile(cbz_path, "w") as zf:
            for i in range(10):
                img = self._create_dummy_image(200, 300)
                buf = io.BytesIO()
                img.save(buf, format="PNG")
                zf.writestr(f"p_{i}.png", buf.getvalue())

        reader = DocumentReader(cbz_path)
        out_dir = os.path.join(self.test_dir, "dataset", "manga_cancel")

        # Cancel after 2 pages
        def cancel_callback(curr, tot):
            if curr >= 2:
                return False
            return True

        extracted = reader.extract_all_pages(out_dir, progress_callback=cancel_callback)
        # Should have stopped early (less than total 10 pages)
        self.assertLess(len(extracted), 10)
        self.assertFalse(os.path.exists(os.path.join(out_dir, "09.png")))
        reader.close()

    def test_recent_books_and_progress(self):
        ds_dir = os.path.join(self.test_dir, "dataset")
        mgr = DatasetManager(ds_dir)

        book_title = "naruto_ch01"
        book_dir = mgr.get_book_dir(book_title)
        os.makedirs(book_dir, exist_ok=True)

        # Create 4 pages: 00.png to 03.png
        for i in range(4):
            img = self._create_dummy_image(100, 150)
            img.save(os.path.join(book_dir, f"{i:02d}.png"))

        # Annotate 2 of the 4 pages (50% progress)
        mgr.set_page_frames(book_title, 1, [Panel(10, 10, 50, 50)])
        mgr.set_page_frames(book_title, 2, [Panel(10, 10, 50, 50)])
        mgr.save_book_dataset(book_title)

        recent = mgr.get_recent_books()
        self.assertEqual(len(recent), 1)
        self.assertEqual(recent[0]["book_title"], book_title)
        self.assertEqual(recent[0]["total_pages"], 4)
        self.assertEqual(recent[0]["annotated_pages"], 2)
        self.assertEqual(recent[0]["progress_percent"], 50)
        self.assertFalse(recent[0]["finished"])

        # Mark finished
        mgr.mark_book_finished(book_title, True)
        recent_after = mgr.get_recent_books()
        self.assertTrue(recent_after[0]["finished"])
        self.assertEqual(recent_after[0]["progress_percent"], 100)

    def test_gitignore_dmca_rule(self):
        import subprocess
        # Check that 00.png, 01.png, 02.png are kept, and 03.png+ are ignored by git
        ds_dir = "tests/dataset-mangas/dataset"
        test_book = os.path.join(ds_dir, "test_dmca_book")
        os.makedirs(test_book, exist_ok=True)
        try:
            for i in range(6):
                with open(os.path.join(test_book, f"{i:02d}.png"), "w") as f:
                    f.write("x")

            res0 = subprocess.run(["git", "check-ignore", os.path.join(test_book, "00.png")], capture_output=True)
            self.assertNotEqual(res0.returncode, 0, "00.png should NOT be ignored")

            res2 = subprocess.run(["git", "check-ignore", os.path.join(test_book, "02.png")], capture_output=True)
            self.assertNotEqual(res2.returncode, 0, "02.png should NOT be ignored")

            res3 = subprocess.run(["git", "check-ignore", os.path.join(test_book, "03.png")], capture_output=True)
            self.assertEqual(res3.returncode, 0, "03.png SHOULD be ignored by git")

            res4 = subprocess.run(["git", "check-ignore", os.path.join(test_book, "04.png")], capture_output=True)
            self.assertEqual(res4.returncode, 0, "04.png SHOULD be ignored by git")
        finally:
            shutil.rmtree(test_book, ignore_errors=True)

    def test_annotator_window_load_and_save(self):
        cbz_path = os.path.join(self.test_dir, "book.cbz")
        with zipfile.ZipFile(cbz_path, "w") as zf:
            img = self._create_dummy_image(400, 600)
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            zf.writestr("p1.png", buf.getvalue())

        ds_dir = os.path.join(self.test_dir, "my_dataset")
        win = AnnotatorMainWindow(dataset_dir=ds_dir)
        win.import_or_open_file(cbz_path, friendly_name="test_book")
        self.assertEqual(win.book_title, "test_book")

        # Add full page panel via shortcut
        win.canvas.add_full_page_panel()
        self.assertEqual(len(win.canvas.panels), 1)

        # Save dataset
        win.save_dataset(show_dialog=False)

        # Check book annotation.json generated
        annotation_file = os.path.join(ds_dir, "test_book", "annotation.json")
        self.assertTrue(os.path.exists(annotation_file))
        with open(annotation_file, "r") as f:
            content = json.load(f)
        self.assertEqual(content[0]["book_title"], "test_book")
        self.assertEqual(len(content[0]["pages"][0]["frame"]), 1)
        win.close()

    def test_lua_manifest_interop(self):
        import subprocess
        ds_dir = os.path.join(self.test_dir, "lua_interop")
        mgr = DatasetManager(ds_dir)
        book_dir = mgr.get_book_dir("interop_book")
        os.makedirs(book_dir, exist_ok=True)
        img = self._create_dummy_image(400, 600)
        img.save(os.path.join(book_dir, "00.png"))

        p1 = Panel(50, 100, 300, 400)
        mgr.set_page_frames("interop_book", 1, [p1])
        mgr.save_book_dataset("interop_book")

        lua_code = f'''
        local Manifest = require("tests.dataset-mangas.dataset_manifest")
        local books = Manifest.loadManga("{ds_dir}")
        assert(#books == 1)
        assert(books[1].book_title == "interop_book")
        assert(#books[1].pages == 1)
        assert(books[1].pages[1].frames[1].x == 50)
        '''
        res = subprocess.run(["lua", "-e", lua_code], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Lua failed: {res.stderr}")

    def test_canvas_undo_redo(self):
        canvas = MangaCanvas()
        canvas.native_w = 800
        canvas.native_h = 1200

        self.assertEqual(len(canvas.panels), 0)

        # 1. Add full page panel
        canvas.add_full_page_panel()
        self.assertEqual(len(canvas.panels), 1)

        # 2. Add second panel
        canvas.push_undo()
        canvas.panels.append(Panel(10, 10, 100, 100))
        self.assertEqual(len(canvas.panels), 2)

        # 3. Undo second panel
        canvas.undo()
        self.assertEqual(len(canvas.panels), 1)

        # 4. Undo first panel
        canvas.undo()
        self.assertEqual(len(canvas.panels), 0)

        # 5. Redo first panel
        canvas.redo()
        self.assertEqual(len(canvas.panels), 1)

        # 6. Redo second panel
        canvas.redo()
        self.assertEqual(len(canvas.panels), 2)

    def test_canvas_precision_mode(self):
        canvas = MangaCanvas()
        self.assertTrue(canvas.precision_mouse_enabled)

        canvas.set_precision_mode(False)
        self.assertFalse(canvas.precision_mouse_enabled)

        canvas.set_precision_mode(True)
        self.assertTrue(canvas.precision_mouse_enabled)


if __name__ == "__main__":
    unittest.main()
