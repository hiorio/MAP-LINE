import Link from 'next/link';
import { CreateMapButton } from '@/components/CreateMapButton';

export default function LandingPage() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-2xl flex-col justify-center gap-10 px-6 py-20">
      <header className="space-y-4">
        <p className="text-sm tracking-widest text-ink/40">MAP-LINE v0.1</p>
        <h1 className="text-3xl font-semibold leading-snug">
          손으로 그린 지도를
          <br />
          링크 하나로 공유합니다.
        </h1>
        <p className="text-ink/60">
          핀 몇 개로는 &ldquo;이 골목 들어가서 두 번째 집&rdquo;이 표현되지 않습니다. 선과 맥락을
          그대로 그려서 보내세요.
        </p>
      </header>

      <CreateMapButton />

      <section className="rounded-xl border border-hairline bg-white p-5 text-sm">
        <h2 className="font-semibold">개발 중</h2>
        <p className="mt-2 text-ink/60">
          장소 검색·핀 순서·연결선·공유 링크는 아직 붙지 않았습니다. 현재 편집기에서 되는 것은
          손그림과 텍스트 라벨이며, 작업 내용은 브라우저에 자동 저장됩니다.
        </p>
        <Link
          href="/prototype/draw.html"
          className="mt-3 inline-block text-ink/50 underline underline-offset-4"
        >
          W0 드로잉 프로토타입 →
        </Link>
      </section>
    </main>
  );
}
