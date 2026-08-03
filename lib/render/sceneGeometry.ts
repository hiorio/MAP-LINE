import type { Point } from '@/lib/geo/rdp';
import { drawableRoute } from '@/lib/map/legs';
import {
  stopCentroid,
  type LatLng,
  type Stop,
  type StopLeg,
  type TravelMode,
} from '@/lib/map/types';

/**
 * 화살표와 연결선의 순수 기하 계산.
 *
 * 캔버스(편집기)와 SVG(공유 썸네일)가 같은 그림을 그려야 한다. 두 곳에 따로 두면
 * 한쪽만 고쳐져 "내 화면과 카톡 미리보기가 다른" 상태가 조용히 생긴다.
 * 그리는 방법은 갈라져도 어디에 그릴지는 여기 한 곳에서만 정한다.
 */
export type Projector = (coord: LatLng) => Point;

export const PIN_RADIUS = 13;
export const SAVED_RADIUS = 8;

export const ARROW_COLOR = '#8A8A83';
export const ARROW_WIDTH = 2.5;
export const ARROW_HEAD_PX = 10;
/** 화살표가 핀 안쪽에서 시작·끝나면 지저분하다. 양끝을 이만큼 물려 놓는다. */
export const ARROW_TRIM_PX = PIN_RADIUS + 6;
/** 양끝을 비키고 남는 몸통이 이보다 짧으면 머리만 남아 오히려 지저분하다. */
export const ARROW_MIN_SHAFT_PX = 12;

export const LINK_WIDTH = 1.5;
export const LINK_DASH: readonly [number, number] = [2, 5];
export const HUB_RADIUS = 3;

export const LABEL_PADDING_X = 6;
export const LABEL_PADDING_Y = 3;

export interface CandidateLink {
  /** 후보들이 모이는 중간지점 */
  hub: Point;
  /** 각 후보에서 중간지점으로 향하는 점선. 핀에 가려질 만큼 짧은 것은 빠져 있다. */
  spokes: { from: Point; to: Point }[];
}

/**
 * 같은 단계의 후보들을 중간지점과 잇는 점선.
 *
 * 후보가 하나뿐인 단계는 이을 것이 없으므로 건너뛴다.
 */
export function candidateLinks(stops: readonly Stop[], project: Projector): CandidateLink[] {
  const links: CandidateLink[] = [];

  for (const stop of stops) {
    if (stop.candidates.length < 2) continue;

    const centroid = stopCentroid(stop);
    if (!centroid) continue;
    const hub = project(centroid);

    const spokes: { from: Point; to: Point }[] = [];
    for (const candidate of stop.candidates) {
      const at = project(candidate.location);
      const dx = hub.x - at.x;
      const dy = hub.y - at.y;
      const length = Math.hypot(dx, dy);
      // 핀 안에서 시작하면 지저분하다. 핀에 가려 안 보일 만큼 짧으면 아예 생략한다.
      if (length <= ARROW_TRIM_PX) continue;

      spokes.push({
        from: { x: at.x + (dx / length) * ARROW_TRIM_PX, y: at.y + (dy / length) * ARROW_TRIM_PX },
        to: hub,
      });
    }
    links.push({ hub, spokes });
  }
  return links;
}

/** 이동수단별 선 모양. 색은 자동 연결선과 같은 계열로 두어 손그림을 가리지 않는다. */
export const MODE_STYLE: Record<TravelMode, { color: string; width: number; dash?: [number, number] }> = {
  straight: { color: ARROW_COLOR, width: ARROW_WIDTH },
  // 걷는 길은 촘촘한 점선. 지도의 실선 도로와 겹쳐도 구분된다.
  walk: { color: ARROW_COLOR, width: 3, dash: [1, 6] },
  bicycle: { color: '#2FA35B', width: 3, dash: [8, 5] },
  transit: { color: '#2D6BE4', width: 4 },
};

export interface StopArrow {
  start: Point;
  end: Point;
  /** 진행 방향 단위벡터. 화살촉을 얹을 때 쓴다. */
  ux: number;
  uy: number;
}

/**
 * 한 구간을 어떻게 그릴지.
 *
 * 실제 경로를 받아 둔 구간은 그 궤적을, 아니면 지금까지처럼 중간지점을 잇는 직선
 * 화살표를 그린다. 후보가 여럿인데 대표를 안 정한 단계는 길찾기의 기준이 없으므로
 * 자동으로 직선으로 되돌아온다.
 */
export type LegShape =
  | { kind: 'arrow'; mode: TravelMode; arrow: StopArrow }
  | { kind: 'path'; mode: TravelMode; points: Point[]; end: Point; ux: number; uy: number };

