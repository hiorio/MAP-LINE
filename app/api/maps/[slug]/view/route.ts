import { NextResponse } from 'next/server';
import { getServiceClient } from '@/lib/supabase/server';

/**
 * 조회수 +1.
 *
 * 서버 컴포넌트에서 세지 않고 브라우저에서 한 번 호출하게 한 이유: Next.js의 링크
 * 프리페치와 크롤러가 페이지를 미리 받아 가면 실제로 본 적 없는 조회가 잡힌다.
 * 설계안 §1.4의 핵심 지표라 부풀리면 곤란하다.
 */
export async function POST(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const supabase = getServiceClient();
  if (!supabase) return NextResponse.json({ counted: false });

  const { slug } = await params;
  const { error } = await supabase.rpc('increment_map_view', { p_slug: slug });

  if (error) {
    // 조회수는 부가 정보다. 실패해도 뷰어가 깨지면 안 된다.
    console.error('[api/maps/:slug/view]', error);
    return NextResponse.json({ counted: false });
  }
  return NextResponse.json({ counted: true });
}
