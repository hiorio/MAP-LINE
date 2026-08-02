'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { storeEditToken } from '@/lib/map/persistence';
import { createSlug } from '@/lib/slug';

/**
 * 서버에 지도를 만들고 편집 토큰을 받아 둔다.
 * Supabase가 아직 없으면 클라이언트에서 슬러그만 만들어 로컬 전용으로 편집한다.
 */
async function createMap(): Promise<string> {
  try {
    const response = await fetch('/api/maps', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    if (response.ok) {
      const { slug, editToken } = (await response.json()) as { slug: string; editToken: string };
      storeEditToken(slug, editToken);
      return slug;
    }
  } catch {
    // 로컬 폴백
  }
  return createSlug();
}

export function CreateMapButton() {
  const router = useRouter();
  const [pending, setPending] = useState(false);

  return (
    <button
      type="button"
      disabled={pending}
      onClick={async () => {
        setPending(true);
        router.push(`/edit/${await createMap()}`);
      }}
      className="inline-flex h-12 items-center rounded-xl bg-ink px-6 text-base font-medium text-white disabled:opacity-60"
    >
      {pending ? '여는 중…' : '지도 만들기'}
    </button>
  );
}
