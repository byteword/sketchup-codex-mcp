# 다른 컴퓨터에서 이어가기 — 2026-10-28

## 최신 상태: 0.6.1 UI 갱신과 원자적 일괄 변경

요청한 대량 변경 대비로 UiUpdateScope를 공통 모델 operation에 적용했습니다. 기존 disable_ui=true를 유지하면서 commit/abort 후 invalidate와 refresh_inspectors를 각각 한 번 요청합니다. normal 정책도 선택 가능합니다. 아웃라이너만 독립적으로 freeze하거나 트레이를 닫지 않습니다. 다른 요청/타이머 틱까지 operation을 열지 않습니다.

새 run_batch는39번째 도구로, 기존18종 모델 변경을 최대64단계·48000바이트·협력적4초 범위에서 한 Undo로 실행합니다. 단계 실패/중단은 전체 rollback, 후속 UI 갱신 오류는 완료 결과의 경고입니다. dry_run은 최초 상태 기준이며 생성 ID를 같은 batch의 뒤 단계에서 참조하지 않습니다. [계약·예시·API 근거](UI_UPDATES.md)를 읽으세요.

개발 회귀221개가 통과했습니다. 기존 56항목 native 실기 suite에도 같은 UI 범위를 적용하고 UI 진단을 반환합니다. 실제 사용자 앱의 새 버전 설치/CPU 벤치마크는 아직 미실시입니다. 아래0.6.0/0.5.0은 이력입니다.

## 최신 상태: 0.6.0 확장 기능

MCP 도구38개. 요청 목록의 구현·제한과 추가로 발견한 기본 기능은 [확장 도구 계약](EXTENDED_TOOLKIT.md)에 있습니다. `shared/ToolkitSchemas.json`과 `ToolkitCatalog.cs`의 원본은 `scripts/generate_toolkit_catalog.py` + `ToolkitCatalog.template`이며 변경 후 생성기를 실행합니다. C#5/.NET4.8을 유지합니다.

Ruby는 geometry_plan/extended_geometry/resources/view_commands와 extended_self_checks로 분리했습니다. 정의·태그·재질은 SketchUp2019에서 PID가 없으므로 resource_id/definition_id는 모델 세션의 entityID를 명시한 별도 문자열입니다. 정의 조회를 model.find_entity_by_persistent_id에 의존하지 않습니다. 도형은 기존 PID/전체 경로를 유지합니다.

`run_self_test(suite=all)`은 기능55개+정리=56항목. 기본 core는 기존25항목으로 호환을 유지합니다. 외부 실행기/스킬은 all을 선택합니다. 기존 태그·재질·정의·장면 집합도 복구 검사합니다. 장면 변경과 모델 전체 purge는 자체 임시 형상 검사에서 제외합니다. 실제 0.6.0 앱은 아직 업데이트/실기하지 않았으며 현재 앱을 자동으로 종료·교체하지 않았습니다.

스킬 원본 두 개도 새 계약으로 갱신합니다. [검증 기록](VALIDATION.md), [시험 배포 안내](TEST_RELEASE.md)를 확인하세요. 아래의0.5.0/0.4.x 섹션은 과거 기록입니다.

## 최신 상태: 0.5.0 기본 도구와 일괄 실기 검사

사각형·원·폴리라인, 회전·축척·그룹 묶기·정의 독립화·삭제·프로파일 돌출, 전체 경로의 그룹/면/선 상세 조회를 추가했습니다. MCP 도구는 30개이며 [인수·지원 범위](BASIC_TOOLKIT.md)에 계약을 정리했습니다. 이전 단계의 “도구 19개/다음 구현 예정” 표시는 당시 기록입니다.

