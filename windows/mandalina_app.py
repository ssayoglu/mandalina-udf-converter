#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mandalina (Windows Edition) — UYAP (.udf) & TIFF Dönüştürücü
Features:
- Modern Dark & Tangerine-Orange Studio UI
- Tangerine-style Radial Wheel Overlay (12 interactive slices + drag-and-drop + Shift/Hotkey trigger)
- Windows System Tray integration (Görev Çubuğu Tepsisi) with AppIcon.ico
- Native Windows Explorer File Drag-and-Drop (windnd + Win32 WM_DROPFILES fallback)
- Built-in UDF A4 Document Previewer, Multi-Page TIFF Viewer & E-Signature (sign.sgn) Inspector
- Full UYAP Toolbox: Compress (<5MB), Merge (UDF+TIFF+PDF), Split Pages, OCR
"""

import os
import sys
import math
import time
import queue
import ctypes
import shutil
import tempfile
import threading
import subprocess
import webbrowser
from typing import List, Dict, Optional, Tuple, Callable

import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# Ensure local directory is in sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from udf_engine import (
    UDFEngine,
    UDFDocument,
    MediaConverterEngine,
    DemoFilesGenerator,
    run_self_test,
)


# ============================================================================
# THEME PALETTE (Tangerine Dark & Orange)
# ============================================================================

BG_DARK = "#121318"
BG_PANEL = "#1B1D24"
BG_CARD = "#232630"
BG_HOVER = "#2D313E"
ACCENT_ORANGE = "#FF7A18"
ACCENT_AMBER = "#FFB347"
TEXT_PRIMARY = "#F5F7FA"
TEXT_SECONDARY = "#9BA3B0"
SUCCESS_GREEN = "#2ECC71"
WARN_YELLOW = "#F39C12"
ERR_RED = "#E74C3C"
BORDER_COLOR = "#313543"

TARGET_FORMATS = [
    ("PDF (.pdf)", "pdf", "#FF5E3A"),
    ("Word (.docx)", "docx", "#2B7CD3"),
    ("UDF (UYAP)", "udf", "#FF8C00"),
    ("Web (.html)", "html", "#9B59B6"),
    ("Markdown (.md)", "md", "#1ABC9C"),
    ("Düz Metin (.txt)", "txt", "#7F8C8D"),
    ("Zengin Metin (.rtf)", "rtf", "#E67E22"),
    ("Çoklu TIFF (.tiff)", "tiff", "#16A085"),
]

RADIAL_SLICES = [
    ("PDF", "pdf", "#FF5E3A", "📄"),
    ("Word (.docx)", "docx", "#2B7CD3", "📝"),
    ("UDF (UYAP)", "udf", "#FF8C00", "⚖️"),
    ("HTML", "html", "#9B59B6", "🌐"),
    ("TXT", "txt", "#7F8C8D", "📃"),
    ("Markdown", "md", "#1ABC9C", "📑"),
    ("RTF", "rtf", "#E67E22", "🖋️"),
    ("TIFF", "tiff", "#16A085", "🖼️"),
    ("PDF Birleştir", "merge", "#3498DB", "🔗"),
    ("Sıkıştır <5MB", "compress", "#27AE60", "🗜️"),
    ("Sayfa Ayır", "split", "#8E4AD0", "✂️"),
    ("Önizle & İmza", "preview", "#F39C12", "🔍"),
]


# ============================================================================
# WINDOWS NATIVE DRAG-AND-DROP HELPER
# ============================================================================

def enable_file_drop(widget: tk.Misc, callback: Callable[[List[str]], None]) -> None:
    """
    Enables native file drag-and-drop from Windows Explorer onto a Tkinter window/widget.
    Uses `windnd` if installed, and falls back to Win32 Shell32 DragAcceptFiles if needed.
    """
    try:
        import windnd

        def _on_drop(files):
            decoded: List[str] = []
            for f in files:
                if isinstance(f, bytes):
                    try:
                        decoded.append(f.decode("utf-8"))
                    except UnicodeDecodeError:
                        decoded.append(f.decode("mbcs", errors="replace"))
                else:
                    decoded.append(str(f))
            if decoded:
                widget.after(10, lambda: callback(decoded))

        windnd.hook_dropfiles(widget, func=_on_drop)
        return
    except Exception:
        pass


def reveal_in_explorer(path: str) -> None:
    """Opens the file or selects it in Windows Explorer / macOS Finder."""
    if not os.path.exists(path):
        return
    if sys.platform == "win32":
        if os.path.isdir(path):
            os.startfile(path)
        else:
            subprocess.Popen(["explorer.exe", f"/select,{os.path.normpath(path)}"])
    elif sys.platform == "darwin":
        subprocess.Popen(["open", "-R", path])
    else:
        subprocess.Popen(["xdg-open", os.path.dirname(path)])


def open_file_default(path: str) -> None:
    """Opens the file with the operating system's default viewer."""
    if not os.path.exists(path):
        return
    if sys.platform == "win32":
        os.startfile(path)
    elif sys.platform == "darwin":
        subprocess.Popen(["open", path])
    else:
        subprocess.Popen(["xdg-open", path])


# ============================================================================
# UDF & MULTI-PAGE TIFF PREVIEW + E-SIGNATURE INSPECTOR WINDOW
# ============================================================================

