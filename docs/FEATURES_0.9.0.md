# 0.9.0 — 그룹 없는 그리기와 SketchUp2019 공통 기능

2026-10-29. 기준 소스는 E: OneDrive 저장소/main. 우선순위1–3,4의 주요 공통 연산과5의 표시·그림자 설정을 구현한 **시험 버전**이다. 모든2019 기능의 구현 완료 또는 실기 합격을 뜻하지 않는다. 실행 중인 프로그램과 사용자 모델은 바꾸지 않았다.

## 구현 순서와 상태

| 순서 | 이번 구현 | 남은 범위 |
| --- | --- | --- |
| 1 | 기능 조회, 기존 모델 변경 명령을 이용하는 `sketchup-operations/1`, 그룹 없는 그리기·편집 | 계획 내부에서 방금 생성한 ID를 참조하는 별칭은 없음 |
| 2 | 면적·선 길이·체적, raytest, 면 내부 판정, 사용자 속성 읽기/쓰기 | 새 조회 결과를 선언형 library reads에 직접 바인딩하는 확장, 재질별 물량 집계 |
| 3 | 안내선, 선형/반경 치수, 설명 문자,3D 문자, 단면 생성/수정/활성화,2019 레이어 점선 | 새 주석 도구는 모델 루트에서 사용; 화면 문자·치수 스타일 전체 설정은 제외 |
| 4 | 원본 보존 Boolean, 대상 내부 교차선, 컴포넌트 개구부/접착 행동, UV 배치/조회·면 메시, PNG/JPEG/SKM 텍스처 읽기, 뷰 이미지 출력 | 실제2019 커널·폰트·UV·Solid 연산의 설치 후 검증, 복잡한 교차 재질 보존 |
| 5 | 렌더 표시와 그림자·위치·시간 설정 | 전체 장면 저장/적용, 스타일 파일 관리, SKP/CAD 입출력, 지형·DC·Classifier |

후속 구현은5의 전체 장면·스타일 → SKP/CAD 입출력 → 지형·분류 순서다. DC 내부 재계산, 사진 일치/2점 투시 setter,2019에 없는 API는 공개 계약 확인 없이 임의 내부 호출로 연결하지 않는다. 일반 Offset/지형/메시 감축은 별도 기법 알고리즘과 시험 자료가 필요하다.

## 그룹 없는 생성과 편집

새 `sketchup_draw_geometry`의 `grouping`:

- `auto`(기본): 점·선·면·사각형·원·다각형·호·곡선·평면 offset은 현재 편집 위치에 직접 그린다. 닫힌 polyhedron/revolve/sweep는 그룹으로 만든다.
- `none`: 직접 그리기를 요구한다. 닫힌 입체 요청에는 오류를 반환한다.
- `group`: 기존처럼 주변 형상과 분리해 만든다.

임시 그룹을 만든 뒤 해제하지 않고 처음부터 해당 Entities에 넣는다. 기존 선을 재사용하거나 면을 분할할 수 있으므로 결과의 `created`, `reused_entity_ids`, `invalidated_entity_ids`와 새 구조 조회를 이용한다. `created`는 주 결과이며 모든 새 모서리 목록을 뜻하지 않는다. 기존 객체의 레이어를 덮어쓰지 않고 새 형상만 Layer0에 둔다. 직접 그리기 문맥은20000개, 새 객체2048개 상한. 원/호는 편집 좌표계의 균일·직교 축척이 필요하다.

기존 `create_rectangle/create_circle/create_polyline/create_geometry` 기본값은 호환성을 위해 그룹 생성이다. `edit_geometry`에서 `container_id`를 생략하면 현재 편집 위치의 원시 형상을 편집한다. 선·면 추가/삭제, 꼭짓점 이동, 앞뒤 재질, 면 뒤집기, 부드러운 모서리, 조건에 맞는 평면 접합선 정리가 가능하다. 직접 편집 문맥은2048개 상한이며 공유된 편집 조상은 먼저 독립화해야 한다. 모두 한 요청의 Undo/실패 취소 대상이다.

## Probe 기법에서 사용

`sketchup_library_get(kind="authoring", sections=["operations_example"])`은 `demo.raw-drawing`의4개 파일을 반환한다. 가로1200/세로900 기본 사각형에 선택적으로 두 치수와 설명을 붙이며 그룹 수0이다. `annotate=false`는 도형만 만든다. 이 예제를 저장·검증·수정·선택 패키지로 공유할 수 있다.