`sketchup_run_self_test`는 한 번의 실행 허가와 요청으로 고정 기능 24개 및 정리를 확인합니다. 임시 형상만 쓰고 한 operation을 abort해 제거합니다. 개별 명령 Undo·파일 전환·권한 회수/경합은 별도 시험입니다. 자동 재전송 없이 결과를 조회하며 실패/생략·실제 소요 시간·정리 결과를 반환합니다. [사용법과 경계](BATCH_TEST.md)를 읽으세요.

자동 회귀 169개(Ruby 136개 / 828 assertions + Python 33개)가 통과했습니다. 실제 파이프를 거친 일괄 검사도 API 대역으로 실행했습니다. **0.5.0의 실제 앱 확인은 아직 진행하지 않았습니다.** 시험 ZIP은 계속 필수 5개 파일이며 스킬·실행기·개발 의존성을 넣지 않습니다.

스킬 원본은 `skills/sketchup-mcp`와 `skills/sketchup-self-test`입니다. 전자는 운영/개발, 후자는 빠른 설치 후 일괄 검사를 담당합니다. 후자에 표준 라이브러리만 쓰는 JSON 보고서 실행기가 있습니다. 검증된 원본을 개인 스킬 폴더에도 동기화합니다. 현재 열린 앱을 자동 교체하거나 재시작하지 않습니다.

## 최신 상태: 0.4.1 모델 식별 수정

0.4.0 실기에서 발견한 모델 ID 유지의 원인은 Ruby 객체 동일성만 검사하던 `Panel#metadata`였습니다. `ModelIdentity` AppObserver로 New/Open 문서 수명을 구분하고, 알림 즉시 기존 실행 허가를 회수하도록 수정했습니다. 허가 처리 전과 명령 처리 전에도 현재 모델을 확인합니다. [수정·회귀·설치 후 확인](MODEL_IDENTITY.md)에 상세를 기록했습니다.

전체 자동 검사 137개(Ruby 112개 / 684 assertions + Python 25개)가 통과했고 0.4.1 시험 ZIP을 만들었습니다. 설치 파일은 5개입니다. 이후 사용자가 설치한 실제 앱에서 New와 동일 파일 다시 열기의 모델 ID 갱신·허가 자동 회수, 이전 ID 거부, 최초 저장의 ID 유지를 확인했습니다. [0.4.1 실기 결과](MANUAL_RESULTS_0.4.1.md)에 미리보기로 검사한 범위와 편집 후 저장/Save As 등 남은 조건을 구분했습니다. 실제 형상 변경은 실행하지 않았고 사용자 제어·`modified=false`로 마쳤습니다.

[다음 기능 계획](FEATURE_PLAN.md)은 지정 객체 상세 조회 → 사각형 → 선·폴리라인 순서입니다. 이번 변경에 신규 도구 구현은 포함하지 않았습니다. `skills/sketchup-mcp`는 버전 관리할 스킬 원본이며 이 PC의 개인 스킬 폴더에도 같은 내용을 설치했습니다. 새 PC에서 사용할 때는 원본의 검증 후 해당 PC의 개인 스킬 폴더에 복사합니다. 다음 에이전트는 [스킬](../skills/sketchup-mcp/SKILL.md)과 관련 개발 참조를 읽고 이어갑니다.

## 최신 추가: 실제 SketchUp 시험 결과

시험 배포 준비 커밋 `fa3fa30`을 GitHub `main`에 반영한 뒤 사용자가 시험용 중개 앱과 확장을 실행했습니다. SketchUp 19.2.222 / Ruby 2.5.5에서 생성·그룹 복제·이름 변경·이동과 단계별 Undo, 회전·축척된 부모 내부의 모델 축 X 이동, 잠금 거부와 허가 회수 후 변경 차단을 확인했습니다. 선택·확대·보기 전환은 실제 API 응답과 후속 조회로 확인했습니다.

