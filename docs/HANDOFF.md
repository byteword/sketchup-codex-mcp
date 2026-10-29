# 다른 컴퓨터에서 이어가기 — 2026-10-28

## 최신 상태: 0.12.0 독립 파일·스타일 — 2026-10-29

E: OneDrive 소스/main 기준. C의 `dist/validation-0.12.0`은 검사 복사본이다. 로컬 커밋만 하고 푸시하지 않는다. 도구63개. [0.12 계약·예시·남은 범위](FEATURES_0.12.0.md), [검증](VALIDATION.md), [배포](TEST_RELEASE.md).

사용자가 실제 테스트를 당장 할 수 없어 파일/스타일부터 진행하라고 요청했다. SketchUp 연결·설치 변경·실제 모델 변경은 수행하지 않았다. 선택 그룹/컴포넌트1~25개를 임시 wrapper에 복사하고 current SKP로 저장한 후 abort/메타데이터 복구를 확인한다. 2019 Definition#save_as는 경로/GUID 변경이 있어 원본 정의를 직접 저장하지 않는다. DXF는 Pro 번역기 없이 지정 평면의 mm 선도면을 내보내며 가림선 제거/단면은 없다. IFC는 Pro 및2019–2025/2026+ 옵션을 구분한다.

스타일은2019용 표시 설정 JSON 왕복/미사용 정리를 구현했다. duplicate는2026.2+, remove_style는2026+이므로 메서드 지원을 조회하고 구버전에서는 명시적으로 거부한다. Style#path는2025+임을 반영해2019 목록 오류도 수정했다. 현재/장면 참조 스타일 보호와 미확정 편집 보호를 적용한다. 전체 .style 저장은 아니다.

전체364개 자동 검사 통과(Ruby282/2111 assertions, 라이브러리19, 텍스처7, 지형6, STDIO31, runner6, Win32연동13). 독립 ezdxf1.4.4 판독3방향의 좌표/단위/audit 오류 및 수정0도 확인했다. ZIP5파일·RBZ42소스·SHA·별도 DLL 없는 내장 Jint 실행을 검증했다. 자동 검사와 실제 앱 수용 검사는 별개다.

다음 테스트 가능 시 선택 SKP 왕복/원본 정의/선택/Undo, IFC 번역/분류/단위, DXF 도면, 표시 설정 왕복/스타일 장면 참조와0.9–0.11 미실행 항목을 확인한다. 다음 구현은 가림선 도면, TIN/Drape/Stamp/기존 지형 편집 등이다. OneDrive Git 객체 작성은 이전에 검증한 로컬 객체 생성→내용 해시 검증→E에 새 객체 복사→조건부 main 갱신을 사용한다. 외부 객체 폴더 의존/ACL 변경/전역 Git 설정 변경은 없다. 아래0.11 이하는 이력이다.

## 최신 상태: 0.11.0 전체 장면·파일·지형·분류 — 2026-10-29

E: OneDrive 소스/main이 기준이다. C의 `dist/validation-0.11.0`은 ASCII 검사 복사본이다. 로컬 커밋만 하고 푸시하지 않는다. 도구63개. [0.11 기능·사용법·잔여 범위](FEATURES_0.11.0.md), [자동 검사](VALIDATION.md), [시험 설치](TEST_RELEASE.md).

전체 Page 저장/선택/메타데이터/삭제, 스타일 목록/.style 로드/선택/편집 확정/이름 변경을 구현했다. 2019 `Page.use_style=`는 Style 객체, `Styles.add_style`은 Boolean 반환임을 유지한다. 카메라 전용 scene과0.10 view_preset은 기존 계약을 유지한다. 2019 장면/스타일 Undo는 보장하지 않는다.

SKP는 정의 로드+지정 위치 배치, 모델 복사본 저장(2019/current). DWG/DXF는 Pro native importer/exporter를 호출한다. DefinitionList#import(2021.1+)를 쓰지 않는다. 출력은 새 파일만 생성하고 SHA를 반환한다. CAD importer는 native Undo/단위/그룹화에 맡기며 실패 후 자동재시도 금지다.

