# 웹 표준 점검 기록

점검일: 2026-11-17

## 범위와 방법

웹 진입 문서, 클라이언트 TypeScript, 서비스 워커, 응답 헤더, Vite 설정,
배포 워크플로와 Rive 입력·재생 연동을 확인했다.
`modern-web-guidance@latest legacy-scan`은 수정 전후 모두 0건이었다.
이 스캔은 전체 가이드의 약 20%에 해당하는 38개 가이드·52개 규칙만 검사하므로,
별도로 접근성·HTML·움직임·반응형·성능·보안 가이드를 조회하고 소스를 검토했다.
스캔 결과는 웹 표준 전체 준수나 접근성 인증을 뜻하지 않는다.

## 확인하고 개선한 내용

- **초기화 실패**: `sessionStorage` 읽기가 예외를 던지거나 서비스 워커 등록이
  거부될 때 예외 처리가 없었다. 읽기·쓰기·등록 실패와 4초 활성화 시간 초과를 처리하고,
  새로고침 전에 경로별 가드를 기록한다. 이미 워커가 제어하는 페이지와 늦은 워커
  업데이트는 자동으로 새로고침하지 않는다. 워커가 최초 페이지를 교체할 때는 WASM을
  먼저 초기화하지 않는다. 격리가 불가능한 환경에서는 소리 없이 표시된다는 안내를 제공한다.
- **응답 출처**: 워커가 모든 응답에 `CORP: cross-origin`을 덧붙였다. 같은 출처 응답에만
  격리 헤더와 `CORP: same-origin`을 추가하고, 다른 출처 요청·리디렉션과 불투명 응답은
  원래 응답 정책을 유지한다. 정적 호스트와 로컬 서버에 `nosniff`와 Referrer Policy도 적용했다.
- **실패 안내**: 로딩 상태, 읽기 실패 안내, 재시도 버튼, JavaScript 비활성화 안내를 추가했다.
  상태 메시지는 기존 live region에서 바뀌고, 재시도 버튼으로 전환할 때 키보드 포커스를 보존한다.
  진단 로그는 `?debug`에서 최근 50줄까지 보이고 키보드로 스크롤할 수 있다.
- **접근성**: `main`, 제목, 캔버스 설명, 기본 HTML `details` 사용 안내와 버튼을 추가했다.
  제어부는 키보드로 사용할 수 있고 포커스 표시·44px 터치 영역을 갖는다.
  그림을 조작하지 못하는 캔버스 자체를 Tab 순서에 추가하지 않는다.
- **움직임**: `prefers-reduced-motion`이면 명시적으로 재생하기 전까지 Rive를 로드하지 않는다.
  설정을 켜면 재생 중에도 멈추며, 설정을 다시 꺼도 자동 재개하지 않는다.
  일시정지는 Rive의 재생 상태와 볼륨을 제어한다. 런타임이 이미 처리하는 탭 가시성은 중복 구현하지 않았다.
- **크기와 수명**: `ResizeObserver`와 해상도 미디어 쿼리로 캔버스 크기·DPR 변화에 대응하고,
  연속 크기 변경은 한 애니메이션 프레임으로 묶는다. 버튼과 안내는 동적 뷰포트 높이와
  safe-area를 사용한다. 페이지를 떠나거나 HMR로 교체할 때 observer·이벤트·Rive 리소스를
  정리하되 bfcache에 보관되는 페이지는 유지한다.
- **리소스**: Rive 코드 로딩을 작은 진입 모듈에서 분리하고, 일반·스레드·호환성 대체 WASM을
  모두 같은 출처에서 제공한다. 필요한 호환성 대체 경로를 제거하지 않았다.
- **회귀 검사**: 프로덕션 빌드를 대상으로 Playwright와 axe 검사를 추가하고 CI에도 연결했다.
  테스트 호스트는 도메인 루트와 프로젝트 하위 경로를 모두 다룬다.

## 적용하지 않은 항목

- 전체 화면 캔버스에는 화면 밖 콘텐츠가 없으므로 `content-visibility: auto`를 추가하지 않았다.
- `canvas-html`은 단일 엔진의 실험적 기능으로 명시적인 프로젝트 opt-in이 없으므로 사용하지 않았다.
- 이 프로젝트의 스레드 오디오에는 기존 COOP·COEP가 필요하다. 이를 Chromium 전용 격리 정책으로 대체하지 않았다.
- Rive의 blob worker와 WASM 초기화 경로를 포함한 CSP·Trusted Types 정책은 별도 호환성 검증이
  필요하므로 일괄 강제하지 않았다. 가상의 보고 수집 URL도 추가하지 않았다.

## 검증과 한계

- 타입 검사와 Vite 프로덕션 빌드.
- Chromium 브라우저 회귀 테스트 12개: 같은 출처 WASM, 움직임 줄이기, 키보드 재생 제어,
  일시정지 중 렌더 루프 정지, 고해상도·좁은 화면 리사이즈, Rive/WASM 실패,
  프로젝트 경로의 한 번 재로딩, 저장소 읽기·쓰기 차단, 워커 등록 실패·시간 초과,
  JavaScript 비활성화.
- 일반 화면과 고해상도 좁은 화면의 axe 검사에서 위반 0건.
- 기존 Rive 소스 검증 및 온보딩 테스트 10개 통과.
- 수정 후 legacy-scan 0건.

자동 검사는 캔버스 안의 현·파문에 의미를 부여하거나 스크린 리더로 연주할 수 있게 만들지 않는다.
현 만들기·연주는 현재 마우스 또는 터치 전용이다. 키보드 연주와 현별 의미 정보는
Rive 내부 입력·데이터 모델을 함께 설계해야 하며 완전한 WCAG 준수를 주장하지 않는다.
실제 iOS Safari·Android Chrome의 첫 소리, 스크린 리더 사용성, 노치·회전·브라우저 확대,
서로 다른 DPI 모니터 간 이동은 수동 검증 대상이다.
고해상도 테스트는 실제 고DPR 브라우저 컨텍스트와 뷰포트 크기 변경을 검증한다.
CDP의 DPR 단독 변경은 별도 최소 재현에서도 해상도 `change` 이벤트를 보내지 않아
실제 모니터 이동 검증으로 간주하지 않았다.

Rive 의존성 청크에 대한 Vite의 500kB 경고는 남는다. 시작 모듈은 분리했지만,
필수 렌더러를 임의로 분할하거나 경고 임계값을 높이지 않았다.
원격 CI 실행과 배포는 이번 로컬 점검에 포함하지 않았다.

## 참고한 API 문서

- [Rive 웹 런타임 소스와 API](https://github.com/rive-app/rive-wasm/blob/master/js/src/rive.ts): 재생·일시정지, 크기 변경, 정리, 가시성 처리.
- [Rive 런타임 로더](https://github.com/rive-app/rive-wasm/blob/master/js/src/runtimeLoader.ts): WASM 경로와 대체 바이너리.
- [Rive 움직임 줄이기](https://github.com/rive-app/rive-docs/blob/main/editor/accessibility/reduced-motion.mdx): 호스트가 사용자의 설정을 처리해야 한다.
- [MDN sessionStorage](https://developer.mozilla.org/en-US/docs/Web/API/Window/sessionStorage): 저장소 접근 예외.
- [MDN crossOriginIsolated](https://developer.mozilla.org/en-US/docs/Web/API/Window/crossOriginIsolated): 스레드 실행에 필요한 격리 조건.