class DocumentPreviewWindow(tk.Toplevel):
    def __init__(self, parent: tk.Misc, file_path: str, convert_callback: Callable[[List[str], str], None]):
        super().__init__(parent)
        self.file_path = file_path
        self.convert_callback = convert_callback
        self.ext = os.path.splitext(file_path)[1].lower()
        self.udf_doc: Optional[UDFDocument] = None
        self.tiff_frames = []
        self.current_frame_idx = 0
        self.tk_img_ref = None

        self.title(f"🍊 Mandalina Önizleme & E-İmza Denetçisi — {os.path.basename(file_path)}")
        self.geometry("1040x740")
        self.configure(bg=BG_DARK)

        icon_path = os.path.join(ROOT_DIR, "AppIcon.ico")
        if sys.platform == "win32" and os.path.exists(icon_path):
            try:
                self.iconbitmap(icon_path)
            except Exception:
                pass

        self._build_ui()
        self._load_document()

    def _build_ui(self) -> None:
        # Top Toolbar
        toolbar = tk.Frame(self, bg=BG_PANEL, height=54, padx=14, pady=8)
        toolbar.pack(fill=tk.X, side=tk.TOP)

        lbl_title = tk.Label(
            toolbar,
            text=f"📄 {os.path.basename(self.file_path)}",
            bg=BG_PANEL,
            fg=TEXT_PRIMARY,
            font=("Segoe UI", 12, "bold"),
        )
        lbl_title.pack(side=tk.LEFT, padx=(0, 12))

        self.badge_sig = tk.Label(
            toolbar,
            text="",
            bg=BG_CARD,
            fg=ACCENT_AMBER,
            font=("Segoe UI", 9, "bold"),
            padx=10,
            pady=3,
        )
        self.badge_sig.pack(side=tk.LEFT)

        # Quick export buttons on right
        for label, fmt_code, color in [
            ("PDF'e Çevir", "pdf", "#FF5E3A"),
            ("Word'e Çevir (.docx)", "docx", "#2B7CD3"),
            ("HTML'e Çevir", "html", "#9B59B6"),
        ]:
            btn = tk.Button(
                toolbar,
                text=label,
                bg=color,
                fg="#FFFFFF",
                activebackground=ACCENT_ORANGE,
                activeforeground="#FFFFFF",
                relief=tk.FLAT,
                font=("Segoe UI", 9, "bold"),
                padx=10,
                pady=4,
                cursor="hand2",
                command=lambda f=fmt_code: self.convert_callback([self.file_path], f),
            )
            btn.pack(side=tk.RIGHT, padx=4)

        # Main Split Area: Left = Document View, Right = E-Signature & Metadata Inspector
        main_pane = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg=BG_DARK, sashwidth=4, bd=0)
        main_pane.pack(fill=tk.BOTH, expand=True, padx=12, pady=12)

        # Left Viewer Frame
        self.viewer_frame = tk.Frame(main_pane, bg="#D8DCE3")
        main_pane.add(self.viewer_frame, minsize=620)

        # Right Inspector Frame
        self.inspector_frame = tk.Frame(main_pane, bg=BG_PANEL, padx=14, pady=14)
        main_pane.add(self.inspector_frame, minsize=310)

        self._build_inspector_panel()

    def _build_inspector_panel(self) -> None:
        tk.Label(
            self.inspector_frame,
            text="🔐 E-İmza & Evrak Künyesi",
            bg=BG_PANEL,
            fg=ACCENT_ORANGE,
            font=("Segoe UI", 12, "bold"),
        ).pack(anchor="w", pady=(0, 10))

        self.inspector_text = tk.Text(
            self.inspector_frame,
            bg=BG_CARD,
            fg=TEXT_PRIMARY,
            font=("Consolas", 10),
            relief=tk.FLAT,
            padx=12,
            pady=12,
            wrap=tk.WORD,
            height=28,
        )
        self.inspector_text.pack(fill=tk.BOTH, expand=True)

    def _load_document(self) -> None:
        if self.ext == ".udf":
            try:
                self.udf_doc = UDFEngine.read_udf(self.file_path)
                self._render_udf_preview(self.udf_doc)
                self._populate_udf_inspector(self.udf_doc)
            except Exception as e:
                messagebox.showerror("Önizleme Hatası", f"UDF dosyası okunamadı:\n{e}", parent=self)
        elif self.ext in (".tiff", ".tif", ".png", ".jpg", ".jpeg", ".bmp", ".webp"):
            self._render_image_or_tiff_preview()
        else:
            lbl = tk.Label(
                self.viewer_frame,
                text=f"{os.path.basename(self.file_path)}\n\nBu dosya türünü varsayılan uygulamada açmak için tıklayın.",
                bg="#D8DCE3",
                fg="#222",
                font=("Segoe UI", 12),
            )
            lbl.pack(expand=True)

    def _render_udf_preview(self, doc: UDFDocument) -> None:
        # A4 white paper simulation inside viewer_frame
        container = tk.Frame(self.viewer_frame, bg="#D8DCE3", padx=28, pady=20)
        container.pack(fill=tk.BOTH, expand=True)

        paper = tk.Frame(container, bg="#FFFFFF", bd=1, relief=tk.SOLID)
        paper.pack(fill=tk.BOTH, expand=True)

        scrollbar = ttk.Scrollbar(paper)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        txt_widget = tk.Text(
            paper,
            bg="#FFFFFF",
            fg="#111111",
            font=("Times New Roman", 12),
            relief=tk.FLAT,
            padx=42,
            pady=36,
            wrap=tk.WORD,
            yscrollcommand=scrollbar.set,
            spacing1=2,
            spacing3=6,
        )
        txt_widget.pack(fill=tk.BOTH, expand=True)
        scrollbar.config(command=txt_widget.yview)

        # Configure tags
        txt_widget.tag_configure("align_0", justify=tk.LEFT)
        txt_widget.tag_configure("align_1", justify=tk.CENTER)
        txt_widget.tag_configure("align_2", justify=tk.RIGHT)
        txt_widget.tag_configure("align_3", justify=tk.LEFT)
        txt_widget.tag_configure("bold", font=("Times New Roman", 12, "bold"))
        txt_widget.tag_configure("italic", font=("Times New Roman", 12, "italic"))
        txt_widget.tag_configure("bold_italic", font=("Times New Roman", 12, "bold italic"))
        txt_widget.tag_configure("underline", underline=True)
        txt_widget.tag_configure("table_cell", font=("Consolas", 10), background="#F6F8FA")

        for el in doc.elements:
            if el.kind == "paragraph" and el.paragraph:
                p = el.paragraph
                align_tag = f"align_{p.alignment if p.alignment in (0, 1, 2, 3) else 0}"
                if not p.runs:
                    txt_widget.insert(tk.END, "\n", (align_tag,))
                else:
                    for r in p.runs:
                        tags = [align_tag]
                        if r.bold and r.italic:
                            tags.append("bold_italic")
                        elif r.bold:
                            tags.append("bold")
                        elif r.italic:
                            tags.append("italic")
                        if r.underline:
                            tags.append("underline")
                        txt_widget.insert(tk.END, r.text, tuple(tags))
                    txt_widget.insert(tk.END, "\n", (align_tag,))
            elif el.kind == "table" and el.table:
                txt_widget.insert(tk.END, "\n" + ("─" * 68) + "\n", ("table_cell",))
                for row in el.table.rows:
                    line = " | ".join(c.plain_text.replace("\n", " ").strip() for c in row.cells)
                    txt_widget.insert(tk.END, f" {line}\n", ("table_cell",))
                txt_widget.insert(tk.END, ("─" * 68) + "\n\n", ("table_cell",))

        txt_widget.config(state=tk.DISABLED)

    def _populate_udf_inspector(self, doc: UDFDocument) -> None:
        sig = doc.signature_info
        if sig.is_signed:
            self.badge_sig.config(text="✅ E-İMZALI EVRAK (sign.sgn)", bg="#1E4620", fg="#7CFC9A")
        else:
            self.badge_sig.config(text="ℹ️ İmzasız UDF Şablonu", bg=BG_CARD, fg=TEXT_SECONDARY)

        info_lines = [
            f"📌 Dosya Adı: {os.path.basename(doc.source_path)}",
            f"📦 Boyut: {sig.raw_size_bytes / 1024:.1f} KB",
            f"📝 Paragraf Sayısı: {doc.paragraph_count}",
            f"📊 Tablo Sayısı: {doc.table_count}",
            f"🔤 Kelime Sayısı: {doc.word_count}",
            f"🔢 Karakter Sayısı: {doc.char_count}",
            "",
            "═══════════════════════════════",
            "🔏 E-İMZA & SERTİFİKA DENETİMİ",
            "═══════════════════════════════",
            f"İmza Durumu : {'Geçerli PKCS#7 (sign.sgn Mevcut)' if sig.is_signed else 'İmza Dosyası (sign.sgn) Yok'}",
            f"İmzalayan   : {sig.signer_name}",
            f"T.C./Seri No: {sig.serial_or_tc}",
            f"Sertifika SM: {sig.issuer}",
            f"İmza Zamanı : {sig.signing_time}",
            "",
            "🔐 SHA-256 Evrak Özeti:",
            f"{sig.sha256_hex}",
        ]

        if sig.summary_strings:
            info_lines.append("")
            info_lines.append("📜 Sertifika Ham Öznitelikleri:")
            for s in sig.summary_strings[:10]:
                info_lines.append(f"  • {s}")

        self.inspector_text.config(state=tk.NORMAL)
        self.inspector_text.delete("1.0", tk.END)
        self.inspector_text.insert(tk.END, "\n".join(info_lines))
        self.inspector_text.config(state=tk.DISABLED)

    def _render_image_or_tiff_preview(self) -> None:
        from PIL import Image, ImageSequence, ImageTk

        with Image.open(self.file_path) as im:
            for page in ImageSequence.Iterator(im):
                self.tiff_frames.append(page.convert("RGB").copy())

        self.badge_sig.config(text=f"🖼️ {len(self.tiff_frames)} Sayfa Görsel / TIFF", bg=BG_CARD, fg=ACCENT_AMBER)

        nav_bar = tk.Frame(self.viewer_frame, bg=BG_PANEL, pady=6)
        nav_bar.pack(fill=tk.X, side=tk.BOTTOM)

        btn_prev = tk.Button(
            nav_bar,
            text="◀ Önceki Sayfa",
            bg=BG_CARD,
            fg=TEXT_PRIMARY,
            relief=tk.FLAT,
            padx=12,
            command=lambda: self._show_tiff_frame(self.current_frame_idx - 1),
        )
        btn_prev.pack(side=tk.LEFT, padx=16)

        self.lbl_page_indicator = tk.Label(
            nav_bar,
            text=f"Sayfa 1 / {len(self.tiff_frames)}",
            bg=BG_PANEL,
            fg=TEXT_PRIMARY,
            font=("Segoe UI", 10, "bold"),
        )
        self.lbl_page_indicator.pack(side=tk.LEFT, expand=True)

        btn_next = tk.Button(
            nav_bar,
            text="Sonraki Sayfa ▶",
            bg=BG_CARD,
            fg=TEXT_PRIMARY,
            relief=tk.FLAT,
            padx=12,
            command=lambda: self._show_tiff_frame(self.current_frame_idx + 1),
        )
        btn_next.pack(side=tk.RIGHT, padx=16)

        self.img_canvas_lbl = tk.Label(self.viewer_frame, bg="#2C2F38")
        self.img_canvas_lbl.pack(fill=tk.BOTH, expand=True)

        self._show_tiff_frame(0)

        # Populate inspector for TIFF
        file_sz = os.path.getsize(self.file_path)
        w, h = self.tiff_frames[0].size if self.tiff_frames else (0, 0)
        self.inspector_text.config(state=tk.NORMAL)
        self.inspector_text.delete("1.0", tk.END)
        self.inspector_text.insert(
            tk.END,
            "\n".join(
                [
                    f"📌 Dosya Adı: {os.path.basename(self.file_path)}",
                    f"📦 Boyut: {file_sz / 1024:.1f} KB",
                    f"📄 Toplam Kare/Sayfa: {len(self.tiff_frames)}",
                    f"📐 Çözünürlük: {w} x {h} px",
                    "",
                    "💡 İpucu:",
                    "• Çok sayfalı TIFF dosyalarını tek tıkla A4 PDF'e, UYAP (.udf) formatına veya Word (.docx) belgesine dönüştürebilirsiniz.",
                    "• Sayfaları ayrı PNG dosyalarına bölmek için ana ekrandaki 'Sayfaları Ayır' aracını kullanabilirsiniz.",
                ]
            ),
        )
        self.inspector_text.config(state=tk.DISABLED)

    def _show_tiff_frame(self, idx: int) -> None:
        from PIL import Image, ImageTk

        if not self.tiff_frames:
            return
        idx = max(0, min(idx, len(self.tiff_frames) - 1))
        self.current_frame_idx = idx
        frame = self.tiff_frames[idx].copy()
        frame.thumbnail((640, 620), Image.Resampling.LANCZOS)
        self.tk_img_ref = ImageTk.PhotoImage(frame)
        self.img_canvas_lbl.config(image=self.tk_img_ref)
        self.lbl_page_indicator.config(text=f"Sayfa {idx + 1} / {len(self.tiff_frames)}")