Probe authoring `terrain_example`은 `demo.terrain-grid`4파일. 높이 격자/IDW/완만한 높이 조절을 JS에서 계산하고 `draw_geometry(surface_mesh)`로 열린 삼각 표면을 그룹 유/무 생성한다. native capability `surface-mesh/1`이 추가됐다. 분류는 스키마 목록/로드, 정의의 분류 추가/제거/스칼라 값 읽기/쓰기를 구현했다. 공유 변경 확인·잠긴 조상 거부·값 readback을 사용한다.

자동347개 통과(Ruby266/2002 assertions, 라이브러리19, 텍스처7, 지형6, STDIO30, runner6, Win32연동13). 실패/오류/생략0. ZIP의5개 파일, RBZ40개 소스 일치, SHA와 별도 DLL 없는 추출 폴더의 지형 Jint 실행도 통과했다. 현재 연결된 SketchUp 인스턴스가 없어 실제 앱 수용 검사는 미실행이다. 실행 중인 앱/설치 파일/모델은 교체하지 않았다. 다음은0.11 설치 후 장면의 숨김/단면/스타일 복원, SKP/CAD roundtrip, 지형 면 방향/Undo, 실제 스키마 타입/속성 검증이다. 이후 등고선 제약 TIN·Drape/Stamp·기존 지형 편집, 선택 객체 SKP/2D CAD, DC 재계산 등은 별도 기능이다.

OneDrive Git 객체 작성은 `core.createObject=rename`도 일부 객체 폴더에서 Permission denied로 막혔다. 기존 훅·서명 설정이 없음을 확인하고 C의 임시 객체 폴더에서 blob/tree/commit을 작성한 뒤 SHA-1과 내용을 검증해 E 객체 저장소에 새 파일로 복사하고, 기존 HEAD를 조건으로 main 참조를 갱신했다. E 저장소는 C의 임시 객체 폴더에 의존하지 않는다. ACL/전역 Git 설정은 변경하지 않았다. 아래0.10 이하 기록은 이전 상태다.

## 최신 상태: 0.10.0 텍스처·화면 설정 — 2026-10-29

작업 기준은 E: OneDrive 저장소/main. 로컬 커밋만 하며 원격 푸시는 하지 않는다. 새 view_preset을 포함해60개 도구. face-texture/1 선언형 읽기와 stale 검사를 추가하고, Probe의 demo.face-texture 기법으로 이동/회전/축척/타일mm/fit/flip/shear/tilt/4핀/clear를 처리한다. 재질 복사·이미지 교체/제거·반복 크기, 카메라 비율/초점거리/필름폭, 텍스처·안개 표시와 화면 프리셋도 구현했다. [상세 계약](FEATURES_0.10.0.md).

자동321개 통과(실패/오류/생략0): Ruby248개/1871 assertions, 라이브러리18개, 텍스처 수학7개, STDIO29개, runner6개, Win32 연동13개. Ruby는 SketchUp2020의2.5.5 DLL 별도 호스트+API 대역이며 실제 모델 검증이 아니다. [로그](validation-0.10.0.txt), [검증](VALIDATION.md). C의 dist/validation-0.10.0은 검사 복사본이고 개발 기준은 E다.

시험 설치 ZIP은 필수5개 파일. 현재 실행 앱/모델은 변경하지 않았다. 다음은 0.10.0 Probe/MCP/RBZ 설치·재시작 후 시험 모델에서 텍스처·프리셋·Ctrl+Z 수용 검사다. image_width API는mm이며0이36mm 의미인 점을 유지한다. 공유 재질 변경은 affect_all_uses:true, 면별 변경은 유일한 조상을 요구한다.

