import { describe, expect, it } from 'vitest';
import type { Point } from '@/lib/geo/rdp';
import type { LatLng, MapLabel, Stop, Stroke } from '@/lib/map/types';
import { renderOgOverlay, type OgOverlayInput } from './ogOverlay';

/** 위경도를 그대로 픽셀로 읽는 투영. 기대값을 눈으로 따라갈 수 있다. */
const project = ({ lat, lng }: LatLng): Point => ({ x: lng, y: lat });

function place(id: string, lat: number, lng: number) {
  return { id, name: `가게${id}`, location: { lat, lng }, pinColor: '#E24B4A' };
}

function input(overrides: Partial<OgOverlayInput> = {}): OgOverlayInput {
  return {
    stops: [],
    strokes: [],
    labels: [],
    showCandidateLinks: true,
    showStopArrows: true,
    level: 3,
    width: 800,
    height: 420,
    scale: 2,
    project,
    ...overrides,
  };
}

describe('renderOgOverlay', () => {
  it('CSS 크기를 viewBox로 두고 이미지는 scale배로 낸다', () => {
    // 이래야 선 굵기와 글자 크기를 편집기와 같은 값으로 쓸 수 있다.
    const svg = renderOgOverlay(input());
    expect(svg).toContain('width="1600"');
    expect(svg).toContain('height="840"');
    expect(svg).toContain('viewBox="0 0 800 420"');
  });

  it('단계마다 번호를 단 핀을 그린다', () => {
    const svg = renderOgOverlay(
      input({
        stops: [
          { id: 's1', candidates: [place('a', 100, 200)] },
          { id: 's2', candidates: [place('b', 300, 400)] },
        ],
      }),
    );
    expect(svg).toContain('<circle cx="200" cy="100" r="13"');
    expect(svg).toContain('>1</text>');
    expect(svg).toContain('>2</text>');
    expect(svg).toContain('가게a');
  });

  it('같은 단계의 후보는 모두 같은 번호를 단다', () => {
    const svg = renderOgOverlay(
      input({ stops: [{ id: 's1', candidates: [place('a', 10, 20), place('b', 30, 40)] }] }),
    );
    expect(svg.match(/>1<\/text>/g)).toHaveLength(2);
    expect(svg).not.toContain('>2</text>');
  });

  it('손그림을 path로 그리고 그린 줌에 맞춰 굵기를 보정한다', () => {
    const stroke: Stroke = {
      id: 'k1',
      path: [
        { lat: 10, lng: 20 },
        { lat: 30, lng: 40 },
      ],
      color: '#2D6BE4',
      width: 4,
      zoomCreated: 3,
    };
    const svg = renderOgOverlay(input({ strokes: [stroke], level: 3 }));
    expect(svg).toContain('<path d="M20 10L40 30"');
    expect(svg).toContain('stroke="#2D6BE4"');
    // 그린 줌과 보는 줌이 같으면 보정 없이 원래 굵기다.
    expect(svg).toContain('stroke-width="4"');
  });

  it('점이 하나뿐인 획은 그리지 않는다', () => {
    const svg = renderOgOverlay(
      input({
        strokes: [{ id: 'k1', path: [{ lat: 1, lng: 2 }], color: '#000', width: 4, zoomCreated: 3 }],
      }),
    );
    expect(svg).not.toContain('<path');
  });

  it('연결선과 화살표를 끄면 그리지 않는다', () => {
    const stops: Stop[] = [
      { id: 's1', candidates: [place('a', 0, 0), place('b', 0, 200)] },
      { id: 's2', candidates: [place('c', 400, 400)] },
    ];
    const on = renderOgOverlay(input({ stops }));
    expect(on).toContain('stroke-dasharray');
    expect(on).toContain('<polygon');

    const off = renderOgOverlay(input({ stops, showCandidateLinks: false, showStopArrows: false }));
    expect(off).not.toContain('stroke-dasharray');
    expect(off).not.toContain('<polygon');
  });

  it('메모는 흰 배경 상자와 함께 그린다', () => {
    const label: MapLabel = {
      id: 'l1',
      location: { lat: 100, lng: 200 },
      text: '여기서 만나',
      fontSize: 14,
      color: '#2C2C2A',
    };
    const svg = renderOgOverlay(input({ labels: [label] }));
    expect(svg).toContain('<rect');
    expect(svg).toContain('여기서 만나');
  });

  it('사용자가 넣은 글자의 XML 특수문자를 이스케이프한다', () => {
    // 이스케이프하지 않으면 SVG가 깨져 썸네일 전체가 생성 실패한다.
    const svg = renderOgOverlay(
      input({
        labels: [
          {
            id: 'l1',
            location: { lat: 1, lng: 2 },
            text: '<script>&"\'',
            fontSize: 14,
            color: '#2C2C2A',
          },
        ],
      }),
    );
    expect(svg).toContain('&lt;script&gt;&amp;&quot;&apos;');
    expect(svg).not.toContain('<script>');
  });

  it('가게 이름은 지도 위에서 읽히도록 흰 테두리를 덧그린다', () => {
    const svg = renderOgOverlay(
      input({ stops: [{ id: 's1', candidates: [place('a', 100, 200)] }] }),
    );
    expect(svg).toContain('stroke="rgba(255,255,255,0.9)"');
    // 테두리용과 본문용 두 번 그린다.
    expect(svg.match(/가게a/g)).toHaveLength(2);
  });
});
