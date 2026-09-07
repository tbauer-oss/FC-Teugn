import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';

/** Paginated printable report; unsupported glyphs become visible placeholders. */
export async function talentsReport(title: string, text: string) {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const clean = (s: string) => [...s.replace(/\t/g, '  ')].map(c => { try { font.encodeText(c); return c; } catch { return '?'; } }).join('');
  let page = pdf.addPage([595.28, 841.89]);
  let y = 760;
  const header = () => {
    page.drawText('FC TEUGN TALENTS', { x: 42, y: 803, font: bold, size: 11, color: rgb(.28, .35, .10) });
    const heading = clean(title);
    const headingSize = Math.min(15, 505 / Math.max(1, bold.widthOfTextAtSize(heading, 1)));
    page.drawText(heading, { x: 42, y: 780, font: bold, size: headingSize });
    page.drawText('Vereinsinterne Arbeitsunterlage', { x: 42, y: 25, font, size: 9, color: rgb(.35, .35, .35) });
    page.drawText(`Seite ${pdf.getPageCount()}`, { x: 500, y: 25, font, size: 9 });
  };
  header();
  const line = (value: string) => {
    if (y < 48) { page = pdf.addPage([595.28, 841.89]); y = 750; header(); }
    page.drawText(value, { x: 42, y, font, size: 10 }); y -= 15;
  };
  for (const paragraph of text.split(/\r?\n/)) {
    let current = '';
    for (const word of clean(paragraph).split(/\s+/)) {
      if (current && font.widthOfTextAtSize(`${current} ${word}`, 10) > 505) { line(current); current = ''; }
      if (current) current += ' ';
      for (const character of word) {
        if (font.widthOfTextAtSize(current + character, 10) > 505) { line(current); current = ''; }
        current += character;
      }
    }
    line(current);
  }
  return Buffer.from(await pdf.save());
}
