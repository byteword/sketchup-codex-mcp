# 0.10.0 — 면 텍스처 편집과 화면 설정 프리셋

2026-10-29. E: OneDrive 저장소/main 기준 시험 버전. MCP 도구는60개이며, 새 도구는 `view_preset`이다. 기존 텍스처·재질·카메라·조회·Probe 기법을 확장했다. **자동 검사는 실제 SketchUp2019 모델·화면 검증을 대신하지 않는다. 설치본 교체와 실기는 아직 하지 않았다.**

## 면별 텍스처 기법

`library_get(kind="authoring", sections=["texture_example"])`의 `texture_files`는 `demo.face-texture`의4개 파일이다. 일반 기법처럼 save → offline verify → 선택적 activate → plan → apply로 사용한다. 수정본 관리, 선택 패키지 export/import도 동일하다. 사용자 기법을 자동으로 덮어쓰거나 활성화하지 않는다.

manifest의 선언형 읽기 `face-texture/1`을 추가했다. 실행 bindings는 실제 session_id/model_id/expected_context와 `targets:{face:[조상PID,...,면PID]}`를 준다. 루트 편집 문맥에서 사용하며, 양쪽 재질·UV4점·면의 기준축·모서리·조상 잠금/공유/변환을 읽는다. 이 입력의 fingerprint를 적용 직전에 다시 검사하므로 계획 후 배치나 형상이 바뀌면 재계획해야 한다. `model_query(query="face_texture",options={instance_path:[...]})`로도 같은 입력을 조회한다.

수치 계산은 **Probe의 외부 JS**에서 하고 RBZ는 기존2019 `position_material`을 호출한다. 새로운 배치 기법이나 기본값은 JS를 고쳐 공유할 수 있다.

| params | 의미 |
| --- | --- |
| mode | transform(기존 배치 수정), tile(실제 반복 크기), fit(면의 기준 사각형에 한 장 맞춤), clear(직접 재질 할당 해제) |
| side | front/back, 기본front |
| material | 기존 텍스처 재질 이름. 생략하면 해당 면에 직접 할당된 재질 |
| rotation_degrees | 면 기준축의 법선 방향을 기준으로 회전 |
| scale | [가로,세로] 배율; 확대2는 무늬를 실제로2배 크게 배치 |
| offset_mm | 면 기준u/v 방향 이동. 모델의X/Y축 이동과 구분 |
| tile_size_mm | tile 모드의 이미지 한 장 반복 크기 [가로,세로], 기본300×300 |
| pivot_fraction | 면 기준 사각형 안의 회전·축척 기준점. [0,0] 기본, [.5,.5] 중심 |
| flip_u / flip_v | 방향별 뒤집기 |
| shear_degrees | 면 안에서의 전단 기울기 |
| tilt | [u,v] 원근 왜곡 계수(-.9.. .9). 각도가 아니며0이면 왜곡 없음 |
| corner_offsets_mm | 네 핀의u/v 추가 이동4쌍. 접히거나 교차하는 배치는 거부 |

기본 면 좌표는 첫 외곽 변에서u축을 잡고 외곽의 사각 범위를 사용한다. fit은 임의 다각형의 실제 꼭짓점 전체가 아닌 이 기준 사각형에 맞춘다. transform은 기존4점 UV를 보존하고 면 위의 대응 위치를 바꿔 기존 원근 배치를 이어 편집한다. 부모가 이동·회전·비균일 축척돼 있어도 계산 단위는 모델상의 실제mm다. 앞뒤의 회전 기준은 조회된 동일frame이다.

예: params `{"rotation_degrees":90,"pivot_fraction":[0.5,0.5]}`, 또는 `{"mode":"tile","tile_size_mm":[300,600],"material":"Brick"}`. 기본값과 도구 스키마의 범위를 넘는 입력은 적용 전에 거부한다.

