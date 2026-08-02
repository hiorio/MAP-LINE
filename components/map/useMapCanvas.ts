'use client';

import { useCallback, useEffect, useRef } from 'react';
import type { Point } from '@/lib/geo/rdp';
import { drawScene, type Scene } from '@/lib/render/scene';
import type { LatLng } from '@/lib/map/types';

/**
 * 지도 위 캔버스 오버레이의 공통 동작.
 *
 * 편집기와 뷰어가 같은 그림을 보여줘야 하므로 렌더와 좌표 동기화는 한곳에 둔다.
 * 편집기는 여기에 입력 처리만 얹고, 뷰어는 이 훅만 쓴다.
 */
interface Options {
  map: kakao.maps.Map | null;
  scene: Scene;
  /** drawScene 뒤에 덧그릴 것이 있으면. 편집 중인 획이 여기로 온다. */
  afterDraw?: (ctx: CanvasRenderingContext2D) => void;
}

export function useMapCanvas({ map, scene, afterDraw }: Options) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const anchorRef = useRef<{ coord: LatLng; point: Point } | null>(null);
  const dprRef = useRef(1);
  const followQueuedRef = useRef(false);

  const toScreen = useCallback(
    (coord: LatLng): Point => {
      const p = map!
        .getProjection()
        .containerPointFromCoords(new kakao.maps.LatLng(coord.lat, coord.lng));
      return { x: p.x, y: p.y };
    },
    [map],
  );

  const toCoord = useCallback(
    (point: Point): LatLng => {
      const ll = map!
        .getProjection()
        .coordsFromContainerPoint(new kakao.maps.Point(point.x, point.y));
      return { lat: ll.getLat(), lng: ll.getLng() };
    },
    [map],
  );

  const afterDrawRef = useRef(afterDraw);
  afterDrawRef.current = afterDraw;

  const redraw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || !map) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = dprRef.current;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, canvas.clientWidth, canvas.clientHeight);

    drawScene(ctx, scene, toScreen, map.getLevel());
    afterDrawRef.current?.(ctx);
  }, [map, scene, toScreen]);

  const redrawRef = useRef(redraw);
  redrawRef.current = redraw;

  /* 백버퍼를 dpr배로 잡고 컨텍스트를 scale하지 않으면 레티나에서 선이 흐릿하다. */
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const resize = () => {
      const parent = canvas.parentElement;
      if (!parent) return;
      const dpr = window.devicePixelRatio || 1;
      dprRef.current = dpr;
      canvas.width = Math.round(parent.clientWidth * dpr);
      canvas.height = Math.round(parent.clientHeight * dpr);
      canvas.style.width = `${parent.clientWidth}px`;
      canvas.style.height = `${parent.clientHeight}px`;
      redrawRef.current();
    };

    resize();
    const observer = new ResizeObserver(resize);
    if (canvas.parentElement) observer.observe(canvas.parentElement);
    window.addEventListener('resize', resize);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', resize);
    };
  }, []);

  /* 팬 중에 모든 좌표를 재투영하면 프레임이 무너진다. 기준 좌표 하나의 이동량만 계산해
     캔버스를 통째로 밀고, idle에서 transform을 지우고 정확히 다시 그린다.
     줌 중에는 축척이 바뀌어 transform 근사가 성립하지 않으므로 아예 숨긴다. */
  useEffect(() => {
    if (!map) return;
    const canvas = canvasRef.current;
    if (!canvas) return;

    const captureAnchor = () => {
      const center = map.getCenter();
      const coord = { lat: center.getLat(), lng: center.getLng() };
      anchorRef.current = { coord, point: toScreen(coord) };
    };

    const onCenterChanged = () => {
      if (followQueuedRef.current) return;
      followQueuedRef.current = true;
      requestAnimationFrame(() => {
        followQueuedRef.current = false;
        const anchor = anchorRef.current;
        if (!anchor) return;
        const now = toScreen(anchor.coord);
        canvas.style.transform = `translate3d(${now.x - anchor.point.x}px, ${now.y - anchor.point.y}px, 0)`;
      });
    };

    const onZoomStart = () => {
      canvas.style.opacity = '0';
    };

    const onIdle = () => {
      canvas.style.transform = '';
      canvas.style.opacity = '1';
      captureAnchor();
      redrawRef.current();
    };

    captureAnchor();
    redrawRef.current();

    kakao.maps.event.addListener(map, 'center_changed', onCenterChanged);
    kakao.maps.event.addListener(map, 'zoom_start', onZoomStart);
    kakao.maps.event.addListener(map, 'idle', onIdle);
    return () => {
      kakao.maps.event.removeListener(map, 'center_changed', onCenterChanged);
      kakao.maps.event.removeListener(map, 'zoom_start', onZoomStart);
      kakao.maps.event.removeListener(map, 'idle', onIdle);
    };
  }, [map, toScreen]);

  useEffect(() => {
    redraw();
  }, [redraw]);

  return { canvasRef, toScreen, toCoord, redraw };
}
