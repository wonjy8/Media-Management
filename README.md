# 이음 · 교회 장비 대여

React / TypeScript / Vite 기반 교회 장비 대여 앱입니다. Supabase 연결 코드는 준비되었으며 실제 프로젝트의 스키마/Edge Function 배포가 필요합니다.

## 실행

```sh
npm ci --cache /tmp/media-npm
npm run dev -- --host 0.0.0.0
npm run build
npm run lint
```

## 데이터 연결

- `.env.local`에 프로젝트 URL과 publishable key 설정. `.env.example` 참고.
- 기본 경로는 Supabase Edge Function을 호출합니다. 오류 시 localStorage로 대체하지 않습니다.
- `?demo=1` 경로는 기존 브라우저 저장 미리보기입니다. 서버와 데이터가 분리됩니다.
- 실제 프로젝트 설치 절차: [supabase/SETUP.md](supabase/SETUP.md).
- 관리자는 Supabase Auth 로그인과 `admins` 등록이 모두 필요합니다.

## 준비된 서버 기능

장비 목록/기간별 재고, 원자적 예약 생성, 한국 시간 월별 신청번호, 이름/전화번호 조회,
미반출 신청 수정·취소, 수정 후 재승인, 승인과 실제 반출 분리, 부분 반납,
관리자 반납 취소와 사유 기록, 서버 조회 제한, 1년 후 이름/전화번호 익명화 함수.
원격 배포와 실제 프로젝트 통합 검증은 아직 수행하지 않았습니다.

## 검증

```sh
npm run build
npm run lint
# 개발 서버 실행 상태에서, 시스템 Chromium 필요
npx playwright test --workers=1
```

브라우저 테스트 4개: 미리보기 신청→반출→부분 반납, 모바일 검색,
서버 저장 오류 시 로컬 저장 방지, 연결 오류와 관리자 로그인 화면.
서버 API 테스트는 응답을 모킹하며 원격 배포 성공을 뜻하지 않습니다.

`tests/database.sql`은 마이그레이션 적용 후 일회용 PostgreSQL에서 실행하는 업무 규칙 테스트입니다.
`tests/database_concurrency.py`는 `media-postgres-test` 컨테이너에서 실제 동시 신청 충돌을 검증합니다.
로컬 PostgreSQL 검증은 Supabase Edge Runtime/Cron/Auth 전체 통합 검증과 별개입니다.

## 남은 운영 작업

- 실제 Supabase에 마이그레이션/Edge Function 배포, 관리자 계정 생성, Cron 등록.
- 관리자 장비 등록·수리 상태·승인자 편집 UI, 승인자 스냅샷.
- 이미지 업로드와 1MB 자동 압축·서버 검사.
- PDF 직접 다운로드/한글 글꼴 포함 및 인쇄 품질 검증. 현재 브라우저 인쇄 초안은 8행씩 분할하고 마지막 장 하단에 서명란을 배치합니다.
- 예약 충돌 알림 UI, 지연 표시, 반납 취소 후 후속 예약 충돌 표시.
- 자유 입력 개인정보 및 백업 보존 정책.

Google Sheets, 사용자 회원가입, 확인번호, 장비 세트, 보관 위치, 연장은 사용하지 않습니다.
승인 기한은 신청일 제외 다음 일요일 + 7일이며 지연 표시용입니다. 미승인 자동 취소는 없습니다.
각 클라우드 작업은 격리되어 있으므로 기존 체크아웃을 사용하며 별도 worktree는 만들지 않습니다.

## GitHub Pages

Settings → Pages → Source: **GitHub Actions**.
Settings → Secrets and variables → Actions → Variables에 `VITE_SUPABASE_URL`,
`VITE_SUPABASE_PUBLISHABLE_KEY`를 등록합니다. Secret/service_role 키는 사용하지 않습니다.
`main`에 push하면 React 앱을 빌드해 `dist`만 배포합니다. Jekyll을 사용하지 않습니다.
워크플로는 저장소 이름을 기준으로 `VITE_BASE_PATH`를 설정합니다.
기본 주소: https://wonjy8.github.io/Media-Management/
로컬 루트 개발은 기존대로 `npm run dev`를 사용합니다.
