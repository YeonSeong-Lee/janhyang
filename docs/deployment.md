# 배포

배포 주소: [janhyang.yeonseong.dev](https://janhyang.yeonseong.dev/)

자동 배포는 [GitHub Actions의 CI/CD 워크플로](https://github.com/YeonSeong-Lee/janhyang/actions/workflows/ci-cd.yml)를 사용합니다.
`main` 대상 PR에서는 의존성 설치, 타입 검사, Vite 빌드, Chromium 회귀 테스트를 수행합니다.
`main`에 푸시하면 같은 검사를 통과한 빌드 결과를 Cloudflare Worker에 배포합니다.
배포 작업은 검사 작업이 만든 아티팩트를 사용하며, 아티팩트는 하루 동안 보관합니다.

## 프로젝트 설정

[janhyang Worker](https://dash.cloudflare.com/6ccaac2e604c4c353e2e198c73cac480/workers/services/view/janhyang/production/domains)는 빌드된 정적 파일을 제공합니다. Worker의 Domains 탭에 `janhyang.yeonseong.dev`를 Production Custom Domain으로 연결했습니다. Cloudflare가 이 도메인의 DNS 레코드를 관리하며 DNS 표에는 유형이 `Worker`, Content가 `janhyang`으로 표시됩니다.

GitHub Actions는 `web/dist`를 배포 아티팩트로 전달하고 Wrangler의 `deploy --name janhyang --assets dist`로 배포합니다.

GitHub 저장소의 **Settings → Secrets and variables → Actions**에 다음 값을 설정합니다.

| 종류 | 이름 | 값 |
|---|---|---|
| Secret | `CLOUDFLARE_API_TOKEN` | 해당 계정의 Cloudflare Workers Scripts 편집 권한을 가진 배포 토큰 |
| Variable | `CLOUDFLARE_ACCOUNT_ID` | `6ccaac2e604c4c353e2e198c73cac480` |

토큰 원문은 저장소에 커밋하지 않습니다. 배포 토큰은 `main` 배포 단계에서만 사용하며
PR 검사에는 전달하지 않습니다. 토큰을 교체할 때는 같은 이름의 GitHub Secret을 갱신합니다.

`web/public/_headers`의 COOP·COEP 응답 헤더는 Rive 오디오 스레드에 필요한
cross-origin isolation을 제공합니다. Vite 빌드 시 이 파일도 `dist`로 복사됩니다.
Node 버전은 `web/.node-version`, pnpm 버전은 `web/package.json`에도 명시합니다.

## 로컬 웹 검사

`web` 디렉터리에서 실행합니다. 브라우저 설치는 처음 한 번 필요합니다.

```sh
rtk proxy pnpm install --frozen-lockfile
rtk proxy pnpm exec playwright install chromium
rtk proxy pnpm test
```

테스트는 `127.0.0.1:4187`의 격리 헤더가 있는 Vite preview와
`127.0.0.1:4188/janhyang/`의 헤더 없는 정적 호스트를 직접 시작하고 종료합니다.
이미 사용 중인 포트의 서버를 재사용하거나 종료하지 않습니다.
헤더 없는 호스트는 GitHub Pages의 프로젝트 경로와 서비스 워커 재로딩을 검증하기 위한 것입니다.
실패 시 `web/test-results/`에 진단 정보와 Playwright trace가 남습니다.

Rive WASM은 설치된 패키지에서 Vite가 해시 파일명으로 빌드에 포함합니다.
일반·스레드·호환성 대체 바이너리를 모두 배포하며, 브라우저는 런타임이 선택한 바이너리만 요청합니다.
외부 CDN이 차단되어도 같은 출처에서 런타임을 불러올 수 있습니다.
변경 근거와 남은 검증은 [웹 표준 점검 기록](web-standards.md)에 정리했습니다.
모듈의 책임과 회귀 검사의 경계는 [아키텍처 문서](architecture.md)에 정리했습니다.

## Rive를 수정했을 때

Cloudflare는 커밋된 `web/public/janhyang.riv`를 배포합니다. Rive 소스를 수정했다면
로그인된 로컬 Rive CLI에서 서명 빌드를 만들고, 결과 파일도 함께 커밋하세요.
Cloudflare에서 Rive 소스를 다시 빌드하거나 서명하지는 않습니다.

```sh
rtk proxy rive rive --verify
rtk proxy rive rive --test
rtk proxy rive rive --publish=local
rtk proxy cp rive/build/janhyang.riv web/public/janhyang.riv
```

소스와 `.riv` 파일을 커밋한 뒤 `main`에 푸시하면 배포됩니다.

## 같은 커밋 다시 배포하기

GitHub 저장소의 **Actions → CI/CD → Run workflow**에서 `main`을 선택합니다.
실패한 실행은 **Re-run failed jobs**로 재시도할 수 있습니다.
`main` 이외의 브랜치에서 수동 실행하면 검사만 수행합니다.

## 검색 및 공유 메타데이터

SEO 메타데이터는 JavaScript 실행 없이 읽을 수 있도록 `web/index.html`에 둡니다.
공식 주소를 변경하면 canonical, Open Graph URL·이미지, Twitter 이미지, JSON-LD와
`web/public/robots.txt`, `web/public/sitemap.xml`의 주소를 함께 갱신하세요.
파비콘과 홈 화면 아이콘, 1200×630 공유 이미지는 `web/public/`에서 배포합니다.
