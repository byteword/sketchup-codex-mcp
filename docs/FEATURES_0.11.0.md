# 0.11.0 — 전체 장면·스타일 → SKP/CAD → 지형·분류

2026-10-29, SketchUp2019 공개 API 기준. 도구63개: 새 `sketchup_style`, `sketchup_model_file`, `sketchup_classification`과 기존 장면·조회·그리기 확장. Probe 계산과 RBZ 공통 실행을 분리한다. **실제 SketchUp에서 새 기능의 수용 검사는 아직 하지 않았다.** 자동 검사와 설치 후 절차를 구분한다.

## 공통 실행

변경에는 현재 `session_id`, `model_id`, `command_id`, `expected_context`와 패널 실행 허가가 필요하다. 먼저 `list_instances`에서 정확한 모델을 고르고 새 명령 번호를 조회한다. 아래 예제는 공통 인수를 생략했다. `dry_run:true`는 입력·현재 상태를 검사하며 파일 디코딩이나 CAD 번역 결과까지 보증하지 않는다. 시간 초과 후에는 `get_command_result`로 결과를 확인하고 자동 재전송하지 않는다.

| 기능 | 효과와 복구 계약 |
| --- | --- |
| 전체 장면·스타일 | 2019 모델 Undo 보장 없음. 실패는 `outcome_unknown`; 목록·현재 화면을 확인 |
| SKP 가져오기 | 정의 로드와 지정 위치의 컴포넌트 배치를 한 모델 Undo로 묶음 |
| CAD 가져오기 | native importer가 그룹화·단위·Undo를 처리. 원자적 취소를 약속하지 않음 |
| SKP 복사본·CAD 내보내기 | 새 파일만 생성. 기존 파일 덮어쓰기 없음. 파일은 모델 Undo 대상 아님 |
| 지형 표면·분류 값 | 모델 Undo 한 번. 지형은 typed batch/기법 계획에 포함 가능 |
| 분류 스키마 로드 | native 자원 로드, 모델 Undo 보장 없음 |

파일·장면·스타일·분류 전용 명령은 typed batch/기법 작업 배열에 넣지 않는다. 분류 값 변경도 이번 batch 허용 목록에서는 제외한다.

## 실제 SketchUp 장면과 스타일

`scene`의 기존 인수는 카메라 전용 동작을 유지한다. `options.scope:"full"`이면 실제 Page의 카메라, 레이어 가시성, 숨김 형상/객체, 단면, 그림자, 작업축, 스타일/표시를 현재 모델에서 저장한다. 2019의 숨김 통합 플래그를 사용하며 2020.1 이상에서만 분리 플래그를 함께 적용한다. 최신 버전의 Environment 속성을 2019 전체 상태에 포함시키지 않는다.

```json
{"action":"create","name":"외부 투시","options":{"scope":"full","transition_seconds":2,"delay_seconds":1,"include_in_animation":true}}
```

`update`는 현재 모델 상태로 다시 저장하며 `new_name`, `description`도 받는다. `delete`는 지정한 전체 장면을 삭제한다. `apply`는 전환 시간을 잠시0으로 설정하고 Page를 선택한 뒤 원래 시간을 복원한다. 결과는 native 장면 선택의 확인이며 렌더링 완료 신호가 아니다. 장면 목록의 `saved_properties`, `selected`, `style_name`, 전환/대기 시간으로 확인하고 `model_query(view_state)`로 현재 화면 설정을 읽는다. 0.10 프리셋은 별도의 모델 속성 저장 기능으로 계속 유지한다.

`get_resources(kind:"styles")`는 모델의 스타일·선택 여부·미저장 편집 여부를 반환한다. `style` 동작별 options:

| action | options |
| --- | --- |
| load | `path`(.style), `select`(기본false) |
| select | 정확하고 유일한 `name` |
| update | `affect_all_uses:true` — 현재 편집 내용을 선택된 스타일에 확정 |
| metadata | `name`, `affect_all_uses:true`, `new_name` 또는 `description` |

미저장 스타일 편집이 있으면 전체 장면 저장과 스타일/장면 전환을 중단한다. `style update`로 먼저 저장하거나 전환 명령에만 `discard_style_changes:true`를 명시한다. 스타일 변경은 이를 사용하는 장면들에 영향을 줄 수 있다. 파일 로드는64MiB 이하, 목록 관리 한도1000개다.

