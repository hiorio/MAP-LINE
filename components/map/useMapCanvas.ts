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
  /** 핀치가 시작된 순간의 두 손가락 사이 거리와 중점. 진행 중이 아니면 null이다. */
  const pinchRef = useRef<{ distance: number; mid: Point } | null>(null);

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

     확대·축소는 사정이 다르다. `getProjection()`은 애니메이션 도중에도 목적지 값을
     즉시 돌려준다. 카카오가 타일을 CSS로만 늘리고 있기 때문인데, 그래서 SDK만으로는
     중간 프레임의 좌표를 알 방법이 없다. 대신 두 손가락 사이 거리로 배율을 직접 재서
     캔버스에 같은 transform을 건다. 카카오가 타일에 하는 일을 그대로 따라 하는 셈이다.

     버튼이나 더블탭으로 줌하는 경우에는 우리가 배율을 알 수 없다(카카오의 애니메이션
     곡선을 모른다). 그때는 지금까지처럼 숨겼다가 끝나고 다시 그린다. 어긋난 선을
     보여 주는 것보다 잠깐 없는 편이 낫다. */
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
      // 핀치 중에는 우리가 배율까지 포함해 직접 그리고 있다. 덮어쓰면 안 된다.
      if (pinchRef.current || followQueuedRef.current) return;
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
      // 핀치를 놓은 뒤 정착 애니메이션에도 이게 온다. 그때는 이미 손을 뗀 뒤다.
      if (pinchRef.current) return;
      canvas.style.opacity = '0';
    };

    const onIdle = () => {
      canvas.style.transform = '';
      canvas.style.transformOrigin = '';
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

  /* 두 손가락으로 확대·축소하는 동안 캔버스를 같은 배율로 늘린다. */
  useEffect(() => {
    if (!map) return;
    const canvas = canvasRef.current;
    const node = map.getNode();
    if (!canvas || !node) return;

    const touches = new Map<number, Point>();

    const local = (event: PointerEvent): Point => {
      const rect = node.getBoundingClientRect();
      return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    };

    const spread = () => {
      const [a, b] = [...touches.values()];
      if (!a || !b) return null;
      return {
        distance: Math.hypot(b.x - a.x, b.y - a.y),
        mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 },
      };
    };

    const onDown = (event: PointerEvent) => {
      touches.set(event.pointerId, local(event));
      if (touches.size !== 2) return;
      const now = spread();
      // 두 손가락이 겹쳐 놓이면 배율이 무한대가 된다.
      if (now && now.distance > 1) pinchRef.current = now;
    };

    const onMove = (event: PointerEvent) => {
      if (!touches.has(event.pointerId)) return;
      touches.set(event.pointerId, local(event));

      const start = pinchRef.current;
      if (touches.size !== 2 || !start) return;
      const now = spread();
      if (!now) return;

      const scale = now.distance / start.distance;
      const dx = now.mid.x - start.mid.x;
      const dy = now.mid.y - start.mid.y;
      // 벌린 지점을 중심으로 늘려야 손가락 밑의 지형이 제자리에 남는다.
      canvas.style.transformOrigin = `${start.mid.x}px ${start.mid.y}px`;
      canvas.style.transform = `translate3d(${dx}px, ${dy}px, 0) scale(${scale})`;
    };

    const onUp = (event: PointerEvent) => {
      touches.delete(event.pointerId);
      if (touches.size >= 2) return;
      // transform은 여기서 지우지 않는다. 지도가 정착하기 전에 지우면 한 번 튄다.
      // idle이 오면 그때 지우고 정확히 다시 그린다.
      pinchRef.current = null;
    };

    const options = { capture: true, passive: true } as const;
    node.addEventListener('pointerdown', onDown, options);
    node.addEventListener('pointermove', onMove, options);
    node.addEventListener('pointerup', onUp, options);
    node.addEventListener('pointercancel', onUp, options);
    return () => {
      node.removeEventListener('pointerdown', onDown, options);
      node.removeEventListener('pointermove', onMove, options);
      node.removeEventListener('pointerup', onUp, options);
      node.removeEventListener('pointercancel', onUp, options);
    };
  }, [map]);

  useEffect(() => {
    redraw();
  }, [redraw]);

  return { canvasRef, toScreen, toCoord, redraw };
}
