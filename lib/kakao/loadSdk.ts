const SDK_ORIGIN = 'https://dapi.kakao.com/v2/maps/sdk.js';

let pending: Promise<typeof kakao.maps> | null = null;

/**
 * 카카오 지도 SDK를 한 번만 로드한다.
 *
 * `autoload=false`로 받아 `kakao.maps.load()` 콜백까지 기다린 뒤 resolve한다.
 * 이걸 안 하면 script onload 시점에 `kakao.maps.Map`이 아직 없어서 터진다.
 */
export function loadKakaoMaps(appKey: string): Promise<typeof kakao.maps> {
  if (typeof window === 'undefined') {
    return Promise.reject(new Error('SDK는 브라우저에서만 로드할 수 있습니다.'));
  }
  if (window.kakao?.maps?.Map) {
    return Promise.resolve(window.kakao.maps);
  }
  if (!appKey) {
    return Promise.reject(
      new Error('NEXT_PUBLIC_KAKAO_JS_KEY가 비어 있습니다. .env.local을 확인하세요.'),
    );
  }

  pending ??= new Promise<typeof kakao.maps>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = `${SDK_ORIGIN}?autoload=false&appkey=${encodeURIComponent(appKey)}`;
    script.async = true;
    script.onload = () => {
      const maps = window.kakao?.maps;
      if (!maps) {
        pending = null;
        reject(new Error('SDK를 불러왔지만 kakao.maps가 없습니다.'));
        return;
      }
      maps.load(() => resolve(maps));
    };
    script.onerror = () => {
      // 다음 시도에서 다시 붙일 수 있도록 캐시를 비운다.
      pending = null;
      script.remove();
      reject(
        new Error(
          '카카오 지도 SDK를 불러오지 못했습니다. JavaScript 키와 등록된 SDK 도메인을 확인하세요.',
        ),
      );
    };
    document.head.appendChild(script);
  });

  return pending;
}
