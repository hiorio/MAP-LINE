import { strokeRenderAlpha, strokeRenderWidth } from '@/lib/geo/projection';
import type { Point } from '@/lib/geo/rdp';
import type { LatLng, MapLabel, Place, Stroke, TravelMode } from '@/lib/map/types';

/**
 * 오버레이 한 장에 연결선 → 획 → 핀 → 라벨 순으로 그린다.
 *
 * 설계안 §12.2는 PinLayer/SegmentLayer를 별도 컴포넌트로 두지만, 레이어마다 캔버스를
 * 나누면 팬·줌 동기화와 좌표 재투영을 그 수만큼 반복해야 한다. 캔버스는 하나로 두고
 * 그리는 함수만 분리하는 편이 비용과 코드 양 모두 유리하다.
 */
export interface Scene {
  places: readonly Place[];
  strokes: readonly Stroke[];
  labels: readonly MapLabel[];
}

export type Projector = (coord: LatLng) => Point;

export const PIN_RADIUS = 13;
const LABEL_PADDING_X = 6;
const LABEL_PADDING_Y = 3;
const LABEL_FONT = '-apple-system, BlinkMacSystemFont, "Malgun Gothic", sans-serif';

export function drawScene(
  ctx: CanvasRenderingContext2D,
  scene: Scene,
  project: Projector,
  level: number,
) {
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  drawSegments(ctx, scene.places, project);

  for (const stroke of scene.strokes) {
    const points = stroke.path.map(project);
    if (points.length < 2) continue;
    ctx.globalAlpha = strokeRenderAlpha(stroke.zoomCreated, level);
    ctx.strokeStyle = stroke.color;
    ctx.lineWidth = strokeRenderWidth(stroke.width, stroke.zoomCreated, level);
    tracePolyline(ctx, points);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;

  scene.places.forEach((place, index) => drawPin(ctx, place, index + 1, project(place.location)));
  for (const label of scene.labels) drawLabel(ctx, label, project(label.location));
}

/* ------------------------------------------------------------------ 연결선 */

/**
 * 이동수단별 선 스타일. 지금은 핀 사이를 직선으로 잇는다.
 * 실제 경로 좌표는 `/api/route`(T11 후반)가 붙은 뒤 이 함수의 입력으로 들어온다.
 */
const SEGMENT_STYLE: Record<TravelMode, { dash: number[]; width: number; color: string }> = {
  walk: { dash: [2, 7], width: 3, color: '#6B6B66' },
  car: { dash: [], width: 3, color: '#6B6B66' },
  transit: { dash: [12, 6], width: 4, color: '#2D6BE4' },
};

function drawSegments(ctx: CanvasRenderingContext2D, places: readonly Place[], project: Projector) {
  for (let i = 1; i < places.length; i++) {
    const from = places[i - 1]!;
    const to = places[i]!;
    const style = SEGMENT_STYLE[from.modeToNext];

    const a = project(from.location);
    const b = project(to.location);
    // 핀 원 안쪽에서 선이 시작·끝나면 지저분하다. 반지름만큼 물려 놓는다.
    const [start, end] = trimToPins(a, b);

    ctx.save();
    ctx.setLineDash(style.dash);
    ctx.strokeStyle = style.color;
    ctx.lineWidth = style.width;
    ctx.beginPath();
    ctx.moveTo(start.x, start.y);
    ctx.lineTo(end.x, end.y);
    ctx.stroke();
    ctx.restore();
  }
}

function trimToPins(a: Point, b: Point): [Point, Point] {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const length = Math.hypot(dx, dy);
  if (length <= PIN_RADIUS * 2) return [a, b];

  const ux = dx / length;
  const uy = dy / length;
  return [
    { x: a.x + ux * PIN_RADIUS, y: a.y + uy * PIN_RADIUS },
    { x: b.x - ux * PIN_RADIUS, y: b.y - uy * PIN_RADIUS },
  ];
}

/* ---------------------------------------------------------------------- 핀 */

export function drawPin(
  ctx: CanvasRenderingContext2D,
  place: Place,
  order: number,
  at: Point,
) {
  ctx.save();
  ctx.beginPath();
  ctx.arc(at.x, at.y, PIN_RADIUS, 0, Math.PI * 2);
  ctx.fillStyle = place.pinColor;
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = '#FFFFFF';
  ctx.stroke();

  ctx.fillStyle = '#FFFFFF';
  ctx.font = `600 13px ${LABEL_FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(String(order), at.x, at.y + 0.5);

  // 이름은 핀 아래에 흰 테두리를 두르고 얹는다. 지도 타일 위에서 대비를 확보한다.
  ctx.font = `600 12px ${LABEL_FONT}`;
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
  ctx.strokeText(place.name, at.x, at.y + PIN_RADIUS + 9);
  ctx.fillStyle = '#2C2C2A';
  ctx.fillText(place.name, at.x, at.y + PIN_RADIUS + 9);
  ctx.restore();
}

export function hitsPin(point: Point, at: Point): boolean {
  return Math.hypot(point.x - at.x, point.y - at.y) <= PIN_RADIUS + 4;
}

/* -------------------------------------------------------------------- 라벨 */

export function drawLabel(ctx: CanvasRenderingContext2D, label: MapLabel, at: Point) {
  ctx.save();
  ctx.font = `${label.fontSize}px ${LABEL_FONT}`;
  const width = ctx.measureText(label.text).width + LABEL_PADDING_X * 2;
  const height = label.fontSize + LABEL_PADDING_Y * 2;
  const x = at.x - width / 2;
  const y = at.y - height / 2;

  ctx.fillStyle = 'rgba(255, 255, 255, 0.88)';
  ctx.fillRect(x, y, width, height);
  ctx.strokeStyle = 'rgba(44, 44, 42, 0.18)';
  ctx.lineWidth = 1;
  ctx.strokeRect(x, y, width, height);

  ctx.fillStyle = label.color;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label.text, at.x, at.y);
  ctx.restore();
}

export function hitsLabel(point: Point, label: MapLabel, at: Point): boolean {
  // 대략적인 폭 추정으로 충분하다. 정확한 측정은 컨텍스트가 필요해 과하다.
  const width = label.text.length * label.fontSize * 0.7 + LABEL_PADDING_X * 2;
  const height = label.fontSize + LABEL_PADDING_Y * 2;
  return Math.abs(point.x - at.x) <= width / 2 + 2 && Math.abs(point.y - at.y) <= height / 2 + 2;
}

/* -------------------------------------------------------------------- 공통 */

export function tracePolyline(ctx: CanvasRenderingContext2D, points: readonly Point[]) {
  ctx.beginPath();
  ctx.moveTo(points[0]!.x, points[0]!.y);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i]!.x, points[i]!.y);
}
