'use client';

import { useMapStore } from '@/store/useMapStore';

/**
 * 지도 위에 떠 있는 검색 진입점.
 *
 * 하단 툴바에 두면 모드 버튼들과 섞여 "검색도 하나의 모드"처럼 보인다. 검색은 모드가
 * 아니라 별개의 동작이고, 지도 앱을 써 본 사람은 검색창을 화면 위쪽에서 찾는다.
 */
export function SearchBar({ onOpen }: { onOpen: () => void }) {
  const count = useMapStore((s) => s.places.length);

  return (
    <button
      type="button"
      onClick={onOpen}
      className="absolute inset-x-3 top-3 z-20 flex h-11 items-center gap-2 rounded-full border border-hairline bg-white/95 px-4 text-left shadow-md backdrop-blur-sm sm:max-w-sm"
    >
      <span aria-hidden>🔍</span>
      <span className="flex-1 truncate text-sm text-ink/45">장소 검색 또는 붙여넣기</span>
      {count > 0 && (
        <span className="shrink-0 rounded-full bg-ink/10 px-2 py-0.5 text-xs tabular-nums text-ink/55">
          {count}곳
        </span>
      )}
    </button>
  );
}
