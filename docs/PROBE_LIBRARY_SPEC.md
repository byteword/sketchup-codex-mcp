# Probe 기법 라이브러리 관리 규격 v1 초안

2026-10-29. **구현을 위한 검토 명세이며 현재 MCP 도구/엔진의 구현 또는 검증 완료를 의미하지 않습니다.** 기준 코드0.7.0/main. [설계 배경](TECHNIQUE_LIBRARY_REVIEW.md). 기법은 Probe의 외부 파일과 스크립트 작업 프로세스에서 관리하고, RBZ는 공통 계획 실행/조회만 담당합니다.

## 1. 범위와 용어

목표는 ChatGPT가 설치/재시작 없이 “찾기 → 계약 읽기 → 작성/개선 → 시험 → 이용 → 결과 확인”을 수행하는 것입니다. 새로운 기법마다 MCP 도구/C# 스키마/RBZ 코드를 추가하지 않습니다.

- **Library**: Probe가 등록한 저장 위치/범위. library_id(예: user)는 호스트가 부여하는 핸들이며 기술자 이름/실제 파일 경로와 다름. 사용자/프로젝트/배포 기본 라이브러리를 구분하고 read_only를 반환.
- **Technique**: 호출 가능한 기법. 이름 대신 namespace.local-id 형태의 technique_id로 식별. 예: demo.solid-panel. 동일 ID가 여러 library에 있으면 우선순위로 숨기지 않고 전체 참조를 요구.
- **Revision**: 설명·입력 규칙·소스·시험 파일을 고정한 불변 수정본. 실제 고정 키는 sha256:<64hex>. “최신”은 읽기에서만 쓰고 실행은 고정 revision 사용.
- **Head / Active**: head는 마지막 저장본, active는 기본 이용본. 새 저장본이 실패해도 active와 진행 중 실행은 유지.
- **Plan / Job**: plan은 계산한 실행 계획과 바인딩의 불변 기록, job은 저장 후 검사·계산·적용의 진행/결과 기록. 이 ID들은 SketchUp persistent_id와 별개.
- **Release label**: 선택적1.0.0 같은 배포 이름. 특정 revision에 한 번 연결하면 다시 붙이지 않음. 매 수정마다 사람이 버전 번호를 올릴 필요는 없음.

실행 참조는 (library_id, technique_id, revision). 번들에는 호스트 library_id·경로·계정/세션/모델/PID를 포함하지 않습니다. fork는 새 technique_id를 만들고 derived_from으로 원본 ID/revision을 기록합니다.

## 2. 저장 단위와 소유 관계

기법 한 묶음은 다음 UTF-8 텍스트 파일입니다. 이름 있는 라이브러리 자체도 manage.create_library로 만들 수 있으며 저장 위치는 Probe에 등록된 user/project 범위에서 선택합니다. MCP 요청으로 임의 절대 경로를 쓰게 하지 않습니다.

