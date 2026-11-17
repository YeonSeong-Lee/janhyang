# 배포

`main`에 푸시하면 [Deploy GitHub Pages](../.github/workflows/deploy.yml)가 자동으로 실행됩니다.
Node.js 24와 `web/package.json`에 고정한 pnpm 버전으로 의존성을 설치하고,
타입 검사와 Vite 빌드가 성공하면 `web/dist`를 GitHub Pages에 배포합니다.
배포가 진행 중이면 다음 실행은 기다립니다.

- 사이트: https://yeonseong-lee.github.io/janhyang/
- 실행 내역: https://github.com/YeonSeong-Lee/janhyang/actions/workflows/deploy.yml
- 저장소의 **Settings → Pages → Source**는 **GitHub Actions**를 사용합니다.
- 배포에는 기본 `GITHUB_TOKEN`과 OIDC를 사용하므로 별도 배포 토큰이 필요하지 않습니다.

## Rive를 수정했을 때

CI는 커밋된 `web/public/janhyang.riv`를 배포합니다. Rive 소스를 수정했다면
로그인된 로컬 Rive CLI에서 서명 빌드를 만들고, 결과 파일도 함께 커밋하세요.
CI에서 Rive 소스를 다시 빌드하거나 서명하지는 않습니다.

```sh
rtk proxy rive rive --verify
rtk proxy rive rive --test
rtk proxy rive rive --publish=local
rtk proxy cp rive/build/janhyang.riv web/public/janhyang.riv
```

소스와 `.riv` 파일을 커밋한 뒤 `main`에 푸시하면 배포됩니다.

## 같은 커밋 다시 배포하기

GitHub Actions 화면에서 **Run workflow**를 누르고 `main`을 선택하거나,
GitHub CLI에 로그인한 상태에서 아래 명령을 실행합니다.

```sh
rtk proxy sh deploy.sh
```

이 명령은 원격 `main`의 최신 커밋을 배포합니다. 로컬의 미커밋 변경 사항은 포함하지 않습니다.
`main` 이외의 브랜치에서 수동 실행하면 빌드만 수행하고 배포는 건너뜁니다.
