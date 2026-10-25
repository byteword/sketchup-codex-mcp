# 객체 검색·구조 탐색 (0.4.0 시험 기능)

`sketchup_find_entities`와 `sketchup_get_children`는 선택하지 않은 그룹/컴포넌트의 영구 ID와 배치 경로를 읽습니다. 현재 `session_id`, `model_id`가 필수입니다. 패널의 실행 허가 없이 조회하며 모델 수정 상태·선택·카메라·편집 위치·Undo를 바꾸지 않습니다.

## 이름·태그로 찾기

```json
{
  "session_id": "<목록에서 받은 세션 UUID>",
  "model_id": "<현재 모델 UUID>",
  "scope": "model",
  "name": "기둥",
  "tag": "구조",
  "entity_type": "ComponentInstance",
  "max_depth": 8,
  "limit": 10
}
```

| 인수 | 규칙 |
|---|---|
| `scope` | `current`(기본): 현재 열어 편집 중인 위치부터 / `model`: 모델 루트부터 |
| `name` | 1~256자. 객체 이름 또는 정의 이름에 포함된 문자열, 영문 대소문자 구분 없음. 정규식 아님 |
| `tag` | 1~256자. 직접 지정된 태그의 정확한 내부 이름. 상위 태그 상속이나 유효 표시 상태를 검색하지 않음 |
| `entity_type` | 선택 `Group` 또는 `ComponentInstance`. 생략하면 둘 다 검색 |
| `max_depth` | 1~32, 기본 8. 검색 시작 위치 기준 깊이, 1은 바로 아래만 |
| `limit` | 1~25, 기본 10. 바이트·시간·조사량 제한으로 더 적게 반환할 수 있음 |
| `cursor` | 첫 요청에는 생략. 같은 검색의 `next_cursor`를 그대로 전달 |

필터는 모두 AND로 결합합니다. 이름·태그·종류를 모두 생략하면 지정 범위의 구조를 깊이 우선 순서로 나눠 읽습니다. 필터와 일치하지 않는 부모도 그 하위는 계속 탐색합니다. 숨김·잠금 객체도 포함합니다.

## 특정 배치의 바로 아래 읽기

`sketchup_get_children`에 루트는 `parent_path=[]`, 특정 그룹/컴포넌트는 직전 결과의 전체 `instance_path`를 전달합니다.

```json
{
  "session_id": "<세션 UUID>",
  "model_id": "<현재 모델 UUID>",
  "parent_path": ["100", "101"],
  "limit": 10
}
```

`parent_path`는 루트부터 순서 있는 영구 ID 문자열 배열이며 최대 31개입니다. 경로의 각 객체가 앞 객체의 정의에 직접 속하는지 확인합니다. 다른 부모의 객체 ID를 이어 붙이거나 삭제된 경로를 사용하면 거부합니다. 현재 편집 위치와 별도로 읽을 수 있으며, 경로를 열거나 닫지 않습니다. 이 도구는 하위 그룹/컴포넌트만 반환합니다. 면·선 등 원시 형상은 목록에 포함하지 않습니다.

## 결과

성공 응답은 `ok=true`, `status=entities_found` 또는 `children`, `session_id`, `model_id`, `data`입니다.

| data 필드 | 의미 |
|---|---|
| `queried_at` | UTC 조회 시각 |
| `root_path` | 실제 탐색 시작 위치의 전체 경로 |
| `current_context` | 조회 당시 현재 편집 경로의 영구 ID 배열 |
| `items`, `returned` | 이번 페이지의 결과와 개수 |
| `scanned` | 이번 페이지에서 조사한 그룹/컴포넌트·면·선 등 전체 객체 수 |
| `next_cursor`, `has_more` | 다음 페이지 커서와 남은 탐색 여부 |
| `complete` | 이전 페이지를 포함한 탐색이 끝났고 생략 범위도 없는지 여부 |
| `stop_reason` | `page_limit`, `byte_limit`, `scan_limit`, `time_limit` 또는 null |
| `omitted` | 깊이 제한(`depth`), 순환 정의(`cycle`), 유효 영구 ID 부재(`missing_id`)로 생략한 범위. 이전 페이지의 표시도 유지 |

`items`에는 다음 값이 있습니다.

