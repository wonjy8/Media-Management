# Supabase 프로젝트 활성화

대상: `ngjncdnlfwjumtlrsene`

공개 URL과 publishable key는 `.env.local`에 설정되어 있습니다.
이 키는 관리자 키가 아니며 SQL 실행, 함수 배포 권한이 없습니다.
아래 작업은 프로젝트 소유자 계정으로 Supabase Dashboard에서 실행합니다.

## 1. SQL Editor

새 프로젝트에서 다음 파일 내용을 순서대로 실행합니다.

1. `migrations/001_initial.sql`
2. `migrations/002_workflow.sql`

기존 테이블이 있다면 먼저 백업하고 충돌을 확인하세요. 위 스크립트는 최초 설치용입니다.
공개 사용자에게 `loans`, `loan_items` SELECT 권한을 추가하지 마세요.

## 2. Edge Function

Dashboard → Edge Functions → 새 함수 이름: `equipment-api`

`functions/equipment-api/index.ts` 내용을 붙여 넣고 배포합니다.
공개 사용자가 호출하므로 이 함수의 legacy JWT verification은 끕니다.
관리자 요청의 JWT와 admins 등록 여부는 함수 안에서 검증합니다.
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`는 Supabase Edge 런타임이 제공합니다.
서비스 키를 프런트엔드 환경변수나 채팅에 넣지 마세요.

CLI 인증이 이미 준비된 환경에서는:

```sh
supabase link --project-ref ngjncdnlfwjumtlrsene
supabase db push
supabase functions deploy equipment-api --no-verify-jwt
```

## 3. 첫 관리자

Authentication → Users에서 관리자 계정을 만듭니다. 비밀번호는 안전하게 정하세요.
해당 사용자의 UUID를 복사하고 SQL Editor에서 실행합니다.

```sql
insert into public.admins(user_id) values ('여기에 관리자 사용자 UUID');
```

일반 대여자는 계정을 만들 필요가 없습니다.
장비는 Table Editor의 `groups`, `equipment`에 등록합니다.
수리 필요 수량은 `repair_quantity`, 비활성화는 `active=false`로 관리할 수 있습니다.
장비 이미지 URL은 `image_path`에 입력합니다. 관리자 업로드 화면은 아직 없습니다.

## 4. 개인정보 자동 정리

Supabase Cron을 활성화하고 매일 아래 SQL을 실행하는 작업을 등록합니다.

```sql
select public.anonymize_expired_loans();
```

현재 함수는 신청 1년 후 이름·전화번호를 삭제합니다. 자유 입력 특이사항에 개인 정보를
적지 않도록 운영하고, 프로젝트 백업 보존 기간은 별도로 설정해야 합니다.

## 5. 클라우드 네트워크와 검증

환경 설정 초안에 추가한 `ngjncdnlfwjumtlrsene.supabase.co` 도메인을 검토·저장해
실행 환경에도 적용합니다. 게시 여부는 환경 설정에서 결정합니다.

앱 시작: `npm run dev -- --host 0.0.0.0`
기본 경로는 실제 Supabase API를 사용하며 서버 실패 시 브라우저 저장으로 대체하지 않습니다.
`?demo=1`을 붙인 경로만 기존 미리보기입니다. 미리보기 데이터는 서버로 옮기지 않습니다.

배포 후 확인할 항목:
- 장비 목록이 Table Editor에 등록한 내용과 일치하는지
- 신청 시 `loans`, `loan_items`에 기록되는지
- 다른 브라우저에서 이름·전화번호 조회가 가능한지
- 관리자만 승인·반출·반납 취소를 할 수 있는지
- 반납과 수정 충돌, 개인정보 익명화, 대량 조회 제한이 실제 환경에서 동작하는지

실제 프로젝트 연결과 배포는 현재 권한/네트워크로 확인되지 않았습니다.
