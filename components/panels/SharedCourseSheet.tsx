'use client';

import { buildSharedCourse } from '@/lib/map/courseSummary';
import type { LatLng, Stop, StopLeg } from '@/lib/map/types';

export function SharedCourseSheet({
  stops,
  legs,
  onFocus,
  onClose,
}: {
  stops: readonly Stop[];
  legs: readonly StopLeg[];
  onFocus: (location: LatLng) => void;
  onClose: () => void;
}) {
  const steps = buildSharedCourse(stops, legs);

  return (
    <>
      <button
        type="button"
        aria-label="모임 동선 닫기"
        onClick={onClose}
        className="fixed inset-0 z-40 bg-black/25"
      />
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="shared-course-title"
        className="fixed inset-x-0 bottom-0 z-50 mx-auto max-h-[78dvh] max-w-xl overflow-y-auto rounded-t-2xl bg-white shadow-2xl"
      >
        <header className="sticky top-0 flex items-center gap-3 border-b border-hairline bg-white px-4 py-3">
          <div className="min-w-0 flex-1">
            <h2 id="shared-course-title" className="text-base font-semibold">모임 동선</h2>
            <p className="text-xs text-ink/45">공유한 단계와 후보를 모두 보여 줍니다</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="size-9 rounded-full border border-hairline text-sm"
            aria-label="닫기"
          >
            &#10005;
          </button>
        </header>

        <ol className="divide-y divide-hairline px-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {steps.map((step) => (
            <li key={step.id} className="py-4">
              <div className="flex items-center gap-2">
                <span className="grid size-7 shrink-0 place-items-center rounded-full bg-coral text-xs font-semibold text-white">
                  {step.number}
                </span>
                <strong className="text-sm">후보 {step.candidates.length}곳</strong>
                {step.primaryPending && (
                  <span className="rounded-full bg-coral/10 px-2 py-0.5 text-[11px] text-coral">
                    대표 미정
                  </span>
                )}
              </div>

              <ul className="mt-2 space-y-2 pl-9">
                {step.candidates.map((candidate) => (
                  <li key={candidate.id}>
                    <button
                      type="button"
                      onClick={() => {
                        onFocus(candidate.location);
                        onClose();
                      }}
                      className="w-full rounded-xl border border-hairline px-3 py-2 text-left"
                    >
                      <span className="flex items-center gap-2">
                        <span className="min-w-0 flex-1 truncate text-sm font-medium">
                          {candidate.name}
                        </span>
                        {candidate.isPrimary && (
                          <span className="shrink-0 rounded-full bg-ink px-2 py-0.5 text-[10px] text-white">
                            대표
                          </span>
                        )}
                      </span>
                      {candidate.address && (
                        <span className="mt-0.5 block truncate text-xs text-ink/45">
                          {candidate.address}
                        </span>
                      )}
                      {candidate.memo && (
                        <span className="mt-1 block text-xs text-coral">{candidate.memo}</span>
                      )}
                    </button>
                  </li>
                ))}
              </ul>

              {step.nextLeg && (
                <div className="mt-3 ml-3 border-l-2 border-dashed border-hairline py-1 pl-6 text-xs text-ink/55">
                  <span className="font-medium text-ink">다음 단계까지 {step.nextLeg.label}</span>
                  {step.nextLeg.detail && <span className="ml-2 tabular-nums">{step.nextLeg.detail}</span>}
                  {step.nextLeg.guidance.map((guidance, index) => (
                    <span key={`${guidance}-${index}`} className="ml-1.5 rounded bg-ink/5 px-1.5 py-0.5">
                      {guidance}
                    </span>
                  ))}
                </div>
              )}
            </li>
          ))}
        </ol>
      </section>
    </>
  );
}
