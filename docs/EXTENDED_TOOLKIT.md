# 0.6.0 기능 대조와 확장 도구

> 0.9.0의 그룹 없는 생성/직접 편집·주석·단면·조회·Boolean·UV·표시 및 파일 기능은 [최신 추가 규격](FEATURES_0.9.0.md)에 정리되어 있습니다. 아래 미지원 표시는 작성 당시 범위이며 최신 구현 여부는 추가 규격을 우선합니다.

후속 검토: **0.8.0을 SketchUp 2019에 대조한 최신 지원/누락·API 버전 구분은 [기능 공백 검토](SKETCHUP_2019_GAP_REVIEW.md)를 참고하세요.** 아래는0.6.0 당시 기록이며 태그 폴더 등2019 이후 기능도 남은 항목에 섞여 있습니다.

요청 목록의 누락 기능을 추가해 MCP 도구가 30개에서 **38개**가 되었습니다. 아래의 ‘구현’은 소스·개발 회귀 검증 기준입니다. **실제 SketchUp 2019의 0.6.0 설치 후 검사는 아직 미실시**이며, 이전 0.4.x 실기 결과로 대신하지 않습니다.

## 요청 목록 대조

| 요청 | 0.6.0 구현과 지원 범위 |
|---|---|
| 그룹화 / 그룹 제거 | `group_entities`, `component:explode`. 해제는 내용물을 보존합니다. 삭제는 기존 `erase_entities`입니다. 그룹화는 그룹·컴포넌트·점·선·면, 최대25개를 받습니다. 연결된 면은 경계선과 인접 면을 모두 지정해야 합니다. |
| 다중 그룹 제어 | 최대25개 이동·회전·축척·반전·속성 변경·복제·삭제·그룹화. 서로 다른 편집 위치에 걸친 일괄 변경은 거부합니다. |
| 컴포넌트 생성 / 편집 | 그룹을 컴포넌트로 전환, 정의 이름·설명 변경, 내용의 점·선·면 편집. `make_unique`로 독립화할 수 있습니다. |
| 기존 컴포넌트로 변경 / 기존 정의로 생성 | `component:replace`, `instantiate`. 현재 모델에 있는 정의를 선택하며 변환 행렬을 보존합니다. 외부 SKP 불러오기는 포함하지 않습니다. |
| 공유 컴포넌트 편집 | 기본은 공유 정의 편집을 거부합니다. `edit_geometry`의 `affect_all_instances=true`를 명시하면 같은 정의의 모든 배치에 적용합니다. 잠긴 직접 배치가 있으면 거부합니다. 공유 그룹은 먼저 독립화합니다. |
| 재질 조회 / 변경 | 재질 목록·RGB·불투명도·텍스처 유무 조회, 생성·이름·색·불투명도 수정·삭제. 그룹/컴포넌트 재질 지정과 원시 면의 앞·뒤 재질 지정/해제. 텍스처 파일 입출력·UV 편집은 제외합니다. |
| 레이어(태그) 조회 / 변경 / 생성 / 수정 / 삭제 | 정확한 이름·표시 상태 조회/관리, 객체에 지정. Layer0는 보호합니다. 활성 태그의 삭제·숨김을 거부합니다. 삭제는 형상을 남기고 기본 태그로 재지정합니다. 폴더 기능은 제외합니다. |
| 불필요 항목 제거 | 정의·재질·태그별 `purge_unused`. `confirm_model_wide=true`가 필요하며 모델 전체의 미사용 리소스를 정리합니다. 스타일 정리는 미지원입니다. |
| 표면 단순화 | 지정한 동일 평면 내부선을 제거해 면을 병합합니다. 두 면의 재질·태그·숨김 상태가 같고 텍스처·접착 객체가 없어야 하며 면적 보존을 검사합니다. 곡면 메시의 삼각형 감축은 미지원입니다. |
| 점 생성 / 이동 / 삭제 | ConstructionPoint(가이드 점). 모델 좌표 mm로 생성·이동·삭제합니다. 기하 꼭짓점은 별도로 선의 start/end를 지정해 이동합니다. 고립 Vertex 생성은 SketchUp의 형상 모델에 맞지 않습니다. |
| 선 생성 / 변형 / 삭제 | 폴리라인·자유곡선 생성, 기존 컨테이너에 선 추가, 명시한 끝점 이동, 선 삭제. 연결된 면이 함께 바뀌거나 삭제될 수 있습니다. |
| 면 생성 / 재생성 / 삭제 | 단순 평면 윤곽으로 생성, 기존 선의 `find_faces`로 재생성, 지정 면 삭제·뒤집기. 구멍 포함 윤곽의 신규 생성은 제외합니다. |
| 세 종류 호 / 정밀도 | 중심·반지름·각도, 두 끝점·부호 있는 벌지, 시작·통과·끝 세 점. `segments=3..128`, 기본24. native `ArcCurve`로 만듭니다. |
| 여러 면 부드럽게 / 해제 | 명시한 모서리의 soft/smooth 플래그 설정·해제. 각도 임계값 이하인 두 면 사이의 선에 적용합니다. 형상 감축과 다릅니다. |
| Extrude | 기존 `push_pull`: 독립 단일 면 그룹에 수직 돌출. 균일·직교 스케일 필요. `sweep`은 경로 돌출입니다. |
| 입체 회전 | 기존 `rotate_entities`: 임의의 모델 축·피벗 회전. `revolve`는 프로파일의 회전체 생성입니다. |
| 회전 / 선분 따라 면 생성 | `revolve`: 축을 포함한 한쪽 평면의 닫힌 프로파일을 회전해 닫힌 입체 생성. `sweep`: 닫힌 면과 시작 수직 경로로 native Follow Me 실행. 두 기능 모두 manifold 결과를 요구합니다. |
| 베지어 곡선 | 제어점2..16개를 De Casteljau 방식으로 분할해 SketchUp Curve 생성. 분할 수3..128. 원래 제어점을 유지하는 파라메트릭/NURBS 객체는 아닙니다. |
| 자유곡선 | 입력 좌표2..64개를 연결한 Curve. 화면에서 마우스 궤적을 수집하는 기능은 아닙니다. |
| 장면 생성 / 수정 / 조회 / 적용 / 삭제 | **카메라 전용 장면**을 생성·수정·이름 변경·삭제합니다. 기존 장면은 카메라만 즉시 적용할 수 있습니다. 다른 상태가 포함된 기존 장면의 수정·삭제는 거부합니다. 전체 스타일·그림자·태그 가시성을 포함한 장면 관리는 미지원입니다. |
| 뷰 설정 | 기존 정면·우측·위·등각 뷰/확대, 새 eye/target/up·원근/FOV·평행 투영 높이 설정. 2점 투시·사진 일치는 제외합니다. |
| 다각형 생성 | 중심·평면·반지름·변 수3..128로 정다각형 면 생성. 일반 다각형은 점 배열의 `face`로 생성합니다. |
| 다면체 생성 | 점 배열과 면별 인덱스 목록. 닫히고 일관된 면 방향을 검사하며 최대256면·2048인덱스입니다. 자기 교차 없는 입력이 필요합니다. |
| Offset 도형 | **구멍 없는 볼록 평면 다각형**에서 새 면 생성. 양수는 바깥, 음수는 안쪽. 붕괴·역전·오목 윤곽은 거부합니다. 일반 Offset 전체 범위는 미지원입니다. |
| 확대 / 축소 / 3D 회전 / 반전 | `scale_entities`, `rotate_entities`, 새 `mirror_entities`. 축척은 양수, 반전은 모델 X/Y/Z 축에 수직인 피벗 평면을 지정합니다. |

