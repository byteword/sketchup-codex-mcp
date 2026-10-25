# 0.3.0 읽기 전용 조회

1. `sketchup_list_instances`로 연결 목록을 읽습니다.
2. PID·경로를 확인해 대상의 `session_id`, `model_id`를 그대로 사용합니다.
3. `sketchup_get_model_summary` 또는 `sketchup_get_selection_info`를 호출합니다.

두 조회는 사용자 제어 상태에서도 가능합니다. 작업·Undo·선택·씬·표시 단위·파일 저장을 변경하지 않습니다. SketchUp API는 기존 패널 타이머의 메인 스레드에서만 호출합니다.

## 모델 요약

```json
{"session_id":"<목록에서 받은 UUID>","model_id":"<현재 모델 UUID>"}
```

성공 응답은 `ok=true`, `status=model_summary`, `session_id`, `model_id`, `data`를 포함합니다.

| data 필드 | 의미 |
|---|---|
| `queried_at` | 조회 시각, UTC ISO 8601 |
| `title`, `path` | 현재 이름·경로. 미저장 모델 경로는 빈 문자열 |
| `saved` | 저장 경로 유무. 최신 수정이 디스크에 반영됐다는 뜻은 아님 |
| `modified` | SketchUp API의 현재 수정 상태 |
| `measurement_unit` | 항상 `mm` |
| `model_units` | 모델의 길이 단위 코드/기호·표시 형식 코드·정밀도 |
| `bounds` | 모델 축 기준 외곽 상자, `min`, `max`, `size`는 `[x,y,z]` mm |
| `top_level_entities` | 루트의 총 개수, 조사한 유형별 수, `scanned`, `complete` |
| `collection_counts` | 태그·재질·컴포넌트 정의·씬 개수. 미사용 항목도 포함 |
| `selection_count`, `edit_context` | 현재 선택 수, 열어 편집 중인 그룹/컴포넌트 경로 |

최상위 유형별 집계는 최대 20,000개 또는 0.5초입니다. `complete=false`이면 `by_type`은 조사한 부분의 집계이며 전체 수량으로 해석하면 안 됩니다. 정의 내부로 재귀 탐색하지 않습니다. 같은 컴포넌트의 중첩 배치 수나 재료 수량을 계산하는 기능은 이번 범위에 포함하지 않습니다.

## 선택 객체 상세

```json
{"session_id":"<목록에서 받은 UUID>","model_id":"<현재 모델 UUID>","offset":0,"limit":10}
```

`offset`은 0~1,000,000 정수, `limit`은 1~25 정수이며 기본값은 각각 0, 10입니다. 성공 응답은 `status=selection_info`입니다. `data`에는 공통 단위·시각 정보 외에 `total`, `offset`, `returned`, `next_offset`, `truncated`, `items`가 있습니다. 선택이 없으면 오류 대신 `total=0`, `items=[]`, `next_offset=null`을 반환합니다.

페이지 항목의 JSON 합계는 약 40 KB로 제한됩니다. 요청한 개수보다 적게 올 수 있으므로 `next_offset`이 null일 때까지 사용합니다. **매 호출은 현재 선택을 새로 읽습니다.** 선택이 바뀌면 첫 페이지부터 다시 조회합니다. 고정된 스냅샷은 제공하지 않습니다.

| items 필드 | 의미 |
|---|---|
| `entity_id`, `persistent_id`, `type`, `name` | ID는 정밀도 손실 방지를 위한 문자열. 미지원 PID는 null |
| `tag` | 직접 할당된 태그 이름과 해당 태그 표시 여부 |
| `hidden`, `locked` | 해당 객체 자체의 상태. 지원하는 객체에만 반환 |
| `material`, `back_material` | 직접 할당한 재질 이름·RGB·alpha. 미할당은 null. 뒷면 재질은 지원 객체만 |
| `model_bounds` | 모델 축에 평행한 상자. 중첩 편집 변환을 포함 |
| `definition`, `definition_bounds` | 그룹/컴포넌트 정의 및 정의 좌표계의 축척 적용 전 상자 |
| `instance_axis_lengths_mm` | 정의 상자의 X/Y/Z 방향 변 길이. 인스턴스와 편집 상위 객체의 회전·축척·반전을 적용 |
| `text_truncated` | 객체의 이름/재질 문자열이 256자를 넘어 잘렸는지 여부 |

`model_bounds`는 상자의 여덟 꼭짓점을 변환한 외곽 상자입니다. 특히 회전·기울어진 형상에서 실제 형상보다 클 수 있습니다. 외곽 크기는 모서리 실측 치수나 실내 유효 치수가 아닙니다. `definition_bounds`는 축척 전 크기이므로 실제 배치 크기와 다를 수 있습니다. 직접 재질이 null이어도 부모의 재질을 상속해 보일 수 있고, 객체 자체가 숨김 상태가 아니어도 부모·태그·씬 때문에 안 보일 수 있습니다. 유효 표시 여부는 이번에 계산하지 않습니다.

편집 경로는 최대 32개, 경로 이름은 64자로 제한합니다. 실제 중첩 깊이는 `depth`에 표시하고 경로 개수 초과는 `path_truncated=true`로 알립니다. 각 결과는 선택 객체와 현재 모델 ID에 연결됩니다. 같은 정의의 서로 다른 배치에서 선택한 객체를 구별할 때 편집 경로도 함께 사용합니다.

## 오류와 연결 유지

- `model_mismatch`: 모델이 교체됨. 목록을 갱신하고 대상을 확인한 후 새 ID를 사용합니다.
- `request_expired`: 모달 창 등의 이유로 오래 지연됨. 화면 상태를 확인한 뒤 새 조회를 요청합니다.
- `query_failed`: API 조회 중 오류. 메시지를 반환하며 연결과 다른 시험 작업은 유지합니다.
- `response_too_large`: 전체 결과가 60 KB를 초과함. 연결을 끊는 대신 오류를 반환합니다.
- `query_unavailable` / `unknown_method`: 조회 공급자가 없거나 이전 확장 버전입니다. GUI·MCP·RBZ를 함께 0.3.0으로 업데이트합니다.

메인 스레드가 모달 창이나 API 호출로 오래 점유되면 기존 8초 응답 제한에 걸릴 수 있습니다. 자동 재전송하지 않습니다.

## API 근거

- [Model: entities, active_path, edit_transform, bounds](https://ruby.sketchup.com/Sketchup/Model.html)
- [Drawingelement: bounds의 좌표계](https://ruby.sketchup.com/Sketchup/Drawingelement.html)
- [ComponentInstance: definition 및 transformation](https://ruby.sketchup.com/Sketchup/ComponentInstance.html)
- [Entity: persistent_id 지원 버전](https://ruby.sketchup.com/Sketchup/Entity.html#persistent_id-instance_method) — ComponentDefinition은 2020.1 이후 지원하므로 2019에서는 null 처리합니다.
- [Length: 모델 단위 설정](https://ruby.sketchup.com/Length.html)
