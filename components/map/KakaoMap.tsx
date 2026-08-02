'use client';

import { useEffect, useRef, useState } from 'react';
import { loadKakaoMaps } from '@/lib/kakao/loadSdk';
import type { LatLng } from '@/lib/map/types';

interface KakaoMapProps {
  center: LatLng;
  level: number;
  onReady: (map: kakao.maps.Map) => void;
}

export function KakaoMap({ center, level, onReady }: KakaoMapProps) {
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
     위에 깔리고, 그리기 모드에서 pointerdown이 캔버스에 닿지 않는다. W0에서 실제로 겪었다. */
  return <div ref={containerRef} className="absolute inset-0 z-0" />;
}