export function legShapes(
  stops: readonly Stop[],
  legs: readonly StopLeg[],
  project: Projector,
): LegShape[] {
  // 자리로 짝지어야 하므로 그릴 수 없는 구간도 null로 자리를 지키게 받는다.
  const arrows = stopArrowSlots(stops, project);
  const shapes: LegShape[] = [];

  for (let i = 0; i < Math.max(0, stops.length - 1); i++) {
    const leg = legs[i];
    const route = drawableRoute(stops, i, leg);

    if (route && leg) {
      const points = route.points.map(project);
      const heading = lastHeading(points);
      if (heading) {
        shapes.push({ kind: 'path', mode: leg.mode, points, ...heading });
        continue;
      }
    }

    const arrow = arrows[i];
    if (arrow) shapes.push({ kind: 'arrow', mode: 'straight', arrow });
  }
  return shapes;
}

/** 마지막 두 점이 만드는 방향. 화살촉을 어디에 얹을지 정한다. */
function lastHeading(points: readonly Point[]): { end: Point; ux: number; uy: number } | null {
  const end = points.at(-1);
  if (!end) return null;

  // 끝이 뭉쳐 있으면 방향이 안 나온다. 뒤에서부터 떨어진 점을 찾는다.
  for (let i = points.length - 2; i >= 0; i--) {
    const previous = points[i]!;
    const dx = end.x - previous.x;
    const dy = end.y - previous.y;
    const length = Math.hypot(dx, dy);
    if (length > 0.5) return { end, ux: dx / length, uy: dy / length };
  }
  return null;
}

/**
 * 단계와 단계를 잇는 화살표를 **자리에 맞춰** 돌려준다. 길이가 stops.length - 1이고,
 * 그릴 수 없는 구간은 null로 자리를 지킨다. 걸러 내면 뒤 구간의 모드가 앞으로 밀린다.
 */
export function stopArrowSlots(
  stops: readonly Stop[],
  project: Projector,
): (StopArrow | null)[] {
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

  const arrows: (StopArrow | null)[] = [];
  for (let i = 1; i < centers.length; i++) {
    const from = centers[i - 1];
    const to = centers[i];
    if (!from || !to) {
      arrows.push(null);
      continue;
    }

    const dx = to.point.x - from.point.x;
    const dy = to.point.y - from.point.y;
    const length = Math.hypot(dx, dy);
    // 양끝을 비키고 남는 몸통이 너무 짧으면 머리만 남아 오히려 지저분하다.
    if (length < from.trim + to.trim + ARROW_MIN_SHAFT_PX) {
      arrows.push(null);
      continue;
    }

    const ux = dx / length;
    const uy = dy / length;
    arrows.push({
      start: { x: from.point.x + ux * from.trim, y: from.point.y + uy * from.trim },
      end: { x: to.point.x - ux * to.trim, y: to.point.y - uy * to.trim },
      ux,
      uy,
    });
  }
  return arrows;
}

/** 채운 삼각형 화살촉의 세 꼭짓점. 첫 점이 화살표 끝이다. */
export function arrowHead(at: Point, ux: number, uy: number): [Point, Point, Point] {
  const spread = 0.42; // 라디안. 너무 벌리면 화살표가 아니라 갈매기로 보인다.
  const cos = Math.cos(spread);
  const sin = Math.sin(spread);

  const left = { x: -ux * cos + uy * sin, y: -uy * cos - ux * sin };
  const right = { x: -ux * cos - uy * sin, y: -uy * cos + ux * sin };

  return [
    at,
    { x: at.x + left.x * ARROW_HEAD_PX, y: at.y + left.y * ARROW_HEAD_PX },
    { x: at.x + right.x * ARROW_HEAD_PX, y: at.y + right.y * ARROW_HEAD_PX },
  ];
}

/**
 * 라벨 배경 상자의 크기.
 *
 * 서버에는 캔버스가 없어 글자 폭을 실측할 수 없다. 한글·한자·가나는 정사각형에
 * 가깝고 라틴 문자는 그 절반쯤이라는 사실만으로 어림한다. 배경 상자가 몇 픽셀
 * 넉넉하거나 모자란 것은 눈에 띄지 않는다.
 */
export function labelBoxSize(text: string, fontSize: number): { width: number; height: number } {
  let ems = 0;
  for (const char of text) ems += isWide(char) ? 1 : 0.55;
  return {
    width: ems * fontSize + LABEL_PADDING_X * 2,
    height: fontSize + LABEL_PADDING_Y * 2,
  };
}

function isWide(char: string): boolean {
  const code = char.codePointAt(0) ?? 0;
  return (
    (code >= 0x1100 && code <= 0x11ff) || // 한글 자모
    (code >= 0x3000 && code <= 0x30ff) || // 문장부호·가나
    (code >= 0x3400 && code <= 0x9fff) || // 한자
    (code >= 0xac00 && code <= 0xd7af) || // 한글 음절
    (code >= 0xff00 && code <= 0xff60) // 전각
  );
}
