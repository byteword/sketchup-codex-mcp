# 0.6.1 실제 SketchUp 시험 — 2026-10-28

## 환경

Windows x64, SketchUp20.0.363 / Ruby2.5.5, GUI·MCP·확장0.6.1, 도구39개입니다. 사용자가 작은 시험 모델과 MCP 실행 허가를 확인했습니다. 미저장 모델의 루트 편집 위치이며 기본 인물 컴포넌트1개, 선택0, 검사 전 modified=false였습니다.

첫 검사는 저장소 외부 실행기로 production MCP STDIO를 호출했습니다. ChatGPT 앱 재시작 후에는 이 채팅에 직접 도구가 노출되어 list_instances/get_instance/Ping과 후속 진단을 직접 MCP로 수행했습니다.

## 일괄 검사 결과

`suite=all`, 명령번호1의 결과: **통과36·실패1·생략19**, native duration73ms, 외부 실행 전체895ms입니다. [원본 JSON](native-test-0.6.1-2026-10-28.json)에 단계별 결과가 있습니다.

- 기본24개 기능과 polygon/face/points/freehand/Bezier/세 가지 arc/offset/polyhedron/revolution이 통과했습니다.
- 중앙 경로 `[[500,500,0],[500,500,1000]]`의 sweep는 `Follow Me failed or did not create a closed solid`로 실패했습니다.
- component_convert 이후19항목은 첫 실패 이후 중단되어 실행하지 않았습니다. 성공으로 간주하지 않습니다.
- cleanup 통과, `cleanup_verified=true`, modified_before/after=false였습니다. operation_closed/view_redraw_requested/inspectors_refresh_requested=true, warnings=[]입니다. 실제 화면 렌더 완료나 CPU 개선 측정은 아닙니다.

## 직접 MCP 후속 진단

같은 프로필(1000×1000mm 사각형)에서 경로를 모서리 `[[0,0,0],[0,0,1000]]`로 바꾸자 생성이 완료됐습니다. 후속 객체 조회에서 manifold=true, 면6개·모서리12개, 외곽1000×1000×1000mm를 확인했습니다. 명령번호2로 만든 진단 그룹만 명령번호3으로 삭제했습니다.

삭제 후 루트 객체1개·태그1·재질8·정의1·장면0·선택0과 외곽이 최초 상태와 일치했습니다. 단독 생성/삭제는 commit된 요청이므로 **modified=true이며 두 요청의 Undo 이력이 남습니다.** 개별 Ctrl+Z 확인, 파일 저장, 원래 modified=false의 강제 복구는 수행하지 않았습니다.

## 수정 및 남은 검증

코드상 Follow Me 결과 그룹에 독립 경로선이 남으면 manifold 판정이 실패할 수 있습니다. 기존 대역은 그 선을 지워 오류를 놓쳤습니다. 경로선을 남기는 대역으로 같은 실패를 재현하고, 새 그룹의 면에 연결되지 않은 선만 정리하는0.6.2 수정본을 준비했습니다. 회귀224개 통과는 [개발 검증](VALIDATION.md)에 기록했습니다.

**실제 원인과 수정 효과는0.6.2 설치 후 동일 중앙 경로·전체 suite를 재실행해 확정해야 합니다.** 모서리 경로 성공만으로 중앙 경로 수정이 통과했다고 기록하지 않습니다. 미실행19항목, batch Undo/rollback/후속 요청, 장면 변경·모델 전체 purge·파일 수명과 Outliner 성능 비교도 아직 남아 있습니다.