선언형 읽기가 있는 기법의 native verify는 오프라인 예제PID를 실제 모델에 보내지 않도록 native_fixture_required로 거부한다. 실제 대상 bindings로 plan/apply하여 확인한다. 프리셋은 모델 속성에 저장하며 Pages/전체스타일/개별객체 숨김까지 저장하지 않는다. 이미지 생성은 ChatGPT→로컬PNG/JPEG→재질 등록 흐름; Probe 내 서비스 호출과 techpack 이미지 바이너리 포장은 미구현이다.

OneDrive 저장소에서 Git 객체 파일 작성이 Permission denied로 실패하면 이번처럼 `git -c core.createObject=rename add ...` / `git -c core.createObject=rename commit ...`을 사용할 수 있다. 이번에는 명령별 설정으로 해결했으며 폴더 ACL이나 전역 Git 설정은 바꾸지 않았다.

후속 구현은 전체 SketchUp Page 속성·.style 파일 → SKP/CAD → 지형/분류. 아래0.9.0 이하 기록은 이전 상태다.

## 최신 상태: 0.9.0 우선순위 기능 구현 — 2026-10-29

E: OneDrive 소스/main, 로컬 커밋만 하고 푸시하지 않는다.0.8.0의47개→59개 MCP 도구. 그룹 없는 그리기/직접 편집, `sketchup-operations/1` 기법 계획, 기능·물량·충돌·속성 조회, 치수·주석·단면·점선, 원본 보존 Boolean·교차선·UV·개구부, 텍스처 읽기·이미지 출력·표시/그림자를 구현했다. [상세 사용법·한도·후속 순서](FEATURES_0.9.0.md).

전체299개 자동 검사 통과, Ruby235개/1804 assertions. [검증 기록](VALIDATION.md), [로그](validation-0.9.0.txt). 새 예제 `demo.raw-drawing`은 `library_get(kind=authoring,sections=["operations_example"])`로 조회·저장·수정·공유할 수 있다. 기존 패널/창 계획도 회귀 통과했다. 새 ID를 같은 계획의 다음 단계에서 쓰는 별칭과 신규 조회의 library reads 바인딩은 아직 없다.

설치본은 `dist/sketchup-codex-mcp-0.9.0-test.zip`의5개 파일. 실행 중인 앱과 모델은 교체하지 않았다. **다음 실행 단계는0.9.0 설치·재시작 후 실제 SketchUp 시험**이다. 새 `suite=features2019`(12개+cleanup)는 raw edge 재사용·두 치수·체적·Boolean 방향을 확인한다. 기존 `suite=all`은 과거 범위를 유지한다. UV/재질·개구부·그림자·이미지와 단일 Undo는 별도 확인한다.

우선순위1–3과4 주요 공통 연산을 이번에 구현했고5 일부 표시 설정까지 연결했다. 남은 구현은 전체 장면·스타일 파일 → SKP/CAD 입출력 → 지형/Classifier. DC 내부 재계산과2019 비공개/후속 버전 API는 검증된 공개 계약 없이 연결하지 않는다. 아래0.8.0 및 이전의 ‘미구현’ 표시는 당시 이력이며 최신 판정은 위 문서를 따른다.



## 기능 공백 검토: SketchUp 2019 기준 — 2026-10-29

0.8.0/4b31a07의47개 MCP 도구와 Probe 기법 계획 형식을2019 공식 도구 카드·Ruby API 버전 기록에 대조했습니다. [기능별 지원/제한/누락·개발 우선순위](SKETCHUP_2019_GAP_REVIEW.md), [선별 API 도입 버전](sketchup-2019-api-audit.json). 치수/주석·단면·Boolean·UV·전체 장면/스타일·파일 입출력, raytest/체적/사용자 속성 등 공통 기능이 남아 있습니다.2019 레이어 점선도 미지원입니다. 태그 폴더·active_path setter·weld·EntitiesBuilder·Overlay·PBR는 이후 버전 기능이라2019 누락에 포함하지 않습니다. 기존 MCP 기능도 현재 group/closed-mesh 중심 기법 엔진에는 일부만 연결됐습니다. 검토 문서만 추가했으며 신규 기능 구현/실기 테스트는 하지 않았습니다.