공유 컴포넌트의 한 배치만 바꾸려면 모든 공유 조상을 먼저 독립화한다. 상위 그룹에서 상속된 재질은 직접 UV 편집 대상이 아니므로, textured material을 지정해 tile/fit으로 면에 직접 배치한다. clear는 앞면/뒷면의 직접 할당만 지우므로 부모 재질이 보일 수 있다. 형상과 그룹은 추가하지 않는다. 여러 `face_texture` 명령은 기존 typed batch에서 한 번의Undo로 실행할 수 있다.

초기화 전용API(2022+)와 별도 투영 방향 인수(2021.1+)는 호출하지 않는다. fit/tile은 새 평면 배치를 지정하는 기능이며 UI의 Reset과 같다고 보장하지 않는다. 별도의3D 투영 설정을 유지·변경하는 기능도 포함하지 않는다.

새 기법의 tests.json은 **가짜 면ID를 가진 오프라인 자료**다. 선언형 읽기가 있는 기법의 `verify(environment="native")`는 `native_fixture_required`로 거부해 예제ID를 실제 모델에 제출하지 않는다. 실제 수용 검사는 새 모델의 면을 바인딩한 plan/apply와 후속 UV 조회·Undo로 한다.

## 텍스처 이미지와 재질

`texture_resource`는 다음 action을 지원한다. 모두 한 번의 모델Undo이며 파일을 지우거나 덮어쓰지 않는다.

| action | 인수·동작 |
| --- | --- |
| create_texture | 새name, PNG/JPEG path, 선택 tile_size_mm |
| load_skm | SKM path. 파일에 저장된 이름·크기 사용 |
| copy | source_name → 새로운name. 이미지가 임베드된 경우 원본 파일 없이 복제. 선택 tile_size_mm |
| replace_image | 기존name, PNG/JPEG path, affect_all_uses:true. 크기 생략 시 기존 반복 크기 유지 |
| set_size | 기존name, tile_size_mm, affect_all_uses:true |
| remove_image | 기존name, affect_all_uses:true. 재질은 유지하고 이미지 제거; 색·투명도 유지 |

공유 재질을 바꾸는3개 action은 해당 재질의 모든 사용처에 영향을 주므로 `affect_all_uses:true`가 필요하다. 일부 면에만 쓰려면 copy 후 그 면에 새 재질을 할당한다. **재질의 반복 크기 변경과 면별 UV 축척은 별개**다. PNG/JPEG 입력은64MiB 이하의 로컬 절대 경로이며 폴더가 존재해야 한다. 재질 조회에는 실제 반복 크기mm, 이미지 픽셀 크기, 원본 파일명 정보가 추가됐다.

ChatGPT 이미지 사용 흐름: 이미지 생성 → 로컬 PNG/JPEG 파일 확보 → create_texture와 실제 반복 크기 지정 → 면에 tile/fit/transform 적용. 그림자와 원근이 구워지지 않은 정면 재질 이미지를 만들고, 반복 이음새를 실제로 확인한다. Probe 자체에는 이미지 생성 서비스 호출이나 계정 키 저장을 넣지 않았다. `.probe-techpack`은 기법 소스 패키지이며 이번 버전에서 이미지 바이너리를 포함하도록 바뀌지 않았다. 이미지/SKM은 별도로 전달하고 대상 모델에서 재질 이름을 다시 바인딩한다.

## 화면·카메라·레이어·작업축

`configure_camera`에 aspect_ratio(0=현재뷰, .1..10), focal_length_mm(FOV와 택일), image_width_mm(필름 폭,0=36mm)을 추가했다. 생략한 화면 비율과 필름 폭은 현재 값을 유지한다. SketchUp API의 `image_width`는 **mm**, 위치/평행투영 높이는inch이므로 각각 올바르게 변환한다. 2점 투시·사진 일치 카메라는 계속 제외한다.

`configure_display`에는 텍스처 표시, 안개 표시, 하늘·지면·안개색을 추가했다. 기존 그림자·명암·위도·경도·북쪽·시간 설정을 유지한다. 인공 조명, HDRI, EV 노출, 피사계심도나 외부 렌더러 연결은 포함하지 않는다.

