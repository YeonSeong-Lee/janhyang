# 배포

자동 배포는 Cloudflare Pages의 Git 연동을 사용합니다. `main`에 푸시하면
Cloudflare가 의존성 설치, 타입 검사, Vite 빌드를 수행하고 결과를 배포합니다.
GitHub Actions 실행이나 GitHub 배포용 토큰은 필요하지 않습니다.

## 프로젝트 연결

Cloudflare의 **Workers & Pages → Create application → Pages → Import an existing Git repository**에서
`YeonSeong-Lee/janhyang`을 선택하고 아래 값으로 연결합니다.

| 항목 | 값 |
|---|---|
| 프로젝트 이름 | `janhyang` |
| Production branch | `main` |
| Framework preset | None |
| Root directory | `web` |
| Build command | `pnpm build` |
| Build output directory | `dist` |
| 환경 변수 `NODE_VERSION` | `24` |
| 환경 변수 `PNPM_VERSION` | `9.12.3` |
| Preview deployments | None |

Cloudflare Workers & Pages GitHub 앱에 이 저장소의 접근 권한이 필요합니다.
Git 연동 프로젝트로 만들어야 이후 `main` 푸시를 받아 자동 배포할 수 있습니다.
먼저 Direct Upload 프로젝트를 만들면 나중에 Git 연동으로 바꿀 수 없습니다.

`web/public/_headers`의 COOP·COEP 응답 헤더는 Rive 오디오 스레드에 필요한
cross-origin isolation을 제공합니다. Vite 빌드 시 이 파일도 `dist`로 복사됩니다.
Node 버전은 `web/.node-version`, pnpm 버전은 `web/package.json`에도 명시합니다.

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

Cloudflare Pages 프로젝트의 **Deployments**에서 대상 배포를 선택하고
**Retry deployment**를 실행합니다. 새 변경 사항은 `main`에 푸시해 배포합니다.

기존 GitHub Actions 워크플로와 이를 실행하던 `deploy.sh`는 제거했습니다.
