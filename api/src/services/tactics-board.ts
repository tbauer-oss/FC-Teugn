import { Prisma } from '@prisma/client';

const bad = () => { throw new Error('Ungültiges Taktikboard oder zu viele Zeichenelemente.'); };
const object = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : bad();
const label = (value: unknown, max: number) =>
  typeof value === 'string' && value.trim().length > 0 && value.length <= max ? value.trim() : bad();
const coordinate = (value: unknown) =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1 ? value : bad();
const choice = (value: unknown, options: string[]) =>
  typeof value === 'string' && options.includes(value) ? value : bad();
function array(value: unknown, max: number): unknown[] {
  return Array.isArray(value) && value.length <= max ? value : bad();
}
function unique(items: Array<{ id: string }>) {
  if (new Set(items.map(item => item.id)).size !== items.length) bad();
  return items;
}

/** Strict, bounded JSON, never HTML/SVG or executable drawing instructions. */
export function validateTacticsDocument(input: unknown): Prisma.InputJsonObject {
  if (Buffer.byteLength(JSON.stringify(input) ?? '', 'utf8') > 350_000) bad();
  const doc = object(input);
  if (doc.schemaVersion !== 1) bad();
  let pointCount = 0;
  const scenes = unique(array(doc.scenes, 8).map(raw => {
    const scene = object(raw);
    const tokens = unique(array(scene.tokens, 40).map(rawToken => {
      const token = object(rawToken);
      return { id: label(token.id, 80), kind: choice(token.kind, ['own', 'opponent', 'ball', 'text']),
        label: label(token.label, 50), x: coordinate(token.x), y: coordinate(token.y),
        ...(token.playerId == null ? {} : { playerId: label(token.playerId, 100) }) };
    }));
    const strokes = unique(array(scene.strokes, 80).map(rawStroke => {
      const stroke = object(rawStroke);
      const points = array(stroke.points, 160).map(rawPoint => {
        const point = object(rawPoint);
        return { x: coordinate(point.x), y: coordinate(point.y) };
      });
      pointCount += points.length;
      if (points.length < 2 || pointCount > 8000) bad();
      const kind = choice(stroke.kind, ['pen', 'arrow', 'run', 'zone']);
      if (kind !== 'pen' && points.length !== 2) bad();
      return { id: label(stroke.id, 80), kind,
        color: choice(stroke.color, ['yellow', 'cyan', 'white', 'red']), points };
    }));
    return { id: label(scene.id, 80), name: label(scene.name, 80), tokens, strokes };
  }));
  if (!scenes.length) bad();
  return { schemaVersion: 1, scenes };
}
