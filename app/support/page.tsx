import type { Metadata } from 'next';
import Link from 'next/link';
import { BrandHomeLink } from '@/components/brand/BrandHomeLink';

export const metadata: Metadata = {
  title: '지원',
  description: '도화지 앱 사용 안내와 문의 방법입니다.',
};

const ISSUE_URL = 'https://github.com/hiorio/MAP-LINE/issues/new';

export default function SupportPage() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-2xl flex-col px-5 py-10 sm:px-8 sm:py-16">
      <header className="mb-10 border-b border-hairline pb-7">
        <BrandHomeLink iconSize={32} nameClassName="text-sm font-semibold tracking-tight" />
        <h1 className="mt-3 text-3xl font-semibold tracking-tight">도움이 필요하신가요?</h1>
        <p className="mt-3 leading-7 text-ink/60">
          지도 저장이나 공유가 예상대로 동작하지 않으면 아래 내용을 먼저 확인해 주세요.
        </p>
      </header>

      <div className="space-y-4">
        <SupportItem
          title="지도가 저장되지 않아요"
          body="인터넷 연결을 확인한 뒤 지도 상단의 저장 상태가 ‘저장됨’으로 바뀌는지 확인해 주세요. 기기에 저장된 초안은 앱을 다시 열면 복원됩니다."
        />
        <SupportItem
          title="현재 위치가 보이지 않아요"
          body="iPhone 설정의 개인정보 보호 및 보안 → 위치 서비스에서 도화지의 위치 접근을 허용해 주세요. 도화지는 버튼을 누를 때만 위치를 한 번 확인합니다."
        />
        <SupportItem
          title="공유 링크는 누가 볼 수 있나요?"
          body="링크를 받은 사람은 앱 설치나 로그인 없이 지도를 볼 수 있습니다. 링크가 전달될 수 있으므로 민감한 내용은 넣지 않는 것이 좋습니다."
        />
      </div>

      <section className="mt-10 rounded-2xl border border-hairline bg-white p-6 shadow-sm">
        <h2 className="text-lg font-semibold">문제 신고 및 문의</h2>
        <p className="mt-2 text-sm leading-6 text-ink/60">
          재현 방법, 사용한 iPhone과 iOS 버전, 문제가 보이는 화면을 함께 남겨 주시면 확인에
          도움이 됩니다. 공개 게시물에 개인 주소나 연락처는 적지 마세요.
        </p>
        <a
          href={ISSUE_URL}
          target="_blank"
          rel="noreferrer"
          className="mt-5 inline-flex min-h-11 items-center justify-center rounded-xl bg-ink px-5 text-sm font-semibold text-white"
        >
          문의 작성하기
        </a>
      </section>

      <footer className="mt-auto pt-10 text-sm text-ink/50">
        <Link href="/privacy" className="underline underline-offset-4">
          개인정보 처리방침
        </Link>
      </footer>
    </main>
  );
}

function SupportItem({ title, body }: { title: string; body: string }) {
  return (
    <section className="rounded-2xl border border-hairline bg-white p-5">
      <h2 className="font-semibold">{title}</h2>
      <p className="mt-2 text-sm leading-6 text-ink/60">{body}</p>
    </section>
  );
}