수치·확인 근거·범위는 [실기 결과](MANUAL_RESULTS_0.4.0.md)에 있습니다. 미확인 조건과 새 모델 전환 후 `model_id` 유지 관찰을 후속 확인 대상으로 남겼습니다. 실기 종료 시 박스는 잠금 해제, 권한은 사용자 제어 상태였습니다. 이번 갱신은 문서 기록이며 실행 코드·배포본·버전을 변경하지 않았습니다.

## 현재 상태: main 통합 및 시험 배포

2026-10-28에 기존 PC의 미커밋 변경 21개 파일과 개발 브랜치를 비교했습니다. 기존 기능은 `3fe8482`에 이미 반영되어 있었고, 차이가 있는 MCP 안내 문구는 최신 브랜치가 편집 경로 조회 방법을 더 정확히 설명했습니다. 추가로 옮겨야 할 고유 기능 변경은 없었습니다.

기존 작업은 로컬 Git stash의 `Preserve pre-sync 0.4.0 local work before adopting work/post-0.3.1 (2026-10-28)` 기록으로 보존했습니다. 이 기록은 GitHub에 푸시되지 않습니다. 최신 개발 이력 `5bd926d`까지 기본 브랜치 `main`에 fast-forward로 통합했으며 앞으로의 작업 기준은 `main`입니다. 별도 `master` 브랜치는 만들지 않습니다.

통합 당시 이 PC의 SketchUp 2019 Ruby 2.5.5 DLL 호스트에서 자동 검사 124개(실패·오류·건너뜀 0), Ruby 문법 검사와 x64 빌드를 다시 확인했습니다. 해당 자동 검사의 모델·형상·Undo는 테스트 대역입니다. 이후 실제 앱 확인은 위 최신 추가 항목과 실기 결과 문서에 구분했습니다.

최신 19개 도구를 포함한 `dist/sketchup-codex-mcp-0.4.0-test.zip`과 RBZ를 새로 생성했고 `SHA256SUMS.txt`를 갱신했습니다. ZIP은 실행 필수 파일 5개만 포함합니다. [시험 배포 안내](TEST_RELEASE.md)와 [검증 범위](VALIDATION.md)를 확인하세요. 현재 열린 앱에 자동 설치하거나 정식 릴리스 태그를 만들지는 않았습니다.

아래는 개발 브랜치를 다른 PC로 넘길 당시의 이력입니다. 당시의 시작 브랜치·검사 환경·패키징 상태는 위 현재 상태로 갱신되었습니다.

## 시작할 브랜치

- 저장소: https://github.com/byteword/sketchup-codex-mcp
- 개발 브랜치: `work/post-0.3.1`
- 기준 릴리스: `v0.3.1` / `c1d31ae`
- 현재 기능 구현 마지막 커밋: `dffcbb7` (박스 생성·객체 복제)
- 소스의 버전 문자열: C#/Ruby 모두 `0.4.0`, 아직 시험 개발 상태입니다.

이번 이관 기록 커밋까지 위 개발 브랜치에 푸시합니다. `main`과 릴리스 태그는 이번 작업에서 변경하지 않습니다. 다른 컴퓨터에서는 `main`만 받지 말고 개발 브랜치를 체크아웃하세요.

새로 받는 경우:

```powershell
git clone --branch work/post-0.3.1 https://github.com/byteword/sketchup-codex-mcp.git
cd sketchup-codex-mcp
git status --short --branch
git log -5 --oneline
```

기존 복제본이 있는 경우, 먼저 미커밋 작업을 보존한 다음 진행합니다.

```powershell
git fetch origin
git switch work/post-0.3.1
git pull --ff-only origin work/post-0.3.1
```

로컬 브랜치가 아직 없으면 `git switch --track origin/work/post-0.3.1`을 사용합니다. 기존 작업이 갈라졌으면 강제 초기화하거나 강제 푸시하지 말고 차이를 확인합니다.

## 완료한 기능과 커밋

