import type { MapDocument } from './types';
import { stripNonPersistableRouteCaches } from './persistencePolicy';

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
    // 자동차 길찾기 결과는 브라우저 폴백에도 영구 저장하지 않는다. 서버 저장 실패나
    // 충돌 때 이 경로로 내려와도 사용자가 고른 수단만 남기고 좌표·거리·시간은 버린다.
    const persistable = stripNonPersistableRouteCaches(document);
    window.localStorage.setItem(PREFIX + slug, JSON.stringify(persistable));
  } catch {
    // 용량 초과는 편집을 막을 이유가 되지 않는다. 서버 저장이 붙으면 사라질 경로다.
  }
}
