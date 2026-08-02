import { strokeRenderAlpha, strokeRenderWidth } from '@/lib/geo/projection';
import { flattenStops, type MapLabel, type Stop, type Stroke } from '@/lib/map/types';
import {
  arrowHead,
  candidateLinks,
  labelBoxSize,
  stopArrows,
  ARROW_COLOR,
  ARROW_WIDTH,
  HUB_RADIUS,
  LINK_DASH,
  LINK_WIDTH,
  PIN_RADIUS,
  type Projector,
} from './sceneGeometry';

/**
 * 공유 썸네일에 얹을 오버레이를 SVG로 만든다.
 *
 * 카카오 정적 지도에는 폴리라인 파라미터가 없어서 손그림·화살표·연결선을 API에
 * 맡길 수 없다. 마커 파라미터도 쓸 수 없는데, `markers`를 넘기면 카카오가
 * **`center`를 무시하고 마커에 맞춰 지도를 다시 잡기 때문이다**. 그래서 지도는
 * 마커 없이 받고 그 위의 모든 표시를 여기서 직접 그린다.
 *
 * 좌표계는 CSS 픽셀이다. 실제 이미지는 scale배로 커지지만 viewBox로 확대하므로
 * 선 굵기와 글자 크기를 편집기와 같은 값으로 둘 수 있다.
 */
const FONT = '"Noto Sans CJK KR","Noto Sans KR","Malgun Gothic","Apple SD Gothic Neo",sans-serif';

export interface OgOverlayInput {
  stops: readonly Stop[];
  strokes: readonly Stroke[];
  labels: readonly MapLabel[];
  showCandidateLinks: boolean;
  showStopArrows: boolean;
  /** 지도의 줌 레벨. 획 굵기·투명도 보정에 쓴다. */
  level: number;
  /** CSS 픽셀 기준 크기 */
  width: number;
  height: number;
  /** 결과 이미지를 CSS 크기의 몇 배로 낼지 */
  scale: number;
  project: Projector;
}

export function renderOgOverlay(input: OgOverlayInput): string {
  const { width, height, scale, project } = input;
  const parts: string[] = [];

  // 손그림보다 아래에 깔아 둔다. 사용자가 직접 그린 선이 주인공이다.
  if (input.showCandidateLinks) parts.push(candidateLinkMarkup(input.stops, project));
  if (input.showStopArrows) parts.push(stopArrowMarkup(input.stops, project));

  parts.push(strokeMarkup(input.strokes, input.level, project));
  parts.push(pinMarkup(input.stops, project));
  parts.push(labelMarkup(input.labels, project));

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width * scale}" height="${height * scale}" ` +
    `viewBox="0 0 ${width} ${height}">` +
    `<g stroke-linecap="round" stroke-linejoin="round">${parts.join('')}</g>` +
    `</svg>`
  );
}

function candidateLinkMarkup(stops: readonly Stop[], project: Projector): string {
  let out = '';
  for (const { hub, spokes } of candidateLinks(stops, project)) {
    for (const { from, to } of spokes) {
      out +=
        `<line x1="${n(from.x)}" y1="${n(from.y)}" x2="${n(to.x)}" y2="${n(to.y)}" ` +
        `stroke="${ARROW_COLOR}" stroke-width="${LINK_WIDTH}" stroke-dasharray="${LINK_DASH.join(' ')}"/>`;
    }
    // 점선이 모이는 자리를 점 하나로 못 박는다. 화살표가 여기서 출발한다.
    out += `<circle cx="${n(hub.x)}" cy="${n(hub.y)}" r="${HUB_RADIUS}" fill="${ARROW_COLOR}"/>`;
  }
  return out;
}

