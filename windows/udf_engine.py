#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mandalina (Windows & Cross-Platform Edition) — UYAP (.udf) & Media Conversion Engine
Supports:
- UDF -> PDF, DOCX, HTML, RTF, TXT, MD, Multi-Page TIFF
- TIFF / PNG / JPG -> PDF, UDF (OCR), DOCX
- DOCX -> UDF (UYAP Editor compatible CDATA offset XML + ZIP)
- PDF -> UDF (UYAP Editor compatible)
- UYAP Tools: Compress (<5MB), Merge (UDF + TIFF + PDF + Images -> Single PDF), Split Pages, E-Signature (sign.sgn) Inspector
"""

import os
import re
import sys
import io
import zipfile
import hashlib
import base64
import shutil
import tempfile
import datetime
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple


# ============================================================================
# DATA MODELS
# ============================================================================

@dataclass
class UDFRun:
    text: str
    bold: bool = False
    italic: bool = False
    underline: bool = False
    font_family: str = "Times New Roman"
    font_size: float = 12.0


@dataclass
class UDFImageItem:
    image_bytes: bytes
    width: float = 240.0
    height: float = 120.0


@dataclass
class UDFParagraph:
    alignment: int = 0  # 0=Left, 1=Center, 2=Right, 3=Justify
    left_indent: float = 0.0
    right_indent: float = 0.0
    first_line_indent: float = 0.0
    runs: List[UDFRun] = field(default_factory=list)
    images: List[UDFImageItem] = field(default_factory=list)

    @property
    def plain_text(self) -> str:
        return "".join(r.text for r in self.runs)


@dataclass
class UDFTableCell:
    paragraphs: List[UDFParagraph] = field(default_factory=list)

    @property
    def plain_text(self) -> str:
        return "\n".join(p.plain_text for p in self.paragraphs)


@dataclass
class UDFTableRow:
    cells: List[UDFTableCell] = field(default_factory=list)


@dataclass
class UDFTable:
    rows: List[UDFTableRow] = field(default_factory=list)


@dataclass
class UDFElement:
    kind: str  # "paragraph" or "table"
    paragraph: Optional[UDFParagraph] = None
    table: Optional[UDFTable] = None


@dataclass
class UDFSignatureInfo:
    is_signed: bool = False
    signer_name: str = "Bilinmiyor"
    serial_or_tc: str = "-"
    issuer: str = "-"
    signing_time: str = "-"
    sha256_hex: str = "-"
    raw_size_bytes: int = 0
    summary_strings: List[str] = field(default_factory=list)


@dataclass
class UDFDocument:
    source_path: str
    raw_content_buffer: str
    elements: List[UDFElement] = field(default_factory=list)
    signature_info: UDFSignatureInfo = field(default_factory=UDFSignatureInfo)
    raw_xml: str = ""

    @property
    def plain_text(self) -> str:
        lines: List[str] = []
        for el in self.elements:
            if el.kind == "paragraph" and el.paragraph:
                lines.append(el.paragraph.plain_text)
            elif el.kind == "table" and el.table:
                for row in el.table.rows:
                    lines.append(" | ".join(c.plain_text.replace("\n", " ") for c in row.cells))
        return "\n".join(lines)

    @property
    def word_count(self) -> int:
        words = self.plain_text.split()
        return len(words)

    @property
    def char_count(self) -> int:
        return len(self.plain_text)

    @property
    def paragraph_count(self) -> int:
        return sum(1 for e in self.elements if e.kind == "paragraph")

    @property
    def table_count(self) -> int:
        return sum(1 for e in self.elements if e.kind == "table")


# ============================================================================
# UDF PARSER & WRITER ENGINE
# ============================================================================

class UDFEngine:

    @staticmethod
    def read_udf(file_path: str) -> UDFDocument:
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Dosya bulunamadı: {file_path}")

        with open(file_path, "rb") as f:
            raw_bytes = f.read()

        file_sha256 = hashlib.sha256(raw_bytes).hexdigest().upper()
        xml_bytes: Optional[bytes] = None
        sign_bytes: Optional[bytes] = None

        # Check if ZIP archive ('PK') or raw XML
        if len(raw_bytes) >= 4 and raw_bytes[:2] == b"PK":
            with zipfile.ZipFile(io.BytesIO(raw_bytes), "r") as zf:
                names = zf.namelist()
                for name in names:
                    low = os.path.basename(name).lower()
                    if low == "content.xml" or low.endswith(".xml"):
                        if xml_bytes is None or low == "content.xml":
                            xml_bytes = zf.read(name)
                    elif low == "sign.sgn" or low.endswith(".sgn") or low.endswith(".p7s"):
                        sign_bytes = zf.read(name)
        else:
            # Might be raw XML saved with .udf extension
            xml_bytes = raw_bytes

        if not xml_bytes:
            raise ValueError("Geçerli bir UYAP (.udf) içerik dosyası (content.xml) bulunamadı.")

        xml_str = xml_bytes.decode("utf-8", errors="replace")
        sig_info = UDFEngine._parse_signature(sign_bytes, file_sha256, len(raw_bytes))

        return UDFEngine._parse_content_xml(file_path, xml_str, sig_info)

    @staticmethod
    def _parse_signature(sign_bytes: Optional[bytes], sha256_hex: str, file_size: int) -> UDFSignatureInfo:
        info = UDFSignatureInfo(
            is_signed=(sign_bytes is not None and len(sign_bytes) > 0),
            sha256_hex=sha256_hex,
            raw_size_bytes=file_size,
        )
        if not sign_bytes:
            return info

        # Extract printable UTF-8 / ASCII strings from PKCS#7 / ASN.1 DER signature
        text_decoded = sign_bytes.decode("utf-8", errors="ignore")
        candidates = re.findall(r"[A-Za-z0-9ÇĞİÖŞÜçğıöşü\.\-\s:/]{4,80}", text_decoded)
        cleaned: List[str] = []
        for c in candidates:
            s = c.strip()
            if len(s) >= 4 and not s.isdigit() and s not in cleaned:
                cleaned.append(s)

        info.summary_strings = cleaned[:20]

        # Identify issuer, signer name, TC / serial
        issuers = ["TÜBİTAK", "TUBITAK", "Kamu SM", "KAMU SM", "E-Tuğra", "E-TUGRA", "EBG", "TürkTrust", "TURKTRUST", "e-İmza", "NES"]
        for item in cleaned:
            for iss in issuers:
                if iss.lower() in item.lower():
                    info.issuer = item
                    break

        # Find 11-digit Turkish ID number if present
        tc_match = re.search(r"\b([1-9][0-9]{10})\b", text_decoded)
        if tc_match:
            info.serial_or_tc = tc_match.group(1)

        # Find date-like string (YYYYMMDDHHMMSSZ or ISO)
        date_match = re.search(r"(20[1-3][0-9])([01][0-9])([0-3][0-9])([0-2][0-9])([0-5][0-9])", text_decoded)
        if date_match:
            y, m, d, hh, mm = date_match.groups()
            info.signing_time = f"{d}.{m}.{y} {hh}:{mm}"

        # Find signer name heuristic
        for item in cleaned:
            if item != info.issuer and any(ch.isalpha() for ch in item) and " " in item and len(item) <= 45:
                if not any(k in item.lower() for k in ["http", "www", " authority", "ca ", "oid", "sha"]):
                    info.signer_name = item
                    break

        if info.signer_name == "Bilinmiyor" and cleaned:
            info.signer_name = cleaned[0]
        if info.issuer == "-":
            info.issuer = "Nitelikli Elektronik Sertifika (PKCS#7 / CAdES)"

        return info

    @staticmethod
    def _parse_content_xml(file_path: str, xml_str: str, sig_info: UDFSignatureInfo) -> UDFDocument:
        # Remove potential BOM or invalid control chars outside CDATA
        clean_xml = xml_str.lstrip("\ufeff").strip()
        root = ET.fromstring(clean_xml)

        # 1. Extract the master <content> text buffer (root.find('content'))
        master_buffer = ""
        content_node = root.find("content")
        if content_node is not None and content_node.text:
            master_buffer = content_node.text

        elements_node = root.find("elements")
        parsed_elements: List[UDFElement] = []

        if elements_node is not None:
            for child in elements_node:
                tag = child.tag.lower()
                if tag == "paragraph":
                    p = UDFEngine._parse_paragraph_node(child, master_buffer)
                    parsed_elements.append(UDFElement(kind="paragraph", paragraph=p))
                elif tag == "table":
                    t = UDFEngine._parse_table_node(child, master_buffer)
                    parsed_elements.append(UDFElement(kind="table", table=t))

        # Fallback: if no <elements> existed, split master_buffer by newline
        if not parsed_elements and master_buffer:
            for line in master_buffer.split("\n"):
                p = UDFParagraph(alignment=0, runs=[UDFRun(text=line)])
                parsed_elements.append(UDFElement(kind="paragraph", paragraph=p))

        return UDFDocument(
            source_path=file_path,
            raw_content_buffer=master_buffer,
            elements=parsed_elements,
            signature_info=sig_info,
            raw_xml=xml_str,
        )

    @staticmethod
    def _parse_paragraph_node(p_node: ET.Element, master_buffer: str) -> UDFParagraph:
        align = int(p_node.attrib.get("Alignment", p_node.attrib.get("alignment", "0")) or "0")
        left_ind = float(p_node.attrib.get("LeftIndent", "0") or "0")
        right_ind = float(p_node.attrib.get("RightIndent", "0") or "0")
        first_ind = float(p_node.attrib.get("FirstLineIndent", "0") or "0")

        p_bold = p_node.attrib.get("bold", "false").lower() == "true"
        p_italic = p_node.attrib.get("italic", "false").lower() == "true"
        p_under = p_node.attrib.get("underline", "false").lower() == "true"
        p_family = p_node.attrib.get("family", "Times New Roman")
        p_size = float(p_node.attrib.get("size", "12") or "12")

        runs: List[UDFRun] = []
        images: List[UDFImageItem] = []

        for child in p_node:
            ctag = child.tag.lower()
            if ctag in ("content", "field", "space", "tab"):
                start_off = child.attrib.get("startOffset")
                length_val = child.attrib.get("length")
                text_piece = ""
                if start_off is not None and length_val is not None:
                    s = int(start_off)
                    ln = int(length_val)
                    if 0 <= s <= len(master_buffer):
                        text_piece = master_buffer[s : s + ln]
                elif child.text:
                    text_piece = child.text
                elif ctag == "tab":
                    text_piece = "\t"
                elif ctag == "space":
                    text_piece = " "

                # Strip trailing paragraph newline if UYAP included it in the run slice
                text_piece = text_piece.replace("\r", "")
                if text_piece.endswith("\n"):
                    text_piece = text_piece[:-1]

                bold = child.attrib.get("bold", str(p_bold)).lower() == "true"
                italic = child.attrib.get("italic", str(p_italic)).lower() == "true"
                under = child.attrib.get("underline", str(p_under)).lower() == "true"
                fam = child.attrib.get("family", p_family)
                sz = float(child.attrib.get("size", str(p_size)) or str(p_size))

                if text_piece:
                    runs.append(
                        UDFRun(
                            text=text_piece,
                            bold=bold,
                            italic=italic,
                            underline=under,
                            font_family=fam,
                            font_size=sz,
                        )
                    )
            elif ctag == "image":
                b64_str = child.attrib.get("imageData") or (child.text or "")
                b64_str = b64_str.strip()
                if b64_str:
                    try:
                        img_bytes = base64.b64decode(b64_str)
                        w = float(child.attrib.get("width", "240") or "240")
                        h = float(child.attrib.get("height", "120") or "120")
                        images.append(UDFImageItem(image_bytes=img_bytes, width=w, height=h))
                    except Exception:
                        pass

        # If paragraph had direct text without child <content> nodes
        if not runs and not images and p_node.text and p_node.text.strip():
            runs.append(
                UDFRun(
                    text=p_node.text.strip(),
                    bold=p_bold,
                    italic=p_italic,
                    underline=p_under,
                    font_family=p_family,
                    font_size=p_size,
                )
            )

        return UDFParagraph(
            alignment=align,
            left_indent=left_ind,
            right_indent=right_ind,
            first_line_indent=first_ind,
            runs=runs,
            images=images,
        )

    @staticmethod
    def _parse_table_node(t_node: ET.Element, master_buffer: str) -> UDFTable:
        rows: List[UDFTableRow] = []
        for r_node in t_node:
            if r_node.tag.lower() == "row":
                cells: List[UDFTableCell] = []
                for c_node in r_node:
                    if c_node.tag.lower() == "cell":
                        cell_paras: List[UDFParagraph] = []
                        for p_node in c_node:
                            if p_node.tag.lower() == "paragraph":
                                cell_paras.append(UDFEngine._parse_paragraph_node(p_node, master_buffer))
                        cells.append(UDFTableCell(paragraphs=cell_paras))
                rows.append(UDFTableRow(cells=cells))
        return UDFTable(rows=rows)

    # ========================================================================
    # BUILD VALID UYAP (.UDF) FILE FROM ELEMENTS OR TEXT
    # ========================================================================

    @staticmethod
    def write_udf(elements: List[UDFElement], output_path: str) -> str:
        """
        Writes a 100% UYAP Editor compatible .udf file (ZIP archive containing content.xml
        with CDATA master buffer and exact startOffset/length attributes).
        """
        buffer_parts: List[str] = []
        current_offset = 0
        xml_elements_lines: List[str] = []

        def encode_paragraph(p: UDFParagraph, indent_str: str = "    ") -> str:
            nonlocal current_offset
            p_attrs = f'Alignment="{p.alignment}"'
            if p.left_indent > 0:
                p_attrs += f' LeftIndent="{p.left_indent:.1f}"'
            if p.right_indent > 0:
                p_attrs += f' RightIndent="{p.right_indent:.1f}"'
            if p.first_line_indent > 0:
                p_attrs += f' FirstLineIndent="{p.first_line_indent:.1f}"'

            lines = [f"{indent_str}<paragraph {p_attrs}>"]

            for img in p.images:
                b64 = base64.b64encode(img.image_bytes).decode("ascii")
                lines.append(
                    f'{indent_str}  <image width="{int(img.width)}" height="{int(img.height)}" imageData="{b64}" />'
                )

            if not p.runs:
                # Empty line in UYAP has a single '\n'
                text_with_nl = "\n"
                start = current_offset
                length = len(text_with_nl)
                buffer_parts.append(text_with_nl)
                current_offset += length
                lines.append(f'{indent_str}  <content startOffset="{start}" length="{length}" family="Times New Roman" size="12" />')
            else:
                for idx, run in enumerate(p.runs):
                    clean_txt = run.text.replace("\r", "")
                    if idx == len(p.runs) - 1:
                        clean_txt = clean_txt + "\n"
                    if not clean_txt:
                        clean_txt = " "
                    start = current_offset
                    length = len(clean_txt)
                    buffer_parts.append(clean_txt)
                    current_offset += length

                    r_attrs = [
                        f'startOffset="{start}"',
                        f'length="{length}"',
                        f'family="{ UDFEngine._xml_attr_escape(run.font_family) }"',
                        f'size="{int(run.font_size)}"',
                    ]
                    if run.bold:
                        r_attrs.append('bold="true"')
                    if run.italic:
                        r_attrs.append('italic="true"')
                    if run.underline:
                        r_attrs.append('underline="true"')
                    lines.append(f"{indent_str}  <content {' '.join(r_attrs)} />")

            lines.append(f"{indent_str}</paragraph>")
            return "\n".join(lines)

        for el in elements:
            if el.kind == "paragraph" and el.paragraph:
                xml_elements_lines.append(encode_paragraph(el.paragraph, "    "))
            elif el.kind == "table" and el.table:
                col_count = max((len(r.cells) for r in el.table.rows), default=1)
                col_spans = ",".join(["150"] * col_count)
                t_lines = [f'    <table columnCount="{col_count}" columnSpans="{col_spans}" border="borderCell">']
                for row in el.table.rows:
                    t_lines.append("      <row>")
                    for cell in row.cells:
                        t_lines.append("        <cell>")
                        if cell.paragraphs:
                            for cp in cell.paragraphs:
                                t_lines.append(encode_paragraph(cp, "          "))
                        else:
                            t_lines.append(encode_paragraph(UDFParagraph(alignment=0, runs=[UDFRun(text="")]), "          "))
                        t_lines.append("        </cell>")
                    t_lines.append("      </row>")
                t_lines.append("    </table>")
                xml_elements_lines.append("\n".join(t_lines))

        full_buffer = "".join(buffer_parts)
        if not full_buffer:
            full_buffer = "\n"
            xml_elements_lines.append(
                '    <paragraph Alignment="0">\n      <content startOffset="0" length="1" family="Times New Roman" size="12" />\n    </paragraph>'
            )

        # Escape ']]>' if it ever appears inside CDATA
        safe_cdata = full_buffer.replace("]]>", "]]]]><![CDATA[>")

        content_xml = f"""<?xml version="1.0" encoding="UTF-8" ?>
