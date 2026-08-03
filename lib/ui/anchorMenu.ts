import type { Point } from '@/lib/geo/rdp';

/**
 * 누른 지점에 붙여 띄우는 메뉴의 위치.
 *
 * 지점을 그대로 중심에 두면 화면 가장자리를 눌렀을 때 메뉴가 밖으로 밀려 나간다.
 * 모바일에서는 손이 닿지 않아 닫지도 못한다. 가로는 화면 안으로 밀어 넣고, 세로는
 * 위아래 중 여유 있는 쪽으로 뒤집는다.
 *
 * 세로 크기는 내용에 따라 달라져 미리 알 수 없다. 누른 지점이 위쪽 절반이면 아래로,
 * 아래쪽 절반이면 위로 편다는 규칙만으로도 화면 밖으로 나가는 일은 없다.
 */
export interface AnchorInput {
  point: Point;
  /** 메뉴의 가로 크기(px). Tailwind의 w-64면 256이다. */
  menuWidth: number;
  container: { width: number; height: number };
  /** 누른 지점과 메뉴 사이 간격 */
  gap?: number;
  /** 화면 가장자리에서 최소한 띄울 여백 */
  margin?: number;
}

export interface AnchorStyle {
  left: number;
  top: number;
  /** 위로 펼 때만 있다. 가로는 left로 이미 확정했으므로 옮기지 않는다. */
  transform?: string;
}

export function anchorMenuStyle({
  point,
  menuWidth,
  container,
  gap = 16,
  margin = 8,
}: AnchorInput): AnchorStyle {
  const left = clamp(
    point.x - menuWidth / 2,
    margin,
    // 메뉴가 화면보다 넓으면 최소값이 최대값보다 커진다. 그때는 왼쪽 여백에 붙인다.
    Math.max(margin, container.width - menuWidth - margin),
  );

  const flipDown = point.y < container.height / 2;
  return flipDown
    ? { left, top: point.y + gap }
    : { left, top: point.y - gap, transform: 'translateY(-100%)' };
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
