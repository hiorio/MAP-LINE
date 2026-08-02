# 마이그레이션 적용

`supabase/migrations/` 안의 SQL 파일을 데이터베이스에 반영하는 방법입니다.

지금까지는 Supabase 대시보드의 SQL Editor에 손으로 붙여넣어 왔습니다. CLI를 한 번 연결해
두면 `npm run db:push` 한 줄로 밀린 것만 알아서 적용됩니다.

## 한 번만 하는 설정

### 1. Supabase 로그인

```bash
npx supabase login
```

브라우저가 열리고 인증하면 액세스 토큰이 저장됩니다.

### 2. 프로젝트 연결

```bash
npm run db:link
```

프로젝트를 고르라고 나오면 이 앱이 쓰는 것을 선택합니다. 데이터베이스 비밀번호를 물어보면
Supabase 프로젝트를 만들 때 정한 값을 넣습니다.

> 비밀번호가 기억나지 않으면 대시보드 > Settings > Database > `Reset database password`에서
> 새로 만들면 됩니다. 앱은 이 비밀번호를 쓰지 않으므로(서비스 키로 접속) 바꿔도 영향이 없습니다.

### 3. ⚠️ 이미 손으로 적용한 것들을 "적용됨"으로 표시

**이 단계를 건너뛰면 `db push`가 0001부터 전부 다시 실행합니다.**

지금까지 SQL Editor에서 직접 돌렸기 때문에 Supabase의 마이그레이션 이력 테이블에는
아무 기록이 없습니다. CLI는 그걸 보고 "하나도 적용 안 됐다"고 판단합니다.

```bash
npx supabase migration repair --status applied 0001 0002 0003 0004 0005 0006 0007 0008
```

그다음 확인:

```bash
npm run db:status
```

`0001`~`0008`이 Local과 Remote 양쪽에 모두 찍혀 있으면 정상입니다.

## 이후 사용법

새 마이그레이션 파일이 생기면:

```bash
npm run db:push
```

밀린 것만 순서대로 적용됩니다. 무엇이 밀렸는지 먼저 보려면:

```bash
npm run db:status
```

## 마이그레이션을 쓸 때 지킬 것

**같은 파일을 두 번 돌려도 결과가 같아야 합니다.** 손으로 적용하던 흔적 때문에 이력이
어긋나거나, 복구 중에 재실행되는 일이 실제로 생깁니다.

- 테이블·컬럼·인덱스는 `if not exists`
- 함수는 `create or replace`
- **데이터 백필이 가장 위험합니다.** `0007`에서 겪은 예:

  ```sql
  -- 위험: 두 번 돌면 한 단계의 후보들이 제각각 다른 단계로 쪼개진다
  alter table places add column if not exists stop_index int not null default 0;
  update places set stop_index = order_no where stop_index = 0;

  -- 안전: 널만 채우므로 두 번째 실행은 0건
  alter table places add column if not exists stop_index int;
  update places set stop_index = order_no where stop_index is null;
  alter table places alter column stop_index set default 0;
  alter table places alter column stop_index set not null;
  ```

## 파일 이름

`0001_init.sql`처럼 앞자리 숫자가 버전입니다. CLI가 이 숫자를 그대로 버전으로 읽고
오름차순으로 적용합니다. 새 파일은 다음 번호를 이어서 붙이면 됩니다.

Supabase가 새로 만드는 파일은 `20260802123045_name.sql` 같은 타임스탬프 형식이지만,
숫자로 시작하기만 하면 되므로 지금 방식을 그대로 유지해도 됩니다.

## 배포와의 관계

**배포는 마이그레이션을 적용하지 않습니다.** Railway는 앱만 올립니다.
스키마를 바꾸는 변경을 배포할 때는 `npm run db:push`를 먼저 돌려야 합니다.
순서가 뒤바뀌면 새 코드가 아직 없는 컬럼을 찾아 오류가 납니다.
