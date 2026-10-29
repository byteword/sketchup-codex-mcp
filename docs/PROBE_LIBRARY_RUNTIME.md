# Probe 기법 라이브러리 0.8.0

## 0.9.0 추가: 그룹 없는 명령 계획

`sketchup-operations/1`과 `commands/1`을 추가했습니다. `get(kind=authoring,sections=["operations_example"])`로 그룹 없는 사각형·치수·문자 예제를 가져올 수 있습니다. 기존 계획/패키지는 호환됩니다. [인수·제한·실기 절차](FEATURES_0.9.0.md).

2026-10-29. [검토 규격](PROBE_LIBRARY_SPEC.md)을 바탕으로 구현한 첫 시험 버전입니다. Probe의 외부 파일과 내장 JavaScript 엔진에서 기법을 관리하고 SketchUp에는 한 번의 형상 계획으로 전달합니다. 지원하는 연산을 조합하는 새 기법은 EXE/RBZ 재설치 없이 추가·수정할 수 있습니다.

## 설치와 저장 위치

처음에는 GUI·MCP·RBZ를 모두 0.8.0으로 교체하고 다시 시작해야 합니다. [설치 안내](TEST_RELEASE.md). MCP 도구는 기존40개와 라이브러리7개, 총47개입니다. 스크립트 엔진 Jint 3.1.6과 의존 DLL은 Probe EXE에 포함되며 사용자가 Node/Python을 설치할 필요는 없습니다. 설치 ZIP은 필수5개 파일을 유지합니다. 빌드 시 고정 버전 NuGet 원본의 SHA-256을 확인하며 라이선스 고지는 Probe에서 볼 수 있습니다.

기본 저장 위치는 `%LOCALAPPDATA%\SketchUpCodexMcp\Library`입니다. Probe의 **기법 라이브러리 폴더** 버튼으로 엽니다. 이름 있는 여러 라이브러리를 이 저장소 안에 만들 수 있습니다. `user`가 기본입니다. 임의 프로젝트 폴더를 별도 루트로 등록하거나 사용자 간 동기화하는 기능은 이번 버전에 없습니다. 공유에는 패키지를 사용합니다.

| 폴더 | 내용 |
| --- | --- |
| `workspaces/<library_id>/<technique_id>` | 직접 편집 가능한 기법 파일 |
| `revisions/<sha256>` | 실행·공유에 쓰는 불변 수정본 |
| `commits`, `receipts` | 등록부 변경 이력과 중복 요청 기록 |
| `jobs`, `plans` | 검증·실행 상태와 고정 계획 |
| `transfers` | 내보낸 패키지와 가져오기 준비 자료 |
| `workspace-status` | 작업 파일 반영 상태·오류 |

불변 저장소/기록을 직접 편집하지 마세요. 작업 파일에는 UTF-8 BOM 없는 텍스트를 사용합니다. 기법은 `manifest.json`, `inputs.schema.json`, `technique.js`, `tests.json` 네 파일이 필수이며, 선택적으로 `presets.json`과 manifest에 선언한 `helpers/*.js`를 포함합니다.

## ChatGPT가 사용하는 고정 도구

| 도구 | 주요 기능 |
| --- | --- |
| `sketchup_library_list` | 라이브러리 목록, 기법 검색·필터·페이지 조회 |
| `sketchup_library_get` | 입력 계약·예제·소스·검사·이력·수정 차이, 작성 안내/스키마/완전한 예제 |
| `sketchup_library_save` | 전체 파일 묶음 저장, 기준 수정본 충돌 검사, 새 초안 생성 |
| `sketchup_library_manage` | 라이브러리 생성·정책 설정, 기법 활성화·보관·복구·릴리스 태그 |
| `sketchup_library_run` | 고정 수정본 검증(`verify`), 계획(`plan`), 모델 적용(`apply`) |
| `sketchup_library_job` | 작업 조회·이벤트·취소·불확정 native 결과 재조회 |
| `sketchup_library_transfer` | 여러 기법 패키지 내보내기, 전송, 내용 확인, 선택적 가져오기 |

정확한 인수는 설치된 도구 스키마를 따릅니다. 쓰기 요청은 UUID `request_id`를 사용합니다. 같은 ID/동일 인수는 이전 결과를 반환하고 같은 ID/다른 인수는 거부합니다. native 적용은 별도의 최신 `command_id`도 필요합니다.

기본 목록은 활성 기법만 보여 줍니다. 초안까지 보려면 `state=all`을 사용합니다. 실행 대상은 `library_id`, `technique_id`, `revision=sha256:...`로 고정합니다. `head`는 최근 저장본, `active`는 기본 이용본입니다. 새 초안이 실패해도 이전 활성본은 유지됩니다.