| 파일 | 내용 |
| --- | --- |
| manifest.json | 식별·발견용 설명, 종류, 역할, 필요 기능, 예산 |
| inputs.schema.json | mm·열림·분할 등 매개변수 형식과 기본값 |
| technique.js | build(ctx) 단일 진입점과 로컬 계산 |
| tests.json | 정상·경계·거부 입력과 기대 출력 |
| presets.json | 선택. 이름 있는 입력 묶음, 실제 모델 재질/PID 없음 |
| helpers/*.js | 선택. 명시한 패키지 내부 순수 보조 코드 |

[설명 파일 스키마](library-spec/manifest.schema.json), [형상 계획 스키마](library-spec/plan.schema.json), [분석 결과 스키마](library-spec/report.schema.json), [실제 묶음 예제](library-spec/example/solid-panel/manifest.json)를 함께 둡니다. 예제는 등록된 기법이 아닙니다.

Probe 저장소는 revisions/<digest>/의 불변 파일과, head/active·변경 사유·시험 결과·작업 이력을 분리합니다. 사용자는 작업용 workspace를 편집하고 Probe가 유효한 스냅샷을 저장합니다. 불변 파일을 직접 수정한 것은 손상으로 감지하며 덮어쓴 revision으로 인정하지 않습니다. 인덱스는 재구축 가능해야 하고 원본 파일이 유일한 active 포인터 저장 장소가 되어서는 안 됩니다.

기법의 JSON 파일/소스 문자열에 숨은 실행 지시가 있어도 별도 권한으로 취급하지 않습니다. 설명/주석/예제는 자료이고, 엔진에는 정해진 ctx만 제공합니다.

## 3. 설명·입력·출력 계약

manifest의 필수 필드는 format_version=probe-technique/1, id, title, summary, kind, entrypoint, input_schema, tests, runtime, output, requires, material_roles, dependencies, reads, budgets입니다. title/summary/keywords는 한글 검색에 사용하고 id를 바꾸지 않습니다. kind는 generator/analyzer/calculator, output은 각각 sketchup-plan/1 또는 probe-report/1입니다. generator는 plan, 나머지는 report만 반환하며 보고서 기법의 모델 적용은 거부합니다.

- **단위/축**: 선형 입력은 mm 숫자. 생성 계획은 오른손 좌표 X/Y/Z, 창 표기는 가로X·세로Z·깊이Y. 좌표/객체 배치와 재질은 bindings로 분리하고 라이브러리 기본값에 모델 핸들을 저장하지 않음.
- **기본값**: JSON Schema의 default 표기를 썼다는 이유로 입력이 자동 수정되는 것은 아님. Probe가 누락된 선택 속성의 기본값을 한 번 채우고 normalized_params를 반환한 뒤 검사/실행. required 필드는 기본값으로 누락을 덮지 않음. null·문자열 숫자·불리언 수치를 강제 변환하지 않음.
- **입력 규칙**: JSON Schema2020-12의 제한 프로필. object/properties/required/additionalProperties=false, array/items/minItems/maxItems/uniqueItems, string 길이/enum/const, number/integer 범위, boolean과 설명/default를 지원. 로컬 $defs/$ref만 허용하고 재귀/원격 참조는 금지. 키워드 중 지원하지 않는 것은 무시하지 않고 schema_unsupported로 거부. 입력 객체는 닫힌 구조·유한 깊이/배열 한도를 가져야 함.
- **연동 조건**: “유리 두께에 비해 깊이가 부족” 같은 관계는 선택적 validate(ctx)가 필드 경로를 가진 진단을 반환. 독립적인 host/계획/native 검사를 대체하지 못함.
- **결과**: generator는 그룹·닫힌 메시·면별 재질 역할·검증 기대값을 포함한 plan. analyzer/calculator는 summary/metrics/findings의 report. 보고서도 크기·깊이·유한 수치 제한 적용.
- **필요 기능**: requires는 group/1, mesh/1 같은 정확한 capability ID. 런타임/계획 규격/필요 기능과 대상 확장의 교집합으로 이용 가능 여부를 판정. 새 기법이 지원하지 않는 연산을 요구하면 실행 전에 이유를 반환.

기법 ID/파일명/버전/기본값 규칙은 위치를 바꿔도 같습니다. 설명 파일에 수정본 해시나 active 상태를 넣어 자기 참조하지 않습니다.

## 4. ChatGPT용 고정 MCP 창구

아래 **일곱 도구는 제안 이름**입니다. 공통 외부 스키마는 정적이고 params의 상세 검사는 Probe가 현재 revision의 입력 규칙으로 합니다. 모델이 없어도 목록·코드 작성·순수 시험이 동작해야 합니다.

| 도구 | 핵심 입력 | 반환과 효과 |
| --- | --- | --- |
| sketchup_library_list | kind=libraries/techniques, library_id?, query?, keywords?, state?, compatible_with?, cursor?, limit? | 요약 목록, catalog_revision, next_cursor. 읽기 |
| sketchup_library_get | library_id, technique_id, revision?, sections[], source_page? | 선택한 계약·예제·소스·시험·이력/두 revision 차이. 읽기 |
| sketchup_library_save | request_id, library_id, technique_id, base_revision, files, change_summary, derived_from? | 새 불변 revision/head. 라이브러리 변경, 모델 변경 없음 |
| sketchup_library_manage | request_id, action=create_library/activate/archive/restore/tag, action별 참조·비교 조건, 기타 action별 필드 | 포인터/보관/배포 이름 변경. 라이브러리 변경 |
| sketchup_library_run | request_id, mode=verify/plan/apply, 아래 mode별 인수 | job_id와 확인 경로를 신속 반환. apply만 모델 변경 가능 |
| sketchup_library_job | action=get/cancel, job_id, cursor?, wait_ms? | 상태·단계·결과·추가 이벤트. cancel은 계산/대기 취소 요청 |
| sketchup_library_transfer | action=export/open_import/write_chunk/inspect_import/commit_import/read_export, 아래 전송 필드 | 불변 번들 또는 제한된 임시 업로드. import commit은 라이브러리 변경 |

위 도구의 action/mode별 필드 집합을 각각 닫힌 스키마로 검사하고 알려지지 않은 필드는 거부합니다. 라이브러리 핸들/기법 ID/해시는 UUID가 아니므로 현재 ToolCatalog의 모든 *_id=UUID 규칙으로 검사하지 않습니다.

목록 기본은 active·미보관 기법, limit=10/최대25, ID 정렬. head와 active가 다른 경우 draft_available=true. q는 ID/한글 이름/summary/keywords에서 찾고 커서에 필터+catalog_revision을 묶습니다. 목록 사이 변경으로 커서가 오래되면 catalog_changed와 새 시작점을 주며 항목을 조용히 건너뛰지 않습니다. 기본 목록에 소스/전체 입력 규칙/모든 예제를 넣지 않습니다.

요약은 참조·title·summary·kind·keywords·active/head·시험 상태·호환성/불가 이유·estimated_cost만 포함. compatible_with를 주지 않으면 “모델과 호환 확인됨”으로 표시하지 않습니다. get 기본 sections는 contract/examples, 소스·시험·이력은 요청 시 읽습니다. 소스는 고정 revision과 파일 해시·줄 번호로 페이지를 제공하고, diff는 base/target 두 revision을 고정합니다. 모든 페이지는 truncated와 다음 위치를 명시합니다.

MCP 결과는 JSON 구조의 일관된 data/error를 담고 기존 content.text 경로를 유지합니다. structuredContent/outputSchema는 클라이언트 협상과 별도 구현 후 사용할 수 있습니다. 새 기법은 library 목록이 바뀌는 것이므로 tools/list_changed나 앱 재시작에 의존하지 않습니다. [MCP 도구·결과 규격](https://modelcontextprotocol.io/specification/2025-06-18/server/tools).

## 5. 생성·개선·동시 수정

save의 files는 허용 상대 경로→UTF-8 내용의 완전한 스냅샷입니다. save는 묶음 구조·설명/입력 스키마·경로/예산을 검사해 저장하고, 소스 실행과 시험은 verify가 담당합니다. 문법 오류가 있는 소스도 draft로 보존해 고칠 수 있지만 활성화/계획 계산은 통과시킬 수 없습니다. 부분 패치를 앞선 코드에 추측 적용하지 않습니다. 큰 파일은 transfer 경로를 사용합니다.

- 최초 생성: base_revision=null, 해당 ID가 없을 때만 성공. 기존 기법은 id_exists와 현재 head 반환.
- 개선: 읽은 head를 base_revision으로 보냄. 달라졌으면 revision_conflict와 현재 head 반환. ChatGPT가 차이를 읽고 합쳐 새로 저장하며 강제 덮어쓰기하지 않음.
- 내용이 이미 같은 경우 새 revision을 늘리지 않고 기존 revision과 no_change=true 반환.
- change_summary는 “손잡이 위치 수정”처럼 의도와 기대 변화를 기록. 비교 결과는 Probe가 파라미터/코드/기대 품질 변경으로 요약하며 작성자 설명만으로 검증 완료를 표시하지 않음.
- 저장은 active를 자동 변경하지 않음. verify의 activate_if_passed=true와 expected_active_revision으로 검사 후 교체를 연속 처리할 수 있음. 요청 범위가 허용하면 ChatGPT가 이 과정을 자동 수행하며 단계마다 인간 확인을 요구하지 않음.
- activate는 형식·JS 로딩·오프라인 시험 통과 revision만 허용. native 실기 미확인은 별도 표시하며 모든 기법 변경마다 SketchUp 재설치를 요구하지 않음. 검증 실패 시 head는 보존해 개선할 수 있고 active는 유지.
- 되돌리기는 activate에 이전 불변 revision을 지정하는 것으로 구현. 새 코드를 과거 파일 위에 덮지 않음. archive는 새 이용을 숨기고 기존 기록/파일은 보존, restore로 재노출. 진행 중 작업은 명시적 cancel 없이 다른 버전으로 바뀌지 않음.

파일 감지 갱신도 save/verify/activate와 같은 경로를 사용합니다. 정책은 draft_only 또는 after_checks. after_checks는 정상 저장·시험 성공·base/head/active 일치 시에만 다음 실행부터 교체하며, 불완전 저장/문법 오류/충돌은 진단으로 남깁니다. “갱신” 요청에 실패했는데 이전 코드를 성공한 새 버전처럼 실행하지 않습니다.

## 6. verify·plan·apply

**verify**: 전체 참조, tests 선택(기본 전체), environment=offline(기본)/native, activate_if_passed(기본false)를 받음. 오프라인은 문법·스키마·기본/경계/거부 입력·계획/의존성·예산을 검사하며 연결 모델/패널 허가가 불필요. native 시험은 명시적 시험 대상과 기존 실행 허가가 필요하고 그 결과를 별도 기록. 활성화 최소 조건은 오프라인 전체 통과이며 이전 native 성공이 다른 revision에 자동 전이되지 않음.

**plan**: 전체 참조, params, bindings(대상 세션/모델/편집 경로·원점·기존 재질 역할·선택적 교체 대상), preset?를 받음. preset을 먼저 적용하고 명시한 params로 덮은 후 default 처리·검사. 필요한 읽기만 먼저 수행하고 build(ctx)에 정규화 입력·읽기 전용 스냅샷을 제공. 결과는 plan_id/plan_hash, 고정 revision과 의존성, normalized_params, 예상 외곽/부품/품질·경고/예산. 모델을 변경하지 않고 native command_id를 예약/소비하지 않음. 현재 Ruby dry_run과 이 Probe 계획 단계를 구분.

**apply**: request_id, plan_id, plan_hash, 현재 session_id/model_id/expected_context, fresh command_id를 받음. params나 다른 revision을 함께 받아 계획을 몰래 재계산하지 않음. native 제출 직전에 세션/모델·문맥·허가·지원 연산·재질·대상 신선도를 다시 확인. 파일이 갱신돼도 이미 만든 계획은 고정된 구버전이며 결과에 그 버전을 명시. active 변경만으로 계획을 바꾸지 않지만 archive/만료/대상 변경은 적용 거부.

계획은 기본10분 유효, 모델별 바인딩/관련 읽기 fingerprint를 기록. 계층·좌표·재질 등 필요한 조건을 실행 시 확인하며 modified=false를 모델 동일성/신선도의 증거로 쓰지 않음. 신선도 확인은 변동 이후 실제로 읽고 변경하기 직전에 RBZ 공통 실행기에서도 수행. 계획별 적용 잠금을 잡고 ready에서 submitting으로 옮기는 것과 request/native 매핑 기록을 원자적으로 처리합니다. 같은 계획의 두 적용 요청이 동시에 통과할 수 없어야 합니다. 적용 완료된 계획의 다른 request_id/command_id는 plan_already_applied, 제출 중/미확정 계획은 plan_in_use로 거부합니다. 실제 제출된 계획은 실패·취소 결과여도 소비된 것으로 기록해 재실행에는 새 plan을 요구합니다. 허가/바인딩 검사에서 제출 전에 거부된 것은 소비하지 않습니다. 반복 배치/재생성도 새 계획을 만듭니다.

기법을 만들어 이번 작업에 곧바로 쓰려면 save → verify(자동 활성화 선택) → plan → apply를 ChatGPT가 연속 호출합니다. 순수 계산/분석 기법은 plan 대신 report_ready로 끝나며 apply 대상이 아닙니다.

## 7. JS·의존성과 형상 계획

probe-js/1은 **동기 순수 계산 프로필**. build(ctx)는 정확히 한 JSON 결과를 반환. ctx.params, 선언해 미리 조회한 ctx.inputs, ctx.call(alias,params), 제한된 수학/로그를 제공. 모델 쓰기/원시 파일/네트워크/일반 CLR 객체·시계/난수·비동기 타이머는 노출하지 않음. Jint 프로세스의 메모리/시간 종료는 별도 관리하며 JS 제한만으로 OS 권한 격리를 주장하지 않음.

helpers는 같은 불변 묶음의 명시 경로만 로드. 외부 의존성은 alias+정확한 ID+revision으로 선언하고 호출 때 active를 다시 해석하지 않음. 누락/순환/한도 초과는 저장 검증에서 거부. 의존 analyzer가 모델을 읽어야 하면 부모의 reads 계약에 포함해 같은 스냅샷을 전달. 의존성 수정은 부모의 새 revision에서 참조를 올리는 명시적 개선이며 진행 중 실행에 섞지 않음.

계획 노드는 요청 내부 id로 연결. root는 유일한 상위 group, 나머지는 먼저 나온 group을 parent로 참조. mesh 노드 하나는 raw 면/선이 든 그룹 하나가 되므로 root+3개 mesh는4그룹. 인덱스는0부터, 모든 좌표는 mm, 법선은 외향, 면별 역할 수=면 수, 역할은 manifest.material_roles에 있어야 함. transform은16개 숫자의 column-major affine matrix, 평행 이동은 mm. 마지막 행[0,0,0,1]·가역성과 실제 좌표 예산을 별도로 검사.

부품 중복 ID·존재하지 않는 parent/role·범위 밖 인덱스·비평면/열린 메시·공통 계획에 없는 연산은 거부. cleanup=material_safe는 기존 재질 경계/텍스처 영역/닫힘을 보존하는 공통 정리. v1의 generator 메시 계약은 닫힌 솔리드로 좁히고 선·면/새 SDK 연산은 별도 capability 버전으로 확장. 단위·재질·부품의 의미 검사는 JSON 스키마 통과만으로 끝내지 않음.

plan의 assertions는 기대 외곽/닫힘을 설명하고 native 공통 검사는 실제 생성 결과를 읽어 확인. 스크립트가 내놓은 “검증 통과” 문구를 그대로 실기 결과로 채택하지 않음. 교체·삭제 대상은 bindings의 명시적 대상만 참조하고 기법 코드가 읽어온 임의 PID로 삭제 범위를 확대할 수 없게 함.

## 8. 작업·중복 방지·오류 복구

상태는 queued/running/succeeded/failed/canceled/outcome_unknown. 별도 stage=load/validate/test/plan/submit/native_wait/reconcile과 effect=none/library_changed/model_applied/model_rollback_verified/unknown을 반환. 단계 이름을 전체 진행률로 꾸미지 않음. 모델 적용 후 표시만 실패한 것은 성공+warning으로 반환.

request_id는 UUID이며 library mutation/run/transfer commit의 Probe 측 중복 방지 키. 정규화한 요청 서명과 receipt/job_id를 기록하고 같은 ID/같은 내용은 동일 결과, 다른 내용은 request_id_conflict. 90일 receipt 보존 후의 재전송 보장은 제공하지 않고, 클라이언트는 저장 상태/계획/작업을 조회해 확인한 뒤 새 ID 사용 여부를 결정. native 제출 이력이 있는 불확실 작업은 receipt 기간과 무관하게 자동 반복하지 않음.

submit 전에 request_id↔job_id↔계획 해시↔정확한 native command_id를 내구성 기록. Probe 재시작 시 완료된 결과를 되살리고, 제출 전 계산은 interrupted_before_submit으로 실패 처리, 제출됐을 수 있으면 outcome_unknown으로 복구해 RBZ 명령 결과를 조회. RBZ의 최근32개 캐시에서 이미 사라졌으면 “미실행”으로 바꾸지 않고 불확실 상태 유지.

취소는 submit 전에는 계산/대기를 멈춰 canceled와 effect=none을 반환. native 제출 후에는 조회/협력적 취소 가능 여부를 보고하고, 동기 SDK 실행을 강제 중단/이미 적용한 형상을 자동 삭제하지 않음. 라이브러리 job 취소가 같은 모델의 더 새 작업을 취소해서도 안 됨. get은 cursor 이후 이벤트와 결과를 읽고 wait_ms는 최대30초. 소스/전체 메시가 로그에 매번 붙지 않도록 요약·추가 진단을 구분.

## 9. 오류와 수정 안내

실행 오류 응답의 error는 code/message/path/stage/retry/recover/details를 가지며, 변경 효과는 최상위 effect로 구분. retry는 never/query_first/refresh_then_retry만 사용. query_first는 새 변경 요청을 보내라는 의미가 아님. path는 /params/depth_mm 같은 JSON Pointer, 소스 오류는 파일/줄/열. 진단은 입력 한도/가능한 선택/현재 revision 등 실제 정보만 제시.

| 코드 | 처리 |
| --- | --- |
| technique_not_found / capability_missing | 목록·지원 기능 확인, 자동으로 다른 기법으로 바꾸지 않음 |
| schema_unsupported / input_invalid / script_invalid | 필드/소스 위치를 읽고 수정본 또는 입력 수정 |
| revision_conflict / active_conflict / catalog_changed | 최신 head/active/목록과 차이를 읽고 명시적으로 재계산 |
| dependency_missing / dependency_cycle | 고정 참조·의존 그래프 수정 |
| budget_exceeded / plan_too_large | 크기/정밀도/기법을 줄이거나 지원하는 전송 방식 사용 |
| plan_expired / model_stale / context_mismatch | 현재 상태로 새 plan 생성; 기존 계획을 몰래 수정하지 않음 |
| request_id_conflict / plan_already_applied / plan_in_use | 기존 receipt/job/result를 조회, 중복 실행 금지 |
| native_failed | rollback_verified이면 변경 없음, 그 외 outcome_unknown |
| outcome_unknown | 기존 native 결과/모델 조회, 자동 재적용 금지 |

library-only 오류에는 SketchUp 명령 결과 조회를 안내하지 않습니다. 모델 apply의 취소/통신 오류만 기존 native 조회 의미와 연결합니다. 현재 CommandCatalog.IsWrite의 한 bool만으로 이 분류를 처리할 수 없으므로 effect class(none/library/model)를 추가하는 것이 필요합니다.

## 10. 공유·한도·영속성

transfer는 기법의 JSON/JS 파일을 담은 선택형 ZIP 패키지를 내보내거나 제한된 임시 업로드를 받아 저장합니다. 단일/여러 대표 기법과 선택적 가져오기의 상세 규칙은 부록E를 따릅니다. export는 정확한 revision과 고정 의존성을 포함한 bundle_id/해시를 반환하고 read_export로 나눠 읽음. open_import는 요청 ID·전체 크기·기대 digest로 임시 upload_id를 만들고, write_chunk는 offset+base64를 전달. 같은 offset/같은 bytes만 재전송 허용, 빈틈/중복 충돌/크기 초과 거부. inspect_import로 내용과 선택 계획을 읽고 commit_import는 전체 해시·경로·기법/의존 스키마를 확인해 draft로 저장하며 실행/활성화하지 않음.

내보낸 번들에는 manifest/code/schema/tests와 선택한 preset/helper, 고정 의존 묶음만 포함. 호스트 저장 경로·세션/모델·명령 이력·재질 실물은 제외. import 중 ID가 같고 revision도 같으면 no_change, ID가 같고 revision이 다르면 충돌/새 draft/fork를 명시적으로 선택하고 active를 덮지 않음. 파일 확장자보다 허용 경로와 콘텐츠 계약으로 검사하고 경로 탈출/절대 경로/심볼릭 링크를 허용하지 않음.

| 항목 | 초안 기본/상한 |
| --- | --- |
| 목록/상세 응답 | 목표8KiB, hard32KiB UTF-8; 큰 소스/이력은 페이지 |
| 직접 save JSON |192KiB(이스케이프 포함), 파일64KiB·32파일·전체1MiB; 초과는 임시 전송 |
| 업로드 | chunk16KiB raw, 전체1MiB,10분 만료; 완료 전 활성화 없음 |
| 의존성 | 총16개, 깊이8, 순환 금지 |
| 저장소 용량 | 사용자 library당 초기256MiB 제안, 설정에서 조정. 초과 시 library_quota_exceeded와 사용량 반환, 과거 revision 자동 삭제 안 함 |
| plan |48000bytes,64노드, 총4096점/2048면; manifest와 host 중 작은 예산 적용 |
| 엔진 | 기본 계산1000ms/64MiB, 최대5000ms/256MiB; 실제 Jint 작업 프로세스에서 검증 필요 |
| native 적용 | 현4초 협력적 예산/응답8초 유지가 초기 목표. 계획 생성 시간과 분리 |
| 계획/작업 | plan10분, 일반 완료 job/receipt90일. 미확정 native 기록은 자동 삭제로 미실행 처리하지 않음 |

현 MCP/Control JSON 채널 한도1MiB와 SketchUp native frame65536bytes를 혼동하지 않습니다. 라이브러리 파일은 Probe에서 끝나므로 native 작은 frame으로 코드를 잘라 실행할 필요가 없습니다. 저장 예산·소스/파일 전송과 생성 계획 전송은 각각 검사합니다. 처음에는 한 native frame에 담는 계획만 지원하고, 이후 비변경 업로드+마지막 한 apply는 별도 프로토콜 확장.

저장 시 라이브러리별 writer lock과 head/active의 비교 후 교체(CAS), 임시 쓰기→검사→불변본 확정→포인터/receipt journal 확정 순서를 사용. 동기화 폴더에서는 rename/부분 저장 실패를 실제 확인해야 하며, 실패한 저장을 성공 receipt로 내보내지 않음. index를 잃어도 파일/내구성 journal로 head/active/작업을 복구할 수 있어야 함.

revision은 아래 파일 내용 규칙으로 계산합니다. 허용 상대 경로를 ASCII 순으로 정렬하고 UTF-8 파일(저장 전 CRLF→LF, BOM 거부)의 실제 bytes를 사용. SHA256에 UTF-8 `probe-technique/1\n`을 넣은 뒤 파일마다 path bytes+NUL+10진 byte length+NUL+content bytes를 이어 넣음. 결과에 sha256: 접두사를 붙임. 변경 사유/시간/head/active/시험 결과는 해시 입력에서 제외. 이 규칙의 테스트 벡터를 예제와 함께 둡니다. 실제 적용은 별도 plan_hash에 고정 입력·의존·바인딩·계획 bytes를 포함해야 하며 소스 revision과 같은 의미로 쓰지 않음.

## 11. 검증·도입 순서

1. 아래 예제 묶음의 스키마/기본·경계·거부 입력과 순수 JS 결과·메시 닫힘을 검증. 이것은 명세 예제의 일관성 검사이며 Jint/MCP/native 구현 검사가 아님.
2. Probe 저장소·목록/get/save/이력·CAS/불변 revision·충돌/손상/복구를 먼저 구현. 모델 없이 ChatGPT 생성/개선이 가능해야 함.
3. Jint 작업·verify/plan·정규화/동적 스키마·시험/의존·자동 활성화 도입. 무한 반복/출력 폭주/엔진 종료·파일 감지 실패/진행 중 버전 고정 검사.
4. RBZ 공통 plan 적용·일괄 읽기와 내구성 제출 기록을 연결. fresh context·잠금/공유·실제 형상·Undo·실패 복구·응답 유실을 실제 SketchUp에서 검사.
5. 실행 중 새 파일 등록/수정/되돌림, 두 편집자의 충돌, 동일 request replay, apply 재시도 차단, 다른 컴퓨터 공유를 검증. 목록이커져도 필요한 계약만 읽는지 확인.

[예제 검사기](library-spec/verify_examples.py)는 개발용이며 배포본에 들어가지 않습니다. 실행 예: 개발 환경에 jsonschema4.25.1을 준비하고 `python docs/library-spec/verify_examples.py --node <Node 실행 파일>`을 사용합니다. 이 의존성은 Probe 사용자 설치 요구가 아닙니다. 기존245개 검사는0.7.0의 결과이며 신규 관리 규격의 구현 검사를 대체하지 않습니다. 기법별 native 성공은 정확한 revision·SketchUp/커널 버전·시험 이름·결과와 함께 저장하고 목록에는 짧은 요약만 보여줍니다.

## 부록 A. action/mode별 필드와 결과

아래는 위 표의 생략된 필드를 보완합니다. 공통적으로 알 수 없는 필드는 거부하며 request_id는 변경/작업 시작 요청에 필수입니다. 단순 조회에는 필요하지 않습니다.

| 창구 | 필수/선택 필드 |
| --- | --- |
| list | kind 필수. library_id/query/keywords/state/compatible_with(session_id,model_id)/cursor/limit 선택. 최초 library 목록에는 각 저장소의 read_only·지원 규격·정책·가능 작업도 반환 |
| get | library_id/technique_id 필수. revision 생략 시 active, 없으면 head와 draft 표시. sections=contract/examples/source/tests/history/diff 중 선택. diff에는 base_revision/target_revision 필수, source_page에는 file/start_line/line_count 필수 |
| save | request_id/library_id/technique_id/base_revision(null 또는 읽은 head)/files/change_summary 필수. derived_from(원본 전체 참조) 선택. files에 manifest의 id와 요청 technique_id가 다르면 거부 |
| manage.create_library | request_id/title/scope(user 또는 설정된 project) 필수, summary 선택. Probe가 새 library_id와 관리 정책 반환; 기존 사용자 루트 자체를 덮지 않음 |
| manage.activate | 전체 참조/request_id/expected_active_revision 필수. 대상 보관 중이면 먼저 restore. rollback도 같은 action. 새 코드 로딩이 실패하면 포인터 유지 |
| manage.archive·restore | request_id/library_id/technique_id/expected_active_revision 필수. 멱등 no_change 가능, 보관 중 새 apply는 거부 |
| manage.tag | 전체 참조/request_id/expected_active_revision/label 필수. 동일 label·동일 revision은 no_change, 다른 revision은 label_conflict |
| run.verify | request_id/전체 참조 필수. environment/tests/activate_if_passed 선택. 자동 활성화 요청은 expected_active_revision 필수이며 성공 시 head도 해당 검사 revision인지 비교 |
| run.plan | request_id/전체 참조/params 필수. preset/bindings 선택. reads 또는 재질/모델 배치가 필요한 기법은 bindings 필수. 읽기 대상·역할 누락은 bindings_required |
| run.apply | request_id/plan_id/plan_hash/session_id/model_id/expected_context/command_id 필수. 저장된 bindings와 다르면 plan_binding_mismatch, 다른 입력·revision 필드는 거부 |
| job.get | job_id 필수. cursor/wait_ms 선택. 변경이 없으면 요약과 unchanged=true, 마지막 성공 문장을 매번 복제하지 않음 |
| job.cancel | job_id 필수. 같은 job에 반복 요청 가능. 모델 제출 이후라면 중단 가능 여부와 기존 결과 확인 경로 반환 |
| transfer.export | selections[1..32] 전체 참조 목록과 package_info 필수. include_dependencies 기본true. 부록E의 선택형 패키지 규칙 적용 |
| transfer.open_import | request_id/total_bytes/digest 필수. 서버가 upload_id·정확한 chunk 한도·expires_at 반환 |
| transfer.write_chunk | upload_id/offset/data_base64 필수. 데이터 디코딩 후 실제 길이/위치 검사 |
| transfer.inspect_import | upload_id 필수. library_id/selected_roots/conflict_policy 선택. 내용·의존·충돌 미리보기와 import_plan_id 반환; 실행/등록 없음 |
| transfer.commit_import | request_id/upload_id/import_plan_id/library_id/conflict_policy 필수. policy=fail/stage/fork, fork에는 새 ID 매핑 필수 |
| transfer.read_export | bundle_id/offset/max_bytes 필수. digest·total_bytes·next_offset 반환 |

save 결과는 technique_ref/head/active/no_change/file_hashes/catalog_revision, verify는 per_case/code 위치/validation 결과와 선택적 active 전환, plan은 plan_id/hash/ref/input 요약, apply는 native command 매핑/실제 생성 경로·품질/한 Undo 여부를 반환합니다. 각 단계에 같은 필드 이름을 일관되게 사용합니다. 성공 응답의 공통 틀은 ok, request_id(해당 시), job_id(해당 시), effect, data, warnings. 실패는 ok=false, effect, error이며 partial success는 data와 warnings로 구체적으로 설명합니다.

시험 상태는 단일 passed로 합치지 않고 schema/script/offline/native의 status=not_run/passed/failed와 검사 대상 revision·엔진/커널 버전·시각을 저장합니다. job.state는 실행 수명, result_type=verified/plan_ready/report_ready/applied는 결과 종류, validation은 검증 증거이므로 서로 대체하지 않습니다.

분석 보고서 metrics는 수치·문자열뿐 아니라 벡터/표용 배열·객체를 허용하되 host가 전체 JSON 깊이8·원소2048·문자열4096자·결과32KiB를 제한합니다. 테스트의 inputs는 선언된 reads의 익명화 스냅샷이며 오프라인 검사에 사용합니다. 실제 세션/모델/PID가 들어간 시험 데이터를 공유 묶음의 기본 자료로 저장하지 않습니다.

helpers는 manifest.helpers의 alias/path 목록으로 명시하고 ctx.helper(alias,params)로 호출합니다. helper도 같은 순수 프로필·공유 예산을 사용하고 직접 파일 접근/별도 native 적용을 할 수 없습니다. 선언되지 않은 파일을 라이브러리 폴더에 넣는 것만으로 로드하지 않습니다.

## 부록 B. ChatGPT가 수행할 대표 흐름

- **기존 이용**: list(query=미닫이 창) → get(contract/examples) → 고정 ref와 params로 plan → 현재 command_id로 apply → job.get의 실제 결과 확인.
- **새로 작성**: 유사 기법 검색 → 새 ID로 완전한 파일 묶음 save → verify(필요하면 activate_if_passed) → plan/apply. 생성/시험/활성화는 기존 사용자 요청 안에서 연속 처리.
- **개선**: 기존 head/source/tests와 실패 진단 읽기 → 기존 시험을 보존하고 새 실패 재현 사례 추가 → base_revision을 포함해 save → verify → 기본본 전환. 실패하면 head 진단을 읽고 다시 수정.
- **되돌림**: get(history/diff) → 원하는 이전 revision을 manage.activate. 이미 만든 사용자 형상을 자동 삭제하거나 바꾸지 않음.
- **공유**: 대표 기법1개 이상 선택 → export(고정 의존 포함) → 패키지 전달 → 다른 호스트 inspect_import → 필요한 대표 기법 선택·commit_import → verify와 호환성 확인 → 활성화. 받는 호스트의 재질과 실행 허가는 별도 설정.

## 부록 C. 현재 코드에서 바꿀 연결 지점

| 현재 파일 | 구현 시 변경 |
| --- | --- |
| shared/ToolCatalog.cs·신규 LibraryCatalog | 고정7개 도구와 action/mode별 바깥 형식 검사. params는 크기·깊이를 제한한 JSON으로 받고 기법별 내부 스키마는 Probe에서 검사 |
| bridge/ControlHub.cs | 라이브러리 요청을 SketchUp peer 선택 전에 분기. 모델 없는 save/verify 허용, apply만 현재 모델 경로 사용 |
| mcp/McpServer.cs·오류 분류 | library/model/none 효과 구분. 라이브러리 저장 오류에 native get_command_result를 무조건 안내하지 않음 |
| Probe 서비스/작업 프로세스 | 등록부·불변 저장·writer lock·복구 journal·엔진·동적 검사·작업 상태·파일 감지 |
| extension/session·공통 실행기 | 한 번의 계획 적용, 현재 문맥/권한·capability·신선도·native 후조건 확인. 개별 JS/기법 ID를 실행 코드로 로드하지 않음 |
| 패키징·검증 | 엔진/worker 의존성·라이선스·최소 배포 구성, 별도 사용자 라이브러리 위치·업데이트 보존을 검증 |

MCP annotations는 라이브러리 동작을 모델 쓰기와 혼동하지 않게 설정합니다. list/get는 읽기, save/manage/import는 라이브러리 변경, run은 mode에 따라 달라지므로 도구 단위 힌트는 보수적으로 두되 실제 실행 권한/오류 처리는 mode/effect로 판단합니다. 힌트만으로 실행 권한을 부여하지 않습니다.

## 부록 D. 이번 명세 예제 확인 결과

JSON Schema4개 자체 검사, 정상3입력(기본·치수 변경·최소값)의 JS 계획/외곽·닫힌 외향 메시, 오류3입력(0·불리언·모르는 필드) 거부를 확인했습니다. 계획의 임의 코드 필드 거부와 파일 순서/줄바꿈의 해시 안정성·내용 변경의 해시 변화를 확인했습니다. [해시 테스트 벡터](library-spec/revision-vector.json). 검사는 Python jsonschema4.25.1과 Node의 예제 실행으로 했고 **Probe/Jint/MCP/SketchUp native 구현을 검사한 것은 아닙니다.**

## 부록 E. 선택형 공유 패키지

이 절은 단일 기법 내보내기를 **1개 이상의 기법을 선택하는 패키지**로 확장하며, 앞선 transfer 표의 상세 규칙을 보완합니다. 아직 구현된 기능은 아닙니다.

### E.1 패키지 생성

transfer.export는 package_info와 selections[1..32]를 받습니다. selections의 각 항목은 library_id/technique_id/revision의 전체 참조입니다. 서로 다른 라이브러리에서 선택할 수 있지만 내보낸 파일에는 호스트 library_id와 실제 경로를 넣지 않습니다. “현재 active” 선택은 export 시작 때 정확한 revision으로 고정하고 그 결과를 반환합니다.

같은 ID/revision을 여러 번 선택하면 하나로 합칩니다. 같은 ID의 서로 다른 revision을 둘 다 대표 기법으로 선택하면 selection_conflict로 어느 것을 대표로 할지 정하게 합니다. 의존성 때문에 같은 ID의 구버전과 신버전이 함께 필요한 경우에는 (ID,revision)별로 저장할 수 있습니다.

include_dependencies 기본값은 true입니다. 선택 기법들에 필요한 고정 의존성을 재귀적으로 모으고 같은 ID/revision은 한 번만 넣습니다. false이면 빠진 정확한 의존 목록과 self_contained=false를 기록하며, 가져올 호스트에 같은 revision이 없으면 이용할 수 있다고 표시하지 않습니다. active에 있는 다른 버전을 대신 쓰지 않습니다.

### E.2 파일과 식별

파일 확장자는 .probe-techpack을 제안하며 내부는 ZIP입니다. package.json과 techniques/<technique-id>/<revision-digest>/ 아래에 manifest/code/schema/tests/preset/helper를 담습니다. package.json에는 다음을 넣습니다.

- format_version=probe-techpack/1, package_id(UUID), title/summary, 선택적 배포 label/작성자 표시.
- roots: 사용자가 직접 선택한 대표 기법의 ID/revision 목록.
- entries: 대표와 의존 기법의 ID/revision, 상대 디렉터리, 파일별 byte length/SHA256.
- dependency lock과 빠진 외부 의존성, 요구 runtime/공통 capability 요약, self_contained.
- 선택적 출처·시험 요약. 출처의 native 통과 기록은 받은 호스트에서 실행했다는 증거가 아니며 imported_evidence로 구분.

패키지 이름/작성자 표시는 고유성이나 신뢰의 증거로 쓰지 않습니다. 실제 기법은 불변 revision으로 고정하고 다운로드/업로드 파일은 별도 archive_digest로 검사합니다. ZIP 생성 시각 등이 다르면 동일 기법 내용이어도 archive_digest는 달라질 수 있습니다.

이전에 언급한 “JSON 텍스트 묶음”은 기법 파일 콘텐츠를 뜻하며, 외부 공유 파일 형식은 이 ZIP 컨테이너로 정합니다. JSON/JS 텍스트 외의 모델·텍스처·실행 파일·계정/현재 모델 정보는 v1 패키지에 포함하지 않습니다. 설치용5파일 ZIP과도 별개의 사용자 자산입니다.

### E.3 읽어보기와 선택적 가져오기

전송 순서는 open_import → write_chunk → inspect_import → commit_import입니다. inspect_import를 기존 transfer 도구의 action에 추가하며 별도 MCP 도구를 늘리지 않습니다.

inspect_import는 upload_id와 대상 library_id(선택)를 받아, 코드를 실행하지 않고 패키지 이름/대표 기법/의존 항목·호환성·검증 상태·로컬 충돌을 페이지로 보여줍니다. 완전한 업로드, 전체 archive_digest, 허용 경로/압축 해제 예산, 파일별 해시와 기법 revision부터 확인합니다. 이 단계는 사용자 라이브러리에 등록하거나 활성화하지 않습니다.

사용자는 대표 기법을 **하나·여러 개·전체** 선택할 수 있습니다. inspect_import에 selected_roots와 conflict_policy를 주면 필요한 의존성 closure와 신규/기존 재사용/새 draft/충돌 항목을 계산한 import_plan_id를 반환합니다. 선택에 필요한 의존성을 빠뜨리는 선택은 허용하지 않으며, 필요 없는 대표 기법·그 의존성은 가져오지 않습니다. 선택하지 않은 대표 기법이라도 선택한 기법의 필수 의존성이면 포함하고 이유를 표시합니다.

commit_import의 필수 인수는 request_id/upload_id/import_plan_id/library_id/conflict_policy입니다. 읽어본 계획의 대상/정책/선택과 다르면 재계산을 요구합니다. 내부 활성본을 즉시 교체하지 않고 선택 항목과 의존성을 draft/불변 저장본으로 등록합니다. 코드를 실행하거나 SketchUp 모델을 바꾸지 않습니다. 그 후 verify/activate를 기존 사용자 요청 범위에서 연속 수행할 수 있습니다.

### E.4 충돌과 묶음 단위 저장

같은 ID와 revision이 있으면 재사용/no_change, ID는 같지만 revision이 다르면 fail/stage/fork 정책을 적용합니다. stage는 새 불변본만 보관하고 active를 유지합니다. 대표 기법이 아닌 의존 revision을 저장할 때도 현재 head/active를 덮지 않습니다. 로컬 기본본과 다른 구버전 의존성은 정확한 revision으로 함께 보관할 수 있습니다.

fork는 새 ID를 만드는 것이므로 manifest와 그 ID를 참조하는 의존 lock이 바뀌며 revision도 새로 계산해야 합니다. 의존 순서대로 새 ID/revision 매핑과 derived_from을 미리 보여주고 원본 해시를 새 파일의 해시인 것처럼 보존하지 않습니다. 임의 문자열 치환으로 JS 소스를 고치지 않습니다.

선택한 묶음의 모든 파일/의존/충돌 조건을 먼저 검사한 뒤 하나의 commit receipt로 등록합니다. 중간 실패 시 일부 기법만 새로 등록됐는데 전체 성공으로 응답하지 않습니다. inspect 이후 관련 로컬 head/active가 바뀌면 import_conflict와 새 계획을 반환합니다. 같은 request_id 재전송은 같은 등록 결과를 돌려줍니다.

### E.5 한도와 확인 조건

초안 한도는 대표32개·의존 포함64개 revision, 압축 파일1MiB, 전체 해제4MiB, 파일2048개입니다. 개별 기법의 파일32개/1MiB 한도도 적용합니다. 한도 초과 시 패키지를 나누거나 호스트 설정 범위를 조정하게 하며 압축 파일 크기만 보고 통과시키지 않습니다. 절대 경로/상위 경로 탈출/중복 경로/심볼릭 링크/암호화 ZIP은 거부하고, 모든 항목을 검증하기 전 코드를 로드하지 않습니다.

구현 확인에는 단일/여러 기법 선택, 공유 의존성 중복 제거, 일부 대표만 가져오기, 누락 의존성·버전 충돌, 같은 패키지 재등록, 중간 실패와 내구성 복구, 경로/해시/압축 크기 오류 거부를 포함합니다. 이 절은 설계 검토이며 패키지 생성·가져오기 런타임 검사를 통과했다고 기록하지 않습니다.
