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

/**
 * 꾹 누르기로 인정하는 시간.
 *
 * 450ms로 뒀더니 실기기에서 그냥 톡 누른 것도 메뉴가 떴다. 손가락으로 지도의 한 점을
 * 겨냥해 누르는 동작은 마우스 클릭보다 느려서 300~500ms가 예사다. 눌러야 뜬다는 걸
 * 몸으로 알 만큼은 길어야 하고, 기다린다는 느낌이 들 만큼 길면 안 된다.
 */
const DEFAULT_DELAY_MS = 650;

/**
 * 손가락이 이만큼 움직이면 지도를 끄는 중으로 본다.
 *
 * 8px은 너무 빡빡했다. 마우스와 달리 손가락은 가만히 누르고 있어도 몇 픽셀씩 떤다.
 */
const DEFAULT_MOVE_TOLERANCE_PX = 14;

export function useLongPress({
  target,
  delayMs = DEFAULT_DELAY_MS,
  moveTolerancePx = DEFAULT_MOVE_TOLERANCE_PX,
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
    let capturing = false;
    /**
     * 화면에 닿아 있는 손가락들.
     *
     * 두 손가락으로 확대·축소하면 각 손가락은 제자리에서 벌어지기만 해서 이동 허용치에
     * 안 걸린다. 그래서 줌이 끝나고 손을 떼는 순간 메뉴가 떴다. 꾹 누르기는 손가락
     * 하나짜리 동작이므로 둘째가 닿는 순간 취소한다.
     */
    const active = new Set<number>();

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

      active.add(event.pointerId);
      // 손가락이 둘 이상이면 확대·축소다. 이미 재던 것도 없던 일로 한다.
      if (active.size > 1) {
        clear();
        return;
      }

      const point = localPoint(event);

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
        timer = null;
        // CSS로 막아도 눌리기 전에 잡힌 선택이 남아 있을 수 있다. 메뉴를 띄우기 전에 지운다.
        window.getSelection()?.removeAllRanges();
        handlers.current.onLongPress(point);
      }, delayMs);
    };

    const onMove = (event: PointerEvent) => {
      if (!start || active.size > 1) return;
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
      active.delete(event.pointerId);
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
    /**
     * 지도 위에서는 브라우저 기본 메뉴를 언제나 막는다.
     *
     * 예전에는 우리 메뉴가 뜬 뒤(fired)에만 막았다. 그때는 우리가 450ms로 먼저
     * 떴으니 그걸로 충분했다. 지금은 650ms라 안드로이드 크롬의 기본 길게 누르기
     * (대략 500ms)가 **먼저** 뜬다. 조건을 두면 남의 메뉴가 우리 메뉴를 덮는다.
     */
    const onContextMenu = (event: Event) => {
      event.preventDefault();
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