| 커밋 | 내용 | 당시 자동 검사 |
|---|---|---|
| `3fe8482` | OneDrive 참조 작업본의 0.4.0 기초 명령 전달 반영, 권한·명령 ID/결과 이력·중복 방지·Undo 및 문서 정리 | 84개 |
| `98e0374` | 읽기 전용 객체 검색·구조 탐색, 중첩 배치 경로와 커서 분할 조회 | 104개 |
| `dffcbb7` | mm 원점·치수의 박스 그룹 생성, 그룹/컴포넌트 복제·상대 이동·롤백 | 124개 |

v0.3.1 이후 위 세 기능 커밋과 이번 이관 기록을 이어가면 됩니다. OneDrive 참조 폴더를 다시 복사할 필요는 없습니다.

현재 MCP 도구는 총 **19개**입니다.

- 연결·상태·Ping: `sketchup_bridge_status`, `sketchup_list_instances`, `sketchup_get_instance`, `sketchup_ping`.
- 읽기 조회: `sketchup_get_model_summary`, `sketchup_get_selection_info`, `sketchup_find_entities`, `sketchup_get_children`.
- 선택·화면: `sketchup_set_selection`, `sketchup_set_view`, `sketchup_zoom`.
- 모델 변경: `sketchup_update_entity_properties`, `sketchup_move_entities`, `sketchup_create_box`, `sketchup_duplicate_entities`.
- 명령 결과: `sketchup_get_command_result`.
- 기존 연결 시험: `sketchup_start_demo`, `sketchup_get_job`, `sketchup_cancel_job`.

검색은 이름/정의 이름·직접 태그·객체 종류를 지원합니다. 같은 정의의 여러 배치를 전체 `instance_path`로 구분하며 편집 위치를 자동으로 열지 않습니다. 박스는 모델 축 기준 1~1,000,000 mm 변 길이의 독립 그룹이고, 복제는 현재 편집 위치의 그룹/컴포넌트 최대 25개를 각각 한 번 복사합니다. 그룹의 상위 정의는 독립화하고 컴포넌트 정의는 공유합니다.

## 마지막 검증과 아직 하지 않은 일

마지막 전체 자동 검사 실행은 **2026-10-26**입니다. **124개 통과**, 실패·오류·건너뜀 0입니다. 이번 2026-10-28 이관은 문서 기록 작업이며 전체 검사를 새로 실행한 결과로 표시하지 않습니다.

- Python MCP STDIO 검사 19개.
- Ruby 검사 합계 100개 / 629 assertions.
- 실제 MCP → GUI 제어 허브 → Win32 Named Pipe → Ruby 통합 검사 5개.
- Ruby 문법과 .NET Framework x64 배포/테스트 실행 파일 빌드 통과.
- 위 통합 검사는 실제 통신 경로를 쓰지만 모델·형상·카메라·Undo는 테스트 대역입니다.

**실제 SketchUp에서 0.4.0의 형상 생성·복제·중첩 변환·속성 사전·Undo·UI 확인은 아직 남아 있습니다.** 사용자는 우선 기능 개발을 이어가기로 했으므로, 이를 이미 확인했다고 기록하거나 새 기능 개발의 완료 결과와 혼동하지 마세요. [검증 범위](VALIDATION.md)와 [수동 시험](MANUAL_TEST.md)에 구분해 두었습니다.

이번 요청은 외부 저장소로의 개발 브랜치 푸시입니다. 정식 0.4.0 릴리스 생성·`main` 병합·실제 앱 설치는 범위에 포함하지 않았습니다. 브랜치 푸시로 GitHub Actions가 자동 실행될 수 있지만, 원격 CI 성공 여부는 별도로 확인해야 합니다.

## 다른 Windows 컴퓨터의 빌드·검사 준비

실행/소스 빌드 기준은 Windows x64, .NET Framework 4.8, C# 5/WinForms입니다. 별도 NuGet 의존성은 없으며 기본 Framework 컴파일러로 빌드합니다.

