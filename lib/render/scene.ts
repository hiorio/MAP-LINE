import { strokeRenderAlpha, strokeRenderWidth } from '@/lib/geo/projection';
import type { Point } from '@/lib/geo/rdp';
import {
  flattenStops,
  stopCentroid,
  type LatLng,
  type MapLabel,
  type Place,
  type Stop,
  type Stroke,
} from '@/lib/map/types';

/**
 * 오버레이 한 장에 화살표 → 획 → 핀 → 라벨 순으로 그린다.
 *
 * 설계안 §12.2는 PinLayer/SegmentLayer를 별도 컴포넌트로 두지만, 레이어마다 캔버스를
 * 나누면 팬·줌 동기화와 좌표 재투영을 그 수만큼 반복해야 한다. 캔버스는 하나로 두고
 * 그리는 함수만 분리하는 편이 비용과 코드 양 모두 유리하다.
 *
 * 단계 사이 화살표는 후보 하나가 아니라 후보들의 중간지점에서 출발한다. 특정 후보에서
 * 선을 뽑으면 나머지 후보가 동선에서 빠진 것처럼 보이지만, 무리의 가운데에서 출발하면
 * "이 단계에서 다음 단계로"만 말하게 되어 어느 후보를 고르든 틀리지 않는다.
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
  /** 자동으로 그리는 선. 지도를 만든 사람이 끌 수 있다. */
  showCandidateLinks?: boolean;
  showStopArrows?: boolean;
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

  // 손그림보다 아래에 깔아 둔다. 사용자가 직접 그린 선이 주인공이다.
  if (scene.showCandidateLinks !== false) drawCandidateLinks(ctx, scene.stops, project);
  if (scene.showStopArrows !== false) drawStopArrows(ctx, scene.stops, project);

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

/* ------------------------------------------------------------------ 화살표 */

const ARROW_COLOR = '#8A8A83';
const ARROW_WIDTH = 2.5;
const ARROW_HEAD_PX = 10;
/** 화살표가 핀 안쪽에서 시작·끝나면 지저분하다. 양끝을 이만큼 물려 놓는다. */
const ARROW_TRIM_PX = PIN_RADIUS + 6;
/** 양끝을 비키고 남는 몸통이 이보다 짧으면 머리만 남아 오히려 지저분하다. */
const ARROW_MIN_SHAFT_PX = 12;

const LINK_WIDTH = 1.5;
const LINK_DASH = [2, 5];
const HUB_RADIUS = 3;

/**
 * 같은 단계의 후보들을 중간지점과 점선으로 잇는다.
 *
 * 화살표가 아무 핀에도 붙어 있지 않은 허공에서 시작하면 왜 거기서 나오는지 알 수 없다.
 * 후보들이 중간지점으로 모이는 점선을 깔아 두면 그 지점이 이 무리의 대표라는 것이
 * 그림만으로 읽힌다.
 *
 * 후보가 둘일 때는 중간지점이 두 핀을 잇는 선 위에 있으므로, 결과적으로 "두 후보를
 * 잇는 점선 하나"와 같은 모양이 된다.
 */
function drawCandidateLinks(
  ctx: CanvasRenderingContext2D,
  stops: readonly Stop[],
  project: Projector,
) {
  ctx.save();
  ctx.setLineDash(LINK_DASH);
  ctx.strokeStyle = ARROW_COLOR;
  ctx.fillStyle = ARROW_COLOR;
  ctx.lineWidth = LINK_WIDTH;

  for (const stop of stops) {
    if (stop.candidates.length < 2) continue;

    const centroid = stopCentroid(stop);
    if (!centroid) continue;
    const hub = project(centroid);

    for (const candidate of stop.candidates) {
      const at = project(candidate.location);
      const dx = hub.x - at.x;
      const dy = hub.y - at.y;
      const length = Math.hypot(dx, dy);
      // 핀 안에서 시작하면 지저분하다. 핀에 가려 안 보일 만큼 짧으면 아예 생략한다.
      if (length <= ARROW_TRIM_PX) continue;

      ctx.beginPath();
      ctx.moveTo(at.x + (dx / length) * ARROW_TRIM_PX, at.y + (dy / length) * ARROW_TRIM_PX);
      ctx.lineTo(hub.x, hub.y);
      ctx.stroke();
    }

    // 점선이 모이는 자리를 점 하나로 못 박는다. 화살표가 여기서 출발한다.
    ctx.setLineDash([]);
    ctx.beginPath();
    ctx.arc(hub.x, hub.y, HUB_RADIUS, 0, Math.PI * 2);
    ctx.fill();
    ctx.setLineDash(LINK_DASH);
  }
  ctx.restore();
}

function drawStopArrows(
  ctx: CanvasRenderingContext2D,
  stops: readonly Stop[],
  project: Projector,
) {
  const centers = stops.map((stop) => {
    const centroid = stopCentroid(stop);
    if (!centroid) return null;
    return {
      point: project(centroid),
      // 후보가 하나면 중간지점에 핀이 서 있으므로 핀 반지름만큼 비켜야 한다.
      // 여럿이면 그 자리에 허브 점만 있으니 거기에 붙여야 이어져 보인다.
      trim: stop.candidates.length === 1 ? ARROW_TRIM_PX : HUB_RADIUS + 3,
    };
  });

  ctx.save();
  ctx.strokeStyle = ARROW_COLOR;
  ctx.fillStyle = ARROW_COLOR;
  ctx.lineWidth = ARROW_WIDTH;

  for (let i = 1; i < centers.length; i++) {
    const from = centers[i - 1];
    const to = centers[i];
    if (!from || !to) continue;

    const dx = to.point.x - from.point.x;
    const dy = to.point.y - from.point.y;
    const length = Math.hypot(dx, dy);
    if (length < from.trim + to.trim + ARROW_MIN_SHAFT_PX) continue;

    const ux = dx / length;
    const uy = dy / length;
    const start = { x: from.point.x + ux * from.trim, y: from.point.y + uy * from.trim };
    const end = { x: to.point.x - ux * to.trim, y: to.point.y - uy * to.trim };

    ctx.beginPath();
    ctx.moveTo(start.x, start.y);
    ctx.lineTo(end.x, end.y);
    ctx.stroke();

    drawArrowHead(ctx, end, ux, uy);
  }
  ctx.restore();
}

/** 진행 방향 끝에 채운 삼각형을 얹는다. 어느 쪽으로 가는지가 화살표의 존재 이유다. */
function drawArrowHead(ctx: CanvasRenderingContext2D, at: Point, ux: number, uy: number) {
  const spread = 0.42; // 라디안. 너무 벌리면 화살표가 아니라 갈매기로 보인다.
  const cos = Math.cos(spread);
  const sin = Math.sin(spread);

  const left = { x: -ux * cos + uy * sin, y: -uy * cos - ux * sin };
  const right = { x: -ux * cos - uy * sin, y: -uy * cos + ux * sin };

  ctx.beginPath();
  ctx.moveTo(at.x, at.y);
  ctx.lineTo(at.x + left.x * ARROW_HEAD_PX, at.y + left.y * ARROW_HEAD_PX);
  ctx.lineTo(at.x + right.x * ARROW_HEAD_PX, at.y + right.y * ARROW_HEAD_PX);
  ctx.closePath();
  ctx.fill();
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