`model_query(query="view_state", options={})`가 현재camera/rendering/shadows/tags/axes를 반환한다. `view_preset`:

- `action:"save", name:"외관"`: 현재 설정을 모델 안에 저장. 같은 이름이면 갱신.
- `action:"apply", name:"외관"`: 저장된 설정 적용.
- `action:"apply", state:{...}`: 일부 설정만 직접 적용. 예: `{"tags":[{"name":"가구","visible":false}]}`.
- `action:"delete", name:"외관"`: 저장값 삭제.
- 목록은 `model_query(query="view_presets",options={})`; 저장값 조회는 options.name.

state의 axes는 origin_mm/xaxis/yaxis/zaxis로 작업축을 지정한다. 직교·오른손 좌표계만 받고 방향벡터는 정규화한다. 형상을 이동시키거나 컴포넌트 정의축을 바꾸지 않는다. 모델상의mm 명령 좌표도 변하지 않는다.

저장/삭제는 모델Undo, 적용은 **이전 상태 스냅샷을 이용한 복구**다. 카메라·표시의2019 Undo를 보장하지 않으므로 typed batch에서 제외한다. 모든 항목을 먼저 검사하고 적용 중 실패하면 카메라·표시·그림자·레이어·축을 복구·재조회한다. 복구도 검증할 수 없으면 outcome_unknown을 반환하며 자동 재시도하지 않는다. 성공 후에도 before 상태를 반환해 명시적으로 되돌릴 수 있다.

최대16개 프리셋,128개 레이어,상태12KB. Layer0/현재 작업 레이어 숨김과 사라진 레이어 참조는 거부한다. 프리셋은 모델 속성에 저장되며 **SketchUp 장면 탭(Page)을 새로 만들지는 않는다.** 개별 객체 숨김, 단면 활성화, .style 파일·전체Page 속성은 아직 저장 범위 밖이다.

## 설치 후 수용 검사와 후속 순서

1. 0.10.0 Probe/MCP/RBZ를 함께 설치하고 재시작. 실제 session/model/context와 실행 허가를 새로 조회한다.
2. 시험 모델에 체크무늬PNG를 create_texture(300×600mm)로 등록하고 앞뒤가 있는 면2개에 적용한다.
3. 한 면만90도 회전/2배 축척/50mm 이동. 다른 면과 반대쪽 재질이 유지되는지 확인한다. 기울임·4핀 왜곡과 부모의 비균일 축척도 확인한다.
4. 계획 후 수동으로UV를 바꾸고 이전 계획 적용이 model_stale로 거부되는지 확인한다. 새 계획은 적용 후 UV 조회와 Ctrl+Z 한 번으로 복구를 확인한다.
5. 재질copy 후 한 면에만 적용하고 복제본의 이미지 교체/제거/실제 크기 변경, 원본 보존과Undo를 확인한다.
6. view_preset 저장 → 카메라/투영/명암/레이어/작업축 변경 → 저장값 적용 → 뷰 이미지 출력. 기존 화면 상태와 비교한다. 2점 투시 등 지원 밖 상태는 변경 전에 거부돼야 한다.

다음 구현은 실제 SketchUp Page의 전체 장면 속성 및 .style 파일 관리 → SKP/CAD 입출력 → 지형/분류다. 이번 프리셋의 지원 범위를 전체 렌더러/전체 장면 지원으로 확대 해석하지 않는다.

공식 API 근거: [면 UV 배치](https://ruby.sketchup.com/Sketchup/Face.html#position_material-instance_method), [텍스처 실제 크기](https://ruby.sketchup.com/Sketchup/Texture.html#size=-instance_method), [재질 이미지](https://ruby.sketchup.com/Sketchup/Material.html#texture=-instance_method), [카메라 필름 폭 단위](https://ruby.sketchup.com/Sketchup/Camera.html#image_width-instance_method), [작업축](https://ruby.sketchup.com/Sketchup/Axes.html#set-instance_method).
