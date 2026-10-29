# 0.12.0 — 독립 파일 출력과 스타일 관리

2026-10-29. 기존 `sketchup_model_file`, `sketchup_style`, `sketchup_model_query`를 확장했다. 도구 수는63개다. 사용자의 요청에 따라 실제 SketchUp 검사는 보류하고 자동 검사·독립 DXF 판독·배포본 검증을 수행한다. 설치된 앱이나 사용자 모델은 변경하지 않는다.

## 공통 계약

모델 루트 편집 위치에서 사용한다. 변경/파일 명령에는 현재 `session_id`, `model_id`, `command_id`, `expected_context`와 패널 실행 허가가 필요하다. 예제에서는 이 공통 인수를 생략했다. `dry_run:true`는 입력과 현재 상태만 검사하고 파일을 생성하거나 모델을 변경하지 않는다. 파일/스타일 작업은 형상 batch/기법 계획의 한 번 Undo에 넣지 않는다.

먼저 `sketchup_model_query(query="file_style_support",options={})`로 실행 중인 SketchUp의 버전, Pro 여부, 스타일 복제/삭제/path 지원 여부를 조회한다. `translator_verified:false`는 설치된 IFC 번역기가 정상 작동하는지 아직 검증하지 않았다는 뜻이다.

모든 출력은 기존 파일을 덮어쓰지 않는다. 같은 출력 폴더의 임시 디렉터리에서 작성한 뒤 비어 있지 않은 결과만 새 파일로 공개하고 SHA-256을 반환한다. 경합으로 목적 파일이 생겨도 덮어쓰지 않는다. 내보낸 파일은 모델 Undo로 제거되지 않는다. 실패/시간 초과 시 명령 결과를 조회하며, `outcome_unknown`을 무조건 재시도하지 않는다.

## 선택 객체 SKP 저장

```json
{"action":"export_selection_skp","path":"C:/Exports/window.skp","options":{"entity_ids":["123"],"coordinates":"first_local"}}
```

