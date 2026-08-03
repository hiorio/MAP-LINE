'use client';

import { useEffect, useRef, useState } from 'react';
import { loadKakaoMaps } from '@/lib/kakao/loadSdk';
import type { LatLng } from '@/lib/map/types';

interface KakaoMapProps {
  center: LatLng;
  level: number;
  onReady: (map: kakao.maps.Map) => void;
  /**
   * 지도 타일이 들어 있는 요소. 꾹 누르기 감지가 여기에 붙는다.
   * 캔버스가 아니라 이 요소여야 지도의 팬·줌을 막지 않고 지켜볼 수 있다.
   */
  onContainer?: (container: HTMLDivElement | null) => void;
}

export function KakaoMap({ center, level, onReady, onContainer }: KakaoMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const onReadyRef = useRef(onReady);
  const [error, setError] = useState<string | null>(null);

  onReadyRef.current = onReady;

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    let cancelled = false;
    loadKakaoMaps(process.env.NEXT_PUBLIC_KAKAO_JS_KEY ?? '')
      .then((maps) => {
        if (cancelled) return;
        const map = new maps.Map(container, {
          center: new maps.LatLng(center.lat, center.lng),
          level,
        });
        onReadyRef.current(map);
      })
      .catch((cause: Error) => {
        if (!cancelled) setError(cause.message);
      });

    return () => {
      cancelled = true;
    };
    // 지도는 한 번만 만든다. 이후 center/level 변경은 map 인스턴스로 직접 다룬다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (error) {
    return (
      <div className="absolute inset-0 z-0 grid place-items-center bg-paper p-6">
        <div className="max-w-sm space-y-2 text-center">
          <p className="text-sm font-medium">지도를 불러오지 못했습니다.</p>
          <p className="text-xs text-ink/60">{error}</p>
          <p className="text-xs text-ink/40">
            카카오 콘솔 &gt; 앱 &gt; 플랫폼 키 &gt; JavaScript 키의 SDK 도메인에 현재 주소가
            등록돼 있는지 확인하세요.
          </p>
        </div>
      </div>
    );
  }

  /* z-index를 명시하는 이유:
     카카오 SDK는 이 컨테이너 안에 z-index가 붙은 레이어를 여러 개 만든다. 컨테이너가
     z-index:auto면 그 자식들이 상위 스태킹 컨텍스트에 그대로 참여해 드로잉 캔버스보다
     위에 깔리고, 그리기 모드에서 pointerdown이 캔버스에 닿지 않는다. W0에서 실제로 겪었다.

     선택 관련 속성을 끄는 이유:
     지도를 꾹 누르면 브라우저가 그 자리의 글자를 드래그 선택으로 잡아 파랗게 칠한다.
     카카오가 지명·상호를 DOM 텍스트로 그리기 때문이다. 웹뷰의 한계가 아니라 어느
     브라우저에서나 나오는 기본 동작이고, 아래 네 줄로 전부 막힌다.
     - user-select: 글자 선택 자체
     - -webkit-user-select: iOS/안드로이드 웹뷰는 접두사 붙은 쪽을 본다
     - -webkit-touch-callout: 길게 눌렀을 때 뜨는 "복사/공유" 팝업
     - -webkit-tap-highlight-color: 탭할 때 잠깐 덮이는 회색 사각형

     touch-action: none을 주는 이유:
     카카오 SDK는 팬·줌을 직접 구현한다. 브라우저에게도 기본 터치 동작이 남아 있으면
     두 손가락 제스처를 브라우저가 가로채 페이지 전체를 확대해 버린다. 지도 라이브러리가
     흔히 쓰는 방법대로 이 영역의 기본 터치 동작을 전부 넘겨받는다. */
  return (
    <div
      ref={(node) => {
        containerRef.current = node;
        onContainer?.(node);
      }}
      className="absolute inset-0 z-0 touch-none select-none [-webkit-touch-callout:none] [-webkit-user-select:none] [-webkit-tap-highlight-color:transparent]"
    />
  );
}
