# Probe 소스 애드온 — 0.14.1 / VWorld 0.2.0

Probe에는 공통 애드온 로더·설정창·HTTPS 조회·암호화 저장 기능만 둔다. VWorld의 요청 작성과 결과 해석은 실행파일 옆 `AddOns/vworld/addon.json`, `addon.js`에 있다. 소스 교체 후 Probe 재빌드 없이 창을 다시 열고 해당 버전을 활성화한다. SketchUp 연결 없이 외부 데이터만 조회하며 모델은 변경하지 않는다.

## 설치와 사용

1. 0.14.1 Probe/MCP 배포본을 준비한다. 실행파일과 같은 위치에 `AddOns/vworld/`의 `addon.json`, `addon.js`, `terrain.html`을 복사한다. 저장소의 `AddOns` 폴더가 원본이다. VWorld 0.2.0은 0.14.1 이상 호스트가 필요하다.
2. Probe에서 **AddOns 설정 / 조회**를 연다.
3. VWorld 인증키와 키 발급 시 등록한 URL(`domain`)을 입력한다. 표시된 HTTPS 서비스 사용 체크를 켜고 **설정 저장**을 누른다. 처음에는 비활성이다.
4. **건물 높이 · 윤곽** 또는 **지적도 · 필지 경계**를 선택한다. PNU 19자리 / `서쪽경도,남쪽위도,동쪽경도,북쪽위도` / 중심점 `경도,위도` 중 하나만 입력하고 **조회**한다. 범위는 각 방향 최대 0.02도, 최대 100건이다. 중심점은 주변 약 ±0.0001도 후보 조회이며 해당 지점을 포함하는 필지만 골라주는 기능은 아니다.
5. 결과의 `height_m`, `height_mm`, `height_status`, `source_height_raw`, `source_updated_at`를 확인한다. 높이 0·누락은 미제공으로 처리하고 층수로 추정하지 않는다. `possibly_truncated=true`면 범위를 줄여야 한다.
6. 경계 지도에서 휠로 확대, 드래그로 이동, 경계를 클릭해 속성을 확인한다. 배경지도 없는 벡터 미리보기이며 **GeoJSON 저장**으로 내보낸다. 지적도는 지번·PNU·갱신일과 경계를 제공한다. 법적 경계 확정이나 소유권 조회 기능은 아니다.
7. 위치가 주소뿐이면 **주소 → 좌표 검색**에서 `road`(도로명) 또는 `parcel`(지번)을 선택한다. 결과 아래 **결과 위치로 다음 조회**를 누르면 지적도 중심점 입력으로 이동한다. **조회**를 눌러 주변 필지를 확인한다.

### 지점·작은 범위 지형 수치

**지형 높이 · 지점/격자 조회 열기**는 기본 브라우저에 별도 화면을 연다. VWorld 3D API 사용 권한이 있는 키와 등록 URL을 이 화면에 입력하고 **3D 지도 시작**을 누른다. 브라우저 키는 저장하지 않으며 Probe의 DPAPI 키를 HTML이나 브라우저로 전달하지 않는다. 키에 등록된 도메인 정책이 로컬 파일 실행을 허용하지 않으면 등록한 웹 환경에서 원본 `terrain.html`을 열어야 한다. 임의 우회 proxy를 사용하지 않는다.

- 한 점: `126.9780,37.5665` 입력 → **좌표 높이 조회**.
- 작은 범위: `126.977,37.566,126.979,37.568` 입력, 한 변 지점 수 2~10 → 경계 포함 최대 100점 균등 격자 조회.
- 타일 단계 10~16(기본 14), 누적 최대 500점, 좌표·높이·누락 상태·단계·조회 시각을 CSV 저장. 숫자의 소수 자릿수는 정확도 보장이 아니다.
- 지도 클릭도 클릭 위치의 **지형 타일을 다시 조회**한다. 클릭 표면의 건물 지붕 높이나 카메라 고도를 표고로 사용하지 않는다.
- VWorld WebGL3의 `ws3d.viewer.terrainProvider`와 SDK의 `Cesium.sampleTerrain`을 사용한다. 평면 `EllipsoidTerrainProvider`는 거부하며 누락은 `미제공`/CSV 빈칸이다. 타일 보간값이며 원본 DEM 파일 추출 기능은 아니다.
- Cesium 계약상 반환값은 타원체 기준 높이다. **VWorld 원자료의 수직 기준/변환과 실측 정확도는 검증 전**이다. 확정된 해발 표고로 취급하거나 건물 `hg`와 무조건 합산하지 않는다.
- 지형 수치 조회는 현재 브라우저 도구에서 수행한다. MCP `sketchup_addon_query`는 건물·지적도·주소를 제공하며 지형 조회를 자동 실행하지 않는다. SDK 호환성·인증·타일 서비스의 실환경 확인은 아직 필요하다. 조회가 멈추면 지도 종료 후 다시 시작한다.