## 공통 계약

조회는 현재 session/model만 필요합니다. 변경은 로컬 실행 허가·현재 model ID·`expected_context`·새 `next_command_id`가 필요합니다. `dry_run`도 ID를 소비합니다. 시간 초과 시 동일 ID의 결과만 조회하고 변경을 자동 재전송하지 않습니다.

새 도형은 독립 그룹에 만들고 새 원시 형상은 Layer0를 사용합니다. mm는 중첩 그룹의 변환과 관계없이 모델 축 좌표입니다. 그룹/컴포넌트 대상은 현재 편집 위치의 직접 자식입니다. `edit_geometry`는 그 직접 자식 컨테이너 안의 원시 ID를 받습니다. 상세 조회의 전체 경로로 소속을 확인한 후 사용합니다. 편집 위치를 자동으로 열거나 닫지 않습니다.

SketchUp 2019에서는 정의·재질·태그에 persistent ID가 없습니다. `get_resources`와 `get_entity_info.item.definition`의 **`definition_id="definition:<entityID>"`**는 현재 모델 세션에서만 사용하는 리소스 식별자입니다. 도형의 persistent ID와 혼동하지 말고 문서 전환 후 다시 조회합니다. [공식 버전별 PID 지원](https://ruby.sketchup.com/Sketchup/Entity.html#persistent_id-instance_method)을 기준으로 처리합니다.

형상·리소스 변경은 요청당 한 model operation을 사용하고 실패하면 abort합니다. 카메라는 별도 상태 복구를 사용합니다. **SketchUp 2019의 장면 속성 변경에는 같은 Undo 보장을 하지 않습니다.** 장면 변경 오류는 보수적으로 `outcome_unknown`으로 반환합니다. [공식 Page API](https://ruby.sketchup.com/Sketchup/Page.html)에 카메라 등 장면 속성의 Undo 지원이 2026부터 추가된 것으로 명시되어 있습니다.

## 새 도구의 인수

모든 변경 도구는 공통 인수 외에 아래 인수를 사용합니다. `options`는 JSON 객체이며 각 동작에 해당하지 않는 키는 거부합니다. 정확한 타입/범위는 MCP schema와 [스키마 원본](../shared/ToolkitSchemas.json)을 참조합니다.

| 도구 | 인수 |
|---|---|
| `get_resources` | `kind=materials/tags/definitions/scenes`, 선택 `offset`, `limit`(최대25). `next_offset`으로 이어 조회. |
| `manage_resource` | `kind`, `action=create/update/delete/purge_unused`, `options`. create/update는 `name`, 선택 `new_name`(update), `color_rgb`,`alpha`(재질) 또는 `visible`(태그). delete는 name만. purge는 confirm_model_wide만. 정의는 purge만 지원. |
| `component` | `action`, `options`. convert: entity_ids, 선택 name. explode: entity_ids. replace: entity_ids,definition_id. instantiate: definition_id,origin_mm, 선택 name. metadata: definition_id,affect_all_instances=true와 name/description. |
| `create_geometry` | `kind`, `name`, `options`. 아래 목록 참조. |
| `edit_geometry` | `container_id`, `action`, `options`, 선택 `affect_all_instances`. 추가는 points_mm, 꼭짓점 이동은 vertex_moves, 나머지는 entity_ids. move_points는 delta_mm 추가, properties는 material/back_material/hidden, soften은 angle_degrees(기본30) 선택. |
| `mirror_entities` | entity_ids(최대25),pivot_mm,axis=X/Y/Z. |
| `configure_camera` | eye_mm,target_mm,up,perspective. 원근이면 선택 fov_degrees(기본35), 평행이면 선택 height_mm(기본10000). |
| `scene` | action=create/update/apply/delete,name,options. create/update에서 new_name,description 선택, 나머지는 빈 options. apply는 저장된 카메라만 적용하고 선택 장면 탭/다른 상태는 바꾸지 않음. |

`create_geometry.options`:

- points / face / freehand: points_mm. face는3..64개 단순 평면 윤곽.
- polygon: origin_mm,plane=XY/XZ/YZ,radius_mm,sides.
- arc_center: origin_mm,plane,radius_mm,start_degrees,sweep_degrees.
- arc_two_point: points_mm=[start,end],plane,bulge_mm. 양수 벌지는 평면 normal × chord 방향.
- arc_three_point: points_mm=[start,through,end]. 3D 평면도 가능.
- bezier: points_mm(제어점2..16개).
- polyhedron: points_mm,faces(0부터 시작하는 점 인덱스의 면별 배열).
- offset: points_mm,distance_mm.
- revolve: points_mm(닫힌 면 윤곽, 마지막 점 반복하지 않음),pivot_mm,axis,sweep_degrees(0 제외, ±360까지).
- sweep: points_mm(닫힌 면 윤곽),path_mm(2..64점). 경로 시작은 면 평면 위, 첫 구간은 면에 수직.
- 호/베지어/revolve의 선택 segments는3..128, 기본24. 회전체도 전체 메시256면/2048인덱스 제한을 받으므로 프로파일이 복잡하면 분할 수를 낮춰야 함.

`edit_geometry.vertex_moves`는 `[{"edge_id":"...","endpoint":"start","position_mm":[x,y,z]}]` 형식입니다. 같은 꼭짓점은 한 번만 지정합니다. 선/면의 삭제나 이동은 연결된 형상을 바꾸므로 이후 경로·자식을 다시 조회합니다. add_face/rebuild_faces는 기존 컨테이너의 형상과 결합할 수 있습니다.

## 목록에 없었던 기본 기능과 남은 항목

공식 [드로잉 도구 안내](https://help.sketchup.com/en/sketchup/drawing-lines-shapes-and-3d-objects)와 [호 도구 안내](https://help.sketchup.com/ko-kr/sketchup/drawing-arcs)를 대조했습니다. 이번 구현과 별도로 아래 기능이 남아 있습니다.

| 기능 | 상태 / 후속 범위 |
|---|---|
| 숨김·다시 표시, 잠금·해제, 이름 변경, 선택, 줌 | 기존 구현. 원시 형상 숨김도 이번 properties에서 지원. 전체 모델 ‘숨김 해제/격리’는 미지원. |
| 회전 사각형 | 임의 평면 face 또는 기본 사각형 생성 후 회전으로 가능. 세 점 전용 단일 도구는 없음. |
| Pie / 부채꼴 | SketchUp에는 세 종류 호 외에 네 번째 Pie 도구가 있음. 전용 모드 미지원. |
| 줄자·각도기·가이드선·치수·텍스트·3D 텍스트 | ConstructionPoint만 지원. 가이드선, 치수/텍스트 전용 명령 미지원. |
| 섹션 평면 생성·이동·활성화 | 미지원. 다음 기본 문서/뷰 도구 후보. |
| 객체 정렬·축 정렬·원점/축 설정 | 이동/회전의 수치 조합으로 가능. 스냅·추론, 자동 정렬·로컬 축 편집 전용 명령 미지원. |
| 배열 복제 / 등분 배치 | 한 번씩 복제는 지원. 직선/원형 배열과 등분 배치의 단일 명령 미지원. |
| 면 교차·솔리드 합집합/차집합/교집합·외부 셸 | 미지원. 버전/Pro 지원 및 결과 검증이 필요. |
| 면적·길이·체적·질량 | 직접 면적·선 길이 구현. 전체 재귀 집계, 체적·밀도 기반 질량은 미지원. |
| 스타일·그림자·안개·태그 폴더·완전한 장면 상태 | 미지원. 장면은 현재 카메라 전용. |
| 재질 UV·텍스처 파일, 이미지/외부 컴포넌트 입출력 | 미지원. 별도 파일 접근 계약 필요. |
| 일반 오목/구멍 Offset, 곡면 메시 감축 | 이번 제한 구현과 구분해야 하는 후속 알고리즘 과제. |

다음 우선순위는 설치 후 전체 일괄 검사 → 실패한 native 차이 수정 → 가이드/치수·섹션 평면·배열 복제 순으로 권장합니다. 전 기능 구현 완료나 실제 앱 검증 완료로 해석하지 않습니다.

## 구현 근거

- [Entities API](https://ruby.sketchup.com/Sketchup/Entities.html): add_cpoint/add_curve/add_arc/add_face/transform_by_vectors 등 native 형상 조작.
- [ComponentInstance API](https://ruby.sketchup.com/Sketchup/ComponentInstance.html): definition=, explode.
- [Face API](https://ruby.sketchup.com/Sketchup/Face.html): followme, pushpull.
- [Layers API](https://ruby.sketchup.com/Sketchup/Layers.html): remove(layer,false)는 형상을 보존하는 태그 삭제.
- [Materials API](https://ruby.sketchup.com/Sketchup/Materials.html): 재질 관리와 purge_unused.
- [Curve API](https://ruby.sketchup.com/Sketchup/Curve.html): Curve/ArcCurve는 분할된 선들의 묶음. 베지어는 이를 이용한 추가 수치 구현.
