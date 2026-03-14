from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer


def build_pdf(md_path: Path, pdf_path: Path) -> None:
    styles = getSampleStyleSheet()
    body = ParagraphStyle(
        "BodyGuide",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=9.5,
        leading=12,
        spaceAfter=4,
    )
    h1 = ParagraphStyle(
        "H1Guide",
        parent=styles["Heading1"],
        fontName="Helvetica-Bold",
        fontSize=16,
        leading=20,
        spaceAfter=8,
    )
    h2 = ParagraphStyle(
        "H2Guide",
        parent=styles["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=12,
        leading=15,
        spaceBefore=6,
        spaceAfter=5,
    )
    code = ParagraphStyle(
        "CodeGuide",
        parent=body,
        fontName="Courier",
        fontSize=8.8,
        leading=11,
        leftIndent=12,
    )

    story = []
    for raw_line in md_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if not line:
            story.append(Spacer(1, 2.5))
            continue

        if line.startswith("# "):
            story.append(Paragraph(escape(line[2:]), h1))
            continue
        if line.startswith("## "):
            story.append(Paragraph(escape(line[3:]), h2))
            continue
        if line.startswith("---"):
            story.append(Spacer(1, 4))
            continue

        # Render inline code by replacing markdown backticks with simple courier spans.
        # This keeps dependencies low while preserving readability.
        escaped = escape(line)
        while "`" in escaped:
            left = escaped.find("`")
            right = escaped.find("`", left + 1)
            if right == -1:
                break
            token = escaped[left + 1 : right]
            repl = f'<font name="Courier">{token}</font>'
            escaped = escaped[:left] + repl + escaped[right + 1 :]

        if line.startswith("- "):
            text = escaped[2:]
            story.append(Paragraph(f"&bull; {text}", body))
        else:
            # Short code-like lines are easier to read in monospaced style.
            if len(line) <= 80 and (":" in line or "=" in line) and not line.endswith("."):
                story.append(Paragraph(escaped, code))
            else:
                story.append(Paragraph(escaped, body))

    doc = SimpleDocTemplate(
        str(pdf_path),
        pagesize=A4,
        rightMargin=14 * mm,
        leftMargin=14 * mm,
        topMargin=12 * mm,
        bottomMargin=12 * mm,
        title="GS Quant Architect Variable Guide",
        author="GS Quant Architect Assistant",
    )
    doc.build(story)


if __name__ == "__main__":
    md = Path("/workspace/GSQ4_EA_Variable_Guide.md")
    pdf = Path("/workspace/GSQ4_EA_Variable_Guide.pdf")
    build_pdf(md, pdf)
    print(f"Generated: {pdf}")