## 최신 상태: 0.8.0 Probe 동적 라이브러리 구현 — 2026-10-29

작업 기준은 E: OneDrive 소스/main입니다. 기존 규격에 따라 Probe 라이브러리 고정7개 MCP 도구(총47개), Jint3.1.6 별도 프로세스, 내구성 수정본/작업/요청 이력, 작업 파일 자동 반영, RBZ 공통 계획 실행·조회, 여러 기법 선택 패키지 export/부분 import를 구현했습니다. 패널과 미닫이 창은 외부 JS 예제로 제공하고 창 스킬은 라이브러리를 우선 사용합니다. 사용자가 개선한 기법을 덮어쓰지 않습니다. [실제 사용 안내·한도](PROBE_LIBRARY_RUNTIME.md), [검증 기록](VALIDATION.md).

자동 검사271개 통과(실패·오류·생략0). API 대역과 실제 Win32/Jint 검사를 구분해 기록했습니다. 시험 배포본 `dist/sketchup-codex-mcp-0.8.0-test.zip`은 필수5개 파일이며 엔진 DLL/라이선스를 Probe에 내장합니다. 변경은 로컬 커밋으로 보관하고 원격 푸시는 하지 않습니다. 소스 기준 E를 유지하고 C의 `dist/validation-0.8.0`은 검사 복사본으로만 사용합니다.

다음 단계는 사용자 설치/재시작 후 0.8.0의 실제 SketchUp 시험입니다. 현재 설치 프로그램과 모델은 변경하지 않았습니다. 새 세션/모델 ID·편집 위치를 조회한 뒤 시험 모델에서 라이브러리 native verify(생성 후 abort/복구), 창 생성·치수/열림 변경·직접 자식 교체·Ctrl+Z 한 번, 기존56항목 suite를 확인하세요. 라이브러리 소스 파일 변경과 일부 패키지 가져오기도 실제 환경에서 확인합니다. 새 generic 연산을 추가할 때는 RBZ 업데이트가 필요하지만 지원 연산을 조합하는 새 기법은 재설치 없이 반영됩니다.

아래 규격/검토의 ‘구현 전’ 상태와0.7.0 준비 내용은 당시 이력입니다. 최신 구현은 위0.8.0을 기준으로 합니다.

## 추가 관리 규격: 여러 기법 선택 패키지 — 2026-10-29

