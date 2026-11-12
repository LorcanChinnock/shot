/**
 * The geometry of a drawn arrow, as Shot's arrow tool makes one: a curved shaft and a solid head whose tip is exactly at
 * `to` and which points along the shaft's last stretch. The shaft is a quadratic curve from `from` to `to`, bowed sideways
 * by `bend` times its length, and it stops inside the head so its round cap never pokes past the tip.
 *
 * Everything is in the arrow's own pixels. The SVG is sized to fit the arrow, and its viewBox keeps these coordinates,
 * so a caller can place the tip by placing the SVG.
 */
export type Point = readonly [number, number];

export interface ArrowOptions {
  from: Point;
  to: Point;
  /** How far the middle bows out, as a fraction of the arrow's length. Positive bows to the left of the direction of travel (clockwise on screen), negative to the right, 0 is straight. */
  bend?: number;
  /** The head's length along the shaft. */
  head?: number;
  /** The shaft's stroke width; the head is about three of these wide. */
  stroke?: number;
}

export interface ArrowGeometry {
  shaft: string;
  head: string;
  /** The shaft's length, for the draw animation's dash. */
  length: number;
  viewBox: string;
  width: number;
  height: number;
}

const round = (n: number) => Math.round(n * 10) / 10;

function quad(p0: Point, c: Point, p2: Point, t: number): Point {
  const u = 1 - t;
  return [u * u * p0[0] + 2 * u * t * c[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * c[1] + t * t * p2[1]];
}

export function arrowGeometry({ from, to, bend = 0.2, head = 16, stroke = 4.5 }: ArrowOptions): ArrowGeometry {
  const [dx, dy] = [to[0] - from[0], to[1] - from[1]];
  const length = Math.hypot(dx, dy);
  if (length === 0) throw new Error('An arrow needs two different points.');

  // The control point sits off the middle, along the normal. On screen (y down), (dy, -dx) is to the left of travel.
  const control: Point = [(from[0] + to[0]) / 2 + (dy / length) * bend * length, (from[1] + to[1]) / 2 - (dx / length) * bend * length];

  // Find where the shaft should stop: the point on the curve about 0.6 of a head length back from the tip, by bisection.
  const stopAt = head * 0.6;
  let lo = 0, hi = 1;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    const p = quad(from, control, to, mid);
    if (Math.hypot(to[0] - p[0], to[1] - p[1]) > stopAt) lo = mid; else hi = mid;
  }
  const t = lo;

  // Split the curve at t (de Casteljau), so the shaft is exactly the first part of the same curve.
  const c1: Point = [from[0] + (control[0] - from[0]) * t, from[1] + (control[1] - from[1]) * t];
  const end = quad(from, control, to, t);

  // The head points from the shaft's end to the tip, so its base always meets the shaft square on.
  const [ux, uy] = [(to[0] - end[0]) / Math.hypot(to[0] - end[0], to[1] - end[1]), (to[1] - end[1]) / Math.hypot(to[0] - end[0], to[1] - end[1])];
  const half = Math.max(head * 0.5, stroke * 1.6);
  const base: Point = [to[0] - ux * head, to[1] - uy * head];
  const corners: Point[] = [to, [base[0] - uy * half, base[1] + ux * half], [base[0] + uy * half, base[1] - ux * half]];

  // The shaft's length, from samples, so the dash covers it exactly.
  let drawn = 0;
  let prev = from;
  for (let i = 1; i <= 32; i++) {
    const p = quad(from, c1, end, i / 32);
    drawn += Math.hypot(p[0] - prev[0], p[1] - prev[1]);
    prev = p;
  }

  // Fit the box to the curve and the head, with room for the stroke's round caps.
  const pts: Point[] = [...corners];
  for (let i = 0; i <= 16; i++) pts.push(quad(from, c1, end, i / 16));
  const pad = stroke;
  const minX = Math.floor(Math.min(...pts.map((p) => p[0])) - pad);
  const minY = Math.floor(Math.min(...pts.map((p) => p[1])) - pad);
  const maxX = Math.ceil(Math.max(...pts.map((p) => p[0])) + pad);
  const maxY = Math.ceil(Math.max(...pts.map((p) => p[1])) + pad);

  const f = (p: Point) => `${round(p[0])} ${round(p[1])}`;
  return {
    shaft: `M${f(from)} Q${f(c1)} ${f(end)}`,
    head: `M${f(corners[0])} L${f(corners[1])} L${f(corners[2])} Z`,
    length: Math.ceil(drawn),
    viewBox: `${minX} ${minY} ${maxX - minX} ${maxY - minY}`,
    width: maxX - minX,
    height: maxY - minY,
  };
}