```powershell
.\build.cmd
.\dist\SketchUpMcp.exe --version
```

전체 검사에는 **Ruby x64 2.5 + Minitest 5.15.0**, Python 3이 필요합니다. 마지막 로컬 실행은 Python 3.13.17이었고 CI 설정은 Ruby 2.5 / Python 3.12입니다. 일반 Ruby 실행 환경을 준비한 경우:

```powershell
gem install minitest --version 5.15.0 --no-document
.\scripts\windows-tests.ps1 -Ruby ruby -Python python
```

전체 검사 스크립트가 GUI/MCP와 테스트 실행 파일을 빌드합니다. `PROBE_TEST`와 일시적인 `SUPIPE_TEST=1`로 시험 파이프를 분리합니다. 일반 SketchUp 모델을 시험 대상으로 연결하지 않습니다. 일반 실행 환경에 `SUPIPE_TEST`를 영구 설정하지 마세요.

### 기존 컴퓨터에서 쓴 SketchUp Ruby DLL 호스트 방식

별도 Ruby 실행 파일 대신 SketchUp 2020의 `x64-msvcrt-ruby250.dll` (Ruby 2.5.5)을 사용했습니다. 새 컴퓨터에 같은 DLL/표준 라이브러리가 있을 때만 아래 방식을 쓸 수 있습니다. `scripts/build-test-ruby.cmd`에는 Visual Studio C++ x64 Build Tools가 필요합니다.

```powershell
.\scripts\build-test-ruby.cmd
$sketchupRoot = 'C:\Program Files\SketchUp\SketchUp 2020'
$minitestLib = 'C:\dev-tools\minitest-5.15.0\lib' # 실제 준비한 Minitest 경로로 변경
$previousRubyLib = $env:RUBYLIB
try {
    $env:RUBYLIB = @(
        (Join-Path $sketchupRoot 'Tools\RubyStdLib'),
        (Join-Path $sketchupRoot 'Tools\RubyStdLib\platform_specific'),
        $minitestLib
    ) -join ';'
    $runner = (Resolve-Path '.\dist\sketchup_ruby_runner.exe').Path
    & $runner $sketchupRoot -v
    .\scripts\windows-tests.ps1 -Python python -Ruby $runner -RubyArguments @($sketchupRoot)
} finally {
    $env:RUBYLIB = $previousRubyLib
}
```

Minitest는 별도로 준비해야 합니다. 기존 컴퓨터의 `dist/dev-deps/minitest-5.15.0/lib`와 테스트 실행 도우미 `dist/dev-local.ps1`는 Git에 포함되지 않습니다. 이 도우미에는 기존 장비의 SketchUp/Python 절대 경로가 들어 있으므로 다른 장비에서 그대로 실행한다고 가정하지 마세요. 표준 진입점은 저장소에 포함된 `build.cmd`와 `scripts/windows-tests.ps1`입니다.

Win32 보조 DLL은 소스 트리에 포함되어 있습니다. 이를 다시 빌드하려면 C++ x64 Build Tools와 `scripts/build-native.cmd`를 사용합니다. DLL을 재빌드한 경우 바이너리 차이를 확인하고 필요할 때만 커밋합니다.

## Git에 없는 로컬 파일과 배포 상태

`dist/`는 무시되는 디렉터리입니다. EXE·RBZ·ZIP·검사 로그·개발 라이브러리·참조 작업본 스냅샷은 이번 푸시에 포함되지 않습니다. 소스, 테스트, 네이티브 보조 DLL, 문서는 Git에 있습니다.

