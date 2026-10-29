# 검증 범위

## 0.9.0 그룹 없는 그리기·2019 공통 기능 — 2026-10-29

전체 **299개 통과**, 실패·오류·생략0. Ruby235개/1804 assertions, 라이브러리/Jint17개, MCP STDIO28개, 외부 실행기6개, Win32/MCP/Ruby13개. [최종 로그](validation-0.9.0.txt). Windows/.NET4.8 x64, SketchUp2020 Ruby2.5.5 DLL 호스트/Minitest5.15.0/Python3.13. 원본 E와 ASCII 검사 복사본의 소스·빌드 입력 일치를 확인했다. 설치 ZIP의5개 파일과 체크섬, RBZ의34개 소스 일치, 외부 DLL 없는 추출 폴더에서 내장 엔진의4단계 원시 도면 계획 실행을 확인했다. [패키지 검사](validation-0.9.0-package.json).

추가 검증: raw 선·면/기존 그룹 호환, 직접 편집·Undo, 편집 좌표 변환·공유 조상 거부, typed library plan 성공/실패 전체 취소, 새 예제 저장·검증·패키지, 허용 명령/transport override 차단. API 대역에서 native 체적의 부모 행렬식·ray/분류 좌표, 속성 읽기/쓰기/삭제, 주석·단면, Boolean의 복사본/호출 방향·원본 보존, 교차 좌표계, UV·공유 거부, 표시 상태·파일 전용 생성·오류 정리를 검사했다. 실제 Windows IPC와 Jint는 기존 통합 검사를 통과했다.

초기 회귀 검사에서 기존 mesh manifest에 commands/1까지 요구하던 호환성 오류와 batch 개수 단정(18→26)을 수정했다. Windows 초기 로딩 지연에 정상 예제가 외부 프로세스 감시로 종료되어, Jint script 시간 제한은 그대로 유지하고 로딩/JIT/직렬화 여유만1.5초→5초로 조정했다. 최종 전체 검사에서 시간 제한/격리 검사도 통과했다.

**299개는 실제 SketchUp2019 형상 커널 실기299개를 뜻하지 않는다.** 새 native `suite=features2019`는 구현·dry-run 계약을 검사했지만 실제 설치에서는 아직 실행하지 않았다. 병합/면 분할, Boolean 실제 방향·체적, 치수/폰트, UV/개구부, SKM, 점선·그림자·이미지 출력은 [설치 후 절차](FEATURES_0.9.0.md)로 확인한다. 기존0.6.3의56항목 실기와 구분한다. 실행 중인 프로그램/모델은 변경하지 않았다.


## 0.8.0 Probe 라이브러리·엔진·패키지 — 2026-10-29

전체 **271개 통과**, 실패·오류·생략0: Ruby211개/1688 assertions, 라이브러리/Jint14개, Python STDIO27개·외부 실행기6개·Win32/MCP/Ruby 통합13개. [최종 로그](validation-0.8.0.txt). 설치 ZIP의5개 파일·RBZ 전체 소스·체크섬과 DLL 없는 추출 폴더의 windowless 한글 엔진 실행도 [패키지 검사](validation-0.8.0-package.txt)에서 확인했습니다. Windows/.NET4.8 x64, SketchUp2020 Ruby2.5.5 DLL 호스트·Minitest5.15.0, Python3.13.17. ASCII 검사 복사본에서 실행하고 소스/빌드 입력을 원본과 대조했습니다.

검증 범위: 전체 수정본 저장/CAS·동일 요청 재조회·재시작 복구, 초안 실패 시 활성본 유지, Jint 격리/시간 제한/한글 입출력, 긴 소스 바이트 페이지·계획 해시, 빈 라이브러리 작성 안내, 작업 파일 자동 초안/검사 후 활성화, 다중 대표 기법 export/일부 import·의존 폐쇄·fork 재작성·가져오기 충돌·경로/해시 검증·코드 미실행. 실제 Win32 pipe에서 native 실행 허가/거부·작업 ID와 명령 이력 연결·중복 생성 방지·임시 검증 abort와 복구를 확인했습니다. Ruby API 대역에서 한 operation/Undo, 재질/bounds/solid/교체 취소/지문 변경 감지를 검사했습니다. 창 JavaScript의5개 fixture와 기본 형상 모든 면/재질 역할은 기존 승인 창 fixture에 대조했습니다.

엔진은 실제 내장 Jint이고 Windows 통신은 실제 경로지만 SketchUp 형상/Undo/Observer는 API 대역입니다. **0.8.0 설치 후 실제 모델에서 실행·교체·Ctrl+Z·UV/외관·복구 판정 검사는 아직 하지 않았습니다.** 기존0.6.3의56항목 native 결과와 구분합니다. 이번 작업은 실행 중인 프로그램/모델을 교체하지 않았습니다. 초기 검사에서 발견한 도구 스키마 루트 형식, 검사 복사본 skills 누락, GUI 작업 프로세스 인코딩, 새 읽기 상태 라우팅 문제는 수정했고 최초 실패 로그는 `validation-0.8.0-*-run.txt`에 보존합니다.

## 0.7.0 창 생성 레시피·스킬 — 2026-10-28

