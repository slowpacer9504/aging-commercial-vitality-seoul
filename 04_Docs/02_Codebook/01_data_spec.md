# 데이터 명세서

## 1) 계층 구조

- Raw: `01_Data/01_Raw_Data`
- Boundary: `01_Data/02_Boundary`
- Intermediate: `01_Data/03_Processed_Data/01_Intermediate`
- Analysis Ready: `01_Data/03_Processed_Data/02_Analysis_Ready`
- Panel: `01_Data/03_Processed_Data/03_Panel`
- Outputs: `03_Output/*`

## 2) 핵심 입력 데이터셋

- 서울시 상권분석서비스
  - `2019Q1~2025Q4` 분기 패널 구축의 핵심 source
  - 분기 자료는 `adm_cd-yq` 기준으로 직접 발행한다.
- 보조 공공데이터
  - 공시지가, 교통, 병의원, 대형유통, 노인시설, 보행환경 등 구조 변수
- 서울생활인구
  - 관내이동과 대도시권 내외국인 월별 ZIP에서 외부 유입 인구를 산출한다.
  - 생활인구는 시점 인구이므로 연합계가 아니라 월별 평균 시점인구를 먼저 만들고, 분기 내 월평균의 평균으로 발행한다.
  - 월 내부 일수가 부족한 원천 ZIP은 관측일 기반 월평균을 해당 월 대표값으로 사용하고, 월별 성공일수와 coverage flag를 manifest에 기록한다.
- 서울시 상권분석서비스 신생기업 생존율 JSON
  - 홈페이지 조회 응답인 `selectSurvivalRate.json`을 수집해 1년·3년·5년 신생기업 생존율과 분모·분자를 `adm_cd-yq`로 발행한다.
  - active 안정성 하위지수에는 3년 생존율(`survival_3y`)을 사용한다.
- 행정안전부 주민등록인구현황
  - 5세별 월별 행정동 주민등록인구 CSV에서 상주인구 규모와 고령 상주인구 비중을 산출한다.
  - 월별 stock은 분기 내 평균으로, 고령비중은 월별 분모가중 분기 비중으로 발행한다.
  - 원천 행정동명은 2020 기준 서울시 행정동 경계의 `adm_cd`로 매핑하고 분동·개칭은 2020 기준으로 정합한다.
- 2020 기준 서울시 행정동 경계
  - 공간가중행렬과 지도 시각화의 공통 기준
  - `adm_cd`-행정동-자치구-권역생활권 정적 lookup의 원천 기준

## 3) 핵심 분석 데이터셋

- `seoul_quarter_base.parquet`
  - canonical short-run Seoul quarterly base
- `adm_region_lookup.parquet`
  - `adm_cd` 기준 행정동명, 자치구명, 5대 권역생활권 정적 lookup
- `aux_covariates.parquet`
  - `adm_cd-yq` 기준 auxiliary public-data integration layer
- `living_population_external_inflow.parquet`
  - `adm_cd-yq` 기준 서울생활인구 외부 유입 인구 layer
- `golmok_survival_rate.parquet`
  - `adm_cd-yq` 기준 서울시 상권분석서비스 신생기업 생존율 layer
- `registered_resident_population.parquet`
  - `adm_cd-yq` 기준 행정안전부 주민등록인구 기반 상주인구·고령비중 layer
- `registered_resident_population_monthly.parquet`
  - 월별 주민등록인구 중간 layer와 연령합계 검증용 layer
- `medical_source_preagg.parquet`
- `mall_source_preagg.parquet`
- `senior_source_preagg.parquet`
- `walk_betweenness_local800_len_v1.parquet`
  - static walk-environment cache
- `panel_merged_base.parquet`
  - quarter base와 auxiliary covariates 결합 직후의 shared panel
- `panel_main_pre_vitality.parquet`
  - shared quarterly derivation과 contemporaneous contract가 반영된 pre-vitality panel
- `panel_main.parquet`
  - vitality가 추가된 최종 canonical panel
- `vitality_components.parquet`
  - vitality sub-index와 composite 구성요소 table
- `W_queen.rds`, `W_rook.rds`, `W_knn6.rds`, `W_knn8.rds`

## 4) Active QC 규칙

- 키 중복: `adm_cd x yq` 0건
- 시간범위: `2019Q1~2025Q4`
- 좌표계: `EPSG:5179`
- active shared panel에서 `year`, `quarter`, `yq`, `quarter_index` 유지
- 분기 발행 규칙 점검
  - `panel_quarter_aggregation_qc.csv` (`FAIL` if quarterly publication rule or coverage breaks)
- 패널 결합 구조 점검
  - `panel_join_coverage_qc.csv` (`WARN`)
  - `panel_structural_count_flags.csv` (음수 구조 카운트면 `FAIL`)
- 공시지가 관측/보간 점검
  - `land_price_imputation_qc.csv` (`WARN`)
- 서울생활인구 외부 유입 인구 점검
  - `living_population_inflow_manifest.csv` (`WARN`, member-level 처리 로그와 month-level coverage flag)
  - `living_population_inflow_qc.csv` (`WARN`, 연도별 coverage와 값 범위)
- 신생기업 생존율 점검
  - `golmok_survival_rate_qc.csv` (`WARN`, 연도 coverage, rate 범위, 작은 코호트 수, 분자/분모 재계산 diff)
- 주민등록인구 점검
  - `registered_resident_population_mapping_qc.csv` (`FAIL`, 원천 행정동명-`adm_cd` 미매칭)
  - `registered_resident_population_qc.csv` (`FAIL`, 12개월 coverage, 고령비중 범위, 핵심 변수 결측; `WARN`, 분동 배분 건수)
- 활력지수 구성변수 점검
  - `vitality_component_qc.csv` (`WARN`, 핵심 지수 생성 불가 시 `FAIL`)
- 처리 산출물 무결성 점검(수동)
  - `processed_parquet_inventory.csv`
  - `processed_parquet_schema.csv`
  - `processed_parquet_missing_summary.csv`
  - `processed_parquet_qc_checks.csv`
- 행정동-자치구-권역생활권 lookup 점검
  - `adm_region_lookup_qc.csv` (`FAIL`, 425개 행정동, 25개 자치구, 5개 권역생활권, 자치구별 행정동 수 불일치)

## 5) Optional Supplementary Surface

- interaction / age-mix / family-comparison appendix scripts
- `01_run_gtwr_main.R`와 추가 GTWR sidecars
  - opt-in local analysis only

위 자산은 canonical default run, active QC, active success 판정의 필수 계약이 아니다.

## 6) 수동 QC 및 대화형 review helper

- `02_check_processed_parquet_outputs.R`
  - `03_Processed_Data` 아래 parquet 전부를 읽어 inventory, schema, missing summary, QC checks를 남기는 full parquet audit이다.
  - raw quarterly staging과 active quarterly publication layer를 분리해 판정한다.
- `03_open_outputs_for_rstudio_review.R`
  - persisted output을 추가로 만들지 않는 interactive review helper다.