## 빈 라이브러리에서 작성·개선하기

1. `get(kind=authoring)`으로 작성 규칙과 완전한 패널 예제를 읽습니다. `sections=["window_example"]`은 두 짝 미닫이 창의 네 파일을 `window_files`로 반환합니다. `manifest_schema`, `plan_schema`, `report_schema`, `tests_schema`, `package_schema`도 선택 조회할 수 있습니다.
2. manifest의 ID와 일치하는 `technique_id`로 네 파일 전체를 `save`합니다. 신규 생성은 `base_revision=null`, 개선은 읽은 최신 `head`를 기준으로 전달합니다. 작업 파일 경로는 `get`으로 조회합니다.
3. 저장된 정확한 수정본을 `run(mode=verify)`하고 반환된 작업 ID를 `job(action=get)`으로 확인합니다. 전체 검사 통과 후 활성화합니다. `activate_if_passed=true`와 읽은 `expected_active_revision`을 사용하면 검증 후 충돌 없이 활성화할 수 있습니다. 처음에는 `null`입니다.
4. `run(mode=plan)`에 치수 등 `params`를 전달하고 계획 요약을 확인합니다. SketchUp 연결 없는 순수 계획도 가능합니다. 실제 적용은 아래 모델 바인딩이 있는 계획을 사용합니다.
5. 개선은 새 수정본으로 저장합니다. 실행 중인 작업과 패키지는 기존 수정본을 계속 참조합니다. 오래된 기준 저장·활성화는 충돌로 거부하므로 최신 계약/이력을 다시 읽고 수정합니다.

직접 작업 파일을 편집하면 재시작 없이 새 초안이 생성됩니다. 기본 `draft_only`는 활성본을 바꾸지 않습니다. `manage(action=configure_library, update_policy=after_checks)`를 선택하면 파일 변경 뒤 전체 오프라인 검사 통과 시에만 자동 활성화합니다. 실패한 소스/입력 규칙은 오류로 기록하고 이전 활성본을 유지합니다. 다른 경로에서 바뀐 head나 미저장 편집은 덮어쓰지 않습니다. 이 자동 검사는 실제 SketchUp 형상의 실기 통과를 뜻하지 않습니다.

## 엔진과 계산 범위

`build(ctx)`는 계획 또는 제한된 수치 보고서를 반환합니다. 선택적 `validate(ctx)`는 `{path, code, message}` 오류 배열을 반환합니다. 경로는 JSON pointer입니다. `ctx.params`는 입력 규칙으로 검사·기본값 적용 후 고정되고, `ctx.inputs`에는 선언한 읽기 결과만 들어갑니다. `ctx.call(alias, params)`은 수정본이 고정된 의존 기법, `ctx.helper(alias, params)`는 선언한 순수 보조 함수를 호출합니다.

엔진은 모델과 분리된 작업 프로세스에서 실행하며 파일·네트워크·CLR 객체·시계·난수를 제공하지 않습니다. 실행 시간·메모리·문장 수·호출 깊이를 제한하고 부모 프로세스도 초과 작업을 종료합니다. 검증·계획 계산은 SketchUp의 면마다 명령을 보내지 않습니다. 기법은 좌표·단면·조립 계산을 담당하고 Probe가 스키마·닫힘·방향·계획 한도를 검사한 뒤 RBZ가 native 객체를 한 번의 Undo로 생성합니다.

이번 계획 형식은 그룹, 닫힌 면 메시, 변환, 기존 재질 역할, bounds/solid 검사, 접합선 정리와 직접 자식 교체를 지원합니다. 임의 Ruby/SketchUp API, 새 재질 생성, 모든 기존 도구의 임의 조합은 지원하지 않습니다. 새로운 공통 연산 자체를 추가할 때는 RBZ 업데이트가 필요합니다. 읽기 기법에는 대상 요약/하위 구조·형상 스냅샷과 제한된 보고서 형식이 제공됩니다.

## 모델에 적용하기

먼저 실제 인스턴스와 현재 모델·편집 위치를 조회합니다. `plan`의 `bindings`에는 다음을 넣습니다.

- `session_id`, `model_id`: 현재 연결에서 읽은 정확한 ID
- `expected_context`: 현재 편집 경로, 루트는 `[]`
- `origin_mm`: 모델 축 기준 `[x,y,z]`, 치수는 X=가로/Y=깊이/Z=높이
- `materials`: `{frame: "정확한 기존 이름", glass: "...", seal: "...", hardware: "..."}`처럼 기법의 역할별 기존 재질 이름
- 선택 `name`, `replace_entity_id`, 선언한 읽기용 `targets`

