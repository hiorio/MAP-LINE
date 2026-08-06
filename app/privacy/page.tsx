import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: '개인정보 처리방침',
  description: '도화지 앱과 웹 서비스의 개인정보 처리방침입니다.',
};

const UPDATED_AT = '2026년 8월 6일';

export default function PrivacyPage() {
  return (
    <main className="mx-auto min-h-dvh max-w-2xl px-5 py-10 sm:px-8 sm:py-16">
      <header className="mb-10 border-b border-hairline pb-7">
        <Link href="/" className="text-xs font-semibold tracking-[0.18em] text-ink/45">
          도화지
        </Link>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">개인정보 처리방침</h1>
        <p className="mt-3 text-sm text-ink/50">시행 및 최종 수정: {UPDATED_AT}</p>
      </header>

      <article className="space-y-9 text-[15px] leading-7 text-ink/75">
        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">1. 기본 원칙</h2>
          <p>
            도화지는 계정 가입 없이 사용할 수 있으며 광고, 사용자 추적, 개인정보 판매를 하지
            않습니다. 서비스 제공에 필요한 최소한의 지도 콘텐츠만 처리합니다.
          </p>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">2. 처리하는 정보</h2>
          <ul className="list-disc space-y-2 pl-5">
            <li>
              사용자가 공유 지도를 만들면 지도 이름, 장소 이름과 좌표, 메모, 손그림, 단계와
              이동 경로가 공유 링크를 제공하기 위해 서버에 저장됩니다.
            </li>
            <li>
              장소 검색, 주소 해석, 경로 및 중간지점 계산에 입력한 검색어와 좌표는 결과를
              제공하기 위해 서버와 지도 서비스 제공자에게 전송됩니다. 도화지는 이를 사용자
              계정과 연결해 프로필로 만들지 않습니다.
            </li>
            <li>
              현재 위치는 사용자가 현재 위치 버튼을 누를 때 기기에서 한 번 확인하여 지도 화면을
              이동하는 데만 사용합니다. 지속적으로 추적하거나 현재 위치 자체를 서버에 저장하지
              않습니다.
            </li>
            <li>
              보관함, 자동 초안, 중간지점 검색 기록은 사용자의 기기에 저장됩니다. 사용자가 공유
              지도로 저장하기 전에는 도화지 서버로 전송되지 않습니다.
            </li>
          </ul>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">3. 이용 목적</h2>
          <p>
            처리한 정보는 지도 생성·저장·공유, 장소 검색, 이동 경로와 중간지점 계산, 서비스 보안과
            안정적인 운영에만 사용합니다. 맞춤 광고나 타사 마케팅에는 사용하지 않습니다.
          </p>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">4. 공유 링크와 보관 기간</h2>
          <p>
            공유 지도는 링크를 아는 사람이 볼 수 있으므로 민감한 정보를 메모나 지도 이름에 넣지
            마세요. 서버에 저장된 공유 지도는 사용자가 앱에서 삭제할 때까지 보관되며, 삭제하면
            서비스 데이터에서 제거됩니다. 기기에 저장된 보관함과 기록은 앱을 삭제하거나 해당
            항목을 직접 삭제하면 제거됩니다.
          </p>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">5. 서비스 제공자</h2>
          <p>
            지도 표시와 장소·경로 검색에는 Kakao Maps, 데이터 저장에는 Supabase, 서비스 운영에는
            Railway를 사용합니다. 각 제공자는 서비스 제공 과정에서 자신의 개인정보 처리방침과
            보안 기준에 따라 정보를 처리할 수 있습니다.
          </p>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">6. 이용자의 선택과 문의</h2>
          <p>
            위치 권한은 iOS 설정에서 언제든 철회할 수 있습니다. 도화지는 계정을 만들지 않으므로
            별도의 계정 삭제 절차가 없습니다. 삭제나 개인정보 관련 요청은{' '}
            <Link href="/support" className="font-medium text-coral underline underline-offset-4">
              지원 페이지
            </Link>
            를 통해 접수해 주세요.
          </p>
        </section>

        <section>
          <h2 className="mb-3 text-lg font-semibold text-ink">7. 방침 변경</h2>
          <p>
            기능이나 처리 방식이 바뀌면 이 페이지의 내용과 수정일을 갱신합니다. 중요한 변경은 앱
            또는 서비스 화면을 통해 안내합니다.
          </p>
        </section>
      </article>
    </main>
  );
}
