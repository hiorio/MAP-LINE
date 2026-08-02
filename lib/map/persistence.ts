import type { MapDocument } from './types';
import { loadDraft, saveDraft } from './draftStorage';

/**
 * 편집기가 쓰는 단일 저장 인터페이스.
 *
 * 서버(Supabase)가 설정돼 있고 이 슬러그의 편집 토큰을 갖고 있으면 서버에 저장하고,
 * 아니면 브라우저 로컬 초안으로 물러난다. 편집기는 어느 쪽인지 몰라도 된다.
 *
 * 토큰이 사라지면(다른 기기, 저장소 정리) 그 지도는 더 이상 편집할 수 없다.
 * 설계안 §2.1 F8의 "로컬 편집 토큰으로 로그인 없이 재편집"이 감수하는 한계다.
 */
const TOKEN_PREFIX = 'mapline.token.';

export type SaveMode = 'server' | 'local';

export interface LoadedDocument {
  document: MapDocument | null;
  mode: SaveMode;
  /** 낙관적 잠금 기준. 서버에서 읽었을 때만 있다. */
  updatedAt?: string;
}

export function readEditToken(slug: string): string | null {
  if (typeof window === 'undefined') return null;
  try {
    return window.localStorage.getItem(TOKEN_PREFIX + slug);
  } catch {
    return null;
  }
}

export function storeEditToken(slug: string, token: string): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(TOKEN_PREFIX + slug, token);
  } catch {
    // 저장소를 못 쓰면 이 지도는 이번 세션에서만 편집된다.
  }
}

/** 서버에 있으면 서버 것을, 없으면 로컬 초안을 쓴다. */
export async function loadDocument(slug: string): Promise<LoadedDocument> {
  try {
    const response = await fetch(`/api/maps/${slug}`, { cache: 'no-store' });
    if (response.ok) {
      const body = (await response.json()) as MapDocument & { updatedAt?: string };
      return {
        document: body,
        mode: readEditToken(slug) ? 'server' : 'local',
        ...(body.updatedAt ? { updatedAt: body.updatedAt } : {}),
      };
    }
  } catch {
    // 네트워크 실패는 로컬 폴백으로 처리한다.
  }
  return { document: loadDraft(slug), mode: 'local' };
}

export interface SaveResult {
  mode: SaveMode;
  updatedAt?: string;
  /** 다른 곳에서 먼저 저장돼 이번 저장을 버린 경우 */
  conflict?: boolean;
}

export async function saveDocument(
  slug: string,
  document: MapDocument,
  expectedUpdatedAt?: string,
): Promise<SaveResult> {
  const token = readEditToken(slug);

  if (token) {
    try {
      const response = await fetch(`/api/maps/${slug}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', 'X-Edit-Token': token },
        body: JSON.stringify({ document, expectedUpdatedAt: expectedUpdatedAt ?? null }),
      });

      if (response.status === 409) {
        // 덮어쓰면 다른 탭의 작업이 사라진다. 로컬에만 남겨 두고 알린다.
        saveDraft(slug, document);
        return { mode: 'local', conflict: true };
      }
      if (response.ok) {
        const body = (await response.json()) as { updatedAt?: string };
        return { mode: 'server', ...(body.updatedAt ? { updatedAt: body.updatedAt } : {}) };
      }
    } catch {
      // 아래 로컬 저장으로 떨어진다.
    }
  }

  saveDraft(slug, document);
  return { mode: 'local' };
}
