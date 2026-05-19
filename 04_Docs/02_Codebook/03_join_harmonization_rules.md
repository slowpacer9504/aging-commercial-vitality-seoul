# 조인/정합 규칙서

## 1) 기본 조인 키

- 패널 키: `adm_cd`, `yq`
- 분기 조인: `adm_cd`, `yq`
- 연도/as-of 조인: `adm_cd`, `year`를 정리한 뒤 `adm_cd`, `yq` 패널에 결합
- 정적 조인: `adm_cd`

## 2) 공간 기준

- 모든 분석 단위는 2020 기준 서울시 행정동(`adm_cd`)이다.
- spatial weights와 지도 시각화도 같은 경계를 사용한다.
- `adm_region_lookup.parquet`는 2020 기준 행정동 경계의 `adm_cd`와 행정동명을 읽고, `adm_cd` 앞 6자리 자치구 prefix로 서울 5대 권역생활권 분류를 결합한 정적 lookup이다.
- 추가 cross-year boundary reconciliation 단계는 두지 않는다.

## 3) 서울 상권 raw quarterly publication

- 서울 상권 raw 중 분기 source는 `adm_cd-yq` 기준으로 직접 발행한다.
- additive flow는 분기 합계, level/share는 분기 대표값 또는 분모가중 분기 비중을 사용한다.
- temporal/stability 구성요소는 분기 단면과 rolling 4-quarter 분포를 이용해 계산한다.
- 연도·정적 source는 `adm_cd-year` 또는 `adm_cd` 기준으로 정리한 뒤 source precision을 명시하고 quarter-end as-of 규칙으로 결합한다.
- active base publication 이후에는 표준 시간키 `year`, `quarter`, `yq`, `quarter_index`만 남긴다.
- canonical quarterly base는 `seoul_quarter_base.parquet`다.

## 4) Auxiliary covariate 정합

- `03_build_auxiliary_covariates.R`는 auxiliary public-data sources를 `adm_cd-year`, `adm_cd`, 또는 record-level pre-aggregation 단위로 정리한 뒤 `adm_cd-yq` panel에 맞춰 발행한다.
- 공시지가는 필지 대표점 기반 행정동-연도 면적가중평균을 만든 뒤 원 연간값으로 보존한다.
- 한국부동산원 월별 지역별 지가지수는 법정동명으로 서울 법정동 경계와 1:1 매칭한 뒤, 법정동-행정동 공간교차 면적가중 crosswalk로 행정동 분기 보정계수 `land_price_lpi_factor`를 만든다. 최종 active 토지가격 통제변수는 연간 공시지가에 이 보정계수를 곱한 `land_price_adjusted`와 그 로그 `ln_land_price_adjusted`다.
- 대중교통 source는 `adm_cd-yq`로 발행한다. 버스정류장 count는 단일 연도 snapshot 반복, 월별 snapshot의 quarter-end latest, carry-forward status를 QC에 기록하고, 지하철역 count는 개통일 규칙의 `open_date <= quarter_end`로 계산한다.
- 의료, 대형점포, senior source는 record-level pre-aggregation layer를 남기되, active panel에는 분기 as-of count 또는 status만 반영한다.
- walk-environment cache는 `adm_cd` static layer로 관리한다.

## 5) Shared panel build

- `01_build_living_population_inflow.R`는 서울생활인구 관내이동·대도시권 내외국인 월별 ZIP에서 `living_population_external_inflow.parquet`를 발행한다.
- 관내이동은 대상 행정동 자치구와 거주지 자치구가 다른 row만 사용하고, 대도시권 자료는 모든 row를 외부 유입으로 사용한다.
- 생활인구는 시점 인구이므로 일자-시간대 row를 누적하지 않고 `adm_cd-month` 평균 시점인구를 만든 뒤, 같은 분기 월평균을 다시 평균해 `adm_cd-yq` 값으로 결합한다.
- 일부 월의 ZIP member 수가 부족한 경우 관측된 일자의 월평균을 해당 월 대표값으로 쓰고, `living_population_inflow_manifest.csv`의 `month_success_days`, `month_expected_days`, `month_coverage_flag`로 추적한다.
- `04_build_golmok_survival_rate.R`는 서울시 상권분석서비스 `selectSurvivalRate.json` 응답에서 `golmok_survival_rate.parquet`를 발행한다.
- 신생기업 생존율은 `2019`, `2022`, `2025` 기준연도 Q4 요청의 3개년 block을 행정동-분기 row로 as-of 재구성하고, `survival_3y`를 active 안정성 하위지수에 사용한다.
- 생존율 코호트 분모가 0인 행정동-분기는 임의 대체하지 않고 결측으로 유지하며 `golmok_survival_rate_qc.csv`에 기록한다.
- `05_build_registered_resident_population.R`는 행정안전부 주민등록인구현황 5세별 월별 CSV에서 `registered_resident_population.parquet`를 발행한다.
- 주민등록인구는 행정동명과 2020 기준 경계의 `adm_cd`를 매칭하고, `상일제1동 -> 상일동`, `강일동+상일제2동 -> 강일동`, `개포3동 -> 일원2동`, 2025년 `신설동+용두동+용신동 -> 용신동`처럼 분석기간의 분동·개칭을 2020 기준으로 환원한다.
- 주민등록인구 월별 stock은 분기 평균으로, 고령비중은 월별 분모가중 분기 비중으로 결합한다.
- 2020년에 `오류제2동`에서 분동된 `항동`은 2019년에 분동 전 `오류제2동`에 포함되어 있었으므로, 2019년 `오류제2동` 원천값을 2020년 `오류제2동`/`항동`의 같은 월·같은 연령대 비율로 배분한다. 이 분동 배분 row는 `registered_boundary_proxy_flag`와 `registered_boundary_proxy_reference_year`로 추적한다.
- `06_build_analysis_panel.R`는 `seoul_quarter_base`, `aux_covariates`, `living_population_external_inflow`, `golmok_survival_rate`, `registered_resident_population`을 `adm_cd`, `year`, `quarter`, `yq`, `quarter_index` 기준으로 결합한다.
- 결합 직후 결과는 `panel_merged_base.parquet`, shared derivation 후 결과는 `panel_main_pre_vitality.parquet`로 저장한다.
- 분기 중첩 변수는 active contract에서 제거한다.

## 6) Shared derived transforms

- shared quarterly transform은 `adm_cd` 그룹 안에서 `quarter_index`순 정렬 후 계산한다.
- active shared panel은 동시점 변수만 유지하며 legacy shift/lead 파생열은 발행하지 않는다.
- `store_density` 등 공유 파생변수는 `panel_main_pre_vitality` 단계에서 계산한다.
- `07_build_vitality_index.R`가 최종 `panel_main.parquet`와 `vitality_components.parquet`를 발행한다.

## 7) Model-side contract

- `panel_main.parquet`는 모든 active model의 공통 입력이다.
- appendix sidecar도 동일한 `panel_main` contract에서 출발한다.
- TWFE의 시간 FE는 `yq`, SPDM의 panel time index도 `yq` 기반 `time_id`다.
- GTWR는 quarterly resident-only local sidecar다.

## 8) 조인 실패 정책

- `FAIL`
  - 필수 키/입력 누락
  - quarterly publication/as-of rule 위반
  - 음수 구조 카운트 검출
  - 핵심 산출물 생성 불가
- `WARN`
  - coverage 저하
  - source-specific partial missing
  - 선택 보조변수 누락
- `MANUAL`
  - full processed parquet audit
  - interactive output review
