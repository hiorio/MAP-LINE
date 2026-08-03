import { describe, expect, it } from 'vitest';
import { anchorMenuStyle } from './anchorMenu';

const container = { width: 375, height: 812 };
const menuWidth = 256;

describe('anchorMenuStyle', () => {
  it('가운데를 누르면 그 지점을 중심에 둔다', () => {
    const { left } = anchorMenuStyle({ point: { x: 187, y: 400 }, menuWidth, container });
    expect(left).toBe(187 - menuWidth / 2);
  });

  it('오른쪽 끝을 눌러도 화면 밖으로 나가지 않는다', () => {
    // 모바일에서 밖으로 밀리면 손이 닿지 않아 닫지도 못한다.
    const { left } = anchorMenuStyle({ point: { x: 370, y: 400 }, menuWidth, container });
    expect(left + menuWidth).toBeLessThanOrEqual(container.width);
    expect(left).toBeGreaterThanOrEqual(0);
  });

  it('왼쪽 끝을 눌러도 화면 밖으로 나가지 않는다', () => {
    const { left } = anchorMenuStyle({ point: { x: 4, y: 400 }, menuWidth, container });
    expect(left).toBeGreaterThanOrEqual(0);
  });

  it('메뉴가 화면보다 넓으면 왼쪽 여백에 붙인다', () => {
    // 최소값이 최대값보다 커지는 경우다. clamp가 뒤집히면 음수가 나온다.
    const { left } = anchorMenuStyle({
      point: { x: 100, y: 400 },
      menuWidth: 500,
      container: { width: 320, height: 600 },
    });
    expect(left).toBeGreaterThanOrEqual(0);
  });

  it('위쪽을 누르면 아래로 편다', () => {
    const style = anchorMenuStyle({ point: { x: 187, y: 100 }, menuWidth, container });
    expect(style.top).toBeGreaterThan(100);
    expect(style.transform).toBeUndefined();
  });

  it('아래쪽을 누르면 위로 편다', () => {
    // 손가락이 아래에 있는데 아래로 펴면 손에 가려진다.
    const style = anchorMenuStyle({ point: { x: 187, y: 700 }, menuWidth, container });
    expect(style.top).toBeLessThan(700);
    expect(style.transform).toBe('translateY(-100%)');
  });
});
