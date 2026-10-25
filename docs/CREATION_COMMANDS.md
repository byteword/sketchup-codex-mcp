# 객체 생성·복제 (0.4.0 시험 기능)

박스 그룹 생성과 그룹/컴포넌트 복제를 지원합니다. 두 도구는 기존 명령과 같은 공통 인수(`session_id`, `model_id`, `command_id`, `expected_context`, 선택 `dry_run`)와 SketchUp 패널의 로컬 실행 허가가 필요합니다.

미리보기와 실제 실행은 각각 새 `next_command_id`를 사용합니다. 같은 ID·같은 내용은 보관 결과만 반환하며 새 객체를 또 만들지 않습니다. 실패·통신 끊김으로 결과가 불명확하면 자동 재전송하지 말고 `sketchup_get_command_result`로 조회합니다.

## 박스 그룹 생성

`sketchup_create_box`는 현재 편집 위치에 독립 그룹 하나를 만듭니다.

```json
{
  "session_id": "<대상 세션 UUID>",
  "model_id": "<현재 모델 UUID>",
  "command_id": "<상태 조회의 next_command_id>",
  "expected_context": [],
  "name": "A동",
  "origin_mm": [0, 0, 0],
  "size_mm": [6000, 12000, 3000],
  "dry_run": true
}
```

- `name`: 1~256자, NUL 문자 불가.
- `origin_mm`: 모델 축 기준 최소 모서리 좌표 `[X,Y,Z]`, 각 값 ±1,000,000,000 mm 이내.
- `size_mm`: 모델 축 방향 변 길이 `[X,Y,Z]`, 각각 1~1,000,000 mm. 음수·0·불리언·무한값은 거부합니다.
- 박스는 모델 축과 나란합니다. 회전·반전·비균등 축척된 부모 안을 편집 중이어도 모델 좌표의 원점·치수를 맞추도록 그룹 변환을 보정합니다.
- 바깥쪽 법선을 가진 여섯 면과 닫힌 솔리드 여부, 실제 모델 축 외곽을 확인합니다. 임의 다면체·곡면·면/선 생성은 제공하지 않습니다.
- 그룹과 원시 형상은 기본 태그(Untagged/Layer0)에 둡니다. 사용자의 활성 태그·선택·카메라·편집 경로를 바꾸지 않습니다. 재질·태그 지정은 생성 후 기존 속성 명령으로 수행할 수 있습니다.

`dry_run`은 `data.planned`에 이름·모델 원점·치수·부모 경로만 반환합니다. 객체나 정의를 만들지 않고 새 객체 ID를 예측하지 않습니다. 실제 실행은 `data.created`에 그룹 ID와 경로, 원점과 모델 외곽을 반환합니다.

## 기존 객체 복제

`sketchup_duplicate_entities`는 명시한 그룹/컴포넌트를 각각 한 번씩 복제합니다.

```json
{
  "session_id": "<대상 세션 UUID>",
  "model_id": "<현재 모델 UUID>",
  "command_id": "<새 next_command_id>",
  "expected_context": [],
  "entity_ids": ["101", "102"],
  "delta_mm": [1000, 0, 0]
}
```

`entity_ids`는 조회 결과의 영구 ID 문자열 1~25개이며 중복은 거부합니다. 현재 편집 위치의 직접 자식이어야 합니다. `delta_mm`는 모델 축 기준 상대 이동량으로 각 값 ±1,000,000,000 mm 이내입니다. 원본 위치를 바꾸지 않고 복제본에 이동을 적용합니다. `[0,0,0]`도 허용하며 이 경우 원본과 겹치는 새 객체가 생깁니다.

| 대상 | 복제 규칙 |
|---|---|
| 그룹 | `Group.copy` 후 상위 그룹 정의를 `make_unique`로 독립화. 내부 컴포넌트의 정의 공유 규칙까지 전부 없애는 깊은 독립화는 아님 |
| 컴포넌트 | 같은 정의를 공유하는 새 배치. 원본의 회전·축척·반전 변환을 유지하면서 모델 축 상대 이동 적용 |
| 이름·태그·직접 재질·숨김·그림자 | 원본 인스턴스 값을 유지하고 결과를 확인 |
| 그룹 속성 사전 | SketchUp의 그룹 복사 API를 사용 |
| 컴포넌트 직접 속성 사전 | 값을 복사하고 다시 읽어 보존 확인. 사전은 원본당 최대 32개, 전체 요청의 항목 256개·JSON 계량 64 KB까지. 한도를 넘으면 수정 전 거부 |

잠긴 원본, 잠긴 편집 상위 객체, 여러 배치가 공유하는 편집 상위 정의, 현재 위치 밖의 객체, 다른 면에 부착된 객체는 거부합니다. 부착 객체는 SketchUp에서 먼저 분리해야 합니다. 외부 확장의 전용 명령이나 재계산을 호출하지 않습니다.

미리보기 결과에는 원본의 `before`와 예상 복제본 원점의 `planned_after`만 있습니다. 실행 결과 `created`에는 각 복제본의 `source_id`, 새 `persistent_id`, `type`, 잘림 표시를 포함한 `name`, `parent_path`, `instance_path`, `model_origin_mm`, `model_bounds`가 있습니다. 빈 정의의 외곽은 null일 수 있습니다. ID는 정밀도 손실을 막는 문자열입니다.

## Undo·오류·후속 조회

한 요청은 하나의 Undo operation입니다. 다중 복제 일부가 실패하거나 실제 결과·속성·크기를 확인하지 못하면 전체 operation을 중단합니다. 새 그룹·복제본이 남지 않도록 되돌리며, 롤백을 확인하지 못하면 결과를 `unknown`으로 남깁니다. 성공한 새 객체는 사용자가 SketchUp에서 한 번의 Undo로 제거할 수 있습니다.

생성된 ID는 기존 검색·구조 탐색·선택·속성·이동 명령으로 연결할 수 있습니다. 현재 편집 위치를 다시 확인하고 새 명령 ID를 받아야 합니다. 사용자가 Undo로 객체를 지워도 이전 명령 결과는 당시 성공 이력으로 남으므로 현재 존재 여부를 다시 조회합니다. 같은 ID를 다시 보내 Undo를 취소하거나 객체를 재생성하지는 않습니다.

짧은 동기 호출로 실행하며 큰 그룹을 복사하는 개별 SketchUp API 호출을 강제로 중단하지 않습니다. 통신 기한을 넘겼다는 사실만으로 생성이 실패했다고 단정하지 않습니다.

## 검증 상태

자동 검사 124개가 통과했습니다. 실제 파이프와 Ruby 실행기까지 연결했지만, 모델·면 생성·그룹 복사·속성 사전·Undo는 테스트 대역입니다. 실제 SketchUp API 확인은 [수동 시험](MANUAL_TEST.md)에 남아 있습니다. 이번 단계는 로컬 개발과 커밋이며 배포 ZIP 갱신·설치·GitHub 게시를 수행하지 않았습니다.

사용 API: [Entities.add_group](https://ruby.sketchup.com/Sketchup/Entities.html#add_group-instance_method), [Entities.add_face](https://ruby.sketchup.com/Sketchup/Entities.html#add_face-instance_method), [Group.copy](https://ruby.sketchup.com/Sketchup/Group.html#copy-instance_method), [Group.make_unique](https://ruby.sketchup.com/Sketchup/Group.html#make_unique-instance_method), [Entities.add_instance](https://ruby.sketchup.com/Sketchup/Entities.html#add_instance-instance_method), [Entity.set_attribute](https://ruby.sketchup.com/Sketchup/Entity.html#set_attribute-instance_method).
