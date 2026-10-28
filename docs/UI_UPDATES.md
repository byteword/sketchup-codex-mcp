# 0.6.1 대량 작업의 화면·아웃라이너 갱신 관리

기존 모델 변경 명령도 `start_operation(..., true)`로 중간 UI 갱신을 억제했습니다. 이번 변경은 이를 공통 작업 범위로 묶고, 여러 MCP 명령 사이의 반복 갱신을 줄이는 **`sketchup_run_batch`**를 추가합니다. 도구는39개입니다.

## 동작

- 변경 명령의 선택 인수 `ui_updates="defer"`가 기본입니다. native operation을 `disable_ui=true`로 시작하고 종료 시 commit 또는 abort합니다. 갱신 억제를 다른 요청이나 타이머 틱까지 유지하지 않습니다.
- 작업을 닫은 뒤 `View#invalidate`로 화면 재그리기를 예약하고 `UI.refresh_inspectors`를 **명시적으로 한 번만** 요청합니다. 후자는 아웃라이너/컴포넌트 브라우저 등 inspector 전체에 적용됩니다. 각 객체나 일괄 단계마다 호출하지 않습니다.
- `ui_updates="normal"`은 operation의 `disable_ui=false`를 사용합니다. 종료 시 화면 invalidate는 하되 추가 inspector 갱신을 강제하지 않습니다. 즉시 진행 상태를 표시하는 개발/비교 작업 등에 선택할 수 있습니다.
- 실패는 전체 native operation을 abort한 뒤 갱신을 요청합니다. Ruby 중단 예외도 정리 경로를 통과합니다. 시작 실패 시 소유하지 않은 작업을 abort하지 않습니다. 중첩 MCP 작업은 기존 operation을 암묵적으로 닫지 않도록 거부합니다.
- commit은 성공했는데 마지막 화면/inspector 갱신이 실패하면 **변경 완료＋표시 경고**를 반환합니다. 이미 실행한 형상을 다시 만들거나 이동시키지 않습니다.
- abort 자체를 확인할 수 없으면 `outcome_unknown`입니다. 이때 반쯤 변경된 형상으로 inspector를 강제 갱신하지 않으며 자동 재실행도 하지 않습니다. 모델/작업 상태를 직접 확인해야 합니다.

선택·카메라·장면은 native 모델 operation과 다른 경로라 이 옵션의 갱신 억제 대상이 아닙니다. 자체 일괄 실기 검사는 동일 공통 범위에서 임시 작업을 abort하고 UI 상태를 복원한 다음 한 번 갱신합니다.

## 아웃라이너 지원의 정확한 범위

공식 Ruby API의 `disable_ui`를 사용합니다. **아웃라이너만 별도로 잠금/해제하거나 기존 열림·접힘 상태를 조회하고 복구하는 공개 API는 제공되지 않습니다.** 따라서 트레이를 강제로 닫거나 Windows 창 핸들·메뉴·전역 redraw 잠금을 사용하지 않습니다. 기존 레이아웃/표시 상태도 변경하지 않습니다.

SketchUp이 commit/abort 자체에서 수행하는 자동 갱신까지 포함해 실제 렌더 횟수가 정확히 한 번이라고 보장하지 않습니다. 보장하는 것은 중간 강제 갱신을 호출하지 않고, 종료 후 이 확장의 명시적인 화면·inspector 갱신 요청을 각각 최대 한 번 호출한다는 점입니다. 다른 확장의 observer 비용, 매우 큰 모델의 계산 비용, 마지막 아웃라이너 재구성 비용까지 없애지는 못합니다.

0.6.1의 실제 SketchUp/CPU 벤치마크는 아직 미실시입니다. API 대역에서는40개 변경을1개의 operation/Undo와1번의 명시적 inspector 갱신으로 처리하고, 실패·중단·다음 요청에서 정리가 유지됨을 검사했습니다.

## 일괄 실행

한 번의 로컬 실행 허가·현재 모델/편집 경로·새 명령 ID로 최대64개 명령을 실행합니다. `steps`는 아래처럼 실제 도구 이름에서 `sketchup_`를 뺀 method와 인수를 사용합니다. 아래 ID는 예시이며 반드시 현재 조회 결과로 바꿉니다.