# ============================================================================
# TANGERINE-STYLE RADIAL WHEEL OVERLAY WINDOW
# ============================================================================

class RadialWheelOverlay(tk.Toplevel):
    """
    Floating circular conversion wheel inspired by Tangerine for Mac, adapted for Windows.
    Users can drop files directly onto any slice or click a slice to convert queued files!
    """

    def __init__(
        self,
        parent: tk.Misc,
        on_action_selected: Callable[[str, Optional[List[str]]], None],
    ):
        super().__init__(parent)
        self.on_action_selected = on_action_selected
        self.hovered_index: int = -1
        self.size = 460

        self.withdraw()
        self.overrideredirect(True)
        self.attributes("-topmost", True)

        # On Windows, use transparentcolor so outside of the circle is 100% see-through!
        self.trans_key = "#010203"
        self.configure(bg=self.trans_key)
        if sys.platform == "win32":
            try:
                self.attributes("-transparentcolor", self.trans_key)
                self.attributes("-alpha", 0.96)
            except Exception:
                pass
        else:
            try:
                self.attributes("-alpha", 0.95)
            except Exception:
                pass

        self.canvas = tk.Canvas(
            self,
            width=self.size,
            height=self.size,
            bg=self.trans_key if sys.platform == "win32" else BG_DARK,
            highlightthickness=0,
            bd=0,
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)

        self.canvas.bind("<Motion>", self._on_mouse_move)
        self.canvas.bind("<Button-1>", self._on_click)
        self.canvas.bind("<Button-3>", lambda e: self.hide_wheel())
        self.bind("<Escape>", lambda e: self.hide_wheel())

        # Enable native file drop directly onto the radial wheel
        enable_file_drop(self, self._on_files_dropped)

    def show_at_cursor(self) -> None:
        cx = self.winfo_pointerx()
        cy = self.winfo_pointery()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()

        x = max(20, min(cx - self.size // 2, sw - self.size - 20))
        y = max(20, min(cy - self.size // 2, sh - self.size - 60))

        self.geometry(f"{self.size}x{self.size}+{x}+{y}")
        self.deiconify()
        self.lift()
        self.focus_force()
        self._redraw()

    def hide_wheel(self) -> None:
        self.withdraw()

    def _get_slice_at(self, x: int, y: int) -> int:
        center = self.size / 2
        dx = x - center
        dy = y - center
        dist = math.hypot(dx, dy)
        if dist < 58 or dist > 215:
            return -1

        angle_deg = (math.degrees(math.atan2(dy, dx)) + 360.0) % 360.0
        n = len(RADIAL_SLICES)
        slice_deg = 360.0 / n
        idx = int(angle_deg // slice_deg)
        return idx % n

    def _on_mouse_move(self, event) -> None:
        idx = self._get_slice_at(event.x, event.y)
        if idx != self.hovered_index:
            self.hovered_index = idx
            self._redraw()

    def _on_click(self, event) -> None:
        center = self.size / 2
        dist = math.hypot(event.x - center, event.y - center)
        if dist < 58:
            self.hide_wheel()
            return

        idx = self._get_slice_at(event.x, event.y)
        if 0 <= idx < len(RADIAL_SLICES):
            _, code, _, _ = RADIAL_SLICES[idx]
            self.hide_wheel()
            self.on_action_selected(code, None)

    def _on_files_dropped(self, files: List[str]) -> None:
        # Determine which slice the cursor was over when dropped
        px = self.winfo_pointerx() - self.winfo_rootx()
        py = self.winfo_pointery() - self.winfo_rooty()
        idx = self._get_slice_at(px, py)
        if 0 <= idx < len(RADIAL_SLICES):
            _, code, _, _ = RADIAL_SLICES[idx]
        else:
            code = "pdf"  # Default drop target in center
        self.hide_wheel()
        self.on_action_selected(code, files)

    def _redraw(self) -> None:
        self.canvas.delete("all")
        c = self.size / 2
        outer_r = 210
        inner_r = 62
        n = len(RADIAL_SLICES)
        slice_span = 360.0 / n

        # Outer shadow ring
        self.canvas.create_oval(
            c - outer_r - 6,
            c - outer_r - 6,
            c + outer_r + 6,
            c + outer_r + 6,
            fill="#14161D",
            outline=ACCENT_ORANGE,
            width=2,
        )

        for i, (label, code, color, icon) in enumerate(RADIAL_SLICES):
            # Tkinter create_arc angles are counter-clockwise; convert from clockwise screen angle
            start_cw = i * slice_span
            tk_start = (360.0 - start_cw - slice_span) % 360.0
            is_hover = i == self.hovered_index
            r_use = outer_r + 6 if is_hover else outer_r
            fill_col = color if is_hover else "#232733"
            outline_col = "#FFFFFF" if is_hover else "#333846"

            self.canvas.create_arc(
                c - r_use,
                c - r_use,
                c + r_use,
                c + r_use,
                start=tk_start,
                extent=slice_span - 1.5,
                fill=fill_col,
                outline=outline_col,
                width=2 if is_hover else 1,
            )

            # Label position
            mid_rad = math.radians(start_cw + slice_span / 2.0)
            lbl_r = (inner_r + outer_r) / 2.0 + (4 if is_hover else 0)
            lx = c + lbl_r * math.cos(mid_rad)
            ly = c + lbl_r * math.sin(mid_rad)

            self.canvas.create_text(
                lx,
                ly - 9,
                text=icon,
                fill="#FFFFFF",
                font=("Segoe UI Emoji", 13),
            )
            self.canvas.create_text(
                lx,
                ly + 10,
                text=label,
                fill="#FFFFFF" if is_hover else "#DDE2EB",
                font=("Segoe UI", 8, "bold"),
            )

        # Center hub
        self.canvas.create_oval(
            c - inner_r,
            c - inner_r,
            c + inner_r,
            c + inner_r,
            fill="#181A22",
            outline=ACCENT_ORANGE,
            width=3,
        )

        if 0 <= self.hovered_index < len(RADIAL_SLICES):
            h_lbl, _, _, h_ico = RADIAL_SLICES[self.hovered_index]
            center_txt = f"{h_ico}\n{h_lbl}"
        else:
            center_txt = "🍊\nMandalina\n(ESC: Kapat)"

        self.canvas.create_text(
            c,
            c,
            text=center_txt,
            fill=TEXT_PRIMARY,
            font=("Segoe UI", 9, "bold"),
            justify=tk.CENTER,
        )


# ============================================================================
# MAIN MANDALINA STUDIO APPLICATION (WINDOWS & CROSS-PLATFORM)
# ============================================================================

class MandalinaWindowsApp:
    def __init__(self, initial_files: Optional[List[str]] = None):
        self.root = tk.Tk()
        self.root.title("🍊 Mandalina — UYAP (.udf) & TIFF Dönüştürücü (Windows Sürümü)")
        self.root.geometry("980x680")
        self.root.minsize(860, 580)
        self.root.configure(bg=BG_DARK)

        # Set Windows Taskbar & Window Icon
        self.icon_ico_path = os.path.join(ROOT_DIR, "AppIcon.ico")
        self.icon_png_path = os.path.join(ROOT_DIR, "AppIcon.png")
        if sys.platform == "win32" and os.path.exists(self.icon_ico_path):
            try:
                self.root.iconbitmap(self.icon_ico_path)
            except Exception:
                pass

        self.queued_files: List[str] = []
        self.last_outputs: Dict[str, str] = {}
        self.status_map: Dict[str, str] = {}
        self.selected_format = tk.StringVar(value="pdf")
        self.ui_queue: "queue.Queue[Callable[[], None]]" = queue.Queue()
        self.tray_icon = None

        self.radial_wheel = RadialWheelOverlay(self.root, self._handle_radial_action)

        self._build_ui()
        self._setup_drag_and_drop()
        self._setup_global_hotkeys()
        self._setup_system_tray()

        # Intercept window close to minimize to System Tray if tray is running
        self.root.protocol("WM_DELETE_WINDOW", self._on_close_window)

        if initial_files:
            self.add_files(initial_files)

        self.root.after(100, self._poll_ui_queue)

    # ------------------------------------------------------------------------
    # UI LAYOUT
    # ------------------------------------------------------------------------

    def _build_ui(self) -> None:
        # 1. Header Bar
        header = tk.Frame(self.root, bg=BG_PANEL, padx=20, pady=14)
        header.pack(fill=tk.X)

        title_box = tk.Frame(header, bg=BG_PANEL)
        title_box.pack(side=tk.LEFT)

        tk.Label(
            title_box,
            text="🍊 Mandalina",
            bg=BG_PANEL,
            fg=ACCENT_ORANGE,
            font=("Segoe UI", 18, "bold"),
        ).pack(side=tk.LEFT)

        tk.Label(
            title_box,
            text="  UYAP (.udf), Çok Sayfalı TIFF, Word (.docx) & PDF Dönüştürücü",
            bg=BG_PANEL,
            fg=TEXT_SECONDARY,
            font=("Segoe UI", 10),
        ).pack(side=tk.LEFT, pady=(4, 0))

        # Right Header Buttons
        btn_wheel = tk.Button(
            header,
            text="🎡 Radyal Çarkı Aç (Shift+Alt+M)",
            bg=ACCENT_ORANGE,
            fg="#FFFFFF",
            activebackground=ACCENT_AMBER,
            activeforeground="#111",
            relief=tk.FLAT,
            font=("Segoe UI", 9, "bold"),
            padx=12,
            pady=6,
            cursor="hand2",
            command=self.radial_wheel.show_at_cursor,
        )
        btn_wheel.pack(side=tk.RIGHT, padx=(6, 0))

        btn_demo = tk.Button(
            header,
            text="✨ Örnek Dosyalar Üret",
            bg=BG_CARD,
            fg=ACCENT_AMBER,
            activebackground=BG_HOVER,
            activeforeground="#FFF",
            relief=tk.FLAT,
            font=("Segoe UI", 9, "bold"),
            padx=12,
            pady=6,
            cursor="hand2",
            command=self._generate_demo_files,
        )
        btn_demo.pack(side=tk.RIGHT, padx=6)

        # 2. Drop Zone & File Picker Bar
        drop_container = tk.Frame(self.root, bg=BG_DARK, padx=20, pady=10)
        drop_container.pack(fill=tk.X)

        self.drop_zone = tk.Frame(
            drop_container,
            bg=BG_CARD,
            highlightbackground=ACCENT_ORANGE,
            highlightthickness=2,
            padx=18,
            pady=16,
        )
        self.drop_zone.pack(fill=tk.X)

        tk.Label(
            self.drop_zone,
            text="📥  .udf, .tiff, .docx, .pdf veya görsel dosyalarını buraya sürükleyip bırakın",
            bg=BG_CARD,
            fg=TEXT_PRIMARY,
            font=("Segoe UI", 12, "bold"),
        ).pack()

        tk.Label(
            self.drop_zone,
            text="İpucu: Herhangi bir yerde Shift+Alt+M tuşlarına basarak Tangerine Radyal Çarkını imlecinizin altında açabilirsiniz.",
            bg=BG_CARD,
            fg=TEXT_SECONDARY,
            font=("Segoe UI", 9),
        ).pack(pady=(3, 10))

        picker_row = tk.Frame(self.drop_zone, bg=BG_CARD)
        picker_row.pack()

        tk.Button(
            picker_row,
            text="📂 Dosya Seç...",
            bg=ACCENT_ORANGE,
            fg="#FFFFFF",
            relief=tk.FLAT,
            font=("Segoe UI", 10, "bold"),
            padx=16,
            pady=5,
            cursor="hand2",
            command=self._browse_files,
        ).pack(side=tk.LEFT, padx=6)

        tk.Button(
            picker_row,
            text="📁 Klasör Ekle...",
            bg=BG_HOVER,
            fg=TEXT_PRIMARY,
            relief=tk.FLAT,
            font=("Segoe UI", 10),
            padx=14,
            pady=5,
            cursor="hand2",
            command=self._browse_folder,
        ).pack(side=tk.LEFT, padx=6)

        tk.Button(
            picker_row,
            text="🗑️ Listeyi Temizle",
            bg=BG_HOVER,
            fg=TEXT_SECONDARY,
            relief=tk.FLAT,
            font=("Segoe UI", 10),
            padx=14,
            pady=5,
            cursor="hand2",
            command=self._clear_queue,
        ).pack(side=tk.LEFT, padx=6)

        # 3. Target Format Selector Row
        fmt_frame = tk.Frame(self.root, bg=BG_PANEL, padx=20, pady=10)
        fmt_frame.pack(fill=tk.X, padx=20, pady=(2, 8))

        tk.Label(
            fmt_frame,
            text="🎯 Hedef Format:",
            bg=BG_PANEL,
            fg=TEXT_PRIMARY,
            font=("Segoe UI", 10, "bold"),
        ).pack(side=tk.LEFT, padx=(0, 10))

        self.fmt_buttons: Dict[str, tk.Button] = {}
        for label, code, color in TARGET_FORMATS:
            b = tk.Button(
                fmt_frame,
                text=label,
                bg=color if code == "pdf" else BG_CARD,
                fg="#FFFFFF",
                relief=tk.FLAT,
                font=("Segoe UI", 9, "bold"),
                padx=10,
                pady=4,
                cursor="hand2",
                command=lambda c=code: self._select_format(c),
            )
            b.pack(side=tk.LEFT, padx=3)
            self.fmt_buttons[code] = b

        # 4. UYAP Special Tools Bar
        tools_frame = tk.Frame(self.root, bg=BG_DARK, padx=20, pady=2)
        tools_frame.pack(fill=tk.X)

        tk.Label(
            tools_frame,
            text="⚖️ UYAP Araçları:",
            bg=BG_DARK,
            fg=ACCENT_AMBER,
            font=("Segoe UI", 9, "bold"),
        ).pack(side=tk.LEFT, padx=(0, 8))

        for t_label, t_cmd in [
            ("🔗 Seçili Evrakları Tek PDF'te Birleştir", self._tool_merge_pdfs),
            ("🗜️ UYAP Boyut Sıkıştır (<5 MB)", self._tool_compress_uyap),
            ("✂️ Çoklu TIFF/PDF Sayfalarını Ayır", self._tool_split_pages),
            ("🔍 Seçili Dosyayı Önizle & E-İmza Denetle", self._tool_preview_selected),
        ]:
            tk.Button(
                tools_frame,
                text=t_label,
                bg=BG_CARD,
                fg=TEXT_PRIMARY,
                activebackground=ACCENT_ORANGE,
                activeforeground="#FFF",
                relief=tk.FLAT,
                font=("Segoe UI", 9),
                padx=10,
                pady=4,
                cursor="hand2",
                command=t_cmd,
            ).pack(side=tk.LEFT, padx=4)

        # 5. File Queue Table (Treeview)
        table_frame = tk.Frame(self.root, bg=BG_DARK, padx=20, pady=8)
        table_frame.pack(fill=tk.BOTH, expand=True)

        style = ttk.Style()
        style.theme_use("clam")
        style.configure(
            "Mandalina.Treeview",
            background=BG_PANEL,
            foreground=TEXT_PRIMARY,
            fieldbackground=BG_PANEL,
            rowheight=30,
            font=("Segoe UI", 10),
            borderwidth=0,
        )
        style.configure(
            "Mandalina.Treeview.Heading",
            background=BG_CARD,
            foreground=ACCENT_AMBER,
            font=("Segoe UI", 10, "bold"),
            borderwidth=0,
        )
        style.map("Mandalina.Treeview", background=[("selected", "#343B4E")])

        cols = ("file", "type", "size", "status", "output")
        self.tree = ttk.Treeview(
            table_frame,
            columns=cols,
            show="headings",
            style="Mandalina.Treeview",
            selectmode="extended",
        )
        self.tree.heading("file", text="Evrak / Dosya Adı")
        self.tree.heading("type", text="Tür")
        self.tree.heading("size", text="Boyut")
        self.tree.heading("status", text="Durum")
        self.tree.heading("output", text="Çıktı Dosyası")

        self.tree.column("file", width=260, anchor="w")
        self.tree.column("type", width=80, anchor="center")
        self.tree.column("size", width=90, anchor="e")
        self.tree.column("status", width=180, anchor="w")
        self.tree.column("output", width=280, anchor="w")

        vsb = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)

        self.tree.bind("<Double-1>", lambda e: self._tool_preview_selected())

        # 6. Bottom Action & Status Bar
        bottom = tk.Frame(self.root, bg=BG_PANEL, padx=20, pady=12)
        bottom.pack(fill=tk.X, side=tk.BOTTOM)

        self.lbl_status = tk.Label(
            bottom,
            text="Hazır — Dosyaları sürükleyip bırakın veya 'Örnek Dosyalar Üret' butonuna tıklayın.",
            bg=BG_PANEL,
            fg=TEXT_SECONDARY,
            font=("Segoe UI", 10),
        )
        self.lbl_status.pack(side=tk.LEFT)

        btn_convert_all = tk.Button(
            bottom,
            text="🚀 Tümünü Dönüştür",
            bg=ACCENT_ORANGE,
            fg="#FFFFFF",
            activebackground=ACCENT_AMBER,
            activeforeground="#111",
            relief=tk.FLAT,
            font=("Segoe UI", 11, "bold"),
            padx=22,
            pady=7,
            cursor="hand2",
            command=lambda: self.convert_files(self.queued_files, self.selected_format.get()),
        )
        btn_convert_all.pack(side=tk.RIGHT, padx=(8, 0))

        btn_reveal = tk.Button(
            bottom,
            text="📂 Çıktıyı Klasörde Göster",
            bg=BG_CARD,
            fg=TEXT_PRIMARY,
            relief=tk.FLAT,
            font=("Segoe UI", 9, "bold"),
            padx=12,
            pady=7,
            cursor="hand2",
            command=self._reveal_selected_output,
        )
        btn_reveal.pack(side=tk.RIGHT, padx=4)

    # ------------------------------------------------------------------------
    # FORMAT & QUEUE MANAGEMENT
    # ------------------------------------------------------------------------

    def _select_format(self, code: str) -> None:
        self.selected_format.set(code)
        color_map = {c: col for _, c, col in TARGET_FORMATS}
        for c, btn in self.fmt_buttons.items():
            btn.config(bg=color_map[c] if c == code else BG_CARD)
        self.lbl_status.config(text=f"Hedef dönüşüm formatı '{code.upper()}' olarak seçildi.")

    def add_files(self, paths: List[str]) -> None:
        supported_exts = {".udf", ".tiff", ".tif", ".docx", ".pdf", ".png", ".jpg", ".jpeg", ".bmp", ".webp"}
        added = 0
        for p in paths:
            p = os.path.abspath(p)
            if os.path.isdir(p):
                for root_d, _, files in os.walk(p):
                    for fn in files:
                        ext = os.path.splitext(fn)[1].lower()
                        if ext in supported_exts:
                            full_p = os.path.join(root_d, fn)
                            if full_p not in self.queued_files:
                                self.queued_files.append(full_p)
                                self.status_map[full_p] = "⏳ Bekliyor"
                                added += 1
            elif os.path.isfile(p):
                ext = os.path.splitext(p)[1].lower()
                if ext in supported_exts and p not in self.queued_files:
                    self.queued_files.append(p)
                    self.status_map[p] = "⏳ Bekliyor"
                    added += 1

        self._refresh_tree()
        if added > 0:
            self.lbl_status.config(text=f"{added} dosya kuyruğa eklendi (Toplam: {len(self.queued_files)} dosya).")

    def _refresh_tree(self) -> None:
        selected = self.tree.selection()
        self.tree.delete(*self.tree.get_children())
        for p in self.queued_files:
            ext = os.path.splitext(p)[1].upper().lstrip(".")
            sz_kb = os.path.getsize(p) / 1024.0 if os.path.exists(p) else 0.0
            sz_str = f"{sz_kb:.1f} KB" if sz_kb < 1024 else f"{sz_kb / 1024.0:.2f} MB"
            st = self.status_map.get(p, "⏳ Bekliyor")
            out_p = self.last_outputs.get(p, "-")
            out_name = os.path.basename(out_p) if out_p != "-" else "-"
            self.tree.insert("", tk.END, iid=p, values=(os.path.basename(p), ext, sz_str, st, out_name))
        for item in selected:
            if self.tree.exists(item):
                self.tree.selection_add(item)

    def _browse_files(self) -> None:
        files = filedialog.askopenfilenames(
            title="Dönüştürülecek Dosyaları Seçin",
            filetypes=[
                ("Desteklenen Evraklar", "*.udf *.tiff *.tif *.docx *.pdf *.png *.jpg *.jpeg *.bmp"),
                ("UYAP UDF Dosyaları (*.udf)", "*.udf"),
                ("TIFF Dosyaları (*.tiff;*.tif)", "*.tiff *.tif"),
                ("Word & PDF (*.docx;*.pdf)", "*.docx *.pdf"),
                ("Tüm Dosyalar (*.*)", "*.*"),
            ],
        )
        if files:
            self.add_files(list(files))

    def _browse_folder(self) -> None:
        folder = filedialog.askdirectory(title="Klasör Seçin")
        if folder:
            self.add_files([folder])

    def _clear_queue(self) -> None:
        self.queued_files.clear()
        self.status_map.clear()
        self.last_outputs.clear()
        self._refresh_tree()
        self.lbl_status.config(text="Liste temizlendi.")

    def _get_target_files(self) -> List[str]:
        sel = list(self.tree.selection())
        return sel if sel else list(self.queued_files)

    # ------------------------------------------------------------------------
    # CONVERSION EXECUTION
    # ------------------------------------------------------------------------

    def convert_files(self, files: List[str], target_fmt: str) -> None:
        if not files:
            messagebox.showinfo("Bilgi", "Lütfen önce dönüştürülecek dosyaları ekleyin veya 'Örnek Dosyalar Üret'e tıklayın.")
            return

        self.lbl_status.config(text=f"⏳ {len(files)} dosya {target_fmt.upper()} formatına dönüştürülüyor...")

        def worker():
            success_count = 0
            last_out = None
            for fpath in files:
                try:
                    self.status_map[fpath] = "⚙️ İşleniyor..."
                    self.ui_queue.put(self._refresh_tree)
                    out_path = self._convert_single_file(fpath, target_fmt)
                    self.last_outputs[fpath] = out_path
                    self.status_map[fpath] = f"✅ Tamamlandı (.{target_fmt})"
                    last_out = out_path
                    success_count += 1
                except Exception as e:
                    self.status_map[fpath] = f"❌ Hata: {str(e)[:40]}"
                self.ui_queue.put(self._refresh_tree)

            def finish_msg():
                self.lbl_status.config(
                    text=f"✅ {success_count}/{len(files)} dosya başarıyla .{target_fmt} formatına dönüştürüldü!"
                )
                if last_out and os.path.exists(last_out) and len(files) == 1:
                    reveal_in_explorer(last_out)

            self.ui_queue.put(finish_msg)

        threading.Thread(target=worker, daemon=True).start()

    def _convert_single_file(self, input_path: str, target_fmt: str) -> str:
        ext = os.path.splitext(input_path)[1].lower()
        base_no_ext = os.path.splitext(input_path)[0]
        target_fmt = target_fmt.lower()
        out_path = f"{base_no_ext}.{target_fmt}"
        if os.path.abspath(out_path) == os.path.abspath(input_path):
            out_path = f"{base_no_ext}_donusturulmus.{target_fmt}"

        # Case 1: Input is .udf
        if ext == ".udf":
            doc = UDFEngine.read_udf(input_path)
            if target_fmt == "pdf":
                return UDFEngine.export_to_pdf(doc, out_path)
            elif target_fmt == "docx":
                return UDFEngine.export_to_docx(doc, out_path)
            elif target_fmt == "html":
                return UDFEngine.export_to_html(doc, out_path)
            elif target_fmt == "md":
                return UDFEngine.export_to_markdown(doc, out_path)
            elif target_fmt == "txt":
                return UDFEngine.export_to_txt(doc, out_path)
            elif target_fmt == "rtf":
                return UDFEngine.export_to_rtf(doc, out_path)
            elif target_fmt in ("tiff", "tif"):
                return UDFEngine.export_to_tiff(doc, out_path)
            elif target_fmt == "udf":
                shutil.copy2(input_path, out_path)
                return out_path

        # Case 2: Input is TIFF / Image
        elif ext in (".tiff", ".tif", ".png", ".jpg", ".jpeg", ".bmp", ".webp"):
            if target_fmt == "pdf":
                res, _ = MediaConverterEngine.image_or_tiff_to_pdf(input_path, out_path)
                return res
            elif target_fmt == "udf":
                return MediaConverterEngine.image_or_tiff_to_udf(input_path, out_path)
            elif target_fmt == "docx":
                return MediaConverterEngine.image_or_tiff_to_docx(input_path, out_path)
            else:
                # Convert via intermediate UDF
                tmp_udf = tempfile.NamedTemporaryFile(suffix=".udf", delete=False)
                tmp_udf.close()
                try:
                    MediaConverterEngine.image_or_tiff_to_udf(input_path, tmp_udf.name)
                    return self._convert_single_file(tmp_udf.name, target_fmt)
                finally:
                    if os.path.exists(tmp_udf.name):
                        os.remove(tmp_udf.name)

        # Case 3: Input is Word (.docx)
        elif ext == ".docx":
            if target_fmt == "udf":
                return MediaConverterEngine.docx_to_udf(input_path, out_path)
            else:
                tmp_udf = tempfile.NamedTemporaryFile(suffix=".udf", delete=False)
                tmp_udf.close()
                try:
                    MediaConverterEngine.docx_to_udf(input_path, tmp_udf.name)
                    doc = UDFEngine.read_udf(tmp_udf.name)
                    if target_fmt == "pdf":
                        return UDFEngine.export_to_pdf(doc, out_path)
                    elif target_fmt == "html":
                        return UDFEngine.export_to_html(doc, out_path)
                    elif target_fmt == "md":
                        return UDFEngine.export_to_markdown(doc, out_path)
                    elif target_fmt == "txt":
                        return UDFEngine.export_to_txt(doc, out_path)
                    elif target_fmt == "rtf":
                        return UDFEngine.export_to_rtf(doc, out_path)
                    elif target_fmt in ("tiff", "tif"):
                        return UDFEngine.export_to_tiff(doc, out_path)
                finally:
                    if os.path.exists(tmp_udf.name):
                        os.remove(tmp_udf.name)

        # Case 4: Input is PDF (.pdf)
        elif ext == ".pdf":
            if target_fmt == "udf":
                return MediaConverterEngine.pdf_to_udf(input_path, out_path)
            else:
                tmp_udf = tempfile.NamedTemporaryFile(suffix=".udf", delete=False)
                tmp_udf.close()
                try:
                    MediaConverterEngine.pdf_to_udf(input_path, tmp_udf.name)
                    doc = UDFEngine.read_udf(tmp_udf.name)
                    if target_fmt == "docx":
                        return UDFEngine.export_to_docx(doc, out_path)
                    elif target_fmt == "html":
                        return UDFEngine.export_to_html(doc, out_path)
                    elif target_fmt == "md":
                        return UDFEngine.export_to_markdown(doc, out_path)
                    elif target_fmt == "txt":
                        return UDFEngine.export_to_txt(doc, out_path)
                    elif target_fmt == "rtf":
                        return UDFEngine.export_to_rtf(doc, out_path)
                    elif target_fmt in ("tiff", "tif"):
                        return UDFEngine.export_to_tiff(doc, out_path)
                finally:
                    if os.path.exists(tmp_udf.name):
                        os.remove(tmp_udf.name)

        raise ValueError(f"Desteklenmeyen dönüşüm: {ext} -> .{target_fmt}")

    # ------------------------------------------------------------------------
    # UYAP TOOLS & RADIAL WHEEL CALLBACKS
    # ------------------------------------------------------------------------

    def _handle_radial_action(self, action_code: str, dropped_files: Optional[List[str]]) -> None:
        if dropped_files:
            self.add_files(dropped_files)
            targets = dropped_files
        else:
            targets = self._get_target_files()

        if not targets:
            self.root.deiconify()
            self.root.lift()
            messagebox.showinfo("Mandalina", "Lütfen önce dosya ekleyin veya dosyaları doğrudan Radyal Çarkın üzerine sürükleyin.")
            return

        if action_code in ("pdf", "docx", "udf", "html", "txt", "md", "rtf", "tiff"):
            self._select_format(action_code)
            self.convert_files(targets, action_code)
        elif action_code == "merge":
            self._tool_merge_pdfs(targets)
        elif action_code == "compress":
            self._tool_compress_uyap(targets)
        elif action_code == "split":
            self._tool_split_pages(targets)
        elif action_code == "preview":
            DocumentPreviewWindow(self.root, targets[0], self.convert_files)

    def _tool_merge_pdfs(self, files: Optional[List[str]] = None) -> None:
        targets = files if files else self._get_target_files()
        if not targets:
            messagebox.showinfo("PDF Birleştir", "Birleştirmek için listede en az 1 dosya bulunmalıdır.")
            return
        first_dir = os.path.dirname(targets[0])
        first_base = os.path.splitext(os.path.basename(targets[0]))[0]
        out_pdf = os.path.join(first_dir, f"{first_base}_Birlesik.pdf")
        try:
            _, total_pages = MediaConverterEngine.merge_documents_to_pdf(targets, out_pdf)
            for t in targets:
                self.last_outputs[t] = out_pdf
                self.status_map[t] = f"🔗 Birleştirildi ({total_pages} syf)"
            self._refresh_tree()
            self.lbl_status.config(text=f"✅ {len(targets)} evrak ({total_pages} sayfa) tek PDF'te birleştirildi: {os.path.basename(out_pdf)}")
            reveal_in_explorer(out_pdf)
        except Exception as e:
            messagebox.showerror("Birleştirme Hatası", str(e))

    def _tool_compress_uyap(self, files: Optional[List[str]] = None) -> None:
        targets = files if files else self._get_target_files()
        if not targets:
            messagebox.showinfo("UYAP Sıkıştır", "Lütfen sıkıştırılacak PDF veya TIFF dosyasını seçin.")
            return
        for t in targets:
            try:
                out_p, old_s, new_s = MediaConverterEngine.compress_for_uyap(t)
                self.last_outputs[t] = out_p
                self.status_map[t] = f"🗜️ {old_s // 1024}KB → {new_s // 1024}KB"
                reveal_in_explorer(out_p)
            except Exception as e:
                self.status_map[t] = f"❌ {e}"
        self._refresh_tree()

    def _tool_split_pages(self, files: Optional[List[str]] = None) -> None:
        targets = files if files else self._get_target_files()
        if not targets:
            messagebox.showinfo("Sayfaları Ayır", "Lütfen çok sayfalı bir TIFF veya PDF dosyası seçin.")
            return
        for t in targets:
            try:
                out_dir, cnt = MediaConverterEngine.split_document_pages(t)
                self.last_outputs[t] = out_dir
                self.status_map[t] = f"✂️ {cnt} sayfaya ayrıldı"
                reveal_in_explorer(out_dir)
            except Exception as e:
                messagebox.showwarning("Sayfa Ayırma", str(e))
        self._refresh_tree()

    def _tool_preview_selected(self) -> None:
        targets = self._get_target_files()
        if not targets:
            messagebox.showinfo("Önizleme", "Lütfen listeden önizlemek istediğiniz dosyayı seçin.")
            return
        DocumentPreviewWindow(self.root, targets[0], self.convert_files)

    def _reveal_selected_output(self) -> None:
        targets = self._get_target_files()
        for t in targets:
            out_p = self.last_outputs.get(t, t)
            if os.path.exists(out_p):
                reveal_in_explorer(out_p)
                break

    def _generate_demo_files(self) -> None:
        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
        demo_dir = os.path.join(desktop if os.path.exists(desktop) else os.path.expanduser("~"), "Mandalina_Ornek_Evraklar")
        created = DemoFilesGenerator.create_demo_files(demo_dir)
        self.add_files(created)
        self.lbl_status.config(text=f"✨ 4 örnek evrak (UDF, 3 Sayfalı TIFF, DOCX, PDF) oluşturuldu: {demo_dir}")

    # ------------------------------------------------------------------------
    # DRAG & DROP, WINDOWS HOTKEYS, AND SYSTEM TRAY
    # ------------------------------------------------------------------------

    def _setup_drag_and_drop(self) -> None:
        enable_file_drop(self.root, self.add_files)

    def _setup_global_hotkeys(self) -> None:
        # Local keybind inside app
        self.root.bind_all("<Control-Shift-M>", lambda e: self.radial_wheel.show_at_cursor())
        self.root.bind_all("<Control-Shift-m>", lambda e: self.radial_wheel.show_at_cursor())

        # Windows global hotkey listener (Shift+Alt+M) via Win32 RegisterHotKey
        if sys.platform == "win32":
            def win32_hotkey_thread():
                try:
                    user32 = ctypes.windll.user32
                    MOD_ALT = 0x0001
                    MOD_SHIFT = 0x0004
                    VK_M = 0x4D
                    WM_HOTKEY = 0x0312
                    if user32.RegisterHotKey(None, 101, MOD_ALT | MOD_SHIFT, VK_M):
                        msg = ctypes.wintypes.MSG()
                        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) != 0:
                            if msg.message == WM_HOTKEY and msg.wParam == 101:
                                self.ui_queue.put(self.radial_wheel.show_at_cursor)
                            user32.TranslateMessage(ctypes.byref(msg))
                            user32.DispatchMessageW(ctypes.byref(msg))
                except Exception:
                    pass

            threading.Thread(target=win32_hotkey_thread, daemon=True).start()

    def _setup_system_tray(self) -> None:
        """Creates the Windows System Tray (Notification Area) icon using pystray."""
        try:
            import pystray
            from PIL import Image, ImageDraw

            if os.path.exists(self.icon_png_path):
                img = Image.open(self.icon_png_path).convert("RGBA").resize((64, 64))
            else:
                img = Image.new("RGBA", (64, 64), (255, 122, 24, 255))
                d = ImageDraw.Draw(img)
                d.ellipse([8, 8, 56, 56], fill=(255, 140, 0, 255))

            menu = pystray.Menu(
                pystray.MenuItem(
                    "🍊 Mandalina Stüdyo'yu Aç",
                    lambda icon, item: self.ui_queue.put(self._show_main_window),
                    default=True,
                ),
                pystray.MenuItem(
                    "🎡 Radyal Dönüşüm Çarkını Aç (Shift+Alt+M)",
                    lambda icon, item: self.ui_queue.put(self.radial_wheel.show_at_cursor),
                ),
                pystray.MenuItem(
                    "✨ Örnek Dosyalar Oluştur",
                    lambda icon, item: self.ui_queue.put(self._generate_demo_files),
                ),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem(
                    "❌ Çıkış",
                    lambda icon, item: self.ui_queue.put(self._quit_app),
                ),
            )

            self.tray_icon = pystray.Icon("MandalinaUDF", img, "Mandalina — UYAP UDF & TIFF Dönüştürücü", menu)
            threading.Thread(target=self.tray_icon.run, daemon=True).start()
        except Exception:
            self.tray_icon = None

    def _show_main_window(self) -> None:
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def _on_close_window(self) -> None:
        if self.tray_icon is not None:
            # Minimize to Windows System Tray instead of quitting
            self.root.withdraw()
        else:
            self._quit_app()

    def _quit_app(self) -> None:
        if self.tray_icon is not None:
            try:
                self.tray_icon.stop()
            except Exception:
                pass
        self.root.quit()
        self.root.destroy()
        sys.exit(0)

    def _poll_ui_queue(self) -> None:
        while not self.ui_queue.empty():
            try:
                fn = self.ui_queue.get_nowait()
                fn()
            except Exception:
                pass
        self.root.after(80, self._poll_ui_queue)

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(run_self_test())

    cli_files = [arg for arg in sys.argv[1:] if not arg.startswith("-") and os.path.exists(arg)]
    app = MandalinaWindowsApp(initial_files=cli_files)
    app.run()