- 기존 `dist/sketchup-codex-mcp-0.4.0-test.zip`은 **객체 검색 단계(도구 17개)**에서 만든 로컬 시험 패키지입니다. 생성·복제 단계의 최신 도구 19개 배포본이라고 사용하면 안 됩니다.
- 생성·복제 단계는 소스 빌드·검사·로컬 커밋만 했으며 새 패키지는 만들지 않았습니다.
- 추적 중인 `SHA256SUMS.txt`도 마지막 패키징 당시 기록입니다. 지금 소스를 새로 빌드한 실행 파일의 체크섬이라고 간주하지 마세요.
- 새 시험 패키지가 필요할 때 `powershell -File .\scripts\package.ps1 -TestRelease`를 실행합니다. 이 스크립트는 빌드, 버전 검사, RBZ/시험 ZIP 생성과 `SHA256SUMS.txt` 갱신을 수행합니다.
- 설치 ZIP의 허용 파일은 EXE 2개·설정 파일 2개·RBZ 1개뿐입니다. 소스·검사·개발 도구는 넣지 않습니다.
- 실제 설치 때는 GUI·MCP·RBZ를 함께 교체하고 실행 프로세스를 다시 시작해야 합니다. 새 컴퓨터에서는 MCP 실행 파일의 전체 경로도 장비에 맞게 설정해야 합니다.

## 구현을 이어갈 때 읽을 파일

| 파일 | 역할 |
|---|---|
| `shared/ToolCatalog.cs`, `CommandCatalog.cs`, `DiscoveryCatalog.cs` | 도구 목록·JSON 스키마·인수 검증 |
| `bridge/ControlHub.cs` | MCP 호출의 세션 라우팅, 결과 불명 처리 |
| `extension/su_pipe_probe/session.rb` | 모델/권한/기한·소유자·명령 ID·결과 캐시 |
| `extension/su_pipe_probe/command_executor.rb` | 선택·화면·속성·이동, 공통 Undo 경계 |
| `extension/su_pipe_probe/creation_commands.rb` | 박스 생성·복제 및 결과 확인 |
| `extension/su_pipe_probe/entity_browser.rb` | 읽기 전용 구조 탐색·필터·이어보기 커서 |
| `tests/creation_commands_test.rb`, `tests/entity_browser_test.rb` | 새 기능 계산·상태·오류 회귀 |
| `tests/windows_mcp_test.py` | 실제 파이프를 거친 종단 간 자동 검사 |

변경 명령의 계약을 유지해야 합니다. 대상은 정확한 현재 세션·모델과 편집 경로로 한정하고, 새 요청/미리보기마다 새 명령 ID를 받습니다. 시간 초과된 변경을 자동 재전송하지 않습니다. 명령 ID의 보관 결과를 확인하며 캐시에서 만료된 ID도 다시 실행하지 않습니다. 자세한 계약은 [기초 명령 전달](COMMAND_SCOPE.md), [객체 검색](ENTITY_DISCOVERY.md), [생성·복제](CREATION_COMMANDS.md)에 있습니다.

## 다음 작업 후보

다음 기능은 아직 확정하지 않았습니다. 회전·축척, 화면 캡처, 박스 외 기본 형상 생성이 후보입니다. 사용자는 최근 후보에서 먼저 객체 생성·복제를 선택했고 이 기능까지 구현했습니다. 이어갈 기능의 범위를 정한 뒤 기존 패턴대로 도구 계약 → Ruby 실행기 → 회귀/파이프 검사 → 문서 → 기능별 커밋 순서로 진행하면 됩니다.

실제 모델 확인과 정식 릴리스 전에는 수동 시험, 최신 패키징/체크섬, 원격 Windows CI를 확인해야 합니다. 이번 이관 이후의 추가 푸시·릴리스는 그때의 사용자 요청에 따릅니다.

다른 컴퓨터의 작업 채팅에는 이렇게 시작할 수 있습니다.

> `docs/HANDOFF.md`와 현재 Git 상태를 읽고 `work/post-0.3.1`에서 이어가자. 객체 생성·복제까지 구현했고 마지막 자동 검사는 124개 통과했다. 실제 SketchUp 검증은 아직 남아 있다. 다음 기능 후보와 범위를 먼저 정리해줘.