function stopArrowMarkup(stops: readonly Stop[], project: Projector): string {
  let out = '';
  for (const { start, end, ux, uy } of stopArrows(stops, project)) {
    out +=
      `<line x1="${n(start.x)}" y1="${n(start.y)}" x2="${n(end.x)}" y2="${n(end.y)}" ` +
      `stroke="${ARROW_COLOR}" stroke-width="${ARROW_WIDTH}"/>`;
    const points = arrowHead(end, ux, uy)
      .map((p) => `${n(p.x)},${n(p.y)}`)
      .join(' ');
    out += `<polygon points="${points}" fill="${ARROW_COLOR}"/>`;
  }
  return out;
}

function strokeMarkup(strokes: readonly Stroke[], level: number, project: Projector): string {
  let out = '';
  for (const stroke of strokes) {
    const points = stroke.path.map(project);
    if (points.length < 2) continue;
    const d = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${n(p.x)} ${n(p.y)}`).join('');
    out +=
      `<path d="${d}" fill="none" stroke="${esc(stroke.color)}" ` +
      `stroke-width="${n(strokeRenderWidth(stroke.width, stroke.zoomCreated, level))}" ` +
      `stroke-opacity="${n(strokeRenderAlpha(stroke.zoomCreated, level))}"/>`;
  }
  return out;
}

/** 같은 단계의 후보는 모두 같은 번호를 달고 같은 모양으로 찍힌다. */
function pinMarkup(stops: readonly Stop[], project: Projector): string {
  let out = '';
  for (const { place, stopNumber } of flattenStops(stops)) {
    const at = project(place.location);
    out +=
      `<circle cx="${n(at.x)}" cy="${n(at.y)}" r="${PIN_RADIUS}" ` +
      `fill="${esc(place.pinColor)}" stroke="#FFFFFF" stroke-width="2"/>` +
      text(String(stopNumber), at.x, at.y + 0.5, {
        size: 13,
        weight: 600,
        fill: '#FFFFFF',
      }) +
      outlinedText(place.name, at.x, at.y + PIN_RADIUS + 9, {
        size: 12,
        weight: 600,
        fill: '#2C2C2A',
      });
  }
  return out;
}

function labelMarkup(labels: readonly MapLabel[], project: Projector): string {
  let out = '';
  for (const label of labels) {
    const at = project(label.location);
    const { width, height } = labelBoxSize(label.text, label.fontSize);
    out +=
      `<rect x="${n(at.x - width / 2)}" y="${n(at.y - height / 2)}" ` +
      `width="${n(width)}" height="${n(height)}" ` +
      `fill="rgba(255,255,255,0.88)" stroke="rgba(44,44,42,0.18)" stroke-width="1"/>` +
      text(label.text, at.x, at.y, { size: label.fontSize, weight: 400, fill: label.color });
  }
  return out;
}

interface TextStyle {
  size: number;
  weight: number;
  fill: string;
}

function text(value: string, x: number, y: number, style: TextStyle): string {
  return (
    `<text x="${n(x)}" y="${n(y)}" font-family='${FONT}' font-size="${style.size}" ` +
    `font-weight="${style.weight}" fill="${esc(style.fill)}" ` +
    `text-anchor="middle" dominant-baseline="central">${esc(value)}</text>`
  );
}

/**
 * 지도 타일 위에서 글자가 묻히지 않도록 흰 테두리를 두른 글자.
 *
 * `paint-order`는 렌더러에 따라 무시되므로, 캔버스가 하듯 테두리용과 본문용을
 * 두 번 겹쳐 그린다.
 */
function outlinedText(value: string, x: number, y: number, style: TextStyle): string {
  const halo =
    `<text x="${n(x)}" y="${n(y)}" font-family='${FONT}' font-size="${style.size}" ` +
    `font-weight="${style.weight}" fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="3" ` +
    `stroke-linejoin="round" text-anchor="middle" dominant-baseline="central">${esc(value)}</text>`;
  return halo + text(value, x, y, style);
}

/** 좌표는 소수점 두 자리면 충분하다. 문자열이 짧아야 SVG 파싱도 빠르다. */
function n(value: number): string {
  return Number.isFinite(value) ? String(Math.round(value * 100) / 100) : '0';
}

function esc(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}
