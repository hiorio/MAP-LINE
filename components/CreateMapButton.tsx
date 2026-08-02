'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { createSlug } from '@/lib/slug';

export function CreateMapButton() {
  const router = useRouter();
  const [pending, setPending] = useState(false);

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        setPending(true);
        router.push(`/edit/${createSlug()}`);
      }}
      className="inline-flex h-12 items-center rounded-xl bg-ink px-6 text-base font-medium text-white disabled:opacity-60"
    >
      {pending ? '여는 중…' : '지도 만들기'}
    </button>
  );
}