[관리 명세 부록E](PROBE_LIBRARY_SPEC.md#부록-e-선택형-공유-패키지)에 대표 기법1개 이상 선택 export, 공통 의존성 중복 제거, .probe-techpack ZIP, 내용 inspect, 대표 일부/전체 선택 import, 충돌·고정 의존·묶음 등록 원칙을 추가했습니다. 기존 transfer 고정 도구에 inspect_import action을 더하는 설계입니다. 새 런타임 기능을 구현/검사한 것은 아니며 이번 변경은 명세뿐입니다.

## 최신 검토: Probe 라이브러리 관리 규격 v1 초안 — 2026-10-29

ChatGPT가 라이브러리/기법 목록·검색·작성·개선·검증·이용·공유를 관리할 수 있도록 [상세 명세](PROBE_LIBRARY_SPEC.md)를 작성했습니다. 고정7개 MCP 창구, 불변 revision/head/active, 동적 입력 규칙, 수정 충돌·자동 검사/활성화, 계획과 적용 분리, 내구성 작업/중복 방지, 공유 번들·한도를 정의했습니다. 기법 자체뿐 아니라 이름 있는 라이브러리 생성도 포함합니다. JSON 스키마4개와 패널 예제를 함께 저장했고 스키마/정상3건·오류3건/닫힌 메시/수정본 해시를 Python+Node로 확인했습니다. **관리 도구·Jint·RBZ 공통 실행기는 아직 구현하지 않았고 native 검증 결과도 아닙니다.** 이번 변경은 설계·명세 예제뿐이며0.7.0 배포본과 사용자 모델은 바꾸지 않았습니다.

## 최신 설계 수정: Probe 측 동적 기법 라이브러리 — 2026-10-29

사용자가 기법/반복 작업을 즉시 추가·수정하려면 RBZ 내 기법 배포가 부적합하다고 지적했습니다. 기존2026-10-28 권고를 대체해 **Probe 외부 JS/입력 규칙/등록부 + 관리형 작업 프로세스 + RBZ 공통 계획 실행기**로 설계를 수정했습니다. [수정 검토서](TECHNIQUE_LIBRARY_REVIEW.md). Jint는 엔진 후보이며 아직 도입하지 않았습니다. 공통 실행 기능의 최초 RBZ 업데이트는 필요하지만 그 후 지원 연산을 조합하는 새 기법은 EXE/RBZ 재설치 없이 추가·갱신하는 것이 확인 조건입니다. 정적 C# 기법별 스키마도 Probe의 동적 검사로 옮겨야 합니다. 이번에는 문서만 변경했고 버전/배포본/실행 중 모델/기존0.7.0 native 대기 상태는 그대로입니다. 아래 라이브러리 검토는 이전 기록입니다.

## 추가 검토: 기법 프로그램 라이브러리

사용자 요청으로 공통 라이브러리의 타당성과 AI 계산 분담을 검토했습니다. [검토 결과·후보·설계·측정](TECHNIQUE_LIBRARY_REVIEW.md)을 읽으세요. plan/builder/executor 분리와 기법 목록·상세·실행을 권고하며 아직 신규 명령 구현은 하지 않았습니다. 순수 창 계획은3개 크기에서224점/220면, 입력163–164bytes, 중앙값5–6ms였습니다. native/전체 작업/AI 토큰 벤치마크는 아닙니다. 배포본/실행 중인 모델/0.7.0 실기 대기 상태는 그대로입니다.

## 최신 상태: 0.7.0 창 생성 레시피·스킬 준비

0.6.3까지 GitHub main에 푸시한 뒤 사용자 요청에 따라 창 작업을 프로그램과 스킬로 재사용하도록 구현했습니다. 작업 기준은 E: OneDrive 저장소/main입니다. `sketchup_create_sliding_window`를 추가해 도구40개, C#/Ruby0.7.0. 두 짝 미닫이 창을 크기·열림·기존 재질로 한 번에 생성하고 native에서 접합선을 정리하며 네 그룹·하나의 Undo로 묶습니다. [인수·전달 구조·검증 한계](WINDOW_RECIPE.md).

자동 검사245개 통과, 실패/오류/생략0. ASCII 검사 복사본에서 수행하고 source dirs/build 입력 일치를 확인했습니다. 새 스킬 `skills/sketchup-sliding-window`와 기본값을 저장하고 개인 스킬 폴더에도 설치했습니다. 설치 ZIP은 필수5개 파일, `dist/sketchup-codex-mcp-0.7.0-test.zip`. 이번 변경은 로컬 커밋 대상이며 추가 원격 푸시는 하지 않습니다.

**실행 중인 앱은0.6.3이며 새 명령 native 실기는 미실행**입니다. 기존1200×900×100 최적화 창(전체/본틀/두 창짝=4그룹,166면368선)과 사용자900×1800 참조는 개발 검사에서 변경하지 않았습니다. 기본 새 계획기의 형상은 그 실제 창 fixture와 일치합니다. 설치 후 새창 생성·열림/치수 변경·교체·한 번의 Undo를 별도 확인하세요. 기존56항목 suite는 신규 창 레시피를 포함하지 않습니다. 아래 내용은 이전 기록입니다.

## 최신 상태: 0.6.3 실제 전체 검사 통과

사용자가0.6.3 GUI/MCP/RBZ를 설치하고 재시작했습니다. 실제 SketchUp20.0.363/Ruby2.5.5의 새 시험 모델에서 직접 MCP로 suite=all을 한 번 실행한 결과 **56개 통과·실패0·생략0**, 본문48ms입니다. Follow Me, 해제 후 raw_group, 점/꼭짓점 이동이 모두 통과했습니다. cleanup_verified=true, 후속 조회에서 modified=false와 루트 객체/리소스/선택/편집 경로/외곽이 최초 상태와 일치했습니다. UI 갱신 요청 경고0입니다.

[최신 실기 기록](MANUAL_RESULTS_0.6.3.md)과 [원본 응답](native-test-0.6.3-2026-10-28.json)을 읽으세요. 개발 자동 검사229개와 구분합니다. 아래0.6.3 준비/0.6.2 미실행 표시는 당시 기록입니다. 소스 수정은2296b92에 로컬 커밋돼 있고 이번 후속 변경은 문서/실기 결과 기록입니다. 추가 GitHub 푸시는 아직 하지 않았습니다.

이번 전체 검사는 임시 operation의 native API 동작과 정리를 확인했습니다. Outliner CPU·defer/normal 실측, 특수/경계 조건과 다른 SketchUp 버전은 남아 있습니다.0.6.2에서 별도로 확인한 batch rollback/후속 성공/한 번의 Undo와 장면/purge 결과는 그 버전의 기록으로 유지합니다. 같은 suite를 반복하기보다 필요한 다음 작업의 범위를 정하면 됩니다.

## 최신 상태: 0.6.3 수정본 준비 / 실제 앱0.6.2

0.6.2 설치 후 이 채팅의 직접 MCP로 검사했습니다. 전체 suite는43개 통과·raw_group1개 실패·12개 생략이며, 중앙 경로 Follow Me 수정은 실제로 통과했습니다. 추가 개별 검사로 나머지 면/리소스/카메라/장면 기능과 batch 실패 전체 취소·후속 성공·Ctrl+Z 한 번에 두 박스 제거를 확인했습니다. 점/꼭짓점 이동은 후속 좌표 판정에서 취소됐습니다. [실기 기록](MANUAL_RESULTS_0.6.2.md)과 [원본 응답](native-test-0.6.2-2026-10-28.json)을 읽으세요.

실제 해제 결과에는 Vertex·PID0 내부 항목이 섞입니다. 0.6.3은 유효한 직접 Drawingelement만 반환하고 중복/페이지 개수를 정리합니다. 이동 후 검증은 native Length의 허용 오차 비교를 피하도록 Float로 비교합니다. 수정 전 실패 재현 후 전체 자동 검사229개가 통과했습니다. OneDrive 임시 파일 교체 실패가 있어 동일 소스의 비동기화 ASCII 검사 복사본에서 최종 검증했습니다. 검사 복사본은 개발 소스가 아니며 작업 기준은 E: 저장소입니다.

시험 패키지는 `dist/sketchup-codex-mcp-0.6.3-test.zip`, 설치 ZIP은 필수5개 파일입니다. **현재 설치 앱은0.6.2이며0.6.3 실기는 아직 남았습니다.** 사용자가 GUI/MCP/RBZ를 교체하고 재시작한 뒤 새 세션·모델 ID와 로컬 허가를 조회하고 suite=all을 실행합니다. 현재 시험 모델에는 형상이 정리됐지만 modified=true와 Undo 이력이 남습니다. 아래0.6.2 준비/0.6.1 섹션은 이전 기록입니다. 이번 수정은 아직 추가 원격 푸시하지 않았습니다.

## 최신 상태: 0.6.2 Follow Me 수정본 준비

2026-10-28 E: OneDrive 저장소의 0.6.1까지 GitHub main에 푸시했고 이후 작업은 이 폴더에서 진행합니다. ChatGPT 앱 재시작 후 MCP39개 도구의 직접 연결과 한글 Ping을 확인했습니다.

0.6.1 실제 SketchUp20.0.363 일괄 검사에서36개 통과·sweep1개 실패·19개 생략, 임시 작업 정리 성공을 확인했습니다. 모서리 경로의 단독 Follow Me는 성공했으며 진단 그룹은 삭제했습니다. 자세한 상태와 Undo 이력은 [실기 기록](MANUAL_RESULTS_0.6.1.md)에 있습니다.

중앙 경로의 독립 선을 정리하는 수정과 회귀3개를 추가하고 C#/Ruby를 **0.6.2**로 맞췄습니다. 개발 검사224개가 통과했습니다. 수정본 패키지는 `dist/sketchup-codex-mcp-0.6.2-test.zip`입니다. **설치된 앱은 아직0.6.1이므로 수정본 실기는 미확인**입니다. GUI·MCP·RBZ를 함께 교체하고 SketchUp/MCP를 재시작한 다음 새 세션·모델·허가로 `suite=all`을 실행합니다. 남은 기능, batch Undo/rollback, Outliner CPU 비교는 아직 통과로 기록하지 않습니다.

아래0.6.1 섹션은 이 수정 전의 누적 기록입니다.

## 작업 완료 및 다음 확인 기준

현재 작업 기준은 로컬 `main`, 버전 **0.6.1**입니다. 아래 버전별 섹션은 누적 이력이며, 과거의 브랜치·도구 수·설치 상태를 현재 지침으로 사용하지 않습니다.

| 완료 커밋 | 범위 |
|---|---|
| `410c40e` | 0.5.0 기본 드로잉·편집·조회와 빠른 일괄 실기 검사 |
| `a5e99f3` | 0.6.0 컴포넌트·재질·태그·곡선·면·입체·장면·카메라 확장 |
| `667e720` | 0.6.1 UI 갱신 범위, 아웃라이너 갱신 요청 관리, 원자적 일괄 변경 |

최신 사용 계약은 [확장 기능과 제한](EXTENDED_TOOLKIT.md), [UI 갱신·일괄 변경](UI_UPDATES.md), [일괄 검사](BATCH_TEST.md)에 있습니다. 0.6.1 개발 회귀는 **221개 통과**이며 [검증 기록](VALIDATION.md)과 [원본 로그](validation-0.6.1.txt)를 보관했습니다. 이 결과의 형상·UI·Undo는 API 대역입니다. 실제 사용자 앱의 0.6.1 설치·화면 갱신·Undo·CPU 개선은 아직 확인하지 않았습니다.

시험본은 로컬 `dist/sketchup-codex-mcp-0.6.1-test.zip`이며 실행 필수 파일 5개만 포함합니다. 설치 절차와 구성은 [시험 배포 안내](TEST_RELEASE.md), 개별 파일 해시는 [SHA256SUMS.txt](../SHA256SUMS.txt)를 기준으로 합니다. ZIP과 개발 의존성은 Git 추적 대상이 아니므로 다른 PC에서 필요하면 빌드·패키징해야 합니다. 스킬 원본은 `skills/sketchup-mcp`와 `skills/sketchup-self-test`이며 이 PC의 개인 스킬에도 동기화했습니다.

다음 실기 작업은 아래 순서로 진행합니다.

1. 시험본 설치 후 실행 파일·중개 앱·확장 버전이 모두 0.6.1인지 확인하고 현재 세션·모델 ID를 새로 조회합니다.
2. 사용자가 지정한 시험 모델과 실행 허가에서 `run_self_test(suite="all")`을 한 번 실행합니다. 기능 55개와 정리 1개, UI 진단 및 소요 시간을 함께 저장합니다.
3. 별도 `run_batch`로 생성·변경 후 Undo 한 번의 전체 복구, 중간 실패의 전체 rollback, 후속 요청 정상 실행을 확인합니다. 자체 검사 통과만으로 이 항목을 확인했다고 기록하지 않습니다.
4. 아웃라이너를 연 동일 시험 조건에서 `defer`와 `normal`의 실행 시간·CPU·화면 응답을 비교합니다. 최종 표시 복구와 트레이 상태 유지도 확인합니다. 아직 측정값이나 개선율은 없습니다.

위 기능 커밋들은 로컬에 보존되어 있습니다. 이번 문서 정리에서는 GitHub 푸시, 실행 코드 변경, 시험본 재생성 또는 사용자 앱 교체를 수행하지 않습니다.

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
