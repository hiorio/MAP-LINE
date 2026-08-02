import { createClient, type SupabaseClient } from '@supabase/supabase-js';

/**
 * 서버 전용 Supabase 클라이언트.
 *
 * service role 키는 RLS를 통과하므로 **절대 클라이언트로 새어 나가면 안 된다.**
 * 이 모듈은 Route Handler에서만 import한다.
 *
 * Supabase 프로젝트가 아직 없을 수도 있으므로 설정이 없으면 null을 반환한다.
 * 호출부는 이 경우 503을 돌려주고, 편집기는 로컬 저장으로 물러난다.
 */
let cached: SupabaseClient | null = null;

export function getServiceClient(): SupabaseClient | null {
  if (cached) return cached;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;

  cached = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cached;
}

export function isSupabaseConfigured(): boolean {
  return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}
