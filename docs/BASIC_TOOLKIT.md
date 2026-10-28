# 0.5.0 기본 드로잉·편집·조회

기존 19개에 11개 도구를 추가해 총 **30개**입니다. 메뉴나 마우스 위치를 추측해 조작하는 대신 SketchUp 내장 Ruby API의 명시적인 형상·변환 명령을 사용합니다. 실제 0.5.0 설치 후의 결과는 [일괄 실기 검사](BATCH_TEST.md)로 확인합니다.

## 드로잉

| 도구 | 추가 인수 | 동작 |
|---|---|---|
| `sketchup_create_rectangle` | `name`, `origin_mm=[x,y,z]`, `plane=XY/XZ/YZ`, `size_mm=[가로,세로]` | 새 독립 그룹 안에 사각 면 생성. 변 길이 1~1,000,000 mm |
| `sketchup_create_circle` | `name`, `origin_mm`(중심), `plane`, `radius_mm`, 선택 `segments` | 새 독립 그룹 안에 채워진 원 생성. 반지름 1~1,000,000 mm, 분할 8~128(기본 24). 면적은 분할 다각형의 실제 면적 |
| `sketchup_create_polyline` | `name`, `points_mm=[[x,y,z],…]` | 2~64개의 서로 다른 점을 잇는 열린 선. 구간 최소 1 mm. 면은 생성하지 않음 |

모든 좌표는 모델 축 mm입니다. 중첩 편집의 회전·축척·반전을 보정해 그리며, 새 그룹과 원시 형상은 기본 태그에 둡니다. 기존 형상과 병합하지 않습니다. 폴리라인의 자기 교차 등으로 예상과 다른 토폴로지가 생기면 operation을 중단합니다.

## 편집

| 도구 | 추가 인수 | 동작·제한 |
|---|---|---|
| `sketchup_rotate_entities` | `entity_ids`, `pivot_mm`, `axis=[x,y,z]`, `angle_degrees` | 모델 축 기준 피벗·0이 아닌 축으로 -360~360° 회전 |
| `sketchup_scale_entities` | `entity_ids`, `pivot_mm`, `factors=[sx,sy,sz]` | 모델 X/Y/Z 축 기준 0.001~1000배. 0·음수·반전 축척은 미지원 |
| `sketchup_group_entities` | `entity_ids` | 지정 그룹/컴포넌트를 새 바깥 그룹으로 묶고 모델 좌표 변환 유지. 결과의 새 `child_paths` 사용 |
| `sketchup_make_unique` | `entity_ids` | 선택한 그룹/컴포넌트의 상위 정의를 독립화. 내부 컴포넌트 정의까지 깊게 독립화하는 기능은 아님 |
| `sketchup_erase_entities` | `entity_ids` | 명시한 그룹/컴포넌트만 삭제. 한 요청을 한 번 Undo 가능. 면/선 직접 삭제는 미지원 |
| `sketchup_push_pull` | `entity_ids`(그룹 1개), `distance_mm` | 단일 면과 그 경계선만 있는 독립 그룹을 내장 Face.pushpull로 돌출. 거리 절댓값 1~1,000,000 mm |

돌출은 정의가 공유되지 않고 모델 공간에서 직교·균등 축척인 프로파일만 지원합니다. 왜곡·비균등 축척은 거리 해석이 달라질 수 있어 거부합니다. 부호는 변환된 로컬 면 법선 방향을 기준으로 하며, 결과가 닫힌 솔리드인지와 실제 변위 두께를 확인합니다. 새 사각형/원 그룹은 부모 변환을 보정하므로 돌출에 연결할 수 있습니다.

공통 변경 인수는 현재 `session_id`, `model_id`, 새 `command_id`, 현재 `expected_context`, 선택 `dry_run`입니다. 실행 허가가 필요하고 기존 대상은 현재 편집 위치의 직접 자식인 그룹/컴포넌트 최대 25개입니다. 잠금·공유 편집 상위 정의 등 기존 보호 규칙을 유지합니다. 그룹 묶기·정의 독립화 후에는 자식 ID/경로를 다시 조회합니다.

회전·축척·그룹 묶기의 반환 행렬은 열 우선(column-major)이며 위치 성분도 mm입니다. `matrix_translation_unit`으로 단위를 명시하고, 내부 SketchUp API의 inch 행렬을 그대로 mm로 해석하지 않습니다.

기존 선택·화면·이동·속성·박스·복제 도구도 그대로 제공합니다. 일반 편집은 한 operation으로 묶고 실패 시 abort합니다. 일괄 검사는 별도 동작으로, 정상 편집의 Undo 검증과 구분합니다.

## 지정 객체 조회

`sketchup_get_entity_info`는 `session_id`, `model_id`, 전체 `instance_path`로 그룹·컴포넌트·면·선 정보를 읽습니다. 선택·편집 위치를 바꾸지 않고 실행 허가도 요구하지 않습니다.

- 그룹/컴포넌트: 이름·태그·직접 재질·잠금, 모델 축 외곽, 정의 치수, 직접 자식 경로, 제한된 직접 형상 통계.
- 면: 변환을 반영한 `area_mm2`. 선: `length_mm`와 모델 좌표의 `endpoints_mm`.
- `direct_geometry.face_area_mm2`, `edge_length_mm`는 직접 면/선만 합산하며 하위 그룹/컴포넌트를 재귀 합산하지 않습니다. 최대 5000개 또는 0.15초의 협력적 예산이며 `complete`를 확인합니다. 체적은 이번 조회에 포함하지 않습니다.
- 직접 자식은 `child_offset`(기본 0), `child_limit`(1~25, 기본 25)로 나눠 읽습니다. `next_child_offset`이 있으면 다음 페이지로 전달합니다. 실시간 조회이므로 구조가 바뀌면 처음부터 다시 조회합니다.
- 같은 공유 정의의 자식 PID도 배치별 전체 경로로 구분하고 각 부모 소속을 검사합니다. 외곽은 경계 상자 기준이며 실제 형상의 치수보다 클 수 있습니다.

예: 검색으로 박스를 찾은 후 경로로 조회 → 이름/치수 확인 → 회전·축척 → 새 경로/치수 확인. 사각형 생성 → 돌출 → 그룹 정보에서 면적/솔리드 여부 확인도 연결할 수 있습니다.

공식 API: [Entities 생성·그룹·삭제](https://ruby.sketchup.com/Sketchup/Entities.html), [Geom::Transformation](https://ruby.sketchup.com/Geom/Transformation.html), [Face 면적·돌출](https://ruby.sketchup.com/Sketchup/Face.html), [Edge 길이](https://ruby.sketchup.com/Sketchup/Edge.html), [Group 정의 독립화](https://ruby.sketchup.com/Sketchup/Group.html).