<template format_id="1.8">
  <content><![CDATA[{safe_cdata}]]></content>
  <properties>
    <pageFormat mediaSizeName="1" leftMargin="42.5" rightMargin="42.5" topMargin="42.5" bottomMargin="42.5" paperOrientation="1" headerFOffset="20.0" footerFOffset="20.0" />
  </properties>
  <elements resolver="hvl-default">
{chr(10).join(xml_elements_lines)}
  </elements>
  <styles>
    <style name="default" description="Geçerli" family="Times New Roman" size="12" bold="false" italic="false" foreground="-13421773" FONT_ATTRIBUTE_KEY="javax.swing.plaf.FontUIResource[family=Times New Roman,name=Times New Roman,style=plain,size=12]" />
    <style name="hvl-default" family="Times New Roman" size="12" description="Gövde" />
  </styles>
</template>
"""

        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("content.xml", content_xml.encode("utf-8"))

        return output_path

    @staticmethod
    def _xml_attr_escape(val: str) -> str:
        return (
            val.replace("&", "&amp;")
            .replace('"', "&quot;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
        )

    # ========================================================================
    # EXPORT UDF -> HTML, TXT, MD, RTF, DOCX, PDF, TIFF
    # ========================================================================

    @staticmethod
    def export_to_txt(doc: UDFDocument, output_path: str) -> str:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(doc.plain_text)
        return output_path

    @staticmethod
    def export_to_markdown(doc: UDFDocument, output_path: str) -> str:
        md_lines: List[str] = []
        for el in doc.elements:
            if el.kind == "paragraph" and el.paragraph:
                p = el.paragraph
                parts: List[str] = []
                for r in p.runs:
                    txt = r.text
                    if not txt.strip():
                        parts.append(txt)
                        continue
                    if r.bold and r.italic:
                        txt = f"***{txt}***"
                    elif r.bold:
                        txt = f"**{txt}**"
                    elif r.italic:
                        txt = f"*{txt}*"
                    parts.append(txt)
                line = "".join(parts)
                if p.alignment == 1 and line.strip():
                    md_lines.append(f"### {line.strip()}")
                else:
                    md_lines.append(line)
                md_lines.append("")
            elif el.kind == "table" and el.table:
                rows = el.table.rows
                if rows:
                    col_count = max(len(r.cells) for r in rows)
                    for r_idx, row in enumerate(rows):
                        cells_txt = [
                            c.plain_text.replace("\n", " ").replace("|", "\\|").strip()
                            for c in row.cells
                        ]
                        while len(cells_txt) < col_count:
                            cells_txt.append("")
                        md_lines.append("| " + " | ".join(cells_txt) + " |")
                        if r_idx == 0:
                            md_lines.append("| " + " | ".join(["---"] * col_count) + " |")
                    md_lines.append("")

        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\n".join(md_lines))
        return output_path

    @staticmethod
    def export_to_html(doc: UDFDocument, output_path: str) -> str:
        align_map = {0: "left", 1: "center", 2: "right", 3: "justify"}
        body_parts: List[str] = []

        for el in doc.elements:
            if el.kind == "paragraph" and el.paragraph:
                p = el.paragraph
                al = align_map.get(p.alignment, "left")
                style = f"text-align:{al}; margin: 0 0 6pt 0;"
                if p.first_line_indent > 0:
                    style += f" text-indent:{p.first_line_indent}pt;"
                if p.left_indent > 0:
                    style += f" padding-left:{p.left_indent}pt;"

                spans: List[str] = []
                for img in p.images:
                    b64 = base64.b64encode(img.image_bytes).decode("ascii")
                    spans.append(
                        f'<img src="data:image/png;base64,{b64}" style="max-width:100%; width:{int(img.width)}px; height:auto;" />'
                    )
                for r in p.runs:
                    esc = (
                        r.text.replace("&", "&amp;")
                        .replace("<", "&lt;")
                        .replace(">", "&gt;")
                        .replace("\t", "&emsp;&emsp;")
                    )
                    r_style = f"font-family:'{r.font_family}','Times New Roman',serif; font-size:{r.font_size}pt;"
                    if r.bold:
                        r_style += " font-weight:bold;"
                    if r.italic:
                        r_style += " font-style:italic;"
                    if r.underline:
                        r_style += " text-decoration:underline;"
                    spans.append(f'<span style="{r_style}">{esc}</span>')

                inner = "".join(spans) if spans else "&nbsp;"
                body_parts.append(f'<p style="{style}">{inner}</p>')

            elif el.kind == "table" and el.table:
                body_parts.append('<table class="udf-table">')
                for row in el.table.rows:
                    body_parts.append("  <tr>")
                    for cell in row.cells:
                        cell_html = "<br/>".join(
                            UDFEngine._xml_attr_escape(cp.plain_text) for cp in cell.paragraphs
                        )
                        body_parts.append(f"    <td>{cell_html or '&nbsp;'}</td>")
                    body_parts.append("  </tr>")
                body_parts.append("</table>")

        html_doc = f"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8" />
<title>{UDFEngine._xml_attr_escape(os.path.basename(doc.source_path))}</title>
<style>
  body {{
    background: #f0f2f5;
    margin: 0;
    padding: 24px;
    font-family: 'Times New Roman', Times, serif;
    color: #111;
  }}
  .a4-page {{
    background: #fff;
    max-width: 210mm;
    min-height: 297mm;
    margin: 0 auto;
    padding: 20mm;
    box-shadow: 0 6px 24px rgba(0,0,0,0.12);
    box-sizing: border-box;
    line-height: 1.48;
  }}
  .udf-table {{
    width: 100%;
    border-collapse: collapse;
    margin: 10pt 0;
  }}
  .udf-table td, .udf-table th {{
    border: 1px solid #333;
    padding: 6px 8px;
    font-size: 11pt;
    vertical-align: top;
  }}
  @media print {{
    body {{ background: #fff; padding: 0; }}
    .a4-page {{ box-shadow: none; margin: 0; width: 100%; }}
  }}
</style>
</head>
<body>
  <div class="a4-page">
    {chr(10).join(body_parts)}
  </div>
</body>
</html>
"""
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(html_doc)
        return output_path

    @staticmethod
    def export_to_rtf(doc: UDFDocument, output_path: str) -> str:
        def rtf_escape(s: str) -> str:
            out: List[str] = []
            for ch in s:
                code = ord(ch)
                if ch == "\\":
                    out.append("\\\\")
                elif ch == "{":
                    out.append("\\{")
                elif ch == "}":
                    out.append("\\}")
                elif ch == "\t":
                    out.append("\\tab ")
                elif code < 128:
                    out.append(ch)
                else:
                    signed = code if code < 32768 else code - 65536
                    out.append(f"\\u{signed}?")
            return "".join(out)

        align_cmd = {0: "\\ql", 1: "\\qc", 2: "\\qr", 3: "\\qj"}
        rtf_lines = [
            r"{\rtf1\ansi\ansicpg1254\uc1\deff0{\fonttbl{\f0\froman\fcharset162 Times New Roman;}{\f1\fswiss\fcharset162 Arial;}}",
            r"\viewkind4\uc1\pard\f0\fs24",
        ]

        for el in doc.elements:
            if el.kind == "paragraph" and el.paragraph:
                p = el.paragraph
                ac = align_cmd.get(p.alignment, "\\ql")
                p_chunks = [f"\\pard{ac} "]
                for r in p.runs:
                    fs = int(r.font_size * 2)
                    prefix = f"\\fs{fs}"
                    suffix = ""
                    if r.bold:
                        prefix += "\\b"
                        suffix += "\\b0"
                    if r.italic:
                        prefix += "\\i"
                        suffix += "\\i0"
                    if r.underline:
                        prefix += "\\ul"
                        suffix += "\\ulnone"
                    p_chunks.append(f"{prefix} {rtf_escape(r.text)}{suffix} ")
                p_chunks.append("\\par")
                rtf_lines.append("".join(p_chunks))
            elif el.kind == "table" and el.table:
                for row in el.table.rows:
                    row_txt = " | ".join(c.plain_text.replace("\n", " ") for c in row.cells)
                    rtf_lines.append(f"\\pard\\ql {rtf_escape(row_txt)}\\par")

        rtf_lines.append("}")
        with open(output_path, "w", encoding="ascii", errors="replace") as f:
            f.write("\n".join(rtf_lines))
        return output_path

    @staticmethod
    def export_to_docx(doc: UDFDocument, output_path: str) -> str:
        """
        Exports UDFDocument to OpenXML Word (.docx).
        Uses python-docx if available, otherwise falls back to built-in OpenXML ZIP generator
        so it never fails even without external packages.
        """
        try:
            import docx
            from docx.shared import Pt, Inches
            from docx.enum.text import WD_ALIGN_PARAGRAPH

            wdoc = docx.Document()
            align_map = {
                0: WD_ALIGN_PARAGRAPH.LEFT,
                1: WD_ALIGN_PARAGRAPH.CENTER,
                2: WD_ALIGN_PARAGRAPH.RIGHT,
                3: WD_ALIGN_PARAGRAPH.JUSTIFY,
            }

            for el in doc.elements:
                if el.kind == "paragraph" and el.paragraph:
                    p = el.paragraph
                    wp = wdoc.add_paragraph()
                    wp.alignment = align_map.get(p.alignment, WD_ALIGN_PARAGRAPH.LEFT)
                    for img in p.images:
                        try:
                            wp.add_run().add_picture(io.BytesIO(img.image_bytes), width=Inches(min(img.width / 72.0, 5.5)))
                        except Exception:
                            pass
                    for r in p.runs:
                        wr = wp.add_run(r.text)
                        wr.bold = r.bold
                        wr.italic = r.italic
                        wr.underline = r.underline
                        wr.font.name = r.font_family
                        wr.font.size = Pt(r.font_size)
                elif el.kind == "table" and el.table and el.table.rows:
                    rows = el.table.rows
                    col_count = max(len(r.cells) for r in rows)
                    wt = wdoc.add_table(rows=len(rows), cols=col_count)
                    try:
                        wt.style = "Table Grid"
                    except Exception:
                        pass
                    for r_idx, row in enumerate(rows):
                        for c_idx, cell in enumerate(row.cells):
                            if c_idx < col_count:
                                wt.cell(r_idx, c_idx).text = cell.plain_text

            wdoc.save(output_path)
            return output_path
        except ImportError:
            return UDFEngine._export_to_docx_builtin(doc, output_path)

    @staticmethod
    def _export_to_docx_builtin(doc: UDFDocument, output_path: str) -> str:
        """Pure-Python OpenXML (.docx) builder with zero external dependencies."""
        align_map = {0: "left", 1: "center", 2: "right", 3: "both"}
        body_xml: List[str] = []

        def esc(s: str) -> str:
            return (
                s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace('"', "&quot;")
            )

        for el in doc.elements:
            if el.kind == "paragraph" and el.paragraph:
                p = el.paragraph
                jc = align_map.get(p.alignment, "left")
                runs_xml: List[str] = []
                for r in p.runs:
                    rpr: List[str] = [
                        f'<w:rFonts w:ascii="{esc(r.font_family)}" w:hAnsi="{esc(r.font_family)}"/>',
                        f'<w:sz w:val="{int(r.font_size * 2)}"/>',
                    ]
                    if r.bold:
                        rpr.append("<w:b/>")
                    if r.italic:
                        rpr.append("<w:i/>")
                    if r.underline:
                        rpr.append('<w:u w:val="single"/>')
                    runs_xml.append(
                        f'<w:r><w:rPr>{"".join(rpr)}</w:rPr><w:t xml:space="preserve">{esc(r.text)}</w:t></w:r>'
                    )
                body_xml.append(f'<w:p><w:pPr><w:jc w:val="{jc}"/></w:pPr>{"".join(runs_xml)}</w:p>')
            elif el.kind == "table" and el.table:
                t_xml = [
                    '<w:tbl><w:tblPr><w:tblBorders>'
                    '<w:top w:val="single" w:sz="4" w:space="0" w:color="333333"/>'
                    '<w:left w:val="single" w:sz="4" w:space="0" w:color="333333"/>'
                    '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="333333"/>'
                    '<w:right w:val="single" w:sz="4" w:space="0" w:color="333333"/>'
                    '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="333333"/>'
                    '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="333333"/>'
                    '</w:tblBorders></w:tblPr>'
                ]
                for row in el.table.rows:
                    t_xml.append("<w:tr>")
                    for cell in row.cells:
                        t_xml.append(
                            f'<w:tc><w:p><w:r><w:t xml:space="preserve">{esc(cell.plain_text)}</w:t></w:r></w:p></w:tc>'
                        )
                    t_xml.append("</w:tr>")
                t_xml.append("</w:tbl>")
                body_xml.append("".join(t_xml))

        document_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    {"".join(body_xml)}
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417"/>
    </w:sectPr>
  </w:body>
