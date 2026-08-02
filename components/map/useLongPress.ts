'use client';

import { useEffect, useRef } from 'react';
import type { Point } from '@/lib/geo/rdp';

/**
 * 지도 위에서 "꾹 누르기"를 감지한다.
 *
 * 이동이 기본 상태여야 하므로 지도의 팬·줌을 절대 방해하면 안 된다. 그래서 캔버스가
 * 아니라 지도 컨테이너에 붙되 `preventDefault`도 `stopPropagation`도 하지 않고
 * 지켜보기만 한다. 손가락이 일정 거리 이상 움직이면 팬으로 보고 취소한다.
 *
 * 예외는 `shouldCapture`가 참을 돌려줄 때다. 이미 놓인 라벨을 짚은 경우가 그렇고,
 * 그때는 이벤트를 가로채 지도가 따라 움직이지 않게 한다.
 */
interface Options {
  /** 지도 컨테이너. 여기에 리스너를 건다. */
  target: HTMLElement | null;
  delayMs?: number;
  moveTolerancePx?: number;
  onLongPress: (point: Point) => void;
  /** 참이면 이 지점의 입력을 지도 대신 우리가 처리한다. */
  shouldCapture?: (point: Point) => boolean;
  onCapturedDown?: (point: Point) => void;
  onCapturedMove?: (point: Point) => void;
  onCapturedUp?: (point: Point) => void;
}

export function useLongPress({
  target,
  delayMs = 450,
  moveTolerancePx = 8,
  onLongPress,
  shouldCapture,
  onCapturedDown,
  onCapturedMove,
  onCapturedUp,
}: Options) {
  // 리스너를 매번 다시 걸지 않도록 최신 콜백을 ref에 담아 둔다.
  const handlers = useRef({
    onLongPress,
    shouldCapture,
    onCapturedDown,
    onCapturedMove,
    onCapturedUp,
  });
  handlers.current = { onLongPress, shouldCapture, onCapturedDown, onCapturedMove, onCapturedUp };

  useEffect(() => {
    if (!target) return;

    let timer: ReturnType<typeof setTimeout> | null = null;
    let start: Point | null = null;
    let fired = false;
    let capturing = false;

    const localPoint = (event: PointerEvent): Point => {
      const rect = target.getBoundingClientRect();
      return { x: event.clientX - rect.left, y: event.clientY - rect.top };
    };

    const clear = () => {
      if (timer) clearTimeout(timer);
      timer = null;
      start = null;
      capturing = false;
    };

    const onDown = (event: PointerEvent) => {
      // 마우스는 왼쪽 버튼만. 오른쪽 클릭은 브라우저 메뉴에 맡긴다.
      if (event.pointerType === 'mouse' && event.button !== 0) return;

      const point = localPoint(event);
      fired = false;

      if (handlers.current.shouldCapture?.(point)) {
        capturing = true;
        start = point;
        // 지도가 따라 움직이면 라벨을 끌 수 없다.
        event.preventDefault();
        event.stopPropagation();
        handlers.current.onCapturedDown?.(point);
        return;
      }

      start = point;
      timer = setTimeout(() => {
        fired = true;
        timer = null;
        handlers.current.onLongPress(point);
      }, delayMs);
    };

    const onMove = (event: PointerEvent) => {
      if (!start) return;
      const point = localPoint(event);

      if (capturing) {
        event.preventDefault();
        event.stopPropagation();
        handlers.current.onCapturedMove?.(point);
        return;
      }

      // 지도를 끄는 중이면 꾹 누르기가 아니다.
      if (Math.hypot(point.x - start.x, point.y - start.y) > moveTolerancePx) {
        if (timer) clearTimeout(timer);
        timer = null;
        start = null;
      }
    };

    const onUp = (event: PointerEvent) => {
      if (capturing) {
        event.preventDefault();
        event.stopPropagation();
        handlers.current.onCapturedUp?.(localPoint(event));
      }
      clear();
    };

    // 캡처 단계에서 받아야 지도 SDK보다 먼저 판단할 수 있다.
    const options = { capture: true } as const;
    target.addEventListener('pointerdown', onDown, options);
    target.addEventListener('pointermove', onMove, options);
    target.addEventListener('pointerup', onUp, options);
    target.addEventListener('pointercancel', onUp, options);
    // 꾹 눌러 컨텍스트 메뉴가 뜬 뒤 브라우저 기본 메뉴까지 뜨면 겹친다.
    const onContextMenu = (event: Event) => {
      if (fired) event.preventDefault();
    };
    target.addEventListener('contextmenu', onContextMenu);

    return () => {
      clear();
      target.removeEventListener('pointerdown', onDown, options);
      target.removeEventListener('pointermove', onMove, options);
      target.removeEventListener('pointerup', onUp, options);
      target.removeEventListener('pointercancel', onUp, options);
      target.removeEventListener('contextmenu', onContextMenu);
    };
  }, [target, delayMs, moveTolerancePx]);
}