새 출력 형식:

```json
{"format_version":"sketchup-operations/1","units":"mm","steps":[
  {"method":"draw_geometry","arguments":{"kind":"rectangle","grouping":"none","options":{"origin_mm":[0,0,0],"plane":"XY","size_mm":[1200,900]}}}
]}
```

manifest의 `output`과 `requires:["commands/1","verify/1"]`를 선언한다. 전체 필드는 [스키마](library-spec/operations.schema.json)와 각 MCP 명령 스키마를 따른다. 한 계획1–64단계,48KB 이내. Probe가 고정 허용 명령과 중첩 인수를 검사하고 RBZ가 기존 구현을 한 operation으로 실행한다. native verify는 적용 후 abort하고 모델 상태를 확인한다. 검증에 여러 계획을 묶으면 전체64단계 이내다. 실행 중4초 협력적 시간 한도는 단계 사이에서 검사하며 단일 SketchUp 커널 호출을 강제 중단하지는 못한다.

좌표와 대상 ID는 명령에 직접 넣는다. `bindings.origin_mm`은 생략 또는0, `replace_entity_id`는 불가. 기존 mesh 계획의 배치·재질 바인딩을 자동 적용하지 않는다. 계획 안에서 새 ID를 참조하는 기능은 없으며 ID는 적용 결과에서 받아 다음 요청에 사용한다. `dry_run`은 원래 모델 기준 검사이고 앞 단계 결과를 가상 실행하지 않는다. 카메라·선택·장면·표시 상태·파일·중첩 batch·임의 Ruby는 허용하지 않는다. 기존 `sketchup-plan/1` 및 패키지 형식은 유지한다.

JS 실행 자체의 시간·메모리 제한은 유지한다. 내장 DLL 로딩/JIT/직렬화를 포함한 프로세스 외부 감시는 script 시간+5초로 제한한다. 이전+1.5초는 Windows 초기 로딩 지연 때문에 정상 예제도 종료시켰다. 다른 모델 변경을 자동 재시도하지 않는다.

## 신규 도구·조회 계약

총59개 도구. 새12개는 `draw_geometry`, `model_query`, `entity_attributes`, `annotation`, `edit_annotation`, `solid_operation`, `intersect_faces`, `face_texture`, `component_behavior`, `configure_display`, `export_view`, `texture_resource`다. `edit_geometry`와 `manage_resource`도 확장했다.

`model_query`는 읽기 전용이다:

| query | options / 결과 |
| --- | --- |
| capabilities | 빈 options. SketchUp 버전·Pro·지원 batch 명령·plan 형식·점선 이름 |
| metrics | instance_path, 선택 recursive/max_entities. 면적mm²·선 길이mm·솔리드 체적mm³. 반복 배치를 각각 집계하고 겹침을 합집합으로 제거하지 않음 |
| raycast | origin_mm,direction, 선택 include_hidden. 첫 충돌점과 경로; 간섭 체적 아님 |
| classify_point | face instance_path,point_mm. native PointInside/PointOnEdge 등 |
| attributes | instance_path,dictionary, 선택 offset/limit. 최대25개·응답28KB, 다음 offset |
| face_mesh | face instance_path. 모델 좌표 점과 native 삼각분할 인덱스.1부터 시작, 음수는 숨은 모서리 표시 |
| uv | face instance_path,points_mm, 선택 front. 직접 할당된 텍스처의 정규화 UV; Q로 나눠 반환 |
| display | 빈 options. 지원하는 현재 표시/그림자 값 |

metrics/classify/mesh/UV는2019 편집 좌표계 부작용을 피하기 위해 루트 문맥에서 사용한다. metrics는 최대5000개·32단계·0.5초; 넘으면 불완전한 합계 대신 오류. native volume은 자신의 축척을 포함하므로 부모 변환의 행렬식만 추가 적용한다. 속성 쓰기는 현재 문맥의 직접 객체, dictionary/key와 JSON 스칼라/배열을 사용한다. 구조화 객체는 JSON 문자열로 저장한다. 잠금·공유 조상 보호를 따른다.

