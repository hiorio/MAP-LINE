import { strokeRenderAlpha, strokeRenderWidth } from '@/lib/geo/projection';
import type { Point } from '@/lib/geo/rdp';
import { flattenStops, type LatLng, type MapLabel, type Place, type Stop, type Stroke } from '@/lib/map/types';

/**
 * 오버레이 한 장에 획 → 핀 → 라벨 순으로 그린다.
 *
 * 설계안 §12.2는 PinLayer/SegmentLayer를 별도 컴포넌트로 두지만, 레이어마다 캔버스를
 * 나누면 팬·줌 동기화와 좌표 재투영을 그 수만큼 반복해야 한다. 캔버스는 하나로 두고
 * 그리는 함수만 분리하는 편이 비용과 코드 양 모두 유리하다.
 *
 * 단계 사이를 잇는 자동 연결선은 그리지 않는다. 한 단계에 후보가 여러 개이면 선이
 * 어느 후보를 가리키는지 알 수 없어 오히려 잘못된 정보를 준다. 동선은 손그림으로 그린다.
 */
export interface Scene {
  stops: readonly Stop[];
  strokes: readonly Stroke[];
  labels: readonly MapLabel[];
  /**
   * 보관함에 담아 둔 장소. 편집기에서만 겹쳐 보이고 공유되는 지도에는 없다.
   * 코스에 올린 핀과 헷갈리면 안 되므로 번호 없이 다른 모양으로 그린다.
   */
  saved?: readonly { id: string; name: string; location: LatLng }[];
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

  // 보관함은 코스 핀보다 아래에 깔아 둔다. 코스가 주인공이다.
  for (const saved of scene.saved ?? []) {
    drawSavedMarker(ctx, saved.name, project(saved.location));
  }

  // 같은 단계의 후보는 모두 같은 번호를 달고 같은 모양으로 찍힌다.
  for (const { place, stopNumber } of flattenStops(scene.stops)) {
    drawPin(ctx, place, stopNumber, project(place.location));
  }
  for (const label of scene.labels) drawLabel(ctx, label, project(label.location));
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

/* ------------------------------------------------------------------ 보관함 */

export const SAVED_RADIUS = 8;

/**
 * 보관함 표시. 속이 빈 작은 원에 별을 얹는다.
 *
 * 코스 핀(꽉 찬 코랄색 원 + 번호)과 한눈에 구분돼야 한다. 둘이 비슷해 보이면
 * "이건 코스에 넣은 건가 그냥 저장만 한 건가"를 매번 헷갈리게 된다.
 */
export function drawSavedMarker(ctx: CanvasRenderingContext2D, name: string, at: Point) {
  ctx.save();
  ctx.beginPath();
  ctx.arc(at.x, at.y, SAVED_RADIUS, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.92)';
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = '#6B6B66';
  ctx.stroke();

  ctx.fillStyle = '#6B6B66';
  ctx.font = `10px ${LABEL_FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('★', at.x, at.y + 0.5);

  ctx.font = `11px ${LABEL_FONT}`;
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
  ctx.strokeText(name, at.x, at.y + SAVED_RADIUS + 8);
  ctx.fillStyle = '#6B6B66';
  ctx.fillText(name, at.x, at.y + SAVED_RADIUS + 8);
  ctx.restore();
}

export function hitsSavedMarker(point: Point, at: Point): boolean {
  return Math.hypot(point.x - at.x, point.y - at.y) <= SAVED_RADIUS + 5;
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
