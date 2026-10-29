# SketchUp 2019 대비 플러그인·Probe 기능 공백 검토

2026-10-29. 비교 대상: **0.8.0/main, 소스 커밋 `4b31a07`**, MCP47개. 이 문서는 소스·공식 문서 대조 결과이며 신규 기능 구현이나 실제 SketchUp 2019 실행 검증 결과가 아니다.

## 결론

기본 드로잉·객체 변환·검색은 상당 부분 지원하지만 **치수/주석, 단면, 솔리드 연산, 재질 UV, 스타일/그림자, 완전한 장면, 파일 입출력**은 빠져 있다. UI에 독립 도구가 없는 **광선 충돌, 점의 면 내부 판정, 체적 조회, 사용자 속성, 화면 좌표 변환, 메시 일괄 삽입**도 공개 API를 통해 추가할 수 있다.

현재 MCP 전체 지원 범위와 Probe 기법 엔진의 범위는 다르다. 라이브러리는 `group/1`, `mesh/1`, `material-existing/1`, `verify/1`, `cleanup/1`, `target-summary/1`, `target-subtree/1`만 제공한다. **라이브러리 도입으로 SketchUp 기능 전체가 자동 노출된 것은 아니다.**

## 비교 기준

- 기본 기능의 기준은 [Trimble의 2019 Windows Quick Reference Card](https://download.sketchup.com/HC-QRC2019-SU-W.pdf). Solid Tools, Sandbox, Dynamic Components도 당시 제품의 기능군으로 포함하되 Pro/동봉 확장 조건을 구분한다. LayOut·Style Builder·서드파티 렌더러의 기능은 SketchUp 모델 API와 구분한다.
- ‘UI에 없는 내장 기능’은 **공식 Ruby API로 제공되지만 독립 메뉴가 없거나 UI보다 세밀한 기능**으로 해석했다. 비공개 C++ 함수·미문서화 명령·확장 내부 전역변수는 안정적인 지원 대상으로 단정하지 않는다.
- 최신 웹 문서에는 2020~2027 기능이 섞여 있다. 메서드별 `Version`과 overload별 도입 버전을 확인했다. [공식 API 릴리스 기록](https://ruby.sketchup.com/file.ReleaseNotes.html), [선별한 메서드의 버전 확인 자료](sketchup-2019-api-audit.json).
- 아래 ‘미지원’은 현재 공개 MCP 계약/라이브러리 능력에 없다는 뜻이다. 내부 알고리즘에서 비슷한 계산을 하거나 다른 도구 여러 개로 근사할 수 있는 경우는 별도로 표시한다. 전체 메뉴·모든 API 메서드의 완전한 열거 또는 지원율 계산은 아니다.

## 1. 기본 UI 기능과 현재 상태

| 기능군 | 0.8.0 상태 | 부족한 범위 / 추가 경로 |
| --- | --- | --- |
| 선·사각형·원·다각형·세 종류 호 | 지원 | 수치 좌표 중심. UI 마우스 추론·접선 잠금과 동일한 인터랙션은 없음. |
| 회전 사각형·Pie | 조합 가능 / 전용 모드 없음 | 임의 평면 face로 결과 생성 가능. Pie의 native 호/면 의미를 보존하는 전용 모드 추가 가능. |
| 그룹/컴포넌트 이동·회전·축척·반전·복제·독립화 | 지원, 범위 제한 | 직접 자식·수량·편집 경로 제한. 선형/원형 배열·등분·정렬·축 재설정은 별도 명령 없음. 결과 계산은 Probe 기법으로 묶을 후보. 기존 컴포넌트를 참조하는 배열은 라이브러리에 instance 연산이 먼저 필요. |
| 기존 면 Push/Pull | 제한 지원 | 고립 그룹의 단일 면과 균일/직교 변환만. 일반 모델의 임의 면 돌출·연결 형상 편집·추론 깊이는 현재 범위를 넘음. |
| Follow Me·회전체 | 제한 지원 | 새 닫힌 프로파일/경로와 솔리드 결과만. 기존 모델의 임의 경로/면, 열린 표면 결과까지 UI 전체 범위를 제공하지 않음. |
| Offset | 제한 지원 | 구멍 없는 볼록 윤곽만. 오목·구멍·붕괴 처리 필요. 공개 Ruby API에 일반 `Face#offset`이 있는 것으로 가정하지 말고 별도 알고리즘으로 다뤄야 함. |
| 점·꼭짓점·원시 형상 편집 | 지원, 범위 제한 | 가이드 점·끝점 이동·면 재생성·앞뒤 재질·반전 지원. 구멍 있는 면의 직접 신규 생성과 일반 토폴로지 편집은 부족. |
| Soft/Smooth·동일 평면 정리 | 제한 지원 | 지정 모서리 기반. 곡면 메시 감축과 모든 UV 경계 병합까지 지원하는 것은 아님. |
| 줄자·각도기·가이드선 | 부분 / 가이드선 미지원 | 점·선 좌표/길이로 측정 계산 가능. 각도/거리 전용 측정, 무한/유한 가이드선은 없음. `Entities#add_cline`은6.0부터 가능. [Entities](https://ruby.sketchup.com/Sketchup/Entities.html#add_cline-instance_method) |
| 치수선·지시선 텍스트·3D 텍스트 | 미지원 | 선형/반경 치수2014+, 텍스트/3D 텍스트6.0+. native 엔티티로 추가해야 편집·표시 의미를 보존함. 일반 각도 치수 API가 있다고 가정하지 않음. [Entities](https://ruby.sketchup.com/Sketchup/Entities.html#add_dimension_linear-instance_method) |
| 단면 평면·단면 표시/채움 | 미지원 | 평면 생성·이동·이름·활성화와 표시 옵션. 생성/활성화2014+, 이름2018+. 단면선으로 실제 절단 형상을 만드는 기능은 별도. [SectionPlane](https://ruby.sketchup.com/Sketchup/SectionPlane.html) |
| Intersect Faces·Solid Tools | 미지원 | 면 교차선 생성6.0+, union/intersect/subtract/trim/split/outer_shell8.0+. Boolean에는 솔리드와 제품 등급 조건이 있음; Outer Shell과 Pro 제한 연산을 동일 조건으로 처리하지 않음. [Entities](https://ruby.sketchup.com/Sketchup/Entities.html#intersect_with-instance_method), [Group](https://ruby.sketchup.com/Sketchup/Group.html#subtract-instance_method) |
| 컴포넌트 접착·개구부·항상 카메라 향함·축/스케일 행동 | 미지원 | 컴포넌트 배치/교체와 이름/설명은 지원. `Behavior`, instance의 `glued_to=`는2019 이전부터 있음. 개구부 행동은 벽체 전체 관통 Boolean과 같지 않음. [Behavior](https://ruby.sketchup.com/Sketchup/Behavior.html), [ComponentInstance](https://ruby.sketchup.com/Sketchup/ComponentInstance.html#glued_to=-instance_method) |
| 재질 색·투명도·앞/뒤 지정 | 지원 | 기존 재질 조회/관리 및 면별 지정 가능. 텍스처 유무/기본 정보 조회는 있지만 파일·UV 편집은 없음. |
| 텍스처 위치·회전·스케일·UV·이미지·SKM | 미지원 | `Face#position_material`, `get_UVHelper`, `TextureWriter`, 재질 파일 읽기/저장 등을 연결해야 함. 단순 재질 이름 할당과 구분. [Face](https://ruby.sketchup.com/Sketchup/Face.html#position_material-instance_method), [Materials](https://ruby.sketchup.com/Sketchup/Materials.html#load-instance_method) |
| 레이어 이름·표시·할당 | 지원 | 2019 명칭은 Layers. 현재 제품의 Tags 이름으로 노출되어 있지만 같은 기초 자원을 사용. 활성 레이어 변경과 컬러 표시 등 전체 UI 계약은 없음. |
| **2019 레이어 점선 스타일** | **미지원** | `Model#line_styles`, `Layer#line_style=`가 **2019에 추가**됨. 현재 목록/변경 옵션에 없음. 도면 표시 품질 측면에서 누락 가치가 큼. [Layer](https://ruby.sketchup.com/Sketchup/Layer.html#line_style=-instance_method) |
| 스타일·X-ray·숨은선·단색·배경·안개 | 미지원 | `Styles`/`RenderingOptions`를 통한 조회/변경 필요. 기존 hidden 속성 변경은 화면 스타일 제어와 다름. [Styles](https://ruby.sketchup.com/Sketchup/Styles.html), [RenderingOptions](https://ruby.sketchup.com/Sketchup/RenderingOptions.html) |
| 그림자·날짜/시간·태양·위치 | 미지원 | `ShadowInfo` 값과 객체 casts/receives shadows를 다룰 수 있음. 실제 위도/경도/시간대와 표시 단위를 명시해야 함. 지도/위성 서비스 접속은 별도 조건. [ShadowInfo](https://ruby.sketchup.com/Sketchup/ShadowInfo.html) |
| 장면 | 카메라만 지원 | 레이어 가시성·숨김·단면·그림자·스타일·축·장면 선택/전환·애니메이션 미지원. 2019는 숨김을 통합 플래그로 저장함. 형상과 같은 Undo 보장을 가정하지 말아야 함. [Page](https://ruby.sketchup.com/Sketchup/Page.html#update-instance_method) |
| 카메라·줌·표준 뷰·탐색 | 부분 지원 | eye/target/up·원근/평행·FOV·높이·일부 표준 뷰/줌은 가능. Orbit/Pan/Walk의 대화형 조작, 이전 뷰, 2점 투시/사진 일치는 동일 기능으로 제공하지 않음. 카메라 수치 계산으로 일부 결과는 대체 가능. |
| 축 설정·단위·모델 설정 | 부분 조회 / 변경 미지원 | 단위 조회는 있음. `Axes#set`(2016+)·OptionsProvider 변경·컴포넌트 로컬 축 재설정은 없음. 로컬 축 변경은 정의와 모든 배치의 형상 보존을 함께 처리해야 함. [Axes](https://ruby.sketchup.com/Sketchup/Axes.html#set-instance_method), [OptionsManager](https://ruby.sketchup.com/Sketchup/OptionsManager.html) |
| SKP/이미지/CAD 등 입출력·저장·뷰 이미지 | 미지원 | 모델 경로 조회는 파일 입출력이 아님. Model import/export/save, 정의 load/save_as, View write_image 경로가 필요. 파일 포맷·옵션은2019 설치/Pro exporter를 확인. View 이미지는 화면 출력이며 물리 기반 렌더러는 별도. [Model](https://ruby.sketchup.com/Sketchup/Model.html#import-instance_method), [DefinitionList](https://ruby.sketchup.com/Sketchup/DefinitionList.html#load-instance_method), [View](https://ruby.sketchup.com/Sketchup/View.html#write_image-instance_method) |
| Sandbox 지형 | 전용 지원 없음 | From Contours/Scratch·Smoove·Stamp·Drape·Add Detail·Flip Edge. 일부 결과는 Probe 수치 알고리즘으로 재현 가능하지만 현재 라이브러리의 닫힌 메시 조건은 열린 지형 표면을 거부함. 동봉 확장의 UI 기능을 공식 범용 Ruby 메서드와 동일시하지 않음. [2019 도구 카드](https://download.sketchup.com/HC-QRC2019-SU-W.pdf) |
| Dynamic Components·Classifier | 미지원 | 동적 수식 재계산/옵션/Interact와 IFC 등 분류 속성은 없음. 분류는 공개 API가 있지만 DC 내부 재계산 진입점은 별도 확장 계약 검토가 필요. [ComponentDefinition](https://ruby.sketchup.com/Sketchup/ComponentDefinition.html#add_classification-instance_method), [동적 컴포넌트](https://help.sketchup.com/en/sketchup/making-dynamic-component) |
| 선택·숨김·잠금·정리·Undo | 부분 지원 | 명시 대상 제어와 요청별 Undo는 있음. 조건별 전체 선택/격리, UI의 모든 Unhide/Purge, 명시 Undo/Redo MCP 명령은 없음. library_job/command 결과 이력과 모델 Undo 이력은 다름. 모델 전체 임의 Undo는 별도 범위가 필요. |

2019 카드에 보이는 Warehouse·Add Location·Send to LayOut·인쇄·환경설정·확장 관리도 현재 MCP 자동화 범위 밖이다. 이들은 형상 커널 노출과 별개인 앱/온라인 서비스 통합으로 분류한다. 현재 온라인 서비스가2019 클라이언트에서 작동하는지는 이번 소스 검토로 확인하지 않았다.

## 2. 독립 UI가 없거나 API에서 더 세밀하게 쓸 수 있는 기능

| API 능력 | 2019 근거 | 현재 상태와 활용 |
| --- | --- | --- |
| `Model#raytest` |6.0+ [API](https://ruby.sketchup.com/Sketchup/Model.html#raytest-instance_method)| 미노출. 방향으로 쏴 첫 충돌점/배치 경로 확인. 창/가구를 벽·바닥에 배치, 가림 판정에 유용. 실제 간섭 체적을 주는 연산은 아님. |
| `Face#classify_point` |6.0+ [API](https://ruby.sketchup.com/Sketchup/Face.html#classify_point-instance_method)| 미노출. 점이 면 내부/경계/밖인지 판정. 좌표계·구멍·허용 오차를 native 기준으로 판단. |
| `Geom`의 교차·평면 맞춤·점 포함 |6.0+ [API](https://ruby.sketchup.com/Geom.html)| 플러그인에 일부 유사 계산은 있지만 범용 query/helper 계약 없음. 순수 계산은 Probe JS helper로 만들어 재사용 가능. native 허용 오차와 완전히 같다고 단정하지 않음. |
| Group/ComponentInstance `volume` |8.0+ [API](https://ruby.sketchup.com/Sketchup/Group.html#volume-instance_method)| **상세 조회가 volume을 명시적으로 제외**. manifold 조회와 생성 메시의 내부 체적 계산은 있음. 실제 대상 체적/중첩 집계/재질별 물량은 없음. 중첩·비균일 스케일과 체적 단위 변환을 명확히 해야 함. 질량은 별도 밀도 입력으로 계산. |
| Entity 사용자 속성 사전 |6.0+ [API](https://ruby.sketchup.com/Sketchup/Entity.html#set_attribute-instance_method)| 복제에서 속성 보존은 내부 사용. 범용 읽기/쓰기·검색은 없음. 생성 기법 ID/수정본/매개변수를 객체에 남기면 재편집·교체·동기화에 유용. |
| `Face#mesh`, UVHelper, TextureWriter |6.0+ [API](https://ruby.sketchup.com/Sketchup/Face.html#mesh-instance_method)| 기존 snapshot은 면 윤곽·loops·재질 기초 정보. 삼각분할/UVQ/텍스처 픽셀·내보내기 전체 정보는 없음. 외부 렌더러/정확한 면 처리에 유용. |
| `Entities#fill_from_mesh` / `add_faces_from_mesh` |6.0+ [API](https://ruby.sketchup.com/Sketchup/Entities.html#fill_from_mesh-instance_method)| 미사용. 현재 native 실행은 면별 생성. 큰 메시의 생성 오버헤드를 줄일 후보지만 기존 교차/정점 병합·재질 역할·법선·UV 보존을 비교해야 함. 이미 전송은 묶여 있어 RPC 절감과는 별개. |
| InputPoint/PickHelper/화면 좌표·pickray |기초6.0+, 영역 pick2016+, instance_path2017+ [InputPoint](https://ruby.sketchup.com/Sketchup/InputPoint.html), [PickHelper](https://ruby.sketchup.com/Sketchup/PickHelper.html)| 미노출. 화면 클릭 위치에서 면/모서리/경로 찾기·스냅 참조를 얻을 수 있음. 화면 크기/카메라에 의존하므로 순수 JS 계산만으로 같은 결과를 보장하지 않음. |
| ImageRep 픽셀 처리 |2018+ [API](https://ruby.sketchup.com/Sketchup/ImageRep.html)| 미노출. 재질 이미지 분석·변환의 native 입출력 경로 후보. 이미지 파일/바이트 전달 규격 필요. |
| Drawingelement 그림자 플래그·Behavior·분류 속성 |각 공식 클래스의2019 이전 기능 [Behavior](https://ruby.sketchup.com/Sketchup/Behavior.html), [분류](https://ruby.sketchup.com/Sketchup/ComponentDefinition.html#add_classification-instance_method)| 이름/태그/재질 외 의미 데이터·동작 속성은 대부분 없음. |
| Tool의 임시 draw/draw2d·View animation |기초6.0+ [View](https://ruby.sketchup.com/Sketchup/View.html)| 계획의 bounds/가이드/선택 후보를 모델에 저장하지 않고 미리 표시할 후보. 현재 `plan`은 데이터 요약이며 화면 미리보기는 아님. 2019 Tool 수명 관리가 필요. |
| 모델 변경 Observer의 외부 구독 |2019 이전 공개 observer 체계 [ModelObserver](https://ruby.sketchup.com/Sketchup/ModelObserver.html)| 연결/모델 ID/Undo 등에 내부 observer는 사용. 일반적인 객체 수정/삭제/자원 변경 이벤트를 Probe 기법에 지속 전달하는 구독 계약은 없음. |

## 3. 2019에는 없는 기능 또는 공개 API 제약

| 기능 | 판정 |
| --- | --- |
| 편집 경로를 코드로 여는 `Model#active_path=` |**2020.0+**. 2019는 경로 읽기와 `close_active`는 가능하나 동일 setter는 없음. 현재 수동 편집 위치 유지 정책을 단순 누락으로 취급하지 않음. [API](https://ruby.sketchup.com/Sketchup/Model.html#active_path=-instance_method) |
| `Entities#weld` |**2020.1+**. 2019의 곡선 생성/분해 또는 별도 알고리즘과 구분. [API](https://ruby.sketchup.com/Sketchup/Entities.html#weld-instance_method) |
| `Geom.tesselate` |**2020.0+**. 2019에서 쓸 수 있는 `Face#mesh` 또는 Probe 삼각분할과 구분. [API](https://ruby.sketchup.com/Geom.html#tesselate-class_method) |
| 레이어/태그 폴더 |**2021.0+**. 2019 보완 목록에서 제외. 이전 EXTENDED_TOOLKIT의 ‘미지원’ 목록은 버전 제한까지 구분하지 않았음. [Layer](https://ruby.sketchup.com/Sketchup/Layer.html#folder=-instance_method) |
| 그룹의 `glued_to=` |**2021.1+**. 컴포넌트 배치의 `glued_to=`는6.0+로2019에 있음. [Group](https://ruby.sketchup.com/Sketchup/Group.html#glued_to=-instance_method) |
| `EntitiesBuilder`/`Entities#build` |**2022.0+**. 2019 대량 삽입 대안은 PolygonMesh 계열. [API](https://ruby.sketchup.com/Sketchup/EntitiesBuilder.html) |
| 영구 viewport Overlay 클래스 |**2023.0+**. 2019의 Tool draw와 다름. [API](https://ruby.sketchup.com/Sketchup/Overlay.html) |
| PBR roughness/normal 등 최신 Material API |**2025.0+**. 2019의 색·투명도·텍스처/UV와 구분. [API](https://ruby.sketchup.com/Sketchup/Material.html#roughness_enabled=-instance_method) |
| 2점 투시/Match Photo 전체 상태 설정 |기능은 UI에 있으나 확인한 Camera API에 해당 setter가 없음. `center_2d`/`scale_2d`는 읽기만. 카메라 결과 근사와 UI 전체 제어를 구분하고 미문서화 호출로 지원 완료를 주장하지 않음. [Camera](https://ruby.sketchup.com/Sketchup/Camera.html), [사진 일치](https://help.sketchup.com/en/sketchup/matching-photo-model-or-model-photo) |
| `Face#set_texture_projection` |2014부터 이름은 있으나 공식 문서가 정상 작동하지 않았고 모델 손상 가능성을 명시.2021.1부터 NotImplementedError. 2019에서도 신규 지원의 기반으로 권장하지 않음. `position_material`의2019 지원 overload를 검토. [API](https://ruby.sketchup.com/Sketchup/Face.html#set_texture_projection-instance_method) |

오늘 문서에2019 이전 method와 이후 overload가 함께 적힌 경우, 함수 이름만으로 호환성을 판정하면 안 된다. 예: `position_material`의 추가 projection 인수, `DefinitionList#load`의 옵션, View의 새 좌표 타입. [버전 확인 자료](sketchup-2019-api-audit.json)에 확인된 버전들을 함께 기록했다.

## 4. Probe 기법으로 바로 만들 수 있는 것과 먼저 연결해야 하는 것

**현재 공통 기능으로 기법 추가 가능:** 창·문·가구·프레임·계단 등 닫힌 메시의 매개변수 생성, 동일 기법 반복 배치, 입력 치수 검증, 제공된 하위 구조 snapshot으로 제한된 수치 분석. 일반 알고리즘을 실제 작성/검사해야 하므로 이미 등록된 기법이 있다는 뜻은 아니다. 사진/UV/분류/단면 정보는 snapshot에 없으므로 없는 입력을 추정하면 안 된다.

**기존 플러그인에는 있지만 라이브러리에서 바로 못 쓰는 것:** native ArcCurve/Curve/열린 Face, 기존 정의 배치·컴포넌트 교체, 대상 원시 형상 이동·삭제, 리소스 생성, 카메라/장면 제어. 현재 plan 노드는 group/closed mesh뿐이고 `ctx.call`은 등록된 순수 기법 호출이다. **기존40개 MCP 도구의 임의 호출 기능이 아니다.** 연결하려면 Probe 스키마/validator/권한·후조건과 RBZ 실행기의 공통 연산을 함께 확장한다.

**새 native 경로가 필요한 것:** 치수·텍스트·단면, raytest/분류/체적, 사용자 속성, UV/파일 자원, 솔리드 Boolean. 이런 기반 연산은 한 번 공통 기능으로 구현하고 기법별 조립/계산은 외부 JS에 유지하는 것이 기존 요구와 맞다.

**별도 계약이 필요한 것:** 카메라·장면·스타일·파일 저장/내보내기·UI 도구 활성화는 geometry operation과 효과/Undo가 다르다. 하나의 임의 명령 배열로 전부 묶고 원자적 Undo를 약속하면 안 된다. 읽기, 모델 변경, 뷰 상태, 파일 출력을 구분하고 각 결과를 검사해야 한다.

## 5. 권장 순서

1. **기능 정보와 라이브러리 연결 확대:** 버전·Pro 조건·입력/출력·효과/Undo를 포함한 capability 조회를 보강하고 기존 native curve/face/instance/변환을 계획에서 쓸 수 있게 연결. 공통 읽기/변경 경계를 유지.
2. **기법 재사용에 필요한 조회·속성:** 체적/재귀 물량·raytest·면 내부 판정·사용자 속성. 생성 객체에 기법/수정본/매개변수를 기록하고 모델이 바뀌면 재조회하도록 구성.
3. **기본 도면 기능:** 가이드선·선형/반경 치수·텍스트/3D 텍스트·단면·레이어 점선. 창 크기 표기와 설명, 도면 생성의 완성도가 높아짐.
4. **모델링·렌더 준비:** 면 교차/Boolean·개구부 행동·UV/텍스처·뷰 이미지 출력. 재질 경계/속성/ID가 연산 후 어떻게 변하는지 검증.
5. **표현·외부 자원·특수 기능:** 전체 장면·스타일/그림자, SKP/이미지/CAD 입출력, 지형/DC/Classifier. 일반 Offset·지형·메시 감축은 기법 알고리즘으로 따로 검증.

대량 메시의 `fill_from_mesh`는 별도 작은 성능 실험을 권장한다. 면 수·재질·교차 상태를 동일하게 맞추고 현재 방식과 비교해야 하며, 이번 문서 검토만으로 속도 향상 수치를 단정하지 않는다.

## 6. 현재 소스의 판정 근거

- [전체 도구 조합](../shared/ToolCatalog.cs), [기본 변경 도구](../shared/CommandCatalog.cs), [조회 도구](../shared/DiscoveryCatalog.cs), [확장 도구 스키마](../shared/ToolkitSchemas.json).
- [객체 상세](../extension/su_pipe_probe/entity_details.rb): bounded direct geometry와 manifold. [조회 설명](../shared/DiscoveryCatalog.cs)은 체적 제외를 명시.
- [리소스/컴포넌트](../extension/su_pipe_probe/resources.rb), [카메라/장면](../extension/su_pipe_probe/view_commands.rb), [기본 모델링 제약](../extension/su_pipe_probe/basic_commands.rb), [확장 형상](../extension/su_pipe_probe/extended_geometry.rb).
- [라이브러리 capability·검증](../bridge/library/LibraryRun.cs), [계획 형식](library-spec/plan.schema.json), [RBZ 적용/스냅샷](../extension/su_pipe_probe/library_plan.rb), [JS 호출 문맥](../bridge/library/LibraryWorker.cs).
- [복제 속성 보존](../extension/su_pipe_probe/creation_commands.rb)은 존재하지만 범용 속성 관리 도구와는 다름. 내부에서 쓰는 기능을 모두 ‘없음’으로 분류하지 않았다.

이번 작업은 문서/소스 감사다. 구현 소스·실행 파일·설치된 플러그인·사용자 모델은 바꾸지 않았으며, 기존271개 개발 검사나0.6.3 실기56개 결과를2019 전체 기능 지원의 증거로 확대 해석하지 않는다.