주석은 `annotation.kind`별 `options`를 받는다: guide(point_mm,direction), linear_dimension(start_mm,end_mm,offset_mm), radial_dimension(edge_id,leader_mm), text(text,point_mm,offset_mm 선택), text3d(text,origin_mm,height_mm; font/bold/italic/extrusion_mm 선택), section(point_mm,normal; active/symbol 선택).3D 문자는 원점 생성 후 안전하게 배치하기 위해1그룹이다. 나머지는 그룹0. 기존 주석 삭제·문자/단면 변경은 `edit_annotation`을 사용한다. 태그 `line_style`은 capabilities의 정확한 이름 또는 null(실선)이다.

Boolean은 target_id/tool_id 두 루트 솔리드의 복사본으로 계산하고 원본을 유지한다. subtract/trim은 target minus tool. outer_shell 외에는 Pro 필요. 빈 결과나 비솔리드는 실패·취소한다. 결과는 새 ID이며 사용자 속성을 자동 복사하지 않는다. 면 교차는 독립된 target 내부에 원시 교차선만 추가하며 불필요한 면을 자동 삭제하지 않는다. 두 연산 모두 피연산자별5000개 직접 선·면 이내다.

UV 배치는1–4개 `{point_mm,uv}` 쌍과 기존 텍스처 재질을 쓴다. 공유 조상은 독립화해야 한다.2019의3인수 `position_material`만 사용한다. 개구부 행동은 모든 컴포넌트 배치에 영향을 주므로 configure의 `affect_all_instances=true`가 필요하다. face cutting과 벽체 전체 Boolean 관통을 구분한다.

`texture_resource`는64MiB 이하 PNG/JPEG로 새 이름의 재질을 만들거나 SKM을 읽는다. `export_view`는 기존 폴더의 **새** PNG/JPEG 파일로64–4096픽셀 출력하며 파일 크기/SHA256을 반환한다. 출력은 덮어쓰지 않고 실패한 임시 파일을 정리한다. 두 도구는 로컬 절대 드라이브 경로를 사용한다. 파일 읽기/출력은 라이브러리 batch에 들어가지 않는다.

`configure_display`는 명시된2019 렌더 옵션과 그림자·위도/경도·시간대를 변경한다. ShadowTime은 명시적 UTC offset이 있는 ISO8601이다. 표시 상태는 모델 Undo를 보장하지 않으며 실패 시 이전 값을 복구한다. 복구 확인 실패는 outcome_unknown. 파일 출력도 Undo 대상이 아니다.

## 설치 후 실제 확인

1. 0.9.0 Probe/MCP/RBZ 설치·재시작 후 새 세션/모델/편집 ID를 조회한다. 시험 모델과 로컬 실행 허가를 확인한다.
2. `run_self_test(suite="features2019",confirm_test_model=true)`를 먼저 dry_run, 이후 실행.12개 기능 검사+cleanup. 원시 선 재사용, native ArcCurve, 두 치수,3D 문자, 단면, 속성,100mm 정육면체 체적, 면 내부 판정, target minus tool의500000mm³ 및 X위치를 확인한다. Pro가 아니면 Boolean은 skipped로 표시한다.
3. 결과의 passed/failed/skipped와 cleanup_verified를 확인한다. 기존 `suite=all`은 과거 core+extended 범위를 유지하며 새 suite를 포함하지 않는다. 단일 Undo는 별도 확인한다.
4. raw-drawing 예제를 native verify 후 apply하고 그룹0, 두 치수/문자, Ctrl+Z 한 번으로 전체 제거를 확인한다. 기존 창·패널 기법도 함께 확인한다.
5. 교차선의 면 분할/재질 보존, opening의 실제 구멍·glue, UV 앞/뒤 회전·스케일, SKM/이미지 재질, 점선 표시·그림자·PNG 투명도를 실제 설치에서 확인한다. 이들은 자동 API 대역만으로 합격 판정하지 않는다.

공식 계약 근거: [Entities](https://ruby.sketchup.com/Sketchup/Entities.html), [Group/Boolean](https://ruby.sketchup.com/Sketchup/Group.html), [Face/UV](https://ruby.sketchup.com/Sketchup/Face.html), [Behavior](https://ruby.sketchup.com/Sketchup/Behavior.html), [RenderingOptions](https://ruby.sketchup.com/Sketchup/RenderingOptions.html), [ShadowInfo](https://ruby.sketchup.com/Sketchup/ShadowInfo.html), [View 이미지 출력](https://ruby.sketchup.com/Sketchup/View.html#write_image-instance_method). [원래2019 공백 검토](SKETCHUP_2019_GAP_REVIEW.md)는0.8.0 당시 이력이다.
