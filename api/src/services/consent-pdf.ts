import {
  LineCapStyle,
  PDFDocument,
  PDFPage,
  PDFFont,
  StandardFonts,
  rgb,
} from 'pdf-lib';
import { ConsentTemplateDefinition } from './consent-templates';

type SignaturePoint = { x: number; y: number };
type SignatureStroke = SignaturePoint[];

type SignatureData = {
  width: number;
  height: number;
  strokes: SignatureStroke[];
};

export type ConsentPdfData = {
  template: ConsentTemplateDefinition;
  playerName?: string;
  playerBirthDate?: Date | null;
  signerName?: string;
  selections?: string[];
  note?: string | null;
  signedAt?: Date;
  childAssentName?: string | null;
  documentHash?: string;
  signature?: SignatureData | null;
  revokedAt?: Date | null;
};

const PAGE = { width: 595.28, height: 841.89, margin: 48 };
const BLACK = rgb(0.08, 0.09, 0.08);
const GOLD = rgb(0.52, 0.45, 0);
const MUTED = rgb(0.36, 0.36, 0.33);
const LINE = rgb(0.83, 0.82, 0.76);

const SIGNATURE_BOX = { width: 200, height: 55, padding: 4 };

export function signatureLayout(signature: SignatureData) {
  const points = signature.strokes.flat();
  const minX = Math.min(...points.map((point) => point.x));
  const maxX = Math.max(...points.map((point) => point.x));
  const minY = Math.min(...points.map((point) => point.y));
  const maxY = Math.max(...points.map((point) => point.y));
  const contentWidth = Math.max(maxX - minX, 1);
  const contentHeight = Math.max(maxY - minY, 1);
  const availableWidth = SIGNATURE_BOX.width - SIGNATURE_BOX.padding * 2;
  const availableHeight = SIGNATURE_BOX.height - SIGNATURE_BOX.padding * 2;
  const scale = Math.min(
    availableWidth / contentWidth,
    availableHeight / contentHeight,
  );
  const width = contentWidth * scale;
  const height = contentHeight * scale;
  return {
    minX,
    minY,
    scale,
    width,
    height,
    offsetX: (SIGNATURE_BOX.width - width) / 2,
    offsetY: (SIGNATURE_BOX.height - height) / 2,
  };
}

function svgNumber(value: number) {
  return Number(value.toFixed(3)).toString();
}

export function smoothSignaturePath(
  stroke: SignatureStroke,
  layout: ReturnType<typeof signatureLayout>,
) {
  const points = stroke.map((point) => ({
    x: (point.x - layout.minX) * layout.scale,
    y: (point.y - layout.minY) * layout.scale,
  }));
  if (points.length < 2) return '';

  const commands = [`M ${svgNumber(points[0].x)} ${svgNumber(points[0].y)}`];
  for (let index = 0; index < points.length - 1; index += 1) {
    const previous = points[Math.max(index - 1, 0)];
    const current = points[index];
    const next = points[index + 1];
    const following = points[Math.min(index + 2, points.length - 1)];
    const control1 = {
      x: current.x + (next.x - previous.x) / 6,
      y: current.y + (next.y - previous.y) / 6,
    };
    const control2 = {
      x: next.x - (following.x - current.x) / 6,
      y: next.y - (following.y - current.y) / 6,
    };
    commands.push(
      `C ${svgNumber(control1.x)} ${svgNumber(control1.y)} ` +
        `${svgNumber(control2.x)} ${svgNumber(control2.y)} ` +
        `${svgNumber(next.x)} ${svgNumber(next.y)}`,
    );
  }
  return commands.join(' ');
}