Probe는 현재 모델/편집 위치/재질과 읽기·교체 대상의 지문을 확인합니다. 받은 `plan_id`, `plan_hash`는 10분간 유효합니다. `apply`에는 그 계획과 최신 session/model/context/command ID를 전달하고 작업 결과를 조회합니다. 패널의 실행 허가는 기존과 같이 필요합니다. 계획 뒤 대상/재질/편집 위치가 바뀌면 재계획합니다. 교체는 새 형상 검사가 통과한 다음 기존 대상을 제거하며 실패는 전체 취소합니다.

시간 초과나 연결 해제는 재실행의 근거가 아닙니다. 제출된 명령 정보와 `library_job_id`를 저장하고 native 결과 기록과 대조합니다. `outcome_unknown`은 작업 재조회/조정으로 해결하며 생성 요청을 자동 반복하지 않습니다. 계획 파일 무결성도 적용 전에 확인합니다.

`verify environment=offline`은 엔진과 수치 형상을 검사합니다. `environment=native`는 시험 모델·재질 바인딩·실행 허가·새 command ID를 사용하고 여러 정상 케이스를 한 임시 operation에서 실행 후 abort합니다. 루트/정의/재질/태그/선택/편집 위치/modified/외곽의 복구를 대조합니다. 실제 화면 품질·UV·단독 Undo는 설치 후 별도로 확인합니다.

## 여러 기법을 묶어 공유하기

1. `transfer(action=export, selections=[{library_id, technique_id, revision}, ...])`로 대표 기법을 하나 이상 고릅니다. 기본적으로 고정 의존 기법을 포함하고 공통 의존성은 한 번만 넣습니다.
2. 결과의 `local_path`에 `.probe-techpack` 파일이 생성됩니다. 다른 컴퓨터/사용자에게 이 파일을 전달합니다. 원격 클라이언트는 `read_export`의 바이트 조각으로도 받을 수 있습니다. 기법 파일·규칙·검사·의존 잠금만 포함하고 모델 ID·재질 바인딩·사용자 작업 기록은 포함하지 않습니다.
3. 받는 쪽에서 파일의 총 바이트/SHA-256으로 `open_import`, 순서대로 `write_chunk`를 호출합니다. `inspect_import`로 이름·대표 기법·필요한 의존성·충돌을 확인합니다. 처음에는 `selected_roots`를 생략해 전체 내용을 보고, 필요한 `{technique_id, revision}`만 넣어 다시 확인할 수 있습니다.
4. 선택한 대표 기법과 그 의존성만 등록됩니다. 선택하지 않은 다른 대표 기법은 가져오지 않습니다. `conflict_policy=fail`은 다른 기존 수정본이 있으면 거부, `stage`는 기존 활성본을 유지하고 새 초안 등록, `fork`는 `id_map`의 새 ID로 분기합니다. 분기 시 의존 잠금과 수정본 해시도 다시 계산합니다.
5. 검사 결과의 `import_plan_id`와 동일 대상 라이브러리/정책으로 `commit_import`합니다. 내용 확인 이후 대상이 바뀌면 다시 확인해야 합니다. 등록은 묶음으로 처리하며 패키지 코드는 실행하지 않습니다. 받은 기법은 검증 후 활성화하고 현재 모델의 재질을 새로 선택합니다.

경로 탈출·중복 항목·심볼릭 링크·미선언 파일·해시 불일치·누락 의존성은 거부합니다. 패키지 서명/발행자 신뢰 인증·공용 온라인 저장소·자동 다운로드 업데이트는 이번 범위에 없습니다. 해시는 내용 일치를 확인합니다.

기본 한도는 대표32개/패키지 수정본64개, 압축1MiB/해제4MiB, 파일64KiB/기법1MiB, 의존 그래프16개/깊이8, 동시 엔진2개/대기32개, 사용자 라이브러리 소스256MiB입니다. 전송·가져오기 계획은 10분간 유효합니다. 수정본/작업 기록의 정기 정리 기능은 아직 없으므로 장기 사용 시 폴더 용량을 확인합니다.

## 검증과 남은 실기

[개발 검사 기록](VALIDATION.md)의 엔진·저장/복구·자동 반영·패키지·MCP/Win32·Ruby 회귀를 참고하세요. 패널 예제와 두 짝 미닫이 창 예제를 포함합니다. 창 기본 형상은 기존 승인 fixture의 모든 면/재질 역할과 일치합니다. **0.8.0 설치 후 실제 SketchUp API를 사용하는 라이브러리 실행/교체/Undo/정리 확인은 아직 남았습니다.** 개발 검사는 사용 중인 모델·설치 프로그램을 교체하지 않았습니다.
