# 서울영동교회 미디어사역부

교회 장비 대여 앱. React / TypeScript / Vite / Supabase.

- 장비 이미지·검색·그룹, 날짜별 재고, 수량 대여
- 이름·전화번호로 신청/조회/수정/취소/직접 부분 반납 (회원가입 없음)
- 관리자 장비·그룹·승인자 관리, 승인/실제 반출, 반납 취소, 이력/지연/충돌
- 1MB 이하 이미지 압축과 저장소 제한, 반납 사진 비공개
- A4 PDF 직접 저장: 여러 페이지, 마지막 장 하단 승인자/반출자, 한글 글꼴 포함
- 신청 당시 장비/승인자 보존, 수정 시 재승인, 1년 후 이름/전화번호 익명화

확정 요구사항은 [REQUIREMENTS.md](REQUIREMENTS.md).

## 실행

`.env.example`을 참고해 `.env.local`에 공개 URL과 publishable key를 설정합니다.
서비스 키를 VITE 변수에 넣지 마세요.

```sh
npm ci --cache /tmp/media-npm
npm run dev -- --host 0.0.0.0
npm run build
npm run lint
npx playwright test --workers=1
```

기본 경로는 실제 Supabase API를 사용합니다. 실패 시 브라우저 저장으로 대체하지 않습니다.
`?demo=1`만 브라우저 저장 미리보기이며 실제 개인정보는 입력하지 마세요.
관리자는 Supabase Auth 계정과 admins 등록이 필요합니다.
각 클라우드 작업은 격리되어 있으므로 기존 체크아웃을 사용하고 별도 worktree를 만들지 않습니다.

## Supabase 설정

- 최초 설치: migrations/001, 002, 003, 004 순서 적용 후 equipment-api 배포. [SETUP.md](supabase/SETUP.md).
- **기존 설치 업데이트**: [UPGRADE.md](supabase/UPGRADE.md)의 SQL 한 번 실행 + 기존 Edge Function 코드 교체.
- 기존 관리자 등록과 Cron 작업은 유지합니다.
- 원격 관리자 권한이 없는 환경에서는 SQL/서버 배포를 대신 실행할 수 없습니다.

## 검증

브라우저: 관리자 CRUD·그룹·승인자·이미지 압축, 신청/부분 반납, API 오류,
모바일, GitHub Pages 하위 경로, A4 다중 PDF 다운로드/한글/개인정보/최종 서명 페이지.

로컬 PostgreSQL (일회용 DB, Supabase auth/storage 최소 스키마 필요):
- tests/database.sql: 신청/충돌/권한/반출/부분 반납/재승인/조회 제한/익명화
- tests/database_complete.sql: 날짜별 최대 사용량/스냅샷/반납 이력/그룹 RLS/관리자 이력
- tests/database_concurrency.py: 실제 동시 신청에서 한 건만 성공

원격 마이그레이션 적용과 서버 배포 이후 실제 프로젝트에서도 통합 검증해야 합니다.
백업 보존 기간과 자유 입력 개인정보 운영 규칙은 프로젝트 설정에서 관리합니다.

## GitHub Pages

Settings → Pages → Source: GitHub Actions.
Repository Variables: VITE_SUPABASE_URL, VITE_SUPABASE_PUBLISHABLE_KEY.
main에 push하면 React dist를 자동 배포합니다. Jekyll을 사용하지 않습니다.
https://wonjy8.github.io/Media-Management/

PDF 글꼴은 Nanum Gothic (SIL OFL). [라이선스](public/fonts/LICENSE.txt).

## 관리자 전용 창

사용자 화면의 관리자 링크는 별도 창을 엽니다. 전용 주소는
https://wonjy8.github.io/Media-Management/?view=admin 입니다.
직접 접속·새로고침 시에도 관리자 인증을 확인합니다.
PC는 왼쪽 메뉴, 모바일은 상단 관리 메뉴를 사용합니다.
사용자 창의 선택 상태는 유지하며 창 활성화 시 최신 장비/대여 내역을 갱신합니다.
이 UI 변경에는 추가 SQL이나 Edge Function 재배포가 필요하지 않습니다.