전체 **245개 통과**: Ruby202개/1636 assertions, Python STDIO26개·외부 실행기6개·Win32/MCP/Ruby 통합11개. 실패·오류·생략0. SketchUp2020 Ruby2.5.5 DLL 호스트, Minitest5.15.0, Python3.13.17, .NET4.8/x64. OneDrive 임시 제어 파일 간섭을 피한 ASCII 검사 복사본에서 실행하고 원본과 source dirs/build 입력 일치를 확인했습니다. [로그](validation-0.7.0.txt).

추가16개 검사는 크기/열림/재질 역할·실제0.6.3 최적화 기본창 fixture 일치·잘못된 조합·권한/중복방지·한 Undo/교체·실패/예산 전체 취소·재질별 접합선 처리와 MCP 타입 검증을 포함합니다. 스킬의 표준 형식 검사도 통과했습니다. [기능과 정확한 검증 경계](WINDOW_RECIPE.md).

**신규0.7.0 명령의 실제 설치 후 검사는 미실행**입니다. 창 통합 fixture는 annular face 병합을 모델링하지 못해 정리 단계는 기록만 하며, 정리 함수는 분할 큐브로 별도 검사했습니다. 기본 창의0.6.3 실제 최적화 결과와 수치 일치는 native 신규 명령 검사를 대신하지 않습니다. 기존56개 suite에는 새 창 명령을 넣지 않았습니다. 실행 중인0.6.3/사용자 모델에는 이 자동 검사가 연결하지 않았습니다.

## 0.6.3 실제 SketchUp 전체 검사 — 2026-10-28

실제 SketchUp20.0.363/Ruby2.5.5에서 직접 MCP suite=all을 한 번 실행해 **56개 통과·실패0·생략0**, duration48ms, cleanup_verified=true를 확인했습니다. Follow Me·raw_group·점/꼭짓점 이동 수정이 모두 통과했습니다. 후속 모델 조회에서 modified=false와 루트 객체/리소스/선택/편집 경로/외곽이 검사 직전과 일치했습니다. UI 작업 종료·화면/inspector 갱신 요청 성공, 표시 경고0입니다. [실기 기록](MANUAL_RESULTS_0.6.3.md), [원본 응답](native-test-0.6.3-2026-10-28.json).

이번 실행은 한 임시 operation을 abort한 결과입니다. 개별 Undo·모델 수명주기·CPU/렌더·모든 경계 조건의 전체 합격 판정은 아닙니다. batch/장면/purge의 별도 실기는0.6.2 문서에 보존합니다. 아래 개발 검증/실기 대기 문장은 실행 전 기록이며 최신 결과는 이 섹션을 기준으로 합니다.

## 0.6.3 native 타입/Length 회귀 수정 — 2026-10-28

전체 **229개 통과**: Ruby189개 / 1362 assertions, Python STDIO25개·외부 실행기6개·Win32/MCP/Ruby 통합9개. 실패·오류·생략0. [성공 로그](validation-0.6.3.txt). 원본 E: 소스와 검사 복사본의 파일 내용을 비교했습니다.

최초 E: OneDrive 실행에서는 임시 제어 파일 교체에 WinError5가 발생하고 이후 원래 시험 peer가 남아 통합 검사9개가 실패했습니다. [최초 로그](validation-0.6.3-first-run.txt)를 보존합니다. 같은 소스를 동기화되지 않는 ASCII 경로 `dist/validation-0.6.3` 검사 복사본에서 다시 실행하자 전체가 통과했습니다. 프로덕션 모델/파이프에 연결한 자동 검사가 아니며 임시 파일 재시도나 런타임 변경으로 실패를 숨기지 않았습니다.