</w:document>"""

        content_types_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>"""

        rels_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""

        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("[Content_Types].xml", content_types_xml.encode("utf-8"))
            zf.writestr("_rels/.rels", rels_xml.encode("utf-8"))
            zf.writestr("word/document.xml", document_xml.encode("utf-8"))

        return output_path

    @staticmethod
    def export_to_pdf(doc: UDFDocument, output_path: str) -> str:
        """
        Exports UDFDocument to an A4 PDF with full Turkish Unicode support.
        Uses ReportLab with system TrueType fonts (Windows Arial/Times or macOS/Linux TrueType)
        and falls back to built-in PDF writer if ReportLab is not installed.
        """
        try:
            from reportlab.lib.pagesizes import A4
            from reportlab.lib.styles import ParagraphStyle
            from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_RIGHT, TA_JUSTIFY
            from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage
            from reportlab.lib import colors
            from reportlab.pdfbase import pdfmetrics
            from reportlab.pdfbase.ttfonts import TTFont

            font_reg, font_bold, font_italic = UDFEngine._register_turkish_fonts()

            pdf = SimpleDocTemplate(
                output_path,
                pagesize=A4,
                leftMargin=45,
                rightMargin=45,
                topMargin=45,
                bottomMargin=45,
                title=os.path.basename(doc.source_path),
            )

            align_map = {
                0: TA_LEFT,
                1: TA_CENTER,
                2: TA_RIGHT,
                3: TA_JUSTIFY,
            }

            story = []
            for idx, el in enumerate(doc.elements):
                if el.kind == "paragraph" and el.paragraph:
                    p = el.paragraph
                    for img in p.images:
                        try:
                            story.append(RLImage(io.BytesIO(img.image_bytes), width=min(img.width, 460), height=min(img.height, 600)))
                            story.append(Spacer(1, 6))
                        except Exception:
                            pass

                    if not p.runs:
                        story.append(Spacer(1, 10))
                        continue

                    base_size = p.runs[0].font_size if p.runs else 12.0
                    style = ParagraphStyle(
                        name=f"UDF_P_{idx}",
                        fontName=font_reg,
                        fontSize=base_size,
                        leading=base_size * 1.38,
                        alignment=align_map.get(p.alignment, TA_LEFT),
                        leftIndent=p.left_indent,
                        rightIndent=p.right_indent,
                        firstLineIndent=p.first_line_indent,
                        spaceAfter=4,
                    )

                    markup_parts: List[str] = []
                    for r in p.runs:
                        esc = (
                            r.text.replace("&", "&amp;")
                            .replace("<", "&lt;")
                            .replace(">", "&gt;")
                            .replace("\t", "&nbsp;&nbsp;&nbsp;&nbsp;")
                        )
                        if r.bold:
                            esc = f'<font name="{font_bold}">{esc}</font>'
                        elif r.italic:
                            esc = f'<font name="{font_italic}">{esc}</font>'
                        if r.underline:
                            esc = f"<u>{esc}</u>"
                        markup_parts.append(esc)

                    story.append(Paragraph("".join(markup_parts), style))

                elif el.kind == "table" and el.table and el.table.rows:
                    cell_style = ParagraphStyle(
                        name=f"UDF_Cell_{idx}",
                        fontName=font_reg,
                        fontSize=10.5,
                        leading=13.5,
                    )
                    table_data = []
                    for row in el.table.rows:
                        r_cells = []
                        for cell in row.cells:
                            esc_txt = (
                                cell.plain_text.replace("&", "&amp;")
                                .replace("<", "&lt;")
                                .replace(">", "&gt;")
                                .replace("\n", "<br/>")
                            )
                            r_cells.append(Paragraph(esc_txt or "&nbsp;", cell_style))
                        table_data.append(r_cells)

                    if table_data:
                        t = Table(table_data, repeatRows=1)
                        t.setStyle(
                            TableStyle(
                                [
                                    ("GRID", (0, 0), (-1, -1), 0.6, colors.HexColor("#333333")),
                                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                                    ("TOPPADDING", (0, 0), (-1, -1), 5),
                                    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                                    ("LEFTPADDING", (0, 0), (-1, -1), 6),
                                    ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                                ]
                            )
                        )
                        story.append(Spacer(1, 6))
                        story.append(t)
                        story.append(Spacer(1, 8))

            if not story:
                story.append(Spacer(1, 12))

            pdf.build(story)
            return output_path
        except ImportError:
            return UDFEngine._export_to_pdf_fallback(doc.plain_text, output_path)

    @staticmethod
    def _register_turkish_fonts() -> Tuple[str, str, str]:
        """Registers Windows / macOS / Linux TrueType fonts with full Turkish glyph coverage in ReportLab."""
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont

        candidates = [
            # Windows fonts
            (
                r"C:\Windows\Fonts\times.ttf",
                r"C:\Windows\Fonts\timesbd.ttf",
                r"C:\Windows\Fonts\timesi.ttf",
            ),
            (
                r"C:\Windows\Fonts\arial.ttf",
                r"C:\Windows\Fonts\arialbd.ttf",
                r"C:\Windows\Fonts\ariali.ttf",
            ),
            (
                r"C:\Windows\Fonts\calibri.ttf",
                r"C:\Windows\Fonts\calibrib.ttf",
                r"C:\Windows\Fonts\calibrii.ttf",
            ),
            # macOS fonts (for cross-platform self-test)
            (
                "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
                "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf",
                "/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf",
            ),
            (
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Supplemental/Arial Italic.ttf",
            ),
            # Linux DejaVu fonts
            (
                "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf",
            ),
        ]

        for reg_path, bold_path, italic_path in candidates:
            if os.path.exists(reg_path):
                try:
                    pdfmetrics.registerFont(TTFont("MandalinaRegular", reg_path))
                    if os.path.exists(bold_path):
                        pdfmetrics.registerFont(TTFont("MandalinaBold", bold_path))
                    else:
                        pdfmetrics.registerFont(TTFont("MandalinaBold", reg_path))
                    if os.path.exists(italic_path):
                        pdfmetrics.registerFont(TTFont("MandalinaItalic", italic_path))
                    else:
                        pdfmetrics.registerFont(TTFont("MandalinaItalic", reg_path))
                    return ("MandalinaRegular", "MandalinaBold", "MandalinaItalic")
                except Exception:
                    continue

        return ("Helvetica", "Helvetica-Bold", "Helvetica-Oblique")

    @staticmethod
    def _export_to_pdf_fallback(text: str, output_path: str) -> str:
        """Minimal zero-dependency PDF 1.4 generator if ReportLab is not yet installed."""
        # Map Turkish characters to WinAnsi (CP1254) byte values for Type1 Helvetica with /WinAnsiEncoding
        lines = text.splitlines() or [""]
        pages_lines = [lines[i : i + 45] for i in range(0, len(lines), 45)] or [[""]]

        def escape_pdf_bytes(s: str) -> bytes:
            # Replace Turkish-specific chars not in standard WinAnsi with closest readable or CP1254 octals
            tr_map = {
                "ğ": "g", "Ğ": "G",
                "ş": "s", "Ş": "S",
                "ı": "i", "İ": "I",
            }
            for k, v in tr_map.items():
                s = s.replace(k, v)
            s = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
            return s.encode("cp1252", errors="replace")

        objects: List[bytes] = []
        # 1: Catalog, 2: Pages, 3: Font
        page_obj_ids = []
        next_id = 4
        page_streams: List[Tuple[int, int, bytes]] = []
        for p_lines in pages_lines:
            page_id = next_id
            content_id = next_id + 1
            next_id += 2
            page_obj_ids.append(page_id)

            stream_cmds = [b"BT /F1 11 Tf 50 790 Td 15 TL"]
            for ln in p_lines:
                # Wrap at 85 chars
                while len(ln) > 85:
                    stream_cmds.append(b"(" + escape_pdf_bytes(ln[:85]) + b") Tj T*")
                    ln = ln[85:]
                stream_cmds.append(b"(" + escape_pdf_bytes(ln) + b") Tj T*")
            stream_cmds.append(b"ET")
            stream_data = b"\n".join(stream_cmds)
            page_streams.append((page_id, content_id, stream_data))

        kids_str = " ".join(f"{pid} 0 R" for pid in page_obj_ids).encode("ascii")
        objects.append(b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj")
        objects.append(
            b"2 0 obj << /Type /Pages /Kids [" + kids_str + b"] /Count " + str(len(page_obj_ids)).encode("ascii") + b" >> endobj"
        )
        objects.append(
            b"3 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> endobj"
        )

        for page_id, content_id, stream_data in page_streams:
            objects.append(
                f"{page_id} 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >> endobj".encode(
                    "ascii"
                )
            )
            objects.append(
                f"{content_id} 0 obj << /Length {len(stream_data)} >> stream\n".encode("ascii")
                + stream_data
                + b"\nendstream endobj"
            )

        out = bytearray(b"%PDF-1.4\n")
        offsets = []
        for obj in objects:
            offsets.append(len(out))
            out.extend(obj + b"\n")
        xref_pos = len(out)
        out.extend(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii"))
        for off in offsets:
            out.extend(f"{off:010d} 00000 n \n".encode("ascii"))
        out.extend(
            f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n".encode("ascii")
        )

        with open(output_path, "wb") as f:
            f.write(out)
        return output_path

    @staticmethod
    def export_to_tiff(doc: UDFDocument, output_path: str) -> str:
        """Renders UDFDocument pages into a multi-page TIFF file using Pillow."""
        from PIL import Image, ImageDraw, ImageFont

        # Render A4 pages at 150 DPI (1240 x 1754 px)
        page_w, page_h = 1240, 1754
        margin_x, margin_y = 90, 90

        font = UDFEngine._load_pil_font(22)
        bold_font = UDFEngine._load_pil_font(23, bold=True)

        # Wrap lines
        wrapped_lines: List[Tuple[str, bool, int]] = []
        for el in doc.elements:
            if el.kind == "paragraph" and el.paragraph:
                p = el.paragraph
                txt = p.plain_text
                is_bold = any(r.bold for r in p.runs)
                if not txt.strip():
                    wrapped_lines.append(("", False, p.alignment))
                else:
                    words = txt.split(" ")
                    cur = ""
                    for w in words:
                        test = (cur + " " + w).strip()
                        if len(test) > 78:
                            wrapped_lines.append((cur, is_bold, p.alignment))
                            cur = w
                        else:
                            cur = test
                    if cur:
                        wrapped_lines.append((cur, is_bold, p.alignment))
            elif el.kind == "table" and el.table:
                wrapped_lines.append(("-" * 75, False, 0))
                for row in el.table.rows:
                    row_str = " | ".join(c.plain_text.replace("\n", " ") for c in row.cells)
                    wrapped_lines.append((row_str[:78], False, 0))
                wrapped_lines.append(("-" * 75, False, 0))

        lines_per_page = 46
        chunks = [wrapped_lines[i : i + lines_per_page] for i in range(0, len(wrapped_lines), lines_per_page)] or [[("", False, 0)]]

        frames: List[Image.Image] = []
        for chunk in chunks:
            img = Image.new("RGB", (page_w, page_h), color=(255, 255, 255))
            draw = ImageDraw.Draw(img)
            y = margin_y
            for line_txt, is_b, align in chunk:
                fnt = bold_font if is_b else font
                x = margin_x
                if align == 1 and line_txt:
                    bbox = draw.textbbox((0, 0), line_txt, font=fnt)
                    tw = bbox[2] - bbox[0]
                    x = max(margin_x, (page_w - tw) // 2)
                draw.text((x, y), line_txt, fill=(20, 20, 20), font=fnt)
                y += 33
            frames.append(img)

        frames[0].save(
            output_path,
            format="TIFF",
            save_all=True,
            append_images=frames[1:],
            compression="tiff_deflate",
        )
        return output_path

    @staticmethod
    def _load_pil_font(size: int, bold: bool = False):
        from PIL import ImageFont

        font_paths = (
            [
                r"C:\Windows\Fonts\timesbd.ttf",
                r"C:\Windows\Fonts\arialbd.ttf",
                "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
            ]
            if bold
            else [
                r"C:\Windows\Fonts\times.ttf",
                r"C:\Windows\Fonts\arial.ttf",
                "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
            ]
        )
        for fp in font_paths:
            if os.path.exists(fp):
                try:
                    return ImageFont.truetype(fp, size)
                except Exception:
                    pass
        return ImageFont.load_default()


# ============================================================================
# MEDIA & REVERSE CONVERSION ENGINE (TIFF, PNG, JPG, DOCX, PDF -> UDF / PDF)
# ============================================================================

class MediaConverterEngine:

    @staticmethod
    def image_or_tiff_to_pdf(input_path: str, output_path: str) -> Tuple[str, int]:
        """Converts single/multi-page TIFF or image (PNG/JPG/BMP/WEBP) to A4 PDF."""
        from PIL import Image, ImageSequence

        frames: List[Image.Image] = []
        with Image.open(input_path) as im:
            for page in ImageSequence.Iterator(im):
                rgb = page.convert("RGB")
                frames.append(rgb.copy())

        if not frames:
            raise ValueError("Görsel dosyasında okunabilir sayfa bulunamadı.")

        frames[0].save(
            output_path,
            format="PDF",
            resolution=150.0,
            save_all=True,
            append_images=frames[1:],
        )
        return output_path, len(frames)

    @staticmethod
    def extract_ocr_text_from_image(input_path: str) -> str:
        """
        Extracts Turkish text from an image/TIFF if Tesseract OCR is installed on Windows/macOS,
        or provides structured image header text so UYAP .udf conversion always succeeds.
        """
        try:
            import pytesseract
            from PIL import Image, ImageSequence

            texts: List[str] = []
            with Image.open(input_path) as im:
                for idx, page in enumerate(ImageSequence.Iterator(im), start=1):
                    txt = pytesseract.image_to_string(page, lang="tur+eng")
                    if txt.strip():
                        texts.append(f"--- [Sayfa {idx}] ---\n{txt.strip()}")
            if texts:
                return "\n\n".join(texts)
        except Exception:
            pass

        return f"[Görsel Evrak Eki: {os.path.basename(input_path)}]"

    @staticmethod
    def image_or_tiff_to_udf(input_path: str, output_path: str) -> str:
        """Converts single/multi-page TIFF or image into a UYAP-compatible .udf with embedded images + OCR text."""
        from PIL import Image, ImageSequence

        elements: List[UDFElement] = [
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=1,
                    runs=[UDFRun(text=f"T.C. UYAP EVRAK EKİ ({os.path.basename(input_path)})", bold=True, font_size=12)],
                ),
            )
        ]

        ocr_text = MediaConverterEngine.extract_ocr_text_from_image(input_path)
        for line in ocr_text.splitlines():
            elements.append(
                UDFElement(
                    kind="paragraph",
                    paragraph=UDFParagraph(alignment=0, runs=[UDFRun(text=line, font_size=11)]),
                )
            )

        with Image.open(input_path) as im:
            for page in ImageSequence.Iterator(im):
                rgb = page.convert("RGB")
                rgb.thumbnail((900, 1200))
                buf = io.BytesIO()
                rgb.save(buf, format="PNG")
                w, h = rgb.size
                disp_w = min(450.0, float(w))
                disp_h = disp_w * (float(h) / max(1.0, float(w)))
                elements.append(
                    UDFElement(
                        kind="paragraph",
                        paragraph=UDFParagraph(
                            alignment=1,
                            runs=[UDFRun(text=" ")],
                            images=[UDFImageItem(image_bytes=buf.getvalue(), width=disp_w, height=disp_h)],
                        ),
                    )
                )

        return UDFEngine.write_udf(elements, output_path)

    @staticmethod
    def image_or_tiff_to_docx(input_path: str, output_path: str) -> str:
        """Converts single/multi-page TIFF or image into a Word (.docx) document."""
        udf_tmp = tempfile.NamedTemporaryFile(suffix=".udf", delete=False)
        udf_tmp.close()
        try:
            MediaConverterEngine.image_or_tiff_to_udf(input_path, udf_tmp.name)
            doc = UDFEngine.read_udf(udf_tmp.name)
            return UDFEngine.export_to_docx(doc, output_path)
        finally:
            if os.path.exists(udf_tmp.name):
                os.remove(udf_tmp.name)

    @staticmethod
    def docx_to_udf(input_path: str, output_path: str) -> str:
        """Converts a Word (.docx) document to a UYAP-compatible .udf file."""
        elements: List[UDFElement] = []

        try:
            import docx

            wdoc = docx.Document(input_path)
            for p in wdoc.paragraphs:
                align = 0
                if p.alignment is not None:
                    al_val = int(p.alignment)
                    if al_val in (0, 1, 2, 3):
                        align = al_val
                runs: List[UDFRun] = []
                for wr in p.runs:
                    if wr.text:
                        sz = 12.0
                        if wr.font and wr.font.size:
                            try:
                                sz = float(wr.font.size.pt)
                            except Exception:
                                sz = 12.0
                        runs.append(
                            UDFRun(
                                text=wr.text,
                                bold=bool(wr.bold),
                                italic=bool(wr.italic),
                                underline=bool(wr.underline),
                                font_family=(wr.font.name if wr.font and wr.font.name else "Times New Roman"),
                                font_size=sz,
                            )
                        )
                if not runs and p.text:
                    runs.append(UDFRun(text=p.text))
                elements.append(UDFElement(kind="paragraph", paragraph=UDFParagraph(alignment=align, runs=runs)))

            for wt in wdoc.tables:
                t_rows: List[UDFTableRow] = []
                for r in wt.rows:
                    t_cells: List[UDFTableCell] = []
                    for c in r.cells:
                        t_cells.append(
                            UDFTableCell(
                                paragraphs=[UDFParagraph(alignment=0, runs=[UDFRun(text=c.text.strip())])]
                            )
                        )
                    t_rows.append(UDFTableRow(cells=t_cells))
                elements.append(UDFElement(kind="table", table=UDFTable(rows=t_rows)))

        except ImportError:
            # Built-in XML fallback for reading word/document.xml
            with zipfile.ZipFile(input_path, "r") as zf:
                xml_bytes = zf.read("word/document.xml")
            root = ET.fromstring(xml_bytes)
            ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
            for p_node in root.findall(".//w:body/w:p", ns):
                texts = [t.text for t in p_node.findall(".//w:t", ns) if t.text]
                elements.append(
                    UDFElement(
                        kind="paragraph",
                        paragraph=UDFParagraph(alignment=0, runs=[UDFRun(text="".join(texts))]),
                    )
                )

        return UDFEngine.write_udf(elements, output_path)

    @staticmethod
    def pdf_to_udf(input_path: str, output_path: str) -> str:
        """Extracts text from all pages of a PDF and builds a UYAP-compatible .udf file."""
        elements: List[UDFElement] = []
        extracted_any = False

        try:
            from pypdf import PdfReader

            reader = PdfReader(input_path)
            for idx, page in enumerate(reader.pages, start=1):
                txt = page.extract_text() or ""
                if idx > 1:
                    elements.append(
                        UDFElement(
                            kind="paragraph",
                            paragraph=UDFParagraph(alignment=1, runs=[UDFRun(text=f"--- Sayfa {idx} ---", italic=True, font_size=10)]),
                        )
                    )
                for line in txt.splitlines():
                    extracted_any = True
                    elements.append(
                        UDFElement(
                            kind="paragraph",
                            paragraph=UDFParagraph(alignment=0, runs=[UDFRun(text=line)]),
                        )
                    )
        except Exception:
            pass

        if not extracted_any:
            # Fallback raw stream text extraction
            with open(input_path, "rb") as f:
                raw = f.read().decode("latin1", errors="ignore")
            matches = re.findall(r"\(([^\(\)]{2,200})\)\s*Tj", raw)
            for m in matches:
                elements.append(
                    UDFElement(
                        kind="paragraph",
                        paragraph=UDFParagraph(alignment=0, runs=[UDFRun(text=m)]),
                    )
                )

        if not elements:
            elements.append(
                UDFElement(
                    kind="paragraph",
                    paragraph=UDFParagraph(
                        alignment=0,
                        runs=[UDFRun(text=f"PDF Belgesi: {os.path.basename(input_path)}")],
                    ),
                )
            )

        return UDFEngine.write_udf(elements, output_path)

    # ========================================================================
    # UYAP SPECIAL TOOLS: COMPRESS (<5MB), MERGE PDF, SPLIT PAGES
    # ========================================================================

    @staticmethod
    def compress_for_uyap(input_path: str, output_path: Optional[str] = None) -> Tuple[str, int, int]:
        """Compresses a PDF or TIFF/Image file for UYAP (< 5 MB limit). Returns (out_path, old_size, new_size)."""
        ext = os.path.splitext(input_path)[1].lower()
        base_no_ext = os.path.splitext(input_path)[0]
        if output_path is None:
            output_path = f"{base_no_ext}_sikistirilmis{ext if ext in ('.pdf', '.tiff', '.tif') else '.pdf'}"

        old_size = os.path.getsize(input_path)

        if ext in (".tiff", ".tif", ".png", ".jpg", ".jpeg", ".bmp"):
            from PIL import Image, ImageSequence

            frames: List[Image.Image] = []
            with Image.open(input_path) as im:
                for page in ImageSequence.Iterator(im):
                    rgb = page.convert("RGB")
                    rgb.thumbnail((1240, 1754))
                    # Compress via JPEG buffer
                    buf = io.BytesIO()
                    rgb.save(buf, format="JPEG", quality=68, optimize=True)
                    buf.seek(0)
                    frames.append(Image.open(buf).convert("RGB").copy())

            if output_path.lower().endswith(".pdf"):
                frames[0].save(output_path, format="PDF", resolution=120.0, save_all=True, append_images=frames[1:])
            else:
                frames[0].save(output_path, format="TIFF", save_all=True, append_images=frames[1:], compression="jpeg")

        elif ext == ".pdf":
            try:
                from pypdf import PdfReader, PdfWriter

                reader = PdfReader(input_path)
                writer = PdfWriter()
                for page in reader.pages:
                    writer.add_page(page)
                for page in writer.pages:
                    try:
                        page.compress_content_streams()
                    except Exception:
                        pass
                with open(output_path, "wb") as f:
                    writer.write(f)
            except Exception:
                shutil.copy2(input_path, output_path)
        else:
            shutil.copy2(input_path, output_path)

        new_size = os.path.getsize(output_path)
        return output_path, old_size, new_size

    @staticmethod
    def merge_documents_to_pdf(input_paths: List[str], output_path: str) -> Tuple[str, int]:
        """
        Merges any combination of .udf, .tiff, .pdf, .docx, .png, .jpg files into a single PDF!
        Returns (output_path, total_pages).
        """
        from pypdf import PdfReader, PdfWriter

        writer = PdfWriter()
        temp_files: List[str] = []

        try:
            for p in input_paths:
                ext = os.path.splitext(p)[1].lower()
                pdf_part = p
                if ext == ".udf":
                    doc = UDFEngine.read_udf(p)
                    tmp = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
                    tmp.close()
                    UDFEngine.export_to_pdf(doc, tmp.name)
                    pdf_part = tmp.name
                    temp_files.append(tmp.name)
                elif ext in (".tiff", ".tif", ".png", ".jpg", ".jpeg", ".bmp", ".webp"):
                    tmp = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
                    tmp.close()
                    MediaConverterEngine.image_or_tiff_to_pdf(p, tmp.name)
                    pdf_part = tmp.name
                    temp_files.append(tmp.name)
                elif ext == ".docx":
                    tmp_udf = tempfile.NamedTemporaryFile(suffix=".udf", delete=False)
                    tmp_udf.close()
                    temp_files.append(tmp_udf.name)
                    MediaConverterEngine.docx_to_udf(p, tmp_udf.name)
                    doc = UDFEngine.read_udf(tmp_udf.name)
                    tmp_pdf = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
                    tmp_pdf.close()
                    temp_files.append(tmp_pdf.name)
                    UDFEngine.export_to_pdf(doc, tmp_pdf.name)
                    pdf_part = tmp_pdf.name

                if os.path.exists(pdf_part):
                    reader = PdfReader(pdf_part)
                    for page in reader.pages:
                        writer.add_page(page)

            total_pages = len(writer.pages)
            with open(output_path, "wb") as f:
                writer.write(f)
            return output_path, total_pages
        finally:
            for tf in temp_files:
                if os.path.exists(tf):
                    try:
                        os.remove(tf)
                    except Exception:
                        pass

    @staticmethod
    def split_document_pages(input_path: str, output_dir: Optional[str] = None) -> Tuple[str, int]:
        """Splits a multi-page TIFF or PDF into individual page files inside output_dir."""
        ext = os.path.splitext(input_path)[1].lower()
        base_name = os.path.splitext(os.path.basename(input_path))[0]
        if output_dir is None:
            output_dir = os.path.join(os.path.dirname(input_path), f"{base_name}_Sayfalar")
        os.makedirs(output_dir, exist_ok=True)

        count = 0
        if ext in (".tiff", ".tif"):
            from PIL import Image, ImageSequence

            with Image.open(input_path) as im:
                for idx, page in enumerate(ImageSequence.Iterator(im), start=1):
                    out_file = os.path.join(output_dir, f"{base_name}_Sayfa_{idx:02d}.png")
                    page.convert("RGB").save(out_file, format="PNG")
                    count += 1
        elif ext == ".pdf":
            from pypdf import PdfReader, PdfWriter

            reader = PdfReader(input_path)
            for idx, page in enumerate(reader.pages, start=1):
                w = PdfWriter()
                w.add_page(page)
                out_file = os.path.join(output_dir, f"{base_name}_Sayfa_{idx:02d}.pdf")
                with open(out_file, "wb") as f:
                    w.write(f)
                count += 1
        else:
            raise ValueError("Sayfa ayırma işlemi çok sayfalı .tiff veya .pdf dosyalarını destekler.")

        return output_dir, count


# ============================================================================
# DEMO FILES GENERATOR & AUTOMATED SELF-TEST
# ============================================================================

class DemoFilesGenerator:

    @staticmethod
    def create_demo_files(target_dir: str) -> List[str]:
        os.makedirs(target_dir, exist_ok=True)
        created: List[str] = []

        # 1. Ornek_Dava_Dilekcesi.udf
        udf_path = os.path.join(target_dir, "Ornek_Dava_Dilekcesi.udf")
        elements = [
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=1,
                    runs=[UDFRun(text="T.C.\nANKARA NÖBETÇİ ASLİYE HUKUK MAHKEMESİ'NE", bold=True, font_size=13)],
                ),
            ),
            UDFElement(kind="paragraph", paragraph=UDFParagraph(alignment=0, runs=[])),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=0,
                    runs=[
                        UDFRun(text="DAVACI : ", bold=True),
                        UDFRun(text="Mandalina Yazılım ve Hukuk Teknolojileri A.Ş. (Vergi No: 1234567890)"),
                    ],
                ),
            ),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=0,
                    runs=[
                        UDFRun(text="VEKİLİ : ", bold=True),
                        UDFRun(text="Av. Serkan Sayoğlu — Atatürk Bulvarı No: 100 Çankaya / ANKARA"),
                    ],
                ),
            ),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=0,
                    runs=[
                        UDFRun(text="DAVALI : ", bold=True),
                        UDFRun(text="Örnek Lojistik ve Ticaret Ltd. Şti."),
                    ],
                ),
            ),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=0,
                    runs=[
                        UDFRun(text="KONU : ", bold=True),
                        UDFRun(text="Fazlaya ilişkin haklarımız saklı kalmak kaydıyla 125.000,00 TL alacağın tahsili talebidir."),
                    ],
                ),
            ),
            UDFElement(kind="paragraph", paragraph=UDFParagraph(alignment=0, runs=[])),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(alignment=1, runs=[UDFRun(text="AÇIKLAMALAR", bold=True, underline=True)]),
            ),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=3,
                    first_line_indent=24,
                    runs=[
                        UDFRun(
                            text="1. Müvekkil şirket ile davalı arasında 15.01.2026 tarihli Hizmet ve Yazılım Teslim Sözleşmesi akdedilmiştir. Müvekkil edimlerini eksiksiz yerine getirmesine rağmen aşağıda dökümü sunulan fatura bedelleri ödenmemiştir."
                        )
                    ],
                ),
            ),
            UDFElement(
                kind="table",
                table=UDFTable(
                    rows=[
                        UDFTableRow(
                            cells=[
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="Fatura No", bold=True)])]),
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="Tarih", bold=True)])]),
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="Tutar (TL)", bold=True)])]),
                            ]
                        ),
                        UDFTableRow(
                            cells=[
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="MND-2026-001")])]),
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="01.02.2026")])]),
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="75.000,00 TL")])]),
                            ]
                        ),
                        UDFTableRow(
                            cells=[
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="MND-2026-002")])]),
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="01.03.2026")])]),
                                UDFTableCell(paragraphs=[UDFParagraph(runs=[UDFRun(text="50.000,00 TL")])]),
                            ]
                        ),
                    ]
                ),
            ),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=3,
                    first_line_indent=24,
                    runs=[
                        UDFRun(text="SONUÇ VE İSTEM : ", bold=True),
                        UDFRun(
                            text="Yukarıda arz ve izah edilen nedenlerle fazlaya ilişkin talep ve dava haklarımız saklı kalmak kaydıyla 125.000,00 TL alacağın ticari temerrüt faiziyle birlikte davalıdan tahsiline karar verilmesini vekaleten arz ve talep ederiz."
                        ),
                    ],
                ),
            ),
            UDFElement(
                kind="paragraph",
                paragraph=UDFParagraph(
                    alignment=2,
                    runs=[UDFRun(text="Davacı Vekili\nAv. Serkan Sayoğlu\n(e-imzalıdır)", bold=True)],
                ),
            ),
        ]
        UDFEngine.write_udf(elements, udf_path)
        created.append(udf_path)

        # 2. Tebligat_3_Sayfa.tiff (3-page multi-page TIFF)
        tiff_path = os.path.join(target_dir, "Tebligat_3_Sayfa.tiff")
        from PIL import Image, ImageDraw

        tiff_frames: List[Image.Image] = []
        fnt_title = UDFEngine._load_pil_font(28, bold=True)
        fnt_body = UDFEngine._load_pil_font(20, bold=False)
        for pno in range(1, 4):
            im = Image.new("RGB", (1000, 1400), color=(255, 253, 248))
            dr = ImageDraw.Draw(im)
            dr.rectangle([40, 40, 960, 1360], outline=(230, 110, 20), width=4)
            dr.text((80, 90), f"T.C. PTT / UYAP E-TEBLİGAT MAZBATASI — SAYFA {pno} / 3", fill=(20, 20, 20), font=fnt_title)
            dr.text(
                (80, 170),
                f"Barkod No: 2026-998877-0{pno}\nMuhatap: Örnek Lojistik ve Ticaret Ltd. Şti.\nTebliğ Tarihi: 19.10.2026\n\nBu çok sayfalı TIFF belgesi Mandalina Windows & macOS\ndönüştürücü testi için otomatik oluşturulmuştur.",
                fill=(40, 40, 40),
                font=fnt_body,
            )
            tiff_frames.append(im)
        tiff_frames[0].save(tiff_path, format="TIFF", save_all=True, append_images=tiff_frames[1:], compression="tiff_deflate")
        created.append(tiff_path)

        # 3. Sozlesme_Taslagi.docx
        docx_path = os.path.join(target_dir, "Sozlesme_Taslagi.docx")
        doc_obj = UDFEngine.read_udf(udf_path)
        UDFEngine.export_to_docx(doc_obj, docx_path)
        created.append(docx_path)

        # 4. Bilirkisi_Raporu.pdf
        pdf_path = os.path.join(target_dir, "Bilirkisi_Raporu.pdf")
        UDFEngine.export_to_pdf(doc_obj, pdf_path)
        created.append(pdf_path)

        return created