function wrap(text: string, font: PDFFont, size: number, width: number) {
  const words = text.replace(/\s+/g, ' ').trim().split(' ');
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, size) <= width) {
      line = candidate;
    } else {
      if (line) lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function date(value?: Date | null) {
  return value
    ? new Intl.DateTimeFormat('de-DE', {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: 'Europe/Berlin',
      }).format(value)
    : '____________________________';
}

export async function buildConsentPdf(data: ConsentPdfData) {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  let page = pdf.addPage([PAGE.width, PAGE.height]);
  let y = PAGE.height - PAGE.margin;
  const contentWidth = PAGE.width - PAGE.margin * 2;

  const nextPage = () => {
    page = pdf.addPage([PAGE.width, PAGE.height]);
    y = PAGE.height - PAGE.margin;
    footer();
  };
  const ensure = (height: number) => {
    if (y - height < 58) nextPage();
  };
  const text = (
    value: string,
    options: { size?: number; font?: PDFFont; color?: ReturnType<typeof rgb>; gap?: number } = {},
  ) => {
    const size = options.size ?? 10;
    const font = options.font ?? regular;
    const lines = wrap(value, font, size, contentWidth);
    ensure(lines.length * (size + 3) + (options.gap ?? 7));
    for (const line of lines) {
      page.drawText(line, {
        x: PAGE.margin,
        y,
        size,
        font,
        color: options.color ?? BLACK,
      });
      y -= size + 3;
    }
    y -= options.gap ?? 7;
  };
  const heading = (value: string) => {
    ensure(34);
    y -= 4;
    text(value, { size: 13, font: bold, color: BLACK, gap: 8 });
  };
  const field = (label: string, value?: string) => {
    ensure(34);
    page.drawText(label, { x: PAGE.margin, y, size: 8, font: bold, color: MUTED });
    y -= 14;
    page.drawText(value?.trim() || '____________________________________________', {
      x: PAGE.margin,
      y,
      size: 10,
      font: regular,
      color: BLACK,
    });
    y -= 16;
  };
  const footer = () => {
    page.drawText(`FC Teugn e.V. · Einwilligungsvorlage ${data.template.version}`, {
      x: PAGE.margin,
      y: 28,
      size: 7,
      font: regular,
      color: MUTED,
    });
  };

  footer();
  page.drawRectangle({
    x: 0,
    y: PAGE.height - 14,
    width: PAGE.width,
    height: 14,
    color: rgb(1, 0.9, 0),
  });
  page.drawText('FC TEUGN · JUGENDFUSSBALL', {
    x: PAGE.margin,
    y,
    size: 10,
    font: bold,
    color: GOLD,
  });
  y -= 25;
  text(data.template.title, { size: 20, font: bold, gap: 5 });
  text(`Vorlagenversion ${data.template.version}`, {
    size: 8,
    color: MUTED,
    gap: 18,
  });

  field('Kind / Jugendliche Person', data.playerName);
  field(
    'Geburtsdatum',
    data.playerBirthDate
      ? new Intl.DateTimeFormat('de-DE').format(data.playerBirthDate)
      : undefined,
  );
  field('Sorgeberechtigte Person', data.signerName);

  heading('Worum geht es?');
  text(data.template.purpose);
  text(`Rechtsgrundlage: ${data.template.legalBasis}`, { color: MUTED });

  heading('Freiwillige Auswahl');
  const selected = new Set(data.selections ?? []);
  for (const option of data.template.options) {
    ensure(25);
    const checked = selected.has(option.id);
    page.drawRectangle({
      x: PAGE.margin,
      y: y - 2,
      width: 11,
      height: 11,
      borderWidth: 1,
      borderColor: BLACK,
    });
    if (checked) {
      page.drawText('X', {
        x: PAGE.margin + 2,
        y,
        size: 8,
        font: bold,
        color: GOLD,
      });
    }
    const lines = wrap(option.label, regular, 9.5, contentWidth - 22);
    for (const line of lines) {
      page.drawText(line, {
        x: PAGE.margin + 20,
        y,
        size: 9.5,
        font: regular,
        color: BLACK,
      });
      y -= 12;
    }
    y -= 4;
  }
  if (data.note) {
    heading('Ergänzung');
    text(data.note);
  }

  if (data.template.risks) {
    heading('Besonderer Hinweis');
    text(data.template.risks);
  }

  heading('Speicherung, Empfänger und Rechte');
  text(
    `${data.template.retention} Empfänger sind nur die jeweils ausgewählten Stellen und hierfür berechtigte Vereinsverantwortliche beziehungsweise eingesetzte Dienstleister. Es findet keine automatisierte Entscheidungsfindung statt.`,
  );
  text(
    'Die Einwilligung ist freiwillig. Aus einer Ablehnung entstehen keine Nachteile für die sportliche Teilnahme. Sie kann jederzeit mit Wirkung für die Zukunft in der App oder gegenüber dem FC Teugn e.V., Triftweg 1a, 93356 Teugn, E-Mail: fcteugn@web.de, widerrufen werden. Die Rechtmäßigkeit der bis zum Widerruf erfolgten Verarbeitung bleibt unberührt. Es bestehen insbesondere die Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung und Beschwerde bei einer Datenschutzaufsichtsbehörde.',
  );

  ensure(230);
  heading(data.template.explicit ? 'Ausdrückliche Einwilligung' : 'Einwilligung');
  text(
    `${data.template.explicit ? 'Ich willige ausdrücklich' : 'Ich willige'} für die oben ausgewählten Zwecke in die beschriebene Verarbeitung ein. Ich bestätige, sorgeberechtigt oder hierzu nachweislich bevollmächtigt zu sein. Die Datenschutzhinweise und mein Widerrufsrecht habe ich verstanden.`,
  );

  ensure(120);
  y -= SIGNATURE_BOX.height + 10;
  page.drawLine({
    start: { x: PAGE.margin, y },
    end: { x: PAGE.margin + 205, y },
    thickness: 0.8,
    color: LINE,
  });
  page.drawText(`Datum: ${date(data.signedAt)}`, {
    x: PAGE.margin,
    y: y - 14,
    size: 8,
    font: regular,
    color: MUTED,
  });

  const signatureX = PAGE.margin + 250;
  page.drawLine({
    start: { x: signatureX, y },
    end: { x: PAGE.width - PAGE.margin, y },
    thickness: 0.8,
    color: LINE,
  });
  if (data.signature && data.signature.strokes.length > 0) {
    const layout = signatureLayout(data.signature);
    const pathX = signatureX + layout.offsetX;
    const pathTop = y + 4 + layout.offsetY + layout.height;
    for (const stroke of data.signature.strokes) {
      const path = smoothSignaturePath(stroke, layout);
      if (!path) continue;
      page.drawSvgPath(path, {
        x: pathX,
        y: pathTop,
        borderColor: BLACK,
        borderWidth: 1.05,
        borderLineCap: LineCapStyle.Round,
      });
    }
  }
  page.drawText(`Unterschrift: ${data.signerName ?? ''}`, {
    x: signatureX,
    y: y - 14,
    size: 8,
    font: regular,
    color: MUTED,
  });
  y -= 45;
  if (data.childAssentName) {
    text(
      `Zusätzliche Zustimmung des Kindes / der jugendlichen Person: ${data.childAssentName}`,
      { size: 9 },
    );
  }
  if (data.revokedAt) {
    text(`WIDERRUFEN am ${date(data.revokedAt)}`, {
      size: 11,
      font: bold,
      color: rgb(0.72, 0.16, 0.12),
    });
  }
  if (data.documentHash) {
    text(`Nachweis-ID (SHA-256): ${data.documentHash}`, {
      size: 7,
      color: MUTED,
    });
  }
  text(
    'Hinweis: Diese vereinsbezogene Vorlage ersetzt keine individuelle Rechtsberatung. Der Verein muss Kontaktdaten, Datenschutzhinweise, Empfänger und eingesetzte Kommunikationsdienste aktuell halten.',
    { size: 7.5, color: MUTED },
  );

  pdf.setTitle(`${data.template.shortTitle} – FC Teugn`);
  pdf.setAuthor('FC Teugn e.V.');
  pdf.setSubject('Einwilligung Jugendfußball');
  pdf.setCreationDate(new Date());
  return pdf.save();
}