신규5개 검사는 native Length의 허용 오차 비교로 정확한 좌표도 실패하는 조건, 실제 좌표 불일치의 계속 거부, explode 내부 항목/Vertex/PID0·중복 제외와 필터 후128개 제한 판정을 확인합니다. 수정 전4개 실패/오류를 재현하고 수정 후 통과했습니다. [공식 Length 비교](https://ruby.sketchup.com/Length.html#%3C-instance_method)는 Float와 다른 허용 오차를 적용합니다.

0.6.2 실제 앱의 Follow Me·해제/이동 실패·후속 기능·Undo 결과는 [실기 기록](MANUAL_RESULTS_0.6.2.md)에 있습니다. **0.6.3 수정본의 실제 설치 후 전체 검사는 아직 미실행**입니다.

## 0.6.2 Follow Me 회귀 수정 — 2026-10-28

전체 **224개 통과**: Ruby184개 / 1347 assertions, Python STDIO25개·외부 실행기6개·Win32/MCP/Ruby 통합9개. 실패·오류·생략0. SketchUp2020 Ruby2.5.5 DLL 호스트, Minitest5.15.0, Python3.13.17, .NET4.8/x64 환경입니다. [전체 로그](validation-0.6.2.txt).

기존 Follow Me 대역은 경로선을 자동 제거하고 manifold 판정에서 독립 선을 무시했습니다. 이를 보완하니 중앙 경로 sweep와 전체 suite에서 같은 오류가 재현됐습니다. 프로덕션은 Follow Me 성공 후 새 그룹의 면에 속하지 않는 선만 제거하고 솔리드를 확인합니다. 추가3개 검사는 중앙 경로선 정리·외곽 모서리 유지·native 실패 후 전체 취소를 확인합니다.

이 결과는 API 대역 회귀이며 **수정본의 실제 SketchUp 검사는 아직 미실행**입니다. 기존 0.6.1의 실기 실패와 정리는 [실기 기록](MANUAL_RESULTS_0.6.1.md), 원본 응답은 [JSON](native-test-0.6.1-2026-10-28.json)에 있습니다.

## 0.6.1 UI 갱신·일괄 변경 — 2026-10-28

전체 **221개 통과**: Ruby181개 / 1332 assertions, Python STDIO25개·외부 실행기6개·Win32/MCP/Ruby 통합9개. 실패·오류·생략0. [로그](validation-0.6.1.txt).

추가18개 Ruby 검사는40개 변경을 단일 operation/Undo와 한 번의 명시적 inspector 갱신으로 실행, normal/preview, 단계 오류·예산 초과·중단의 rollback, 시작/commit/abort 실패, 중첩 차단, 완료 후 UI 실패의 경고 처리와 다음 요청의 정상 실행을 확인합니다. STDIO는18개 허용 단계의 엄격한 중첩 schema와 정책/금지 동작/권한 필드 덮어쓰기 거부를 검사합니다. 파이프 통합은 허가·cached replay·중간 실패의 전체 취소·다음 batch 실행을 확인합니다.

**형상·UI·Undo는 API 대역입니다.** 실제 앱/CPU 성능을 측정한 결과가 아닙니다. 공식 API의 disable_ui, invalidate, refresh_inspectors만 사용하며 아웃라이너 단독 잠금/가시성 제어와 전역 redraw 잠금은 사용하지 않습니다. 실제 native 자동 갱신 횟수까지 한 번이라고 보장하지 않습니다. [구현 계약과 한계](UI_UPDATES.md).

## 0.6.0 확장 회귀 — 2026-10-28

**전체 자동 검사200개 통과**: Ruby163개 / 1173 assertions, Python STDIO23개, 외부 일괄 실행기6개, 실제 Win32/MCP/Ruby 경로 통합8개. 실패·오류·생략0. 환경은 SketchUp2019 Ruby2.5.5 DLL 호스트, Minitest5.15.0, Python3.12.14, .NET4.8/x64입니다. [실행 로그](validation-0.6.0.txt)를 보관합니다.

새 회귀는 세 종류 호/곡선 분할, 단순 평면/Offset/회전체/닫힌 메시 계산, 큰 모델 좌표의 체적 방향 계산 안정성, 공유 정의 편집 확인·잠금·재귀 정의 차단, 형상 그룹화/해제, 원시 점/꼭짓점/면/재질 편집, 리소스 CRUD·UTF-8 페이지 예산, 카메라 전용 장면 수명과 오류의 unknown 처리를 포함합니다. SketchUp2019 대역은 정의·재질·태그의 persistent_id를 의도적으로 NotImplementedError로 만들어 잘못된 PID 의존을 차단합니다.

프로덕션 도구 목록38개와 중첩 schema 검증, 같은 명령 ID의 결과 재사용을 확인했습니다. `suite=all`의 기능55개+정리=56항목도 실제 Windows 파이프를 거쳐 실행하고 복구를 확인했습니다. **이 검사의 형상·리소스·카메라·Undo는 API 대역입니다. 실행 중인 사용자 SketchUp 모델에는 연결하지 않았고 실제0.6.0 설치 후 동작·속도는 아직 검증하지 않았습니다.**

실기 일괄 검사에서도 장면 변경·모델 전체 purge·개별 명령 Undo·파일 전환은 제외됩니다. 장면 변경은2019에서 model abort와 같은 복구 보장을 할 수 없으며 카메라 전용 범위만 제공합니다. [요청 목록별 지원·제한](EXTENDED_TOOLKIT.md)과 [일괄 검사 경계](BATCH_TEST.md)를 함께 읽으세요. 이전0.5.0/0.4.x 검증은 아래 이력으로 보존합니다.

## 0.5.0 기본 도구·일괄 검사 — 2026-10-28

**전체 자동 검사 169개 통과**, 실패·오류·건너뜀 0입니다. Ruby 136개 / 828 assertions, Python STDIO 21개, 일괄 검사 외부 실행기 5개, 실제 MCP/Win32/Ruby 통합 7개입니다. 기존 Windows/.NET Framework x64 및 SketchUp 2019 Ruby 2.5.5 DLL 호스트·Minitest 5.15.0·Python 3.12.14 환경입니다. [실행 로그](validation-0.5.0.txt)를 보관합니다.

신규 실행기 Ruby 회귀 23개 / 136 assertions는 프로파일 생성/면적·선 길이, 면/선 배치 경로 및 자식 분할 조회, 중첩 회전·비균등/반전 부모 보정, 회전·축척/그룹/정의 독립화/삭제/돌출과 Undo·오류 롤백을 포함합니다. 고정 실기 검사 묶음의 성공·실패·시간 예산·특수 카메라 생략·정리 실패 상태도 검사했습니다. Session 회귀 1개 / 8 assertions를 추가해 실패 보고서의 패널 표시와 캐시 반환을 확인했습니다. 외부 실행기는 권한/버전/대상 불일치 시 변경 전 중단, 응답 유실 시 재실행 없이 결과 조회만 하는 것을 확인했습니다.

실제 파이프 통합은 신규 도구의 라우팅, 임시 형상 검사 묶음 1회 실행/25개 판정/정리, 명령 ID 재사용 시 캐시 결과 반환을 확인합니다. Windows 시험 제어 파일의 atomic replace 중 일시적인 읽기 접근 거부가 발견돼, 시험 fixture의 기존 90초 수명 제한 안에서 해당 읽기만 재시도하도록 보완했습니다. 실제 모델 명령을 재전송하는 변경은 아닙니다.

**형상·카메라·Undo는 API 대역이며 실제 실행 중인 사용자 모델에는 연결하지 않았습니다.** 0.5.0을 실제 앱에 설치한 뒤 [일괄 검사](BATCH_TEST.md)로 신규 네이티브 동작과 시간을 측정해야 합니다. 이 묶음은 한 operation을 abort하므로 개별 명령의 네이티브 Undo·모델 수명·경합을 대신하지 않습니다. 기존 0.4.0/0.4.1 실제 앱 결과는 아래 이력으로 유지합니다.

## 0.4.1 실제 모델 전환 확인 — 2026-10-28

사용자가 0.4.1을 설치한 실제 SketchUp 19.2.222에서 New, 미저장 시험 모델 저장, 동일 파일 다시 열기를 수행했습니다. 같은 프로세스·세션에서 New/Open 각각 모델 ID 변경 및 실행 허가 자동 회수를 확인했고, 최초 파일 저장에는 ID가 유지됐습니다.

이전 ID의 조회·변경 미리보기는 `model_mismatch`, 현재 ID의 미허가 변경 미리보기는 `authority_or_model_mismatch`로 거부됐습니다. 현재 ID의 조회는 성공했고 최종 `modified=false`·사용자 제어·명령 번호 유지도 확인했습니다. 형상 변경은 실행하지 않았으며, 편집 후 저장/Save As·이전 lease·경합 등의 조건은 미확인입니다. [실기 결과와 범위](MANUAL_RESULTS_0.4.1.md)를 보관합니다. 아래 137개 자동 검사와 별도의 기록이며 이번 실기 중 자동 검사를 다시 실행하지 않았습니다.

## 0.4.1 모델 전환 식별 회귀 — 2026-10-28

동일 Ruby Model 객체를 재사용하는 New/Open을 프로덕션 AppObserver 처리로 검사하도록 바꿨습니다. **전체 137개 통과**, 실패·오류·건너뜀 0입니다. Ruby 112개 / 684 assertions, Python STDIO 19개, 실제 MCP/Win32/Ruby 통합 6개입니다. 신규 모델 수명 회귀 12개 / 55 assertions와 파이프 통합 1개를 추가했습니다. Ruby 12개 파일 문법 검사와 배포/시험 x64 빌드도 통과했습니다.

실행 환경은 앞선 로컬 0.4.0 자동 검사와 같은 SketchUp 2019 Ruby 2.5.5 DLL 호스트, Minitest 5.15.0, Python 3.12.14입니다. [실행 로그](validation-0.4.1.txt), [수정 내용과 실기 절차](MODEL_IDENTITY.md)를 보관합니다. 이 자동 검사의 모델·AppObserver 알림은 대역이며 당시에는 실행 중인 앱을 교체하거나 새 모델로 전환하지 않았습니다. 이후 실제 New/Open 확인은 위 실기 항목에 별도로 기록했습니다.

시험 ZIP은 계속 필수 파일 5개만 포함합니다. 소스 버전과 EXE 버전은 `0.4.1`로 맞췄습니다. 새 작업 스킬은 형식 검증을 통과했고 개인 스킬 폴더에도 설치했습니다. 이는 MCP 도구 개수를 늘리거나 사용자의 실행 허가를 대신하지 않습니다.

## 0.4.0 실제 SketchUp 확인 — 2026-10-28

SketchUp 19.2.222 / Ruby 2.5.5, 중개 앱·확장 0.4.0에서 실제 MCP 명령과 사용자 화면/Undo 확인을 진행했습니다. 원점의 6000 × 12000 × 3000 mm 박스 생성, X +10000 mm 그룹 복제, 이름 변경·X +2000 mm 이동 및 단계별 Undo를 확인했습니다. 사용자가 회전·축척한 부모 내부에서는 선택한 자식의 모델 축 X +1000 mm 이동을 조회로 확인했고 크기는 유지됐습니다.

선택·객체 확대·네 가지 보기 전환은 실제 API 완료 응답과 선택/치수 조회로 확인했습니다. 잠긴 객체의 이동·이름 변경은 `entity_locked`로 거부됐고, 별도 잠금 해제 후 원상태를 확인했습니다. 패널 허가 회수 후에는 조회 성공·이동 거부와 위치 유지를 확인했습니다. 최종 상태는 잠금 해제·사용자 제어입니다.

상세 수치, 사용자 확인과 API 확인의 구분, 미확인 항목은 [실기 결과](MANUAL_RESULTS_0.4.0.md)에 기록했습니다. 특히 새 모델로 전환한 뒤 같은 `model_id`가 보고된 관찰은 후속 조사 대상으로 남깁니다. 모든 모델 격리·변환·오류 복구 시험을 통과한 것으로 확대 해석하지 않습니다.

이 기록은 기존 자동 검사 124개와 별개입니다. 이번 문서 갱신에서는 자동 검사를 다시 실행하거나 배포 파일을 재생성하지 않았습니다. 아래 main 통합/패키징 항목의 미확인 표시는 실기 이전 시점의 이력입니다.

## 0.4.0 main 통합 및 시험 패키징 — 2026-10-28, Windows

개발 브랜치의 `5bd926d`까지 기본 `main`에 통합했습니다. 기존 미커밋 변경은 별도 로컬 stash로 보존하고, 이미 개발 이력에 포함된 중복 구현을 다시 적용하지 않았습니다.

이 PC에서 **전체 자동 검사 124개 통과**, 실패·오류·건너뜀 0입니다. Python MCP STDIO 19개, Ruby 100개 / 629 assertions, 실제 MCP → 제어 허브 → Win32 파이프 → Ruby 통합 5개입니다. Ruby 파일 11개의 문법 검사와 배포/테스트 x64 빌드도 통과했습니다. [실행 로그](validation-0.4.0.txt)를 보관합니다.

SketchUp 2019의 Ruby 2.5.5 DLL을 독립 테스트 호스트로 실행했고 Minitest 5.15.0, Python 3.12.14, Windows .NET Framework 컴파일러를 사용했습니다. 한글 경로의 호스트 제약 때문에 자동 검사는 영문 경로 복사본에서, 최종 EXE/RBZ/ZIP 빌드는 실제 OneDrive 작업 폴더에서 수행했습니다. 시험 연결은 일반 SketchUp 연결과 분리했습니다.

`scripts/package.ps1 -TestRelease`로 최신 19개 도구의 시험 ZIP을 생성했습니다. 설치 파일 5개만 포함하는지, 두 EXE의 파일 버전 `0.4.0.0`·제품 버전 `0.4.0`, RBZ의 명령/검색/생성 소스 포함, 파일별 SHA-256 일치를 확인했습니다. 현재 `SHA256SUMS.txt`는 이 로컬 시험 배포 파일의 기록입니다.

모델·형상·카메라·Undo는 테스트 대역입니다. 실제 SketchUp에서 생성·복제·중첩 변환·Undo·UI 확인은 여전히 남아 있으며, 이번 통합 중 실제 모델 수정이나 새 확장 설치는 하지 않았습니다. [시험 배포 안내](TEST_RELEASE.md)를 따라 별도로 확인합니다.

아래는 이전 단계별 기록입니다.

## 0.4.0 객체 생성·복제 추가 — 2026-10-26, Windows

`sketchup_create_box`와 `sketchup_duplicate_entities`를 추가했습니다. **전체 자동 검사 124개 통과**, 실패·오류·건너뜀 0입니다. MCP 도구는 19개이며 Ruby 문법 검사 및 배포/테스트 x64 빌드도 통과했습니다.

- MCP STDIO: 19개. 새 도구의 명령 ID/권한 특성, 이름·mm 삼중 배열·최소/최대 치수·대상 개수·잘못된 인수 검증을 포함합니다.
- Ruby: 합계 100개 / 629 assertions. 생성·복제 실행기 16개 / 147 assertions, 명령 Session 12개 / 92 assertions이며 기존 회귀도 전부 통과했습니다.
- 생성·복제 실행기: 박스의 외곽·여섯 면·바깥 법선·닫힌 위상, 기본 태그, 중첩 회전/반전/비균등 축척 보정, 원본 유지, 그룹 정의 독립/컴포넌트 정의 공유, 속성/그림자/메타데이터 보존, 다중 복제·일부 생성 오류 롤백, 결과 크기 제한 및 Undo.
- 실제 MCP → Win32 파이프 → Ruby 통합: 5개. 허가 거부·미리보기·생성·검색·복제·선택 상세·결과 이력과 중복 ID의 추가 생성 방지를 확인했습니다. 두 인스턴스에 대상이 섞이지 않는 것도 확인했습니다.

실행 환경은 아래와 같은 Windows/.NET Framework x64, SketchUp 2020의 Ruby 2.5.5 DLL 호스트, Minitest 5.15.0, Python 3.13.17입니다. 생성 위상·복제·Undo는 `tests/support/creation_double.rb` 대역을 사용했습니다. 실제 SketchUp의 면 생성·Group.copy/make_unique·속성 사전 복사·Undo 성공을 자동 검사만으로 보장하지 않습니다. 실제 앱 검증은 사용자의 후속 기능 개발 요청에 따라 진행하지 않았으며, 배포 ZIP 생성·설치·GitHub 게시도 이번 단계에서 진행하지 않았습니다.

이전 단계 기록은 아래에 보존합니다.

## 0.4.0 객체 검색·구조 탐색 추가 — 2026-10-25, Windows

선택하지 않은 그룹/컴포넌트를 찾는 `sketchup_find_entities`와 배치 경로별 직접 하위를 읽는 `sketchup_get_children`를 추가했습니다. 도구는 총 17개이며 **전체 자동 검사 104개 통과**, 실패·오류·건너뜀 0입니다. Ruby 문법 및 x64 배포/테스트 실행 파일 빌드도 통과했습니다.

- MCP STDIO: 17개. 새 도구 계약·읽기 전용 특성·UUID·한글/이모지 필터·배열·개수/깊이 제한·잘못된 인수 거부를 포함합니다.
- Ruby: 합계 83개 / 466 assertions. EntityBrowser 16개 / 93 assertions, Session 18개 / 71 assertions이며 나머지 기존 검사는 아래와 같습니다.
- EntityBrowser: 중첩 경로, 현재/전체 범위, 공유 정의의 배치 구분, 직접 하위 탐색, 문자/태그 필터, 숨김/잠금, 페이지/시간/조사량/바이트 제한, 빈 페이지 뒤 계속 조회, 깊이/순환 제한, 커서의 모델/세션/필터/편집 위치 결합, 오래된 경로 거부, 조회 전후 모델·선택·뷰 유지.
- 실제 MCP → Win32 파이프 → Ruby 통합: 4개. 두 인스턴스의 검색·직접 하위·페이지 결과, 검색 ID를 기존 선택 명령으로 전달, 사용자 제어 유지, 오류 후 Ping, 모델 전환 시 이전 ID 거부를 확인했습니다.

환경은 아래 반영 검사와 같은 Windows/.NET Framework x64, SketchUp 2020 Ruby 2.5.5 DLL 테스트 호스트, Minitest 5.15.0, Python 3.13.17입니다. 실제 SketchUp API 대신 모델 대역을 사용했습니다. 실모델 확인은 사용자의 후속 기능 개발 요청에 따라 진행하지 않았고, [수동 시험](MANUAL_TEST.md)에 새 확인 항목을 추가했습니다. GitHub Actions는 실행하지 않았습니다.

아래는 이전 작업 단계의 검사 기록입니다.

## 0.4.0 참조 작업 반영 검사 — 2026-10-25, Windows

v0.3.1 커밋 `c1d31ae04123b6749e5c3423321805fa602f477f`을 기준으로 OneDrive 참조 폴더의 미커밋 소스·빌드·검사 변경 21개 파일을 현재 `work/post-0.3.1` 브랜치에 반영했습니다. 참조 폴더의 Git 이력은 같은 v0.3.1이며 이보다 앞선 커밋은 없었습니다. 반영 후 MCP의 편집 경로 조회 안내와 문서를 실제 구현에 맞췄습니다.

자동 검사 **84개 통과**, 실패·오류·건너뜀 0입니다. Ruby 문법 검사와 배포 GUI/MCP·테스트 실행 파일의 x64 빌드도 통과했습니다.

| 검사 | 결과 |
|---|---|
| MCP STDIO 프로토콜·15개 도구·변경 인수 검증 | Python 15개 |
| 기존 Session 회귀 | Ruby 17개 / 57 assertions |
| 명령 권한·기한·ID 순서·중복·결과 이력·모델/연결 전환 | Ruby 11개 / 76 assertions |
| 선택·뷰·속성·이동·변환·잠금·Undo/롤백 대역 검사 | Ruby 18개 / 100 assertions |
| ModelReader 회귀 | Ruby 10개 / 52 assertions |
| 네이티브 오류 보존 / 파이프 상태 머신 | Ruby 2개 / 4 assertions 및 5개 / 25 assertions |
| 실제 Win32 Named Pipe | Ruby 3개 / 45 assertions |
| 실제 MCP → 제어 허브 → Win32 파이프 → Ruby 명령 실행기 | Python 3개 |

Ruby 합계는 66개 / 359 assertions입니다. 현재 설치된 SketchUp 2020의 Ruby 2.5.5 DLL을 별도 테스트 호스트로 실행했고, Minitest 5.15.0과 Python 3.13.17을 사용했습니다. .NET Framework x64 컴파일러와 기존 Win32 보조 DLL을 사용했습니다. 일반 GUI나 SketchUp 모델을 시험 대상으로 연결하지 않았습니다.

**명령 실행기의 모델·카메라·Undo는 `tests/support/sketchup_double.rb` 대역입니다.** 실제 통신과 실행기 라우팅을 검증했지만 실제 SketchUp 모델의 수정·Undo·카메라 복원을 보장하는 결과는 아닙니다. 새 RBZ의 실제 설치, 중첩 편집에서 변환된 이동, 여러 실제 인스턴스, 사용자 편집과의 충돌, 모달 창 지연, 화면 배치는 [수동 시험](MANUAL_TEST.md)에 따라 추가 확인해야 합니다. GitHub Actions는 이 반영 작업에서 실행하지 않았습니다.

아래 0.3.x 및 0.2.x 항목은 각 버전 당시의 검증 이력입니다.

## 0.3.1 검사 결과 — 2026-10-25, Windows

전체 **52개 자동 검사 통과**, 실패·오류 0입니다. 기존 51개에 평면 객체의 X/Y/Z 순서 회귀 검사를 추가했습니다. ModelReader는 10개 / 52 assertions이며, Ruby 검사 합계는 37개 / 183 assertions입니다. STDIO 프로토콜 13개 및 실제 MCP/Win32/Ruby 통합 2개도 통과했습니다.

두 배포 EXE의 실제 Windows 버전 리소스를 확인했습니다.

| 파일 | 파일 설명 | 파일 버전 | 제품 버전 |
|---|---|---|---|
| SketchUpMcp.exe | SketchUp MCP Adapter | 0.3.1.0 | 0.3.1 |
| SketchUpPipeProbe.exe | SketchUp MCP Bridge | 0.3.1.0 | 0.3.1 |

제품명은 `SketchUp Local MCP Bridge`, 제작자는 `byteword`입니다. `scripts/package.ps1`이 이 버전 정보와 C#/Ruby 버전 일치를 검사하며 설치 ZIP은 실행에 필요한 5개 파일만 포함합니다.

실제 SketchUp 2019의 0.3.0 확장에서 모델 요약과 선택 그룹 조회가 성공했습니다. 이 과정에서 `size`의 Y/Z 순서 오류를 발견했고, 0.3.1에서 좌표 차이로 수정했습니다. 회귀 검사의 BoundingBox 대역도 실제 API의 height=Y, depth=Z에 맞췄습니다. [공식 BoundingBox API](https://ruby.sketchup.com/Geom/BoundingBox.html)를 기준으로 확인했습니다. 0.3.1을 실행 중인 SketchUp에 설치하거나 모델을 변경하지는 않았습니다.

## 0.3.0 검사 결과 — 2026-10-25, Windows

전체 **51개 자동 검사 통과**, 실패·오류 0입니다.

| 검사 | 결과 |
|---|---|
| Windows 기본 C# 컴파일러 / x64 / warnings-as-errors | 배포 GUI·MCP, 테스트 허브·어댑터·하네스 빌드 통과 |
| MCP STDIO 프로토콜·스키마·페이지 인수 검증 | Python 13개 통과 |
| Ruby Session 권한·모델 ID·조회 오류 격리·응답 제한 | 17개 / 57 assertions 통과 |
| ModelReader 단위·크기·중첩 변환·분할 조회·2019 PID 호환 | 9개 / 49 assertions 통과 |
| Win32 오류 반환값 보존 | 2개 / 4 assertions 통과 |
| 파이프 상태 머신 | 5개 / 25 assertions 통과 |
| 실제 Win32 Named Pipe / UTF-8·이모지·취소·재연결 | 3개 / 45 assertions 통과 |
| MCP STDIO → GUI 제어 허브 → 실제 Win32 파이프 → Ruby Session | Python 2개 통과 |

Ruby 검사는 실제 설치된 SketchUp 2019의 `x64-msvcrt-ruby250.dll` **Ruby 2.5.5**를 별도의 테스트 호스트로 실행했습니다. 호스트 소스는 `tests/sketchup_ruby_runner.c`, 빌드는 `scripts/build-test-ruby.cmd`입니다. Minitest 5.15.0과 Python 3.12.14는 개발 검사에만 사용합니다. 배포 실행 의존성은 추가하지 않았습니다.

통합 검사는 실제 배포 통신 코드를 사용하며 `PROBE_TEST`에서 파이프 이름만 분리합니다. 두 Ruby 피어의 사용자 제어 상태에서 모델·선택 조회, 정확한 session/model 라우팅, 오래된 모델 ID 거부, 페이지 인수 전달, 한글 Ping, 기존 데모 허가·진행률·취소·이력·어댑터 종료 시 권한 회수를 확인했습니다. 실행 중인 일반 SketchUp과 GUI를 시험 대상으로 사용하지 않았습니다.

**ModelReader 계산 검사는 SketchUp API의 작은 대역 객체를 사용했습니다.** 통합 검사의 조회 공급자도 라우팅 확인용 데이터입니다. 따라서 실제 SketchUp API로부터 얻은 값의 정확성을 자동 검사만으로 확인했다고 해석하면 안 됩니다. 설치된 Ruby DLL에서 실행했다는 사실도 SketchUp 모델 API를 로드했다는 뜻은 아닙니다.

내장 Ruby 호스트의 Open3 기반 MCP 실행에서 응답 지연이 발생해, 최종 통합 검사는 Python이 STDIO 프로세스를 실행하고 Ruby가 Win32 피어를 담당하도록 분리했습니다. 호스트의 독립 실행 시 한글 작업 경로 인코딩 문제도 있어 검사는 영문 경로 복사본에서 수행했습니다. 실제 배포 EXE는 현재 한글 작업 경로에서 빌드·패키징했습니다. 테스트 호스트는 RBZ와 사용자용 EXE에 포함하지 않습니다.

### 실제 앱에서 남은 확인

- GUI·MCP·RBZ 0.3.0 설치와 재시작 후 두 새 도구가 노출되는지 확인.
- 실제 그룹·면·선의 이름·태그·재질·단위·치수를 SketchUp 화면과 대조.
- 회전·반전·비균등 축척된 부모 안을 열고 자식을 선택했을 때 치수를 대조.
- 조회 전후 선택·씬·모델 수정 상태·Undo 기록 유지 확인.
- GUI/패널 화면의 시각적 확인 및 GitHub Actions 실행.

기존 0.2.0 연결은 사용자 실제 모델의 상태 응답과 한글 Ping으로 확인했습니다. 이 항목은 0.3.0 배포 준비 당시 기록이며, 이후 0.3.0의 실제 모델 조회 확인은 위 0.3.1 기록에 추가했습니다. [설치 후 수동 검사](MANUAL_TEST.md)를 따르세요.

## 아래는 0.2.0 최초 배포 당시의 기록

## 사용자 실기 보고

0.1.0에서는 hello/PID 등록 직후 Ruby의 `ReadFile: 0` 오류로 연결이 끊어졌습니다.
0.1.1의 Win32 오류 코드 보존 수정 후 사용자가 기본 연결 성공을 보고했습니다.
**새로 추가한 0.2.0 MCP 전체 연결에 대한 사용자 실기 결과는 아직 없습니다.**

## 이 환경에서 실행한 검사

검사일: 2026-10-25. Linux 환경에서 실행했습니다.

| 검사 | 결과 |
|---|---|
| Ruby 상태 머신·네이티브 반환값·파이프 상태 회귀 | **21개 테스트 / 73 assertions 통과**, 실패·오류 0 |
| 실제 subprocess STDIO를 이용한 MCP 서버 검사 | **12개 테스트 통과**, 실패·오류 0 |
| 배포용 MCP EXE의 초기화·GUI 부재 오류·EOF 종료 | 통과 |
| GUI·MCP 어댑터·두 테스트 실행 파일 컴파일 | C# 5 / x64 / warnings-as-errors 통과 |
| 전체 Ruby 소스 및 테스트 문법 | 통과 |
| ZIP/RBZ 압축 및 포함 파일 검사 | 통과 |

Ruby 회귀 검사는 권한 거부, lease 무효화, 모델 교체, 진행률·완료, 중복 요청, 다른 세션 차단, 재연결, 작업 이력 제한, 오래된 job_id의 취소 차단, 소유자별 연결 종료 정리, 만료된 시작 차단, MCP 연결 표시 초기화를 포함합니다. 0.1.1의 Fiddle 오류 보존 및 취소 시 네이티브 버퍼 수명 검사도 유지했습니다.

STDIO 검사는 초기화 순서, 프로토콜 협상, 도구 스키마, 입력 검증, UTF-8 분할 프레임, JSON 오류, 동시 요청, 취소, 도구 실행 오류, 알림 처리, EOF, 큰 프레임 거부, 중복 활성 요청 ID를 확인합니다.

**STDIO 테스트의 백엔드는 FakeBridge입니다.** 배포 서버의 실제 MCP 파서·디스패처를 사용하지만 GUI↔SketchUp의 Windows 경로까지 실행한 결과는 아닙니다. 배포 EXE 자체도 GUI가 없는 상황에서 초기화·명확한 도구 오류·정상 종료를 별도로 확인했습니다.

- Ruby: Linux Ruby 3.2.3. SketchUp 내장 Ruby 2.5 실행 결과가 아닙니다.
- C#: Mono C# 6.8 컴파일러 / C# 5 / .NET Framework 참조 / x64.
- 동봉 DLL: 0.1.1과 동일한 바이너리. KERNEL32.dll 단일 의존성의 Win32 x64 보조 DLL입니다.
- Python은 테스트용이며 사용자 실행 의존성이 아닙니다.

## 아직 실행하지 않은 검사

- Windows .NET Framework 4.8의 `csc.exe` 빌드 및 GUI 레이아웃 확인
- 새 MCP 제어 파이프의 실제 Windows 연결, PID 확인 및 ACL
- 0.2.0 RBZ의 실제 SketchUp 2019 로드와 타이머 실행
- 실제 여러 SketchUp 프로세스, 모달 창, 프로세스 종료·재연결
- ChatGPT 로컬 앱에 등록하고 도구를 실제 호출하는 종단 간 시험
- GitHub Actions 실행

위 검사는 Windows 장비에서 진행해야 합니다. 이 작업 환경에서는 사용자의 Windows 설정에 MCP를 등록하지 않았습니다.

## 제공한 Windows 통합 검사

`scripts/windows-tests.ps1`는 다음을 실행하도록 구성했습니다.

1. 두 배포 EXE와 HeadlessHub/McpHarness 빌드.
2. Ruby 회귀 검사와 MCP STDIO 검사.
3. `windows_pipe_test.rb`: 실제 Win32 Named Pipe, UTF-8, 분할 프레임, 취소, 재연결.
4. 당시의 `windows_mcp_test.rb`는 0.3.0에서 `windows_mcp_test.py`와 `windows_session_fixture.rb`로 교체했습니다. 배포 MCP EXE → 실제 GUI 제어 허브 → 실제 Win32 파이프 → 두 Ruby Session의 연결을 검사합니다.

두 Ruby 세션은 테스트 프로세스 안에서 생성합니다. 실제 SketchUp API나 서로 다른 SketchUp 프로세스의 동작을 대신 검증하지 않습니다. 코드가 제공됐다는 사실을 실행 성공으로 해석하면 안 됩니다.

실제 사용 환경에서는 [수동 시험](MANUAL_TEST.md)을 진행하세요. 동봉 EXE는 크로스 컴파일한 시험 빌드이고 설치 프로그램·코드 서명은 포함하지 않았습니다.
