"""
Interactive annotation canvas for manga pages using PyQt6.
Supports drawing sequential panels, dragging, resizing via 8 handles,
zoom/pan, number badges, and full-page panel shortcuts.
"""

from typing import List, Optional, Tuple
from PyQt6.QtCore import Qt, QRect, QRectF, QPoint, QPointF, pyqtSignal
from PyQt6.QtGui import (
    QPainter, QPen, QBrush, QColor, QFont, QPixmap, QImage, QCursor,
    QPaintEvent, QMouseEvent, QWheelEvent, QKeyEvent, QFontMetrics
)
from PyQt6.QtWidgets import QWidget

from .dataset_manager import Panel

HANDLE_SIZE = 8
MIN_BOX_SIZE = 8

# Handle positions
HANDLE_NONE = 0
HANDLE_TL = 1
HANDLE_T = 2
HANDLE_TR = 3
HANDLE_R = 4
HANDLE_BR = 5
HANDLE_B = 6
HANDLE_BL = 7
HANDLE_L = 8
HANDLE_MOVE = 9


class MangaCanvas(QWidget):
    """Interactive canvas widget displaying the page image and bounding box annotations."""

    # Signals
    panels_changed = pyqtSignal()
    panel_selected = pyqtSignal(int)  # index of selected panel, or -1
    status_message = pyqtSignal(str)
    cursor_position = pyqtSignal(int, int)  # (native_x, native_y)
    precision_mode_changed = pyqtSignal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

        self._pixmap: Optional[QPixmap] = None
        self.native_w = 0
        self.native_h = 0
        self.panels: List[Panel] = []
        self.selected_panel_index = -1

        # View transform
        self.zoom_factor = 1.0
        self.offset_x = 0
        self.offset_y = 0

        # Precision mouse fine-tuning
        self.precision_mouse_enabled = True
        self._accum_delta_x = 0.0
        self._accum_delta_y = 0.0
        self._last_raw_mouse_pos: Optional[QPoint] = None
        self._current_image_box: Optional[Tuple[int, int, int, int]] = None

        # Undo / Redo history stacks
        self._undo_stack: List[List[Panel]] = []
        self._redo_stack: List[List[Panel]] = []
        self._panels_at_drag_start: List[Panel] = []

        # Interaction state
        self._mode = "idle"  # "idle", "drawing", "resizing", "moving", "panning"
        self._drag_start_pos: Optional[QPoint] = None
        self._current_mouse_pos: Optional[QPoint] = None
        self._active_handle = HANDLE_NONE
        self._panel_before_drag: Optional[Panel] = None
        self._space_pressed = False
        self._pan_start_pos: Optional[QPoint] = None

    def set_precision_mode(self, enabled: bool):
        """Enable or disable slow mouse precision damping mode."""
        self.precision_mouse_enabled = bool(enabled)
        self.precision_mode_changed.emit(self.precision_mouse_enabled)
        state_str = "ON" if self.precision_mouse_enabled else "OFF"
        self.status_message.emit(f"Precision mouse mode: {state_str}")

    def push_undo(self):
        """Save current panels state to undo stack and clear redo stack."""
        self._undo_stack.append([p.copy() for p in self.panels])
        if len(self._undo_stack) > 50:
            self._undo_stack.pop(0)
        self._redo_stack.clear()

    def undo(self):
        """Revert to previous panels state."""
        if not self._undo_stack:
            return
        self._redo_stack.append([p.copy() for p in self.panels])
        self.panels = self._undo_stack.pop()
        self.selected_panel_index = min(self.selected_panel_index, len(self.panels) - 1)
        self.panels_changed.emit()
        self.panel_selected.emit(self.selected_panel_index)
        self.update()
        self.status_message.emit("Undo performed.")

    def redo(self):
        """Reapply previously undone panels state."""
        if not self._redo_stack:
            return
        self._undo_stack.append([p.copy() for p in self.panels])
        self.panels = self._redo_stack.pop()
        self.selected_panel_index = min(self.selected_panel_index, len(self.panels) - 1)
        self.panels_changed.emit()
        self.panel_selected.emit(self.selected_panel_index)
        self.update()
        self.status_message.emit("Redo performed.")

    def set_page(self, pixmap: Optional[QPixmap], panels: List[Panel]):
        """Update current page pixmap and panels."""
        self._pixmap = pixmap
        if pixmap and not pixmap.isNull():
            self.native_w = pixmap.width()
            self.native_h = pixmap.height()
        else:
            self.native_w = 0
            self.native_h = 0

        self.panels = [p.copy() for p in panels]
        self.selected_panel_index = -1
        self._mode = "idle"
        self._undo_stack.clear()
        self._redo_stack.clear()
        self.update()

    def set_zoom(self, zoom: float):
        """Set zoom factor clamped between 0.05 and 10.0."""
        self.zoom_factor = max(0.05, min(10.0, float(zoom)))
        self.update()

    def fit_to_window(self, view_rect: QRect):
        """Scale image to fit entirely inside view_rect while preserving aspect ratio."""
        if self.native_w == 0 or self.native_h == 0:
            return
        scale_w = view_rect.width() / self.native_w
        scale_h = view_rect.height() / self.native_h
        new_zoom = min(scale_w, scale_h) * 0.95
        self.zoom_factor = max(0.05, min(10.0, new_zoom))
        self.update()

    def fit_to_width(self, view_rect: QRect):
        """Scale image to fit width of view_rect."""
        if self.native_w == 0:
            return
        new_zoom = (view_rect.width() / self.native_w) * 0.96
        self.zoom_factor = max(0.05, min(10.0, new_zoom))
        self.update()

    def image_to_widget(self, ix: float, iy: float) -> Tuple[float, float]:
        """Convert native image coordinates to widget coordinates."""
        wx = ix * self.zoom_factor + self.offset_x
        wy = iy * self.zoom_factor + self.offset_y
        return wx, wy

    def widget_to_image(self, wx: float, wy: float) -> Tuple[int, int]:
        """Convert widget coordinates to clamped native image coordinates."""
        if self.zoom_factor <= 0:
            return 0, 0
        ix = (wx - self.offset_x) / self.zoom_factor
        iy = (wy - self.offset_y) / self.zoom_factor
        ix = max(0, min(self.native_w, int(round(ix))))
        iy = max(0, min(self.native_h, int(round(iy))))
        return ix, iy

    def _get_handle_rects(self, panel: Panel) -> List[Tuple[int, QRectF]]:
        """Return list of (handle_type, QRectF) in widget coordinates for 8 resize handles."""
        wx, wy = self.image_to_widget(panel.x, panel.y)
        ww = panel.w * self.zoom_factor
        wh = panel.h * self.zoom_factor
        hs = HANDLE_SIZE
        half = hs / 2.0

        handles = [
            (HANDLE_TL, QRectF(wx - half, wy - half, hs, hs)),
            (HANDLE_T,  QRectF(wx + ww / 2 - half, wy - half, hs, hs)),
            (HANDLE_TR, QRectF(wx + ww - half, wy - half, hs, hs)),
            (HANDLE_R,  QRectF(wx + ww - half, wy + wh / 2 - half, hs, hs)),
            (HANDLE_BR, QRectF(wx + ww - half, wy + wh - half, hs, hs)),
            (HANDLE_B,  QRectF(wx + ww / 2 - half, wy + wh - half, hs, hs)),
            (HANDLE_BL, QRectF(wx - half, wy + wh - half, hs, hs)),
            (HANDLE_L,  QRectF(wx - half, wy + wh / 2 - half, hs, hs)),
        ]
        return handles

    def _hit_test(self, pos: QPoint) -> Tuple[int, int]:
        """Determine hit handle and panel index under mouse position."""
        # 1. Check handles of selected panel first
        if 0 <= self.selected_panel_index < len(self.panels):
            p = self.panels[self.selected_panel_index]
            for h_type, r in self._get_handle_rects(p):
                if r.contains(QPointF(pos)):
                    return h_type, self.selected_panel_index

        # 2. Check panel bodies (search top-most first)
        ix, iy = self.widget_to_image(pos.x(), pos.y())
        for idx in range(len(self.panels) - 1, -1, -1):
            p = self.panels[idx]
            if p.contains_point(ix, iy):
                return HANDLE_MOVE, idx

        return HANDLE_NONE, -1

    def add_full_page_panel(self):
        """Add a bounding box covering the entire page."""
        if self.native_w == 0 or self.native_h == 0:
            return
        self.push_undo()
        panel = Panel(0, 0, self.native_w, self.native_h)
        self.panels.append(panel)
        self.selected_panel_index = len(self.panels) - 1
        self.panels_changed.emit()
        self.panel_selected.emit(self.selected_panel_index)
        self.update()

    def select_panel(self, idx: int):
        """Set selected panel by index."""
        if -1 <= idx < len(self.panels):
            self.selected_panel_index = idx
            self.panel_selected.emit(idx)
            self.update()

    def delete_selected_panel(self):
        """Remove currently selected panel."""
        if 0 <= self.selected_panel_index < len(self.panels):
            self.push_undo()
            self.panels.pop(self.selected_panel_index)
            self.selected_panel_index = min(self.selected_panel_index, len(self.panels) - 1)
            self.panels_changed.emit()
            self.panel_selected.emit(self.selected_panel_index)
            self.update()

    def clear_panels(self):
        """Clear all panels on this page."""
        if not self.panels:
            return
        self.push_undo()
        self.panels.clear()
        self.selected_panel_index = -1
        self.panels_changed.emit()
        self.panel_selected.emit(-1)
        self.update()

    def move_panel_up(self, idx: int):
        """Move panel earlier in reading order sequence."""
        if idx > 0 and idx < len(self.panels):
            self.push_undo()
            self.panels[idx], self.panels[idx - 1] = self.panels[idx - 1], self.panels[idx]
            self.selected_panel_index = idx - 1
            self.panels_changed.emit()
            self.panel_selected.emit(self.selected_panel_index)
            self.update()

    def move_panel_down(self, idx: int):
        """Move panel later in reading order sequence."""
        if 0 <= idx < len(self.panels) - 1:
            self.push_undo()
            self.panels[idx], self.panels[idx + 1] = self.panels[idx + 1], self.panels[idx]
            self.selected_panel_index = idx + 1
            self.panels_changed.emit()
            self.panel_selected.emit(self.selected_panel_index)
            self.update()

    # --- Mouse & Keyboard Event Handlers ---

    def keyPressEvent(self, event: QKeyEvent):
        if event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            if event.key() == Qt.Key.Key_Z:
                if event.modifiers() & Qt.KeyboardModifier.ShiftModifier:
                    self.redo()
                else:
                    self.undo()
                return
            elif event.key() == Qt.Key.Key_Y:
                self.redo()
                return

        if event.key() == Qt.Key.Key_Space:
            self._space_pressed = True
            self.setCursor(QCursor(Qt.CursorShape.OpenHandCursor))
        elif event.key() == Qt.Key.Key_F:
            self.add_full_page_panel()
        elif event.key() == Qt.Key.Key_P:
            self.set_precision_mode(not self.precision_mouse_enabled)
        elif event.key() in (Qt.Key.Key_Delete, Qt.Key.Key_Backspace):
            self.delete_selected_panel()
        elif event.key() == Qt.Key.Key_Escape:
            if self._mode != "idle":
                self._mode = "idle"
                self._current_image_box = None
                self.update()
            else:
                self.select_panel(-1)
        super().keyPressEvent(event)

    def keyReleaseEvent(self, event: QKeyEvent):
        if event.key() == Qt.Key.Key_Space:
            self._space_pressed = False
            self.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
        super().keyReleaseEvent(event)

    def wheelEvent(self, event: QWheelEvent):
        # Zoom with wheel
        delta = event.angleDelta().y()
        factor = 1.15 if delta > 0 else 0.85

        # Zoom centered on mouse pointer
        pos = event.position()
        old_zoom = self.zoom_factor
        new_zoom = max(0.05, min(10.0, old_zoom * factor))
        if old_zoom != new_zoom:
            self.offset_x = pos.x() - (pos.x() - self.offset_x) * (new_zoom / old_zoom)
            self.offset_y = pos.y() - (pos.y() - self.offset_y) * (new_zoom / old_zoom)
            self.zoom_factor = new_zoom
            self.update()

    def mousePressEvent(self, event: QMouseEvent):
        pos = event.position().toPoint()

        # Middle click or Space+Left click -> Pan
        if event.button() == Qt.MouseButton.MiddleButton or (event.button() == Qt.MouseButton.LeftButton and self._space_pressed):
            self._mode = "panning"
            self._pan_start_pos = pos
            self.setCursor(QCursor(Qt.CursorShape.ClosedHandCursor))
            return

        if event.button() == Qt.MouseButton.LeftButton:
            self._panels_at_drag_start = [p.copy() for p in self.panels]
            self._last_raw_mouse_pos = pos
            self._accum_delta_x = 0.0
            self._accum_delta_y = 0.0
            self._current_image_box = None

            handle, panel_idx = self._hit_test(pos)
            if handle in (HANDLE_TL, HANDLE_T, HANDLE_TR, HANDLE_R, HANDLE_BR, HANDLE_B, HANDLE_BL, HANDLE_L):
                self._mode = "resizing"
                self._active_handle = handle
                self._drag_start_pos = pos
                self._panel_before_drag = self.panels[self.selected_panel_index].copy()
            elif handle == HANDLE_MOVE:
                self.select_panel(panel_idx)
                self._mode = "moving"
                self._active_handle = HANDLE_MOVE
                self._drag_start_pos = pos
                self._panel_before_drag = self.panels[panel_idx].copy()
            else:
                # Start drawing new panel box
                self.select_panel(-1)
                self._mode = "drawing"
                self._drag_start_pos = pos
                self._current_mouse_pos = pos
                start_ix, start_iy = self.widget_to_image(pos.x(), pos.y())
                self._current_image_box = (start_ix, start_iy, start_ix, start_iy)

        elif event.button() == Qt.MouseButton.RightButton:
            # Right click deselects
            self.select_panel(-1)

        self.update()

    def mouseMoveEvent(self, event: QMouseEvent):
        pos = event.position().toPoint()
        ix, iy = self.widget_to_image(pos.x(), pos.y())
        self.cursor_position.emit(ix, iy)

        if self._mode == "panning":
            if self._pan_start_pos:
                dx = pos.x() - self._pan_start_pos.x()
                dy = pos.y() - self._pan_start_pos.y()
                self.offset_x += dx
                self.offset_y += dy
                self._pan_start_pos = pos
                self.update()
            return

        # Calculate precision mouse step with velocity damping
        raw_step_x = 0.0
        raw_step_y = 0.0
        if self._last_raw_mouse_pos is not None:
            raw_step_x = pos.x() - self._last_raw_mouse_pos.x()
            raw_step_y = pos.y() - self._last_raw_mouse_pos.y()
        self._last_raw_mouse_pos = pos

        dist = (raw_step_x ** 2 + raw_step_y ** 2) ** 0.5
        use_precision = self.precision_mouse_enabled or bool(event.modifiers() & Qt.KeyboardModifier.ShiftModifier)

        if use_precision and dist > 0:
            # When moving slowly (dist < 8px), dampen speed by 4x for millimeter pixel precision
            if dist < 6.0:
                damping = 0.25
            elif dist < 18.0:
                damping = 0.25 + 0.75 * ((dist - 6.0) / 12.0)
            else:
                damping = 1.0
        else:
            damping = 1.0

        self._accum_delta_x += raw_step_x * damping
        self._accum_delta_y += raw_step_y * damping

        # Image delta
        dx = int(round(self._accum_delta_x / self.zoom_factor))
        dy = int(round(self._accum_delta_y / self.zoom_factor))

        if self._mode == "drawing" and self._drag_start_pos:
            start_ix, start_iy = self.widget_to_image(self._drag_start_pos.x(), self._drag_start_pos.y())
            curr_ix = max(0, min(self.native_w, start_ix + dx))
            curr_iy = max(0, min(self.native_h, start_iy + dy))
            self._current_image_box = (start_ix, start_iy, curr_ix, curr_iy)
            self._current_mouse_pos = pos
            self.update()
            return

        if self._mode == "moving" and self._panel_before_drag and 0 <= self.selected_panel_index < len(self.panels):
            orig = self._panel_before_drag
            nx = max(0, min(self.native_w - orig.w, orig.x + dx))
            ny = max(0, min(self.native_h - orig.h, orig.y + dy))
            p = self.panels[self.selected_panel_index]
            p.x = nx
            p.y = ny
            self.update()
            return

        if self._mode == "resizing" and self._panel_before_drag and 0 <= self.selected_panel_index < len(self.panels):
            orig = self._panel_before_drag
            x, y, w, h = orig.x, orig.y, orig.w, orig.h

            if self._active_handle in (HANDLE_TL, HANDLE_L, HANDLE_BL):
                new_x = min(orig.x + orig.w - MIN_BOX_SIZE, max(0, orig.x + dx))
                w = orig.x + orig.w - new_x
                x = new_x
            if self._active_handle in (HANDLE_TR, HANDLE_R, HANDLE_BR):
                w = max(MIN_BOX_SIZE, min(self.native_w - orig.x, orig.w + dx))
            if self._active_handle in (HANDLE_TL, HANDLE_T, HANDLE_TR):
                new_y = min(orig.y + orig.h - MIN_BOX_SIZE, max(0, orig.y + dy))
                h = orig.y + orig.h - new_y
                y = new_y
            if self._active_handle in (HANDLE_BL, HANDLE_B, HANDLE_BR):
                h = max(MIN_BOX_SIZE, min(self.native_h - orig.y, orig.h + dy))

            p = self.panels[self.selected_panel_index]
            p.x, p.y, p.w, p.h = x, y, w, h
            self.update()
            return

        # Update cursor based on hover
        if self._space_pressed:
            self.setCursor(QCursor(Qt.CursorShape.OpenHandCursor))
            return

        handle, _ = self._hit_test(pos)
        if handle in (HANDLE_TL, HANDLE_BR):
            self.setCursor(QCursor(Qt.CursorShape.SizeFDiagCursor))
        elif handle in (HANDLE_TR, HANDLE_BL):
            self.setCursor(QCursor(Qt.CursorShape.SizeBDiagCursor))
        elif handle in (HANDLE_T, HANDLE_B):
            self.setCursor(QCursor(Qt.CursorShape.SizeVerCursor))
        elif handle in (HANDLE_L, HANDLE_R):
            self.setCursor(QCursor(Qt.CursorShape.SizeHorCursor))
        elif handle == HANDLE_MOVE:
            self.setCursor(QCursor(Qt.CursorShape.SizeAllCursor))
        else:
            self.setCursor(QCursor(Qt.CursorShape.CrossCursor))

    def mouseReleaseEvent(self, event: QMouseEvent):
        pos = event.position().toPoint()

        if self._mode == "panning":
            self._mode = "idle"
            self._pan_start_pos = None
            self.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
            return

        if self._mode == "drawing" and self._drag_start_pos:
            if self._current_image_box:
                ix1, iy1, ix2, iy2 = self._current_image_box
            else:
                ix1, iy1 = self.widget_to_image(self._drag_start_pos.x(), self._drag_start_pos.y())
                ix2, iy2 = self.widget_to_image(pos.x(), pos.y())

            x = min(ix1, ix2)
            y = min(iy1, iy2)
            w = abs(ix2 - ix1)
            h = abs(iy2 - iy1)

            if w >= MIN_BOX_SIZE and h >= MIN_BOX_SIZE:
                self._undo_stack.append([p.copy() for p in self._panels_at_drag_start])
                self._redo_stack.clear()
                new_panel = Panel(x, y, w, h)
                self.panels.append(new_panel)
                self.selected_panel_index = len(self.panels) - 1
                self.panels_changed.emit()
                self.panel_selected.emit(self.selected_panel_index)

            self._mode = "idle"
            self._drag_start_pos = None
            self._current_mouse_pos = None
            self._current_image_box = None
            self._last_raw_mouse_pos = None
            self.update()
            return

        if self._mode in ("resizing", "moving"):
            changed = False
            if len(self.panels) == len(self._panels_at_drag_start):
                for p_now, p_orig in zip(self.panels, self._panels_at_drag_start):
                    if (p_now.x, p_now.y, p_now.w, p_now.h) != (p_orig.x, p_orig.y, p_orig.w, p_orig.h):
                        changed = True
                        break
            else:
                changed = True

            if changed:
                self._undo_stack.append([p.copy() for p in self._panels_at_drag_start])
                self._redo_stack.clear()

            self._mode = "idle"
            self._drag_start_pos = None
            self._panel_before_drag = None
            self._current_image_box = None
            self._last_raw_mouse_pos = None
            self.panels_changed.emit()
            self.update()

    # --- Rendering ---

    def paintEvent(self, event: QPaintEvent):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)

        # Background canvas fill
        painter.fillRect(self.rect(), QColor("#1e1e1e"))

        # Center image if smaller than widget and offset not manually modified
        img_w = self.native_w * self.zoom_factor
        img_h = self.native_h * self.zoom_factor

        # Draw Image
        if self._pixmap and not self._pixmap.isNull():
            target_rect = QRectF(self.offset_x, self.offset_y, img_w, img_h)
            painter.drawPixmap(target_rect, self._pixmap, QRectF(self._pixmap.rect()))
            # Border around page
            painter.setPen(QPen(QColor("#444444"), 1))
            painter.drawRect(target_rect)

        # Draw Panels
        font = QFont("SansSerif", 10, QFont.Weight.Bold)
        painter.setFont(font)
        fm = QFontMetrics(font)

        for idx, panel in enumerate(self.panels):
            is_selected = (idx == self.selected_panel_index)
            wx, wy = self.image_to_widget(panel.x, panel.y)
            ww = panel.w * self.zoom_factor
            wh = panel.h * self.zoom_factor
            box_rect = QRectF(wx, wy, ww, wh)

            # Box fill & outline
            if is_selected:
                painter.setPen(QPen(QColor("#00e5ff"), 2.5))
                painter.setBrush(QBrush(QColor(0, 229, 255, 35)))
            else:
                painter.setPen(QPen(QColor("#ff9100"), 2.0))
                painter.setBrush(QBrush(QColor(255, 145, 0, 25)))
            painter.drawRect(box_rect)

            # Badge [1], [2], [3]...
            badge_text = f" {idx + 1} "
            tw = fm.horizontalAdvance(badge_text) + 6
            th = fm.height() + 4
            badge_rect = QRectF(wx + 2, wy + 2, tw, th)

            if is_selected:
                painter.fillRect(badge_rect, QColor("#00e5ff"))
                painter.setPen(QColor("#000000"))
            else:
                painter.fillRect(badge_rect, QColor("#ff9100"))
                painter.setPen(QColor("#000000"))
            painter.drawText(badge_rect, Qt.AlignmentFlag.AlignCenter, badge_text)

            # Handles for selected panel
            if is_selected:
                painter.setPen(QPen(QColor("#00e5ff"), 1.5))
                painter.setBrush(QBrush(QColor("#ffffff")))
                for _, hr in self._get_handle_rects(panel):
                    painter.drawRect(hr)

        # Draw rubber-band while currently drawing
        if self._mode == "drawing" and self._current_image_box:
            ix1, iy1, ix2, iy2 = self._current_image_box
            rx = min(ix1, ix2)
            ry = min(iy1, iy2)
            rw = abs(ix2 - ix1)
            rh = abs(iy2 - iy1)

            wx, wy = self.image_to_widget(rx, ry)
            ww = rw * self.zoom_factor
            wh = rh * self.zoom_factor

            painter.setPen(QPen(QColor("#76ff03"), 1.8, Qt.PenStyle.DashLine))
            painter.setBrush(QBrush(QColor(118, 255, 3, 30)))
            painter.drawRect(QRectF(wx, wy, ww, wh))

            # Next sequential badge preview
            next_idx = len(self.panels) + 1
            badge_text = f" {next_idx} "
            tw = fm.horizontalAdvance(badge_text) + 6
            th = fm.height() + 4
            badge_rect = QRectF(wx + 2, wy + 2, tw, th)
            painter.fillRect(badge_rect, QColor("#76ff03"))
            painter.setPen(QColor("#000000"))
            painter.drawText(badge_rect, Qt.AlignmentFlag.AlignCenter, badge_text)

        painter.end()
