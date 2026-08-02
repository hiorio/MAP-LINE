import 'server-only';
import type { MapDocument } from './types';
import { getServiceClient } from '@/lib/supabase/server';

export interface StoredMapDocument extends MapDocument {
  slug: string;
  viewCount: number;
  updatedAt: string;
  /** Storage에 캐시된 OG 썸네일. 아직 만들지 않았으면 null */
  ogImageUrl: string | null;
  ogUpdatedAt: string | null;
}

/**
 * 서버 컴포넌트에서 지도를 읽는다.
 *
 * 뷰어는 SSR로 OG 메타를 채워야 하므로 자기 자신의 Route Handler를 HTTP로 다시 호출할
 * 이유가 없다. 같은 프로세스 안에서 바로 읽는다.
 */
export async function getMapDocument(slug: string): Promise<StoredMapDocument | null> {
  const supabase = getServiceClient();
  if (!supabase) return null;

  const { data, error } = await supabase.rpc('get_map_document', { p_slug: slug });
  if (error) {
    console.error('[getMapDocument]', error);
    return null;
  }
  return (data as StoredMapDocument | null) ?? null;
}