키 입력칸은 다시 열 때 항상 빈칸이다. 빈칸으로 저장하면 기존 키를 유지하며 **저장된 키 삭제**로 지운다. 삭제할 때 활성 체크도 해제한다. 다른 PC/Windows 계정으로 옮긴 경우 키를 다시 등록한다. 조회에는 API 사용량이 발생하며 재시도·캐시·대량 수집은 하지 않는다. 조회 취소나 창 닫기는 해당 조회를 취소한다.

## 저장과 실행 계약

- 사용자 설정: `%LOCALAPPDATA%/SketchUpCodexMcp/AddOns/<id>.json`. 소스·배포 ZIP·Git과 분리한다.
- secret 설정은 Windows DPAPI `CurrentUser`로 암호화하고 애드온 ID와 설정 이름을 추가 엔트로피로 사용한다. 계정 내 다른 프로그램에 대한 보안 경계는 아니다. 평문 키는 요청할 때 Probe 메모리에 존재한다.
- manifest·JS·선택 HTML의 해시를 활성화 시 저장한다. 하나라도 변경되면 조회/화면 열기가 중단되고 로컬 재활성화가 필요하다. 원격 MCP로 활성화하거나 키를 등록/읽는 기능은 없다.
- `probe-addon/2`는 JSON manifest와 순수 JavaScript 소스다. 새 호스트는 기존 `probe-addon/1`도 읽는다. VWorld 0.2.0은 `/2`를 사용해 구형 호스트에서 잘못된 endpoint로 호출되지 않도록 거부된다. C#/DLL 플러그인이나 임의 CLR/파일/네트워크 실행은 제공하지 않는다. 기존 Jint 별도 프로세스의 시간·메모리 제한을 사용한다. 이것을 OS 수준 보안 격리라고 주장하지 않는다.
- 서버 조회는 manifest의 고정 HTTPS endpoint에 GET만 보낸다. 자동 redirect는 거부하며 인증서 기본 검증을 유지한다. 인증키는 prepare/parse worker에 넘기지 않고 Probe가 별도 쿼리 사본에 `secret_query`를 넣는다. `public_query`는 비밀이 아닌 설정만 참조한다.
- 동시에 최대 2조회, 전체 25초, HTTP 10초, 응답 256KiB, JS 단계별 1초/32MiB/20만 문장, JS 출력 128KiB. 조회가 크면 오류로 종료하고 범위를 줄인다.
- 네트워크 예외의 URL/본문은 외부에 반환하지 않고, 반사된 인증키의 평문·URL/JSON 인코딩 형태를 결과에서 가린다. 서비스가 임의 인코딩으로 비밀을 반환하는 상황까지 완전한 DLP를 보장하지 않는다.

## 애드온 작성

`addon.json`의 `api_version`, `id`, `name`, `version`, `endpoint`, `settings`, `inputs`, `public_query`, `secret_query`와 `addon.js`를 작성한다. `id`는 폴더명과 같으며 소문자로 시작하는 소문자/숫자/하이픈 최대 40자다. manifest 16KiB, JS 64KiB, 설정/입력 필드 각 16개까지다. 경로를 돌리는 name-surrogate reparse point(심볼릭 링크/정션)와 경로 탈출을 거부하며 OneDrive 클라우드 파일의 reparse point는 허용한다.

설정 필드에는 `key`, `label`, `secret`, `required`를 지정한다. 입력 필드는 `key`, `label`, 문자열 `default`이며 UI는 텍스트 입력을 만든다. 입력 검증·형 변환은 `prepare`의 책임이다. MCP의 `inputs`는 JSON 객체다.

```javascript
function prepare(input) {
    // 입력 검증 후 문자열 값만 갖는 query 반환. 키·domain은 host가 추가한다.
    return {query: {search: String(input.search)}, limit: 20};
}
function parse(input) {
    // input.body: 제한된 응답 텍스트, input.request: prepare의 반환값(인증키 없음)
    return {status: 'ok', records: JSON.parse(input.body)};
    // 서비스 오류: {status:'error', message:'사용자에게 표시할 설명'}
}
```

선택 `endpoints`는 별칭→고정 URL 사전(최대 8개)이다. `prepare`의 `endpoint`는 그 별칭만 선택할 수 있다. 선택 `operations`는 기능 ID→`{label,inputs}` 사전(최대 8개)이며 설정창이 입력을 전환한다. 기본 operation을 생략한 기존 건물 조회도 유지한다. `parse`의 `geojson`은 경계 미리보기/내보내기, `followup:{operation,inputs}`는 다음 조회 입력에 쓰인다.

선택 `viewer_file`은 같은 폴더의 HTML 파일명(64KiB 이하), `viewer_label`은 버튼 표시다. 승인한 소스만 사용자 설정 폴더의 `Views`에 키 없는 사본으로 저장하고 기본 브라우저로 연다. **브라우저 HTML은 Jint 제한 밖에서 실행되며 SDK 스크립트/네트워크를 사용한다.** 신뢰하는 소스만 활성화한다. 위 HTTP/worker 제한은 브라우저 SDK에 적용되지 않는다.

