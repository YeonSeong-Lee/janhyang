# 배포

배포 주소: [janhyang-924.pages.dev](https://janhyang-924.pages.dev/)

자동 배포는 [GitHub Actions의 CI/CD 워크플로](https://github.com/YeonSeong-Lee/janhyang/actions/workflows/ci-cd.yml)를 사용합니다.
`main` 대상 PR에서는 의존성 설치, 타입 검사, Vite 빌드를 수행합니다.
`main`에 푸시하면 같은 검사를 통과한 빌드 결과를 Cloudflare Pages에 배포합니다.
배포 작업은 검사 작업이 만든 아티팩트를 사용하며, 아티팩트는 하루 동안 보관합니다.

## 프로젝트 설정

[Cloudflare Pages 프로젝트](https://dash.cloudflare.com/6ccaac2e604c4c353e2e198c73cac480/pages/view/janhyang)는
`YeonSeong-Lee/janhyang` 저장소에서 만든 빌드를 Wrangler로 업로드합니다.
기존 Pages 프로젝트와 주소를 유지하고, Cloudflare 자체 Git 자동 빌드는 중복 배포를 막기 위해 끕니다.

| 항목 | 값 |
|---|---|
| 프로젝트 이름 | `janhyang` |
| Production branch | `main` |
| Actions 작업 디렉터리 | `web` |
| 의존성 설치 | `pnpm install --frozen-lockfile` |
| 검사 및 빌드 | `pnpm build` |
| 빌드 결과 | `web/dist` |
| Node.js | `24` |
| pnpm | `web/package.json`의 `packageManager` |
| Cloudflare 자동 Production deployments | Disabled |
| Cloudflare 자동 Preview deployments | None |

GitHub 저장소의 **Settings → Secrets and variables → Actions**에 다음 값을 설정합니다.

| 종류 | 이름 | 값 |
|---|---|---|
| Secret | `CLOUDFLARE_API_TOKEN` | 해당 계정의 Cloudflare Pages 편집 권한을 가진 배포 토큰 |
| Variable | `CLOUDFLARE_ACCOUNT_ID` | `6ccaac2e604c4c353e2e198c73cac480` |

토큰 원문은 저장소에 커밋하지 않습니다. 배포 토큰은 `main` 배포 단계에서만 사용하며
PR 검사에는 전달하지 않습니다. 토큰을 교체할 때는 같은 이름의 GitHub Secret을 갱신합니다.

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

GitHub 저장소의 **Actions → CI/CD → Run workflow**에서 `main`을 선택합니다.
실패한 실행은 **Re-run failed jobs**로 재시도할 수 있습니다.
`main` 이외의 브랜치에서 수동 실행하면 검사만 수행합니다.
