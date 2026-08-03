import { strokeRenderAlpha, strokeRenderWidth } from '@/lib/geo/projection';
import type { Point } from '@/lib/geo/rdp';
import {
  flattenStops,
  type LatLng,
  type MapLabel,
  type Place,
  type Stop,
  type StopLeg,
  type Stroke,
} from '@/lib/map/types';
import {
  arrowHead,
  candidateLinks,
  labelBoxSize,
  legShapes,
  ARROW_COLOR,
  HUB_RADIUS,
  LABEL_PADDING_X,
  LABEL_PADDING_Y,
  LINK_DASH,
  LINK_WIDTH,
  MODE_STYLE,
  PIN_RADIUS,
  SAVED_RADIUS,
  type Projector,
} from './sceneGeometry';

/**
 * 오버레이 한 장에 화살표 → 획 → 핀 → 라벨 순으로 그린다.
 *
 * 설계안 §12.2는 PinLayer/SegmentLayer를 별도 컴포넌트로 두지만, 레이어마다 캔버스를
 * 나누면 팬·줌 동기화와 좌표 재투영을 그 수만큼 반복해야 한다. 캔버스는 하나로 두고
 * 그리는 함수만 분리하는 편이 비용과 코드 양 모두 유리하다.
 *
 * 단계 사이 동선은 두 가지 모습을 갖는다. 이동수단을 고르고 대표 후보까지 정한 구간은
 * 길찾기로 받은 실제 궤적을 그린다. 그렇지 않으면 후보들의 중간지점을 잇는 직선이다.
 * 특정 후보에서 선을 뽑으면 나머지 후보가 동선에서 빠진 것처럼 보이지만, 무리의
 * 가운데에서 출발하면 "이 단계에서 다음 단계로"만 말하게 되어 어느 후보를 고르든 틀리지 않는다.
 */
export interface Scene {
  stops: readonly Stop[];
  legs?: readonly StopLeg[];
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

export type { Projector };
export { PIN_RADIUS, SAVED_RADIUS };

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
  if (scene.showStopArrows !== false) {
    drawStopArrows(ctx, scene.stops, scene.legs ?? [], project);
  }

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
  ctx.strokeStyle = ARROW_COLOR;
  ctx.fillStyle = ARROW_COLOR;
  ctx.lineWidth = LINK_WIDTH;

  for (const { hub, spokes } of candidateLinks(stops, project)) {
    ctx.setLineDash([...LINK_DASH]);
    for (const { from, to } of spokes) {
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      ctx.stroke();
    }

    // 점선이 모이는 자리를 점 하나로 못 박는다. 화살표가 여기서 출발한다.
    ctx.setLineDash([]);
    ctx.beginPath();
    ctx.arc(hub.x, hub.y, HUB_RADIUS, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

/**
 * 단계 사이 동선. 실제 경로를 받아 둔 구간은 그 궤적을, 아니면 직선을 그린다.
 * 어느 쪽이든 진행 방향 끝에 화살촉을 얹는다. 어디로 가는지가 이 선의 존재 이유다.
 */
function drawStopArrows(
  ctx: CanvasRenderingContext2D,
  stops: readonly Stop[],
  legs: readonly StopLeg[],
  project: Projector,
) {
  ctx.save();

  for (const shape of legShapes(stops, legs, project)) {
    const style = MODE_STYLE[shape.mode];
    ctx.strokeStyle = style.color;
    ctx.fillStyle = style.color;
    ctx.lineWidth = style.width;
    ctx.setLineDash(style.dash ? [...style.dash] : []);

    const { end, ux, uy } = shape.kind === 'arrow' ? shape.arrow : shape;

    ctx.beginPath();
    if (shape.kind === 'arrow') {
      ctx.moveTo(shape.arrow.start.x, shape.arrow.start.y);
      ctx.lineTo(end.x, end.y);
    } else {
      tracePolyline(ctx, shape.points);
    }
    ctx.stroke();

    // 화살촉은 채운 삼각형이라 점선 설정이 남아 있으면 테두리가 끊겨 보인다.
    ctx.setLineDash([]);
    const [tip, left, right] = arrowHead(end, ux, uy);
    ctx.beginPath();
    ctx.moveTo(tip.x, tip.y);
    ctx.lineTo(left.x, left.y);
    ctx.lineTo(right.x, right.y);
    ctx.closePath();
    ctx.fill();
  }
  ctx.restore();
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
  const { width, height } = labelBoxSize(label.text, label.fontSize);
  return Math.abs(point.x - at.x) <= width / 2 + 2 && Math.abs(point.y - at.y) <= height / 2 + 2;
}

/* -------------------------------------------------------------------- 공통 */

export function tracePolyline(ctx: CanvasRenderingContext2D, points: readonly Point[]) {
  ctx.beginPath();
  ctx.moveTo(points[0]!.x, points[0]!.y);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i]!.x, points[i]!.y);
}
