import { CreateMapButton } from '@/components/CreateMapButton';
import { DemoMap } from '@/components/DemoMap';

/**
 * 설계안 §7.1 — 데모 지도 + CTA 단일 버튼.
 *
 * 버튼을 하나만 두는 이유: 이 화면의 목적은 설명이 아니라 편집기로 넘기는 것 하나다.
 * 선택지를 늘리면 그만큼 넘어가는 사람이 준다.
 */
const STEPS = [
  { label: '장소를 담고', detail: '검색하거나 지도를 직접 찍어서' },
  { label: '길을 그리고', detail: '골목, 계단, 들어가는 방향까지' },
  { label: '링크로 보냅니다', detail: '받는 사람은 앱 설치도 로그인도 필요 없이' },
];

export default function LandingPage() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-lg flex-col gap-8 px-5 py-12 sm:py-16">
      <header className="space-y-4">
        <p className="text-xs font-medium tracking-[0.2em] text-ink/35">MAP-LINE</p>
        <h1 className="text-[28px] font-semibold leading-[1.35] sm:text-3xl">
          손으로 그린 지도를
          <br />
          링크 하나로 공유합니다.
        </h1>
        <p className="text-[15px] leading-relaxed text-ink/60">
          핀 몇 개로는 &ldquo;이 골목 들어가서 두 번째 집&rdquo;이 전해지지 않습니다.
          <br className="hidden sm:block" /> 지도 위에 그대로 그려서 보내세요.
        </p>
      </header>

      <div className="overflow-hidden rounded-xl border border-hairline bg-white p-2 shadow-sm">
        <DemoMap />
      </div>

      <CreateMapButton />

      <ol className="space-y-3 border-t border-hairline pt-6">
        {STEPS.map(({ label, detail }, index) => (
          <li key={label} className="flex gap-3">
            <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full bg-ink/10 text-[11px] font-semibold text-ink/50">
              {index + 1}
            </span>
            <p className="text-sm leading-relaxed">
              <span className="font-medium">{label}</span>
              <span className="text-ink/50"> — {detail}</span>
            </p>
          </li>
        ))}
      </ol>

      <footer className="mt-auto pt-6 text-xs text-ink/35">
        지도 데이터 © Kakao
      </footer>
    </main>
  );
}
