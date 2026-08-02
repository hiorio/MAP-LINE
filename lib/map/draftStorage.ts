import type { MapDocument } from './types';

/**
 * 서버 저장(T12)이 붙기 전까지 쓰는 로컬 초안 저장소.
 *
 * 저장 형태를 §6.1의 "지도 단위 전체 스냅샷"과 똑같이 맞춰 뒀다. 나중에 이 함수 자리에
 * `PATCH /api/maps/[slug]` 호출을 끼우면 되고, 호출부의 debounce·flush 구조는 그대로 쓴다.
 */
const PREFIX = 'mapline.draft.';

export function loadDraft(slug: string): MapDocument | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.localStorage.getItem(PREFIX + slug);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as MapDocument;
    return Array.isArray(parsed.strokes) ? parsed : null;
  } catch {
    return null;
  }
}

export function saveDraft(slug: string, document: MapDocument): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(PREFIX + slug, JSON.stringify(document));
  } catch {
    // 용량 초과는 편집을 막을 이유가 되지 않는다. 서버 저장이 붙으면 사라질 경로다.
  }
}