def run_self_test() -> int:
    print("🍊 Mandalina (Windows/Cross-Platform) — Otomatik Dönüşüm Testi Başlatılıyor...")
    with tempfile.TemporaryDirectory() as tmpdir:
        demo_files = DemoFilesGenerator.create_demo_files(tmpdir)
        for df in demo_files:
            print(f"  • Örnek dosya hazır: {os.path.basename(df)}")

        udf_file, tiff_file, docx_file, pdf_file = demo_files
        doc = UDFEngine.read_udf(udf_file)

        # 1. UDF -> PDF
        out_pdf = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi.pdf")
        UDFEngine.export_to_pdf(doc, out_pdf)
        assert os.path.exists(out_pdf) and os.path.getsize(out_pdf) > 500
        print("  ✅ [UDF] UDF → PDF: Ornek_Dava_Dilekcesi.pdf")

        # 2. UDF -> DOCX
        out_docx = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi.docx")
        UDFEngine.export_to_docx(doc, out_docx)
        assert os.path.exists(out_docx) and os.path.getsize(out_docx) > 500
        print(f"  ✅ [UDF] UDF → Word (.docx): Ornek_Dava_Dilekcesi.docx ({doc.paragraph_count} paragraf, {doc.table_count} tablo)")

        # 3. UDF -> HTML
        out_html = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi.html")
        UDFEngine.export_to_html(doc, out_html)
        assert os.path.exists(out_html) and os.path.getsize(out_html) > 500
        print("  ✅ [UDF] UDF → HTML: Ornek_Dava_Dilekcesi.html")

        # 4. UDF -> Markdown
        out_md = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi.md")
        UDFEngine.export_to_markdown(doc, out_md)
        assert os.path.exists(out_md) and os.path.getsize(out_md) > 100
        print("  ✅ [UDF] UDF → Markdown: Ornek_Dava_Dilekcesi.md")

        # 5. UDF -> TXT
        out_txt = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi.txt")
        UDFEngine.export_to_txt(doc, out_txt)
        assert os.path.exists(out_txt) and os.path.getsize(out_txt) > 100
        print(f"  ✅ [UDF] UDF → TXT: Ornek_Dava_Dilekcesi.txt ({doc.char_count} karakter)")

        # 6. UDF -> RTF
        out_rtf = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi.rtf")
        UDFEngine.export_to_rtf(doc, out_rtf)
        assert os.path.exists(out_rtf) and os.path.getsize(out_rtf) > 100
        print("  ✅ [UDF] UDF → RTF: Ornek_Dava_Dilekcesi.rtf")

        # 7. TIFF -> PDF
        out_tiff_pdf = os.path.join(tmpdir, "Tebligat_3_Sayfa.pdf")
        _, pages = MediaConverterEngine.image_or_tiff_to_pdf(tiff_file, out_tiff_pdf)
        assert os.path.exists(out_tiff_pdf) and pages == 3
        print(f"  ✅ [TIFF -> PDF] Tebligat_3_Sayfa.pdf ({pages} sayfa PDF'e çevrildi)")

        # 8. TIFF -> UDF (OCR)
        out_tiff_udf = os.path.join(tmpdir, "Tebligat_3_Sayfa.udf")
        MediaConverterEngine.image_or_tiff_to_udf(tiff_file, out_tiff_udf)
        assert os.path.exists(out_tiff_udf)
        print("  ✅ [TIFF -> UDF (OCR)] Tebligat_3_Sayfa.udf (UYAP uyumlu .udf oluşturuldu)")

        # 9. DOCX -> UDF
        out_docx_udf = os.path.join(tmpdir, "Sozlesme_Taslagi.udf")
        MediaConverterEngine.docx_to_udf(docx_file, out_docx_udf)
        verify_doc = UDFEngine.read_udf(out_docx_udf)
        assert len(verify_doc.plain_text) > 100
        print("  ✅ [DOCX -> UDF] Sozlesme_Taslagi.udf (UYAP uyumlu .udf oluşturuldu)")

        # 10. PDF -> UDF
        out_pdf_udf = os.path.join(tmpdir, "Bilirkisi_Raporu.udf")
        MediaConverterEngine.pdf_to_udf(pdf_file, out_pdf_udf)
        assert os.path.exists(out_pdf_udf)
        print("  ✅ [PDF -> UDF] Bilirkisi_Raporu.udf (UYAP uyumlu .udf oluşturuldu)")

        # 11. UYAP Compress
        comp_path, old_sz, new_sz = MediaConverterEngine.compress_for_uyap(pdf_file)
        assert os.path.exists(comp_path)
        print(f"  ✅ [UYAP Sıkıştır] {os.path.basename(comp_path)} ({old_sz // 1024} KB → {new_sz // 1024} KB)")

        # 12. Merge UDF + 3-Page TIFF into single PDF
        merged_pdf = os.path.join(tmpdir, "Ornek_Dava_Dilekcesi_Birlesik.pdf")
        _, total_p = MediaConverterEngine.merge_documents_to_pdf([udf_file, tiff_file], merged_pdf)
        assert os.path.exists(merged_pdf) and total_p >= 4
        print(f"  ✅ [PDF Birleştir (UDF + 3 Sayfa TIFF)] {os.path.basename(merged_pdf)} ({total_p} sayfa birleştirildi)")

    print("🎉 Tüm dönüşüm ve araç testleri başarıyla tamamlandı!")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(run_self_test())