- 루트의 그룹/컴포넌트1~25개를 지정한다. 현재 선택 항목을 암묵적으로 사용하지 않는다. 원시 선/면, 중첩 경로, 벽에 부착된 컴포넌트는 이 모드의 대상이 아니다.
- `coordinates:"model"`은 모델 좌표를 보존한다. `first_local`은 첫 대상의 로컬 좌표계를 기준으로 상대 배치를 저장한다. 비균일 축척은 이 좌표계 변환에 포함된다.
- 임시 바깥 그룹에 대상의 정의를 참조하는 컴포넌트 배치를 만들고 이름·태그·재질·숨김·잠금·그림자 플래그·제한된 사용자 속성을 복사한다. 내보낸 파일에서는 원래 그룹도 컴포넌트 배치로 표현된다. 원본의 내부 정의를 다시 그리거나 불필요한 그룹을 원본 모델에 남기지 않는다.
- 임시 그룹의 정의만 `save_as(path)`한 뒤 operation을 abort한다. 원본 배치/선택, 정의 ID/GUID/path/name과 모델 요약이 이전 상태인지 확인한 후 출력 파일을 공개한다. 복구가 확인되지 않으면 `outcome_unknown`이고 최종 파일을 공개하지 않는다.
- SketchUp2019에는 정의 저장의 버전 인수와 `save_copy`가 없으므로 **실행 중인 SketchUp 형식만 지원**한다. 전체 모델의2019 형식 복사본은 기존 `save_copy` 모드를 사용한다. [정의 저장 API](https://ruby.sketchup.com/Sketchup/ComponentDefinition.html#save_as-instance_method).

실제 SketchUp에서 abort 후 정의 메타데이터/Undo 이력/선택 복구와 SKP 재가져오기는 아직 확인하지 않았다.

## 2D DXF 선도면

```json
{"action":"export_dxf2d","path":"C:/Exports/front.dxf","options":{"plane":"XZ","entity_ids":["123"],"origin_mm":[0,0,0],"include_hidden":false,"include_soft":false}}
```

`plane`은 XY(평면), XZ(정면), YZ(측면) 중 하나다. 모델 좌표를 지정 평면에 직교 투영해 DXF의 X/Y로 쓰고 Z는0으로 고정한다. 원점을 mm로 빼며 중첩 배치의 변환도 적용한다. `entity_ids`를 생략하면 루트 전체, 지정하면 루트의 그룹/컴포넌트/선/면1~25개가 대상이다. Pro CAD 번역기를 호출하지 않는다.

기본값은 숨김 객체·숨김 태그와 soft/smooth 모서리를 제외한다. 같은 투영 선과 길이0인 선을 제거한다. 모든 선은 DXF 레이어0, mm 단위이며 출력 형식은 ASCII DXF2000(AC1015)의 LINE이다. 한도는 방문20,000개, 깊이32, 계산2초, 결과5,000선이다. 한도를 넘으면 부분 파일을 내보내지 않는다.

**가림선 제거·면 해칭·단면 절단·원근 투영·곡선 엔티티·치수/문자·레이어별 구분은 지원하지 않는다.** 뒤에 가려진 모서리도 선도면에 나타날 수 있다. 기존 `export_cad`의 native3D DWG/DXF와 별도 기능이다. [LINE 코드](https://help.autodesk.com/cloudhelp/2020/ENU/AutoCAD-DXF/files/GUID-FCEF5726-53AE-4C43-B4EA-C84EB8686A66.htm), [HEADER 버전·단위](https://help.autodesk.com/cloudhelp/2021/ENU/AutoCAD-DXF/files/GUID-A85E8E67-27CD-4C59-BE61-4DC9FADBE74A.htm).

독립 판독기 ezdxf1.4.4에서 XY/XZ/YZ의 중첩 변환·좌표·단위와 audit 오류/자동수정0을 확인했다. 개발 검사에만 사용하며 설치 ZIP에는 추가하지 않는다. CAD 프로그램과 실제 SketchUp 모델의 검증은 남아 있다.

## IFC 가져오기·내보내기

```json
{"action":"import_ifc","path":"C:/Exports/building.ifc","options":{}}
{"action":"export_ifc","path":"C:/Exports/building-copy.ifc","options":{"hidden_geometry":false,"ifc_types":["IfcWall","IfcWindow","IfcDoor"]}}
```

SketchUp Pro와 설치된 IFC 번역기가 필요하다. 가져오기는64MiB 이하 .ifc와 공통 `show_summary:false`만 전달한다. 구조·단위·Undo는 native importer가 결정하며 실패하면 부분 변경 가능성을 `outcome_unknown`으로 반환한다.

내보내기는 전체 모델을 대상으로 버전별 공식 옵션만 받는다.2019~2025는 `hidden_geometry`, `doublesided_faces`, `ifc_mapped_items`, `ifc_types`. 기본 필터는 공식26종 전체이며 빈 배열·중복·알 수 없는 타입은 거부한다.2026+는 `ifc_version`("IFC 2x3" 또는 "IFC 4"), `standard_ifc_hierarchy`, `hidden_geometry`, `tessellated_geometry`를 받는다. 마지막 옵션은IFC4에만 허용한다. 다른 버전의 옵션을 조용히 무시하지 않는다. [공식 exporter 옵션](https://ruby.sketchup.com/file.exporter_options.html), [importer 옵션](https://ruby.sketchup.com/file.importer_options.html).

## 스타일과 표시 설정 파일

```json
{"action":"export_settings","options":{"path":"C:/Exports/render-settings.json","name":"Render settings","include_shadows":true}}
{"action":"import_settings","options":{"path":"C:/Exports/render-settings.json"}}
{"action":"purge_unused","options":{"confirm_model_wide":true}}
```

표시 설정은 UTF-8 JSON `probe-display/1`로 주고받는다. rendering과 선택적 shadows만 저장하며 크기는16KiB 이하, JSON 중첩은12 이하로 제한한다. 허용된 키/타입/값 범위를 적용 전에 검사한다. 가져오기는 현재 편집 중인 표시 설정에 반영하고 실패하면 이전 설정으로 되돌린다. native Style을 새로 만들거나 선택/편집 확정하지 않는다. `.style` 전체 파일, 워터마크/텍스처 이미지, 카메라·레이어·장면 정보는 포함하지 않는다. 더 넓은 상태는 기존 전체 scene/view_preset을 사용한다.

미사용 스타일 정리는2019에서 지원한다. 모델 전체 작업이므로 명시적 `confirm_model_wide:true`를 요구하고 미확정 스타일 편집이 있으면 거부한다. 선택된 스타일과 장면 참조를 보존했는지 확인하며 제거 수와 최대25개 이름을 반환한다. native 자원 변경은 모델 Undo를 보장하지 않는다.

개별 복제/삭제는 설치 버전의 실제 메서드 지원을 검사한다.

| 동작 | 인수 | 지원·보호 |
| --- | --- | --- |
| `duplicate` | `name`, `new_name`, 선택적 `select`, `discard_style_changes` |2026.2+. 이름이 유일한 확정 스타일을 복제. 현재 미확정 편집은 복사하지 않음. 선택 변경 시 미확정 편집 보호 |
| `delete` | `name` |2026+. 유일한 이름만 허용. 현재/마지막/장면 참조 스타일은 삭제 거부 |

[Style#duplicate](https://ruby.sketchup.com/Sketchup/Style.html#duplicate-instance_method), [Styles#remove_style/purge_unused](https://ruby.sketchup.com/Sketchup/Styles.html).2019에서는 개별 복제/삭제 대신 표시 설정 파일과 미사용 정리를 이용한다. 기존 스타일 목록이2025+ 속성 `Style#path`를 무조건 호출하던 호환성 문제도 수정했다.2019에서는 path를 null로 반환한다.

## 나중에 할 실제 앱 확인과 후속 기능

지금은 실행하지 않는다. 다음 테스트 가능 시 선택 SKP 재가져오기와 원본/Undo 보존, IFC 왕복과 분류/단위, DXF 도면 비교, 표시 설정 왕복과 장면 참조 보존을 확인한다. 개별 스타일 복제/삭제는 각각 지원 버전에서 확인한다. 자동 검사 결과는 [검증 기록](VALIDATION.md)에 분리했다.

남은 구현은 가림선 제거를 포함한 도면 출력, 전체 .style 저장의 공개 API 지원 검토, 등고선 제약 TIN·Drape/Stamp·기존 지형 편집, 공식 계약을 확인한 DC 연동 등이다. 이번 버전이 이 범위를 완료했다고 보지 않는다.