```json
{
  "session_id": "<current-session>",
  "model_id": "<current-model>",
  "command_id": "<fresh-next-command-id>",
  "expected_context": [],
  "ui_updates": "defer",
  "steps": [
    {"method": "move_entities", "arguments": {"entity_ids": ["101", "102"], "delta_mm": [1000, 0, 0]}},
    {"method": "update_entity_properties", "arguments": {"entity_ids": ["103"], "properties": {"hidden": true}}}
  ]
}
```

- 허용: 속성·이동·박스/도형 생성·복제·회전·축척·반전·삭제·그룹화·정의 독립화·돌출·컴포넌트·원시 형상·리소스 변경. 기존 각 도구의 타입·개수·잠금·소속·공유 정의 제약을 그대로 검사합니다.
- 제외: 선택/카메라/장면, 파일 입출력, 허가 변경, 자체 시험, 중첩 batch, 임의 Ruby. 중간에 UI 이벤트를 처리하거나 타이머로 작업을 넘기지 않습니다.
- 하위 단계에는 session/model/command/context/dry_run/ui_updates 등을 넣지 않습니다. 전체 작업의 공통 값을 사용하고 명령 ID도 하나만 소비합니다.
- 단계/입력 타입은 C#에서 모두 먼저 검사합니다. 실제 대상과 결과는 Ruby 실행 단계에서 검사하고 중간 실패 시 앞선 변경도 전부 취소합니다. 전체 요청이 한 Undo입니다.
- 단계 합계는 UTF-8 JSON48000바이트 이하입니다. 단계 사이에4초의 협력적 예산을 확인하고 초과하면 전체를 abort합니다. 개별 native API 호출 자체를 강제로 중단하지는 못합니다. 더 큰 작업은 확정된 결과 뒤에 새 batch로 나눕니다.
- 현재는 앞 단계의 생성 ID를 뒤 단계에서 참조하는 문법이 없습니다. 같은 batch 안에서 존재하던 대상만 사용하거나 서로 독립적인 생성/변경을 묶습니다. 위상 변경으로 ID/경로가 달라지면 뒤 단계를 별도 요청으로 나누고 다시 조회합니다.
- 결과는 단계별 method·created_ids의 요약입니다. `dry_run=true`는 원래 모델을 기준으로 각 단계를 검증하며 앞 단계 변경을 가상으로 시뮬레이션하지 않습니다.
- 시간 초과/통신 끊김 시 동일 command_id의 `get_command_result`로만 조회합니다. 새 ID로 같은 batch를 자동 재전송하지 않습니다.

## 결과의 UI 진단

모델 operation 결과와 자체 시험 보고서의 `ui_update`:

| 필드 | 의미 |
|---|---|
| mode / suppression_requested | 요청한 defer/normal과 native UI 억제 요청 여부 |
| operation_closed | commit 또는 abort가 확인됨. 실제 화면 렌더 완료를 뜻하지 않음 |
| view_redraw_requested | invalidate 호출 성공. 비동기 재그리기 예약 |
| inspectors_refresh_requested | 이 확장에서 refresh_inspectors를 호출했음 |
| outliner_control | operation_disable_ui 방식 |
| outliner_visibility_changed | false. 트레이 표시/접힘 상태 변경 없음 |
| warnings | 완료 후 표시 요청 오류. 형상 변경 재실행 사유가 아님 |

## 공식 API 근거

- [Model.start_operation](https://ruby.sketchup.com/Sketchup/Model.html#start_operation-instance_method): disable_ui로 변경마다 반복되는 UI 갱신을 억제. operation 중첩은 이전 작업을 닫으므로 금지.
- [UI.refresh_inspectors](https://ruby.sketchup.com/UI.html#refresh_inspectors-class_method): 아웃라이너 등을 갱신하며 SketchUp7부터 제공.
- [View.invalidate](https://ruby.sketchup.com/Sketchup/View.html#invalidate-instance_method): 화면 갱신에 권장되는 방식. 강제 동기 View.refresh는 사용하지 않음.