2019 주의점: `Styles#add_style`은 Boolean을 반환한다. `Page#use_style=`는 다른 `use_*`와 달리 Boolean이 아닌 **Style 객체**를 받는다. `.style` 저장/내보내기, 스타일 복제·삭제, 애니메이션 동영상 출력은 제공하지 않는다. [Page 공식 문서](https://ruby.sketchup.com/Sketchup/Page.html#use_style=-instance_method), [Styles](https://ruby.sketchup.com/Sketchup/Styles.html), [Style](https://ruby.sketchup.com/Sketchup/Style.html).

## SKP와 CAD 파일

모델 루트에서 로컬 드라이브 절대 경로를 사용한다. 입력64MiB 이하, 부모 폴더는 미리 있어야 한다. 네트워크/device/상위 이동 경로는 허용하지 않는다.

```json
{"action":"import_skp","path":"C:/Models/window.skp","options":{"origin_mm":[1000,0,0],"name":"참조 창"}}
```

`import_skp`는 정의를 로드하고 컴포넌트 한 개로 넣는다. 내부 구조·재질은 파일의 것을 유지하고 바깥 인스턴스는 Layer0에 배치한다. SketchUp의 정의 로드 캐시가 적용될 수 있다. 파일을 열어 현재 문서를 교체하는 기능은 포함하지 않는다.

```json
{"action":"save_copy","path":"C:/Exports/model-copy.skp","options":{"version":"2019"}}
```

전체 모델의 SKP 복사본을 저장한다. `version`은 `2019`(기본) 또는 `current`. 현재 문서의 경로·저장 상태를 바꾸는 Save As와 구분한다. 선택 객체만 SKP로 저장하는 기능은 이번 범위 밖이다.

`import_cad`는 DWG/DXF를 현재 모델에 넣고 `import_materials`, `merge_coplanar_faces`, `orient_faces`, `preserve_origin`의 명시된 Boolean을 native importer에 전달한다. 생략한 값은 native 기본값/설정을 따른다. 단위와 그룹화는2019 importer 동작을 따르므로 결과 치수·위치·구조를 확인해야 한다. 설치된 Pro 번역기가 필요하다. `DefinitionList#import`는2021.1부터이므로 사용하지 않는다. [Model#import](https://ruby.sketchup.com/Sketchup/Model.html#import-instance_method), [가져오기 옵션](https://ruby.sketchup.com/file.importer_options.html), [DefinitionList#import의 버전](https://ruby.sketchup.com/Sketchup/DefinitionList.html#import-instance_method).

`export_cad`는 전체 모델의3D DWG/DXF를 출력한다. options는 `acad_version`(기본`acad_2013`, 허용12/13/14/2000/2004/2007/2010/2013), `faces_flag`, `construction_geometry`, `dimensions`, `text`, `edges`, `materials`. 요약 대화상자는 끈다. 화면의2D CAD 투영 출력이 아니다. [내보내기 옵션](https://ruby.sketchup.com/file.exporter_options.html).

모든 출력은 전용 임시 폴더에 만든 뒤 새 목적 파일을 배타적으로 생성해 복사한다. 출력 파일의 크기와 SHA-256을 반환한다. 빈 파일, native 실패, 별도 부속 파일이 발생한 출력은 게시하지 않는다. 이미 있는 파일이나 검사 후 다른 프로그램이 만든 파일도 덮어쓰지 않는다. 형상 품질은 파일 재열기 확인이 필요하다. [Model#save_copy](https://ruby.sketchup.com/Sketchup/Model.html#save_copy-instance_method).

## Probe 지형 기법

`library_get(kind:"authoring",sections:["terrain_example"])`가 `terrain_files`4개를 반환한다. `demo.terrain-grid`로 저장 → 오프라인 검증 → 계획 → 적용한다. 기존 선택형 `.probe-techpack` 내보내기/가져오기를 그대로 이용한다. 새 형상 기능이므로 첫 사용에는0.11 Probe/MCP/RBZ가 필요하고, 이후 이 지원 범위 안의 지형 계산 개선은 JS 파일만 바꾸면 된다.

| 입력 | 의미 |
| --- | --- |
| columns, rows | 각1..12셀, 전체128셀 이하 |
| width_mm, depth_mm | 격자 폭·깊이10..1,000,000mm |
| origin_mm | 모델 좌표의 기준점 |
| heights_mm | Y행/X열 순서의 높이 `(columns+1)*(rows+1)`개. 생략하면 평면 |
| samples_mm | 최대64개 측량점 `[x,y,z]`, 기준점 기준의 로컬mm. 높이 배열과 양자택일 |
| bumps | 최대16개 `{center_mm:[x,y],radius_mm,height_mm}`. 반경 끝에서 기울기가0인 완만한 상승/하강 |
| grouping | 기본`auto`는 그룹 없는 면. `group`은 지형 하나만 묶고 `none`도 원시 면 |
| smooth, material | 내부 모서리 부드럽게 표시(기본true), 기존 재질 정확한 이름(선택) |

측량점 보간은 거리 제곱 역수(IDW)이며 동일XY의 중복 측량점은 거부한다. 원점 이동, 보간, 높이 조절, 면 인덱스 계산은 Jint에서 수행한다. RBZ는 `draw_geometry(kind:"surface_mesh")`의 `points_mm`3..256개와0부터 시작하는 `triangles`1..256개를 받아 열린 표면을 만든다. 중복/퇴화 삼각형, 잘못된 인덱스·방향·비다양체 모서리는 사전 거부한다. native 면 생성 실패/예상치 않은 면 분할은 전체 취소한다. 직접 그리기는 주변 형상과 영향을 주고받을 수 있어 빈 편집 공간 또는`group`이 적합하다.

이것은 열린 높이장 지형의 기초 기능이다. 기존 지형의 선택 편집, 등고선 제약 TIN, Drape/Stamp, 절토·성토량, 수직 절벽/중첩 표면, 대규모 메시 감축, DEM 파일 읽기는 미구현이다. Sandbox UI 명령을 비공개 API로 호출하지 않는다. 생성 결과는 닫힌 솔리드가 아니며 원시 면 반환 ID는 최대25개다. 나머지는 다시 탐색한다.

## 분류 스키마와 컴포넌트 속성

`model_query(query:"classification",options:{})`로 로드된 스키마를 조회한다. `offset/limit` 페이지당 최대25개, 전체1000개 한도다. 값 조회는 `definition_id`와 `classification_path`를 함께 지정한다.2019 공개 API는 스키마 내부 타입/속성 목록을 열거하지 않으므로 경로는 스키마 명세에 근거해 지정한다. 없는 경로 또는 native nil은null, choice/트리 객체는 지원하지 않는다.

`classification`의 options:

- `load_schema`: `path`(.skc). 로드 결과는 다시 목록으로 확인한다.
- `add`/`remove`: `definition_id`, `schema_name`, `type_name`, `affect_all_instances:true`.
- `set_value`: `definition_id`, `classification_path`, `value`, `affect_all_instances:true`. 문자열/숫자/Boolean 값만 처리하며 쓰기 후 읽어서 확인한다.

분류는 정의에 붙으므로 모든 배치 인스턴스에 영향을 준다. 잠긴 인스턴스나 잠긴 조상 안의 인스턴스가 하나라도 있으면 변경하지 않는다. 이미지/그룹 정의는 이 명령의 대상이 아니며 컴포넌트로 변환 후 사용한다. 스키마에 따라 값의 타입이 맞지 않으면 native API가 거부하고 모델 작업을 취소한다. choice 값 설정은2019 API가 지원하지 않는다. 스키마 삭제·IFC 파일 입출력·Dynamic Components 수식 재계산은 제공하지 않는다. [Classifications](https://ruby.sketchup.com/Sketchup/Classifications.html), [ComponentDefinition 분류 API](https://ruby.sketchup.com/Sketchup/ComponentDefinition.html#set_classification_value-instance_method).

## 설치 후 실제 모델 수용 검사

1. 시험 모델을 저장하고0.11의5개 실행 파일/RBZ를 설치·재시작한다. `get_state` 버전과 `surface-mesh/1` 기능을 확인한다. 현재 실행 앱을 자동 교체하지 않았다.
2. 보조 레이어·숨긴 객체·단면·다른 축·그림자를 설정해 전체 장면A를 저장하고 상태를 바꿔B를 저장한다. A/B 적용으로 각각의 상태가 돌아오는지 확인한다. 전환 시간과 애니메이션 포함 값도 재조회한다.
3. `.style`을 로드하고 선택·수정·확정한다. 편집 중 전환 거부와 명시적 버리기를 확인한다. 이 단계는 Undo 대신 저장한 시험 모델을 다시 열어 복원한다.
4. 작은SKP를 지정 위치에 가져와 치수·재질·구조를 확인하고 Ctrl+Z 한 번으로 제거한다. SKP 복사본을 별도 창에서 다시 연다.
5. Pro에서 알려진 치수의DWG/DXF를 가져오고 단위·원점·레이어를 확인한다.3D CAD 출력은 CAD 뷰어나 SketchUp에 다시 가져와 검증한다. 기존 파일 거부도 확인한다. native 가져오기 실패가 나면 재시도 전에 모델을 살핀다.
6. 평면/비평면 높이 배열·측량점·높이 조절 지형을 그룹 유/무로 만든다. 면 방향·내부 모서리·경계선·재질·Ctrl+Z를 확인한다. 필요하면 기법 native verify로 임시 생성/abort를 검사한다.
7. 시험용 `.skc`와 컴포넌트의 정확한 타입/경로로 분류 추가·값 변경·제거·Undo를 확인한다. 복수 인스턴스 전체 반영 및 잠긴 조상 거부도 확인한다.

현재 자동 검사의 범위와 한계는 [검증 기록](VALIDATION.md), 다음 컴퓨터 인계는 [HANDOFF](HANDOFF.md)에 있다.
