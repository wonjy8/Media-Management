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
https://wonjy8.github.io/Media-Management/admin/equipment/ 입니다.
직접 접속·새로고침 시에도 관리자 인증을 확인합니다.
PC는 왼쪽 메뉴, 모바일은 상단 관리 메뉴를 사용합니다.
사용자 창의 선택 상태는 유지하며 창 활성화 시 최신 장비/대여 내역을 갱신합니다.
이 UI 변경에는 추가 SQL이나 Edge Function 재배포가 필요하지 않습니다.

## 탭별 URL

배포 주소의 `/Media-Management/` 아래에 다음 경로가 있습니다.

| 화면 | 경로 |
| --- | --- |
| 장비 찾기 | `equipment/` |
| 장바구니 | `cart/` |
| 대여 신청 | `checkout/` |
| 신청 조회·반납 | `returns/` |
| 장비 관리 | `admin/equipment/` |
| 그룹 관리 | `admin/groups/` |
| 반출·반납 관리 | `admin/loans/` |
| 승인자 관리 | `admin/approvers/` |

탭은 실제 링크이며, 주소 공유/새 탭/직접 접속/새로고침/브라우저 뒤로·앞으로 이동을 지원합니다.
루트와 기존 `?view=admin` 링크는 기본 탭 주소로 정리합니다.
GitHub Pages는 SPA rewrite를 제공하지 않으므로 빌드 시 `scripts/build-routes.mjs`가
각 경로의 index.html을 만듭니다. 별도 서버 설정이나 404 리다이렉트는 필요하지 않습니다.
라우트 테스트는 Vite fallback 없이 정적 파일만 제공하는 테스트 서버에서 HTTP 200을 확인합니다.

장비 목록에서 수량을 담고 → 장바구니에서 수량/항목을 확인하고 → 대여하기로 신청 화면에 이동합니다.
날짜는 신청 화면에서 사용자 정보·사유와 함께 입력합니다. 목록에서 날짜별 예약 가능 여부를 미리 단정하지 않으며 신청 시 서버에서 재검사합니다.
장바구니는 장비 ID·수량만 브라우저에 보관하고, 이름·전화번호·사유 등 신청 정보는 저장하지 않습니다.

### 장비 부속품 연결

기존 프로젝트는 Supabase SQL Editor에서 `supabase/migrations/009_equipment_accessories.sql`을 한 번 실행합니다. Edge Function 재배포는 필요하지 않습니다. 이 SQL을 적용하기 전에도 기존 장비 대여는 동작하며, 관리자 화면에 부속품 설정 안내가 표시됩니다.

1. 충전기·케이블·가방·박스 등을 일반 장비로 먼저 등록합니다.
2. 본체 장비의 **수정 → 부속품**에서 연결할 장비와 본체 1개당 기본 수량, 기본 선택 여부를 지정합니다.
3. 사용자는 장바구니에 담을 때 필요한 부속품과 수량을 선택합니다. 연결은 한 단계씩 선택하며, 연결된 장비의 다른 부속품이 재귀적으로 추가되지는 않습니다.

동일한 부속품을 여러 장비에 연결할 수 있습니다. 선택한 수량은 한 재고로 합산되며, 날짜별 예약 충돌 검사·PDF·승인·개별 반납은 기존 품목별 처리 방식을 사용합니다. 본체 수량을 줄이거나 삭제해도 함께 담은 부속품은 자동 삭제하지 않습니다. 부속품을 수정하거나 연결을 해제해도 이미 접수된 신청 내역은 유지됩니다. 대여 이력이 없는 장비를 삭제하면 연결도 삭제되고, 이력이 있어 비활성화된 장비는 사용자 선택 목록에서 제외됩니다.

### 선택 입력·복수 관리번호

`009`까지 적용한 기존 프로젝트는 `supabase/migrations/010_optional_management_codes.sql`을 SQL Editor에서 실행합니다. 관리번호는 비워 둘 수 있으며, 여러 번호는 `CAM-001, CAM-002`처럼 쉼표로 구분합니다. 번호 앞뒤 공백을 정리하고, 개별 번호 중복을 DB에서도 차단합니다. 빈 관리번호는 목록·PDF·CSV에서 내부 ID로 대체하지 않습니다. 관리번호 목록과 보유 수량은 별도로 입력합니다.