현재 서버 프레임워크는 한 조회에 한 HTTP 요청만 지원한다. 주소→필지 조회는 사용자가 이어서 실행한다. 페이지 순회, 모델 배치 및 SketchUp 좌표변환은 제공하지 않는다. 애드온 파일을 배치한 후 설정창을 다시 열면 재검색한다. 한 애드온이 잘못되어도 목록의 다른 항목은 유지한다.

## MCP

`sketchup_addon_list({})`는 ID·버전·소스 해시·활성화/설정 상태·입력 필드를 반환한다. `sketchup_addon_query`는 로컬에서 활성화된 애드온을 호출한다. 전체 도구 수는 65개다.

```json
{"addon_id":"vworld","inputs":{"pnu":"1174011000102450001","limit":20}}
```

```json
{"addon_id":"vworld","inputs":{"operation":"parcels","point":"126.978,37.5665","limit":20}}
```

```json
{"addon_id":"vworld","inputs":{"operation":"address","address":"서울특별시 중구 세종대로 110","address_type":"road"}}
```

실패는 `ok=false`/MCP `isError=true`. 성공 응답에는 소스 해시·조회 UTC 시각·원자료 출처를 포함한다. 건물 높이는 원자료 건축물 높이이며 해발고도나 SketchUp의 Z좌표가 아니다. 결과 목록에서 대상 건물을 식별한 뒤 모델 적용을 별도로 설계해야 한다.

## VWorld 공식 계약 확인

2026-10-30 공식 [GIS건물통합WFS조회](https://www.vworld.kr/dtna/dtna_apiSvcFc_s001.do?apiNum=76)를 HTTPS로 읽어 확인했다.

- endpoint: `https://api.vworld.kr/ned/wfs/getBldgisSpceWFS`
- `typename=dt_d010`, `output=application/json`, `resultType=results`
- 높이: `hg`(m); 식별자 `gis_idntfc_no`; 필지 `pnu`; 기준일 `last_updt_dt`.
- 공식 PNU 최소 8자리/서버 최대 1000개이지만 이번 애드온은 개별 필지 19자리/최대 100개로 제한한다.
- EPSG:4326 BBOX는 공식 문서에 명시된 `(ymin,xmin,ymax,xmax,EPSG:4326)`로 전송한다. UI/MCP 입력은 경도·위도 순서다.
- API 키로 실제 조회는 아직 하지 않았다. 공식 필드에 맞춘 모의 GeoJSON 검사는 실서비스 응답·키별 접근 권한 검증을 대신하지 않는다.

추가 확인한 공식 자료:

- [연속지적도 WFS](https://www.vworld.kr/dtna/dtna_apiSvcFc_s001.do?apiNum=92): `getCtnlgsSpceWFS`, `dt_d002`, `pnu`, `lnm_lndcgr_smbol`, `mnnm`, `slno`, `last_updt_dt`. BBOX 축 순서는 건물과 같다.
- [지오코딩 2.0](https://www.vworld.kr/dev/v4dv_geocoderguide2_s001.do): `/req/address`, `getCoord`, `road/parcel`, `EPSG:4326`.
- [WebGL3 가이드](https://www.vworld.kr/dev/v4dv_opnws3dmap3guide_s001.do)와 [VWorld 공식 예제 저장소](https://github.com/V-world/V-world_API_sample)의 `[WebGL3] 지형 Clipping.html`: `ws3d.viewer`와 SDK `Cesium` 사용 경로 확인. 예제에 포함된 인증키는 복사하거나 사용하지 않는다.
- [Cesium 1.101 sampleTerrain 공식 소스](https://github.com/CesiumGS/cesium/blob/1.101/packages/engine/Source/Core/sampleTerrain.js): 타일 단계·비동기 보간·누락 undefined·타원체 높이 계약. VWorld SDK 제공자의 호환성은 런타임 검사하며 실제 키로 별도 검증해야 한다.

## 개발·배포

`scripts/addon-tests.ps1`은 실제 DPAPI·Jint worker·모의 HTTPS 응답·WinForms 컨트롤 재생성 검사를 실행한다. `scripts/windows-tests.ps1`에도 포함한다. 사용자 모델과 실제 키는 사용하지 않는다.

`node tests/vworld-terrain-test.cjs`는 배포 HTML 스크립트의 좌표/격자 검증과 SDK adapter의 정상·누락·평면 대체 거부·오류 처리를 모의 provider로 확인한다. 실제 WebGL 렌더링이나 VWorld 인증 조회 통과를 뜻하지 않는다.

기존 기본 런타임 ZIP은 계속 5파일이다. `scripts/package-addons.ps1`은 선택 설치용 ZIP을 따로 만들며 그 내부의 `AddOns`를 Probe 실행파일 옆에 푼다. 기존 사용자 설정을 배포하거나 자동 덮어쓰지 않는다. 배포 애드온 소스는 실행에 필요한 파일이므로 이 별도 ZIP에 포함한다.