- `persistent_id`, `type`, `name`, `definition_name`, `tag`: ID는 정밀도 손실을 피하는 문자열입니다. 이름·정의 이름·태그 표시는 256자까지이며 잘리면 `text_truncated=true`입니다. 이름 필터는 잘리기 전 전체 값에 적용합니다.
- `parent_path`, `instance_path`: 루트부터 부모까지의 경로와 해당 객체까지의 전체 배치 경로입니다.
- `in_current_context`: 객체의 부모 경로가 조회 당시 편집 위치와 같은지 표시합니다. 변경 허용 여부나 잠금 해제를 보장하지 않습니다.
- `hidden`, `locked`: 해당 객체 자체의 직접 상태입니다. 조상·태그·씬의 유효 표시 상태를 계산하지 않습니다.
- `child_entity_count`: 정의에 직접 속한 모든 객체 수이며 면·선도 포함합니다. 하위 그룹 수나 전체 재귀 수량이 아닙니다.

같은 컴포넌트 정의를 여러 곳에 배치하면 그 내부 자식의 PID가 같아도 `instance_path`는 다릅니다. 전체 모델에서 유일한 배치로 PID 하나만 사용하지 마세요.

## 계속 조회와 제한

각 호출은 최대 20,000개 객체 조사 또는 0.25초의 협력적 시간 예산, 결과 25개, 항목 JSON 합계 40 KB로 제한합니다. 개별 SketchUp API 호출을 강제로 중단하는 제한은 아닙니다. 절대 배치 경로는 32단계까지입니다. 지정한 검색 깊이나 절대 경로 제한 때문에 하위를 조사하지 못하면 `omitted.depth=true`입니다.

결과가 빈 배열이어도 `next_cursor`가 있으면 조사량/시간 예산 때문에 아직 결과를 만나지 못한 페이지일 수 있으므로 계속 조회합니다. `next_cursor=null`인데 `complete=false`라면 깊이 등으로 생략한 범위가 있습니다. 관련 부모 경로를 직접 조회하거나 검색 범위를 좁혀 확인합니다.

커서는 방문 스택을 담으며 세션·모델·필터·깊이·검색 시작 경로·현재 편집 위치에 결합됩니다. `limit`은 다음 요청에서 바꿀 수 있습니다. 필터나 모델을 바꾼 커서, 깨진 커서, 크기/경로 변경을 확인한 오래된 커서는 `query_failed`로 거부합니다. 오류 후에도 파이프와 기존 권한을 유지합니다.

**페이지는 고정 스냅샷이 아닙니다.** 모든 모델 변경을 감지하지는 않으므로 구조·이름·태그·편집 위치가 바뀌면 커서를 버리고 처음부터 조회합니다. 전체 검색 결과를 동결하거나 서버 메모리에 무제한 저장하지 않습니다.

## 기존 명령에 연결

1. 목록에서 세션·모델을 확인하고 검색하거나 하위를 읽습니다.
2. 대상의 전체 배치 경로와 현재 편집 위치를 확인합니다.
3. 명령 직전 선택 상세 또는 모델 요약에서 편집 경로를 갱신하고 상태 조회에서 새 `next_command_id`를 받습니다.
4. 대상이 현재 편집 위치의 직접 자식일 때만 `persistent_id`를 `entity_ids`에, 부모 경로를 `expected_context`에 전달합니다. 변경에는 별도 로컬 허가가 필요합니다.
5. 다른 편집 위치의 결과는 자동으로 내부로 진입해 변경하지 않습니다. 잠금·공유 정의 등 기존 명령 제한도 유지합니다.

예: “모델 전체에서 구조 태그의 기둥을 찾아줘”, “이 그룹의 하위 구조를 보여줘”, “검색한 루트 그룹을 선택해줘”. 실제 SketchUp API 결과와 UI 상태 유지 확인은 [수동 시험](MANUAL_TEST.md)에 남아 있습니다.

구현에서 사용하는 읽기 API: [Entities 인덱스 접근](https://ruby.sketchup.com/Sketchup/Entities.html#%5B%5D-instance_method), [Group.definition](https://ruby.sketchup.com/Sketchup/Group.html#definition-instance_method), [ComponentInstance.definition](https://ruby.sketchup.com/Sketchup/ComponentInstance.html#definition-instance_method). 공식 API 계약과 별도로 현재 자동 검사는 모델 대역을 사용합니다.
