# 연구절차

## 0. 문서 목적

이 문서는 현재 active 연구설계를 실제로 어떻게 수행하는지 설명하는 상세 절차 문서다. 실행 순서만 적는 체크리스트가 아니라, 분기 패널 구축, 공간진단, TWFE, SPDM, GTWR가 어떤 규칙으로 연결되는지 재현 가능한 수준에서 정리한다.

문서 역할은 아래처럼 구분한다.

- `research_plan.md`
  - 연구 배경, 질문, 변수 역할, 방법론 우선순위
- `research_procedure.md`
  - 실제 수행 절차, 입력-출력 계약, runtime/QC 규칙
- `paper_methods_blueprint.md`
  - 논문 집필용 서사, 표·그림 연결, 본문/부록 배치

active analytical contract는 이 문서가 선언하는 분기 패널 기준을 따른다.

## 1. 핵심 수행 원칙

### 1.1 현재 방법론 계층

현재 canonical methodology stack은 아래 순서를 따른다.

1. `ESDA`
2. `TWFE baseline / residual spatial-diagnostic`
3. `SPDM main global model`
4. `SPDM canonical channel path model`
5. `GTWR resident-only optional local sidecar`

이 순서는 코드 실행 순서이자 해석 순서다. 먼저 공간 패턴의 존재를 확인하고, 비공간 기준선으로 방향성을 잡고, 공간 확장모형으로 직접효과와 파급효과를 해석한 뒤, 필요할 때만 국지적 이질성을 별도 sidecar로 읽는다.

### 1.2 비협상 수행 원칙

1. 공간 단위는 **2020년 기준 서울시 행정동(`adm_cd`)** 으로 통일한다.
2. active canonical workflow의 시간 범위는 **2019년 ~ 2025년** 이다.
3. 공통 active key는 `adm_cd`, `yq`다.
4. active shared panel은 `year`, `quarter`, `yq`, `quarter_index`를 모두 유지한다.
5. 좌표계는 `EPSG:5179`다.
6. canonical timing contract는 **동시점 분기(`t`)** 이다.
7. main exposure는 `age60_resident_share`다.
8. `age60_floating_share`, `age60_sales_share`는 보조 축 또는 appendix에서 다룬다.
9. 종속변수는 개별 활력지표를 우선하고 `vitality_index_base`는 보조 composite로 둔다.
10. 기본 공간가중행렬은 `Queen` row-standardized다.
11. 대안 W는 `Rook`, `kNN6`, `kNN8`다.
12. TWFE는 main inferential endpoint가 아니라 baseline / spatial-diagnostic layer다.
13. SPDM main은 main global model이며 direct / indirect / total effect 보고가 중심이다.
14. `03_run_spdm_channel_path.R`는 canonical channel path model이며 `age60_resident_share -> age60_floating_share -> vitality` 경로를 검정한다.
15. GTWR는 optional local sidecar이며 resident-only quarterly contract에 한정한다.
16. `panel_main.parquet` 하나를 공통 정본으로 두고, ESDA/TWFE/SPDM/GTWR는 method-specific view만 읽는다.
17. raw data와 boundary 원본은 수정하지 않는다.

### 1.3 이용 데이터와 변수 계약 요약

- 핵심 데이터셋
  - `seoul_quarter_base.parquet`
  - `adm_region_lookup.parquet`
  - `aux_covariates.parquet`
  - `golmok_survival_rate.parquet`
  - `panel_merged_base.parquet`
  - `panel_main_pre_vitality.parquet`
  - `panel_main.parquet`
  - `W_queen.rds`, `W_rook.rds`, `W_knn6.rds`, `W_knn8.rds`
- 원천 데이터 축
  - 서울시 상권분석서비스 raw
  - 보조 공공데이터
  - 2020 기준 행정동 경계
- 메인 변수 축
  - main exposure: `age60_resident_share`
  - supporting exposures: `age60_floating_share`, `age60_sales_share`
  - primary outcomes: `vitality_sub_economic`, `vitality_sub_social`, `vitality_sub_temporal`, `vitality_sub_stability`
  - supplementary composite: `vitality_index_base`
- robustness composites: `vitality_index_entropy`, `vitality_index_pca`
- channel path composite: `vitality_index_base`

## 2. 상세 연구 수행 절차

### 2.1 공통 데이터 기준

이 프로젝트의 실질적 분석 단위는 `adm_cd x yq` 분기 패널이다. 전처리의 핵심은 분기 source의 단기 변동을 보존하고, 연도·정적 source를 quarter-end as-of 규칙으로 붙여 source precision을 명시하는 것이다.

공통 수행 원칙은 아래와 같다.

- 서울시 상권분석서비스 중 분기 source는 `adm_cd-yq` 기준으로 직접 정리한다.
- 연도·정적 source는 `adm_cd-year` 또는 `adm_cd` 수준에서 정리한 뒤 분기 패널에 as-of 방식으로 결합한다.
- 모델은 별도 slim panel 파일을 만들지 않고 `panel_main`의 method-specific view만 읽는다.
- 따라서 전처리와 모델 사이의 실질적 handoff는 `panel_main.parquet` 하나로 고정된다.

### 2.1A `01_build_adm_region_lookup.R`: 행정동-자치구-생활권 lookup 구축

이 단계의 목적은 2020 기준 서울시 행정동 경계에서 `adm_cd`, 행정동명, 자치구명, 5대 권역생활권을 연결한 정적 lookup을 만드는 것이다. 이 lookup은 분석 패널의 통계모형에는 직접 투입하지 않지만, 주민등록인구 원천의 행정동명 매핑, GTWR 권역별 요약, QC, 보고 산출물에서 같은 지역 분류를 재사용하기 위한 기준 자산이다.

핵심 산출물은 아래와 같다.

- `adm_region_lookup.parquet`
  - `adm_cd` 기준 정적 lookup
- `adm_region_lookup.csv`
  - 검토와 보고용 companion table
- `adm_region_lookup_qc.csv`
  - 425개 행정동, 25개 자치구, 5개 권역생활권, 자치구별 행정동 수 계약 점검

이 단계는 raw boundary source를 수정하지 않는다. `adm_cd` 앞 6자리로 자치구를 식별하고, 서울 5대 권역생활권 분류표를 결합한다.

### 2.2 `02_build_seoul_quarter_base.R`: 서울 상권 분기 base 구축

이 단계의 목적은 서울시 상권분석서비스 원천표를 source별로 통합하고, 이후 모든 분석의 기준 격자가 되는 분기 base panel을 만드는 것이다.

이 스크립트는 먼저 raw 파일 전체를 스캔해 source type을 식별한다. 그 다음 원천 자료를 두 갈래로 처리한다.

1. `추정매출`, `점포`, `길단위인구(유동인구)`처럼 intra-year 분포를 가진 분기 source
   - `adm_cd-yq` 기준으로 quarterly publication rule을 적용한다.
   - additive flow는 분기 합계, level/share는 분기 대표값 또는 분모가중 분기 비중을 사용하고, temporal/stability 구성요소는 분기 단면과 rolling 4-quarter 분포를 이용해 계산한다.
2. 나머지 연도 source
   - `adm_cd-year` 기준으로 직접 표준화한다.
   - 분기 패널에는 source precision을 명시하고 quarter-end as-of 규칙으로 결합한다.
   - 서울시 상권분석서비스의 Q4 업데이트형 구조 source는 strict Q4 snapshot as-of로 발행한다.
   - Q4 관측값이 없으면 같은 연도 최신분기 값으로 대체하지 않고 결측으로 둔다.

이 단계의 핵심 산출물은 아래와 같다.

- `seoul_quarter_base.parquet`
  - canonical quarterly base
- `seoul_raw_review.parquet`
  - raw integration review companion
- `panel_quarter_aggregation_qc.csv`
  - quarterly publication rule 적용 결과와 coverage를 점검하는 QC 로그

중요한 점은 raw provenance 단계의 원천 분기코드를 표준화해, **active base 이후에는 표준 `year`, `quarter`, `yq`, `quarter_index`만 남기는 것** 이다.

### 2.3 `03_build_auxiliary_covariates.R`: 보조 공공데이터를 `adm_cd-yq` 보조변수로 정리

이 단계의 목적은 상권 quarterly base에 바로 붙일 수 있는 보조변수 집합을 만드는 것이다. 먼저 `seoul_quarter_base.parquet`에서 실제로 존재하는 `adm_cd-yq` 조합을 읽어 `base_quarter`를 정의하고, 모든 보조 source를 이 기준에 맞춰 정리한다.

주요 작업은 아래와 같다.

1. raw 파일 읽기와 컬럼 정리
2. point/line/polygon을 `adm_cd` geometry에 배정
3. geocoding, cache, manual fix 처리
4. annual/static source를 quarterly panel에 맞춘 as-of covariate로 발행

공시지가는 필지 polygon의 내부 대표점으로 행정동을 배정한 뒤, 유효한 필지 면적을 가중치로 하는 행정동-연도별 면적가중평균으로 집계한다. 분기 패널에는 해당 연도 공시지가를 같은 연도의 4개 분기에 동일하게 발행한다. 이는 행정동 전체 토지면적 기준의 지가 수준을 통제하기 위한 active contract이며, 엄밀한 행정동-필지 교차면적 계산은 수행하지 않는다.

이 단계의 주요 산출물은 아래와 같다.

- `aux_covariates.parquet`
  - `adm_cd-yq` 기준의 canonical auxiliary contract
- `medical_source_preagg.parquet`, `mall_source_preagg.parquet`, `senior_source_preagg.parquet`
  - 재현 가능한 record-level intermediate
- `walk_betweenness_local800_len_v1.parquet`
  - static walk-environment cache
- geocode/QC/unmatched log

대중교통 접근성 원천은 분기 source precision을 별도 추적한다. 버스정류장은 2019, 2020, 2025년 단일 snapshot을 해당 연도 분기 대표값으로 반복하고, 2021년 1월~2024년 4월 월별 snapshot은 각 분기말 이전 최신 snapshot을 사용한다. 2024년 5월 이후 원천 공백은 2024년 4월 1일 snapshot을 carry-forward한다. 지하철역은 station master에 개통일 규칙을 부여해 `open_date <= quarter_end`인 역만 해당 분기 count에 포함한다.

이제 의료·대형유통 등도 더 이상 active control pool에 들어가지 않는다. record-level pre-aggregation은 유지하되, active panel에는 permit-based as-of 진단 변수로만 남긴다.

### 2.4 `01_build_living_population_inflow.R`: 서울생활인구 외부 유입 인구 구축

이 단계의 목적은 서울생활인구 월별 ZIP 원천을 전체 압축해제하지 않고 읽어 `adm_cd-yq` 기준 외부 유입 인구를 만드는 것이다. 상업 활력의 사회적 차원은 단순 내부 유동인구뿐 아니라 외부 생활권에서 유입되는 인구 규모도 반영해야 하므로, 이 산출물은 optional preprocessing layer로 관리하되 최종 패널에는 있으면 결합한다.

월별 ZIP 처리 비용이 크기 때문에 `run_all.R`의 default 실행과 required test plan에서는 이 단계를 제외한다. 수동으로 `01_build_living_population_inflow.R`를 실행해 산출물이 있으면 `06_build_analysis_panel.R`에서 `adm_cd-yq` 기준으로 결합한다. 이미 `living_population_external_inflow.parquet`가 있고 `LIVING_POP_FORCE_REBUILD=FALSE`이면 이 optional preprocessing script는 기존 산출물을 재사용한다.
전체 재생성은 월별 ZIP 단위 병렬 처리를 사용할 수 있다. `LIVING_POP_CORES`를 2 이상으로 지정하면 INNER와 METRO 각각의 월별 ZIP 처리를 병렬화하되, 최종 parquet, manifest, QC 파일은 부모 프로세스가 한 번만 기록한다.

집계 정의는 아래와 같다.

- 관내이동 자료: 대상 행정동의 자치구와 거주지 자치구가 다른 row만 사용한다.
- 대도시권 내외국인 자료: 모든 row를 외부 유입으로 사용한다.
- 시간대: 기본값은 `LIVING_POP_HOURS=0-23` 전체 시간대다.
- 최종 지표: 생활인구는 누적 flow가 아니라 시점 인구이므로 월별 평균 시점인구를 먼저 계산한 뒤 같은 분기 월평균의 평균으로 계산한다.
- 월 내부 일수가 부족한 ZIP은 관측된 일자의 월평균을 해당 월 대표값으로 사용하되, `living_population_inflow_manifest.csv`에 `month_success_days`, `month_expected_days`, `month_coverage_flag`를 남긴다.
- 전체 실행에서는 INNER/METRO 각각 12개월 coverage가 없으면 실패시킨다. 1~9일 또는 10~19일만 있는 부분월은 사용하되 manifest에서 강한 경고 또는 경고로 추적한다.

주요 산출물은 아래와 같다.

- `living_population_external_inflow.parquet`
  - `inner_external_inflow_pop`, `metro_external_inflow_pop`, `external_inflow_pop`
- `living_population_inflow_manifest.csv`
  - ZIP member 처리 성공·오류·스킵 로그
- `living_population_inflow_qc.csv`
  - 분기별 finite coverage와 값 범위 점검

### 2.5 `04_build_golmok_survival_rate.R`: 신생기업 생존율 구축

이 단계의 목적은 서울시 상권분석서비스 홈페이지의 `selectSurvivalRate.json` 응답을 직접 호출해 `adm_cd-yq` 기준 신생기업 생존율 layer를 만드는 것이다. PDF/OCR 추출 대신 홈페이지 조회에 쓰이는 JSON 응답을 저장하고 파싱하므로, 생존율뿐 아니라 생존 기업 수와 코호트 분모를 함께 보존할 수 있다.

연구기간 `2019Q1~2025Q4`는 `2019`, `2022`, `2025` 기준연도 Q4 요청으로 확보한다. 각 요청은 3개년 block을 반환하므로 `2019` 요청은 `2017~2019`, `2022` 요청은 `2020~2022`, `2025` 요청은 `2023~2025`를 제공한다. active panel에는 이 중 `2019~2025` 값을 분기 panel에 as-of로 결합하고, 행정동 코드는 project canonical `10자리 adm_cd`로 padding한다.

주요 산출물은 아래와 같다.

- `golmok_survival_rate.parquet`
  - `survival_1y`, `survival_3y`, `survival_5y`와 각 생존 기업 수·코호트 분모
- `golmok_survival_all_levels.parquet`
  - 서울시 전체, 자치구, 행정동을 포함한 원자료성 파싱 결과
- `golmok_survival_rate_qc.csv`
  - key uniqueness, 분기 coverage, rate 범위, 분자/분모 재계산 diff, 작은 코호트 수 점검

`survival_3y`는 active 안정성 하위지수의 점포 존속성 축에 사용한다. 생존율 분모가 0인 행정동-분기는 값을 임의 대체하지 않고 `NA`로 유지하며, QC 로그에 결측과 작은 코호트 수를 남긴다.

### 2.6 `05_build_registered_resident_population.R`: 주민등록인구 기반 상주인구 구축

이 단계의 목적은 행정안전부 주민등록인구현황의 행정동별 5세 단위 월별 CSV를 2020 기준 서울시 행정동 코드로 정합해 상주인구 규모와 고령 상주인구 비중을 만드는 것이다. 서울시 상권분석서비스 상주인구는 active main exposure와 `ln_resident_pop`의 원천으로 사용하지 않는다.

월별 stock 변수는 연합계가 아니라 분기 평균으로 발행한다. `age60_resident_share`, `age60_64_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, `age65plus_resident_share`는 해당 분기 월별 고령 인구 합계를 같은 분기 월별 총인구 합계로 나눈 분모가중 분기 비중이다. age-mix appendix용 `age20_resident_share`~`age60plus_resident_share`는 20세 이상 연령구성 분모에서 계산한다.

2020 기준 경계 정합을 위해 원천 행정동명은 경계 행정동명과 매칭하고, 분석기간 중 분동·개칭은 2020 기준으로 합산 또는 환원한다. `상일제1동`은 `상일동`, `강일동+상일제2동`은 `강일동`, `개포3동`은 `일원2동`, 2025년 `신설동+용두동+용신동`은 `용신동`으로 처리한다. 2020년에 `오류제2동`에서 분동된 `항동`은 2019년에 분동 전 `오류제2동`에 포함되어 있었으므로, 2019년 `오류제2동` 원천값을 2020년 `오류제2동`/`항동`의 같은 월·같은 연령대 비율로 배분한다. 이 분동 배분 row는 `registered_boundary_proxy_flag`와 `registered_boundary_proxy_reference_year`로 추적한다.

주요 산출물은 아래와 같다.

- `registered_resident_population.parquet`
  - `resident_pop`, `age60_resident_pop`, `age60_resident_share`, `age65_74_resident_share`, `age75plus_resident_share` 등
- `registered_resident_population_monthly.parquet`
  - 월별 중간 stock과 연령대 합계 검증용 layer
- `registered_resident_population_mapping_qc.csv`
  - 원천 행정동명과 canonical `adm_cd` 매핑 상태
- `registered_resident_population_qc.csv`
  - 분기 coverage, 3개월 coverage, 분동 배분 건수, 고령비중 범위, 연령합계 diff

### 2.7 `06_build_analysis_panel.R`: 공용 분석패널 결합과 공통 파생변수 생성

이 단계의 목적은 `seoul_quarter_base`, `aux_covariates`, `living_population_external_inflow`, `golmok_survival_rate`, `registered_resident_population`을 결합하고, 모든 downstream 분석이 공유하는 공통 파생변수·QC를 한 번에 만들며, 최종 활력지수 계산 직전 상태인 `panel_main_pre_vitality`를 발행하는 것이다.

먼저 key 무결성을 다시 확인한다.

- `seoul_quarter_base`: `adm_cd-yq` unique
- `aux_covariates`: `adm_cd-yq` unique
- `living_population_external_inflow`: `adm_cd-yq` unique when optional output exists
- `golmok_survival_rate`: `adm_cd-yq` unique
- `registered_resident_population`: `adm_cd-yq` unique

그다음 `adm_cd`, `year`, `quarter`, `yq`, `quarter_index` 기준으로 결합해 `panel_merged_base.parquet`를 만든다. 이 파일은 provenance checkpoint다. 이후 문제가 생기면 “join 자체가 깨졌는지”와 “join 이후 파생변수 계산이 깨졌는지”를 분리해서 볼 수 있어야 한다.

이 스크립트에서 만드는 대표적 변수군은 아래와 같다.

- `covid_period`
- `ln_total_sales`, `ln_sales_count`, `ln_total_store_count`, `ln_sales_per_store`
- `sales_quarter_stability`, `floating_quarter_stability`
- `ln_resident_pop`, `ln_floating_pop`, `ln_external_inflow_pop`, `ln_spend_total`
- `ln_official_land_price`
- `transit_accessibility`
- `store_density`, `resident_pop_density`, `floating_pop_density`
- `sales_per_store`, `sales_per_capita`
- `survival_3y`
- `stability_score` (`-closure_rate`, diagnostic support)
- `age60_sales_lq`

그 다음 shared quarterly contract를 확정한다.

- canonical shared panel은 동시점 변수만 유지한다.
- legacy shift/lead 파생열은 active shared panel에 남기지 않는다.
- timing 민감도는 필요할 때 appendix 또는 별도 robustness로만 다룬다.

이 단계의 주요 QC는 아래와 같다.

- `panel_join_coverage_qc.csv`
- `panel_quarter_aggregation_qc.csv`
- `panel_structural_count_flags.csv`
- `missing_data_log.csv`

### 2.8 `07_build_vitality_index.R`: 활력지수 구성과 `panel_main` 발행

이 단계의 목적은 `panel_main_pre_vitality`를 입력으로 활력지수를 계산하고, 최종 canonical shared panel인 `panel_main.parquet`를 발행하는 것이다.

핵심 원칙은 “공통 패널을 다시 바꾸지 않고 허용된 활력 열만 추가한다”는 publication contract다.

구성요소는 네 개의 하위 차원으로 묶인다.

- `vitality_sub_economic`
  - transaction scale axis: `ln_sales_count`, `ln_total_sales`
  - final subindex: pooled-z `ln_sales_count`와 pooled-z `ln_total_sales`의 동일가중 평균
- `vitality_sub_social`
  - `ln_floating_pop`, `ln_external_inflow_pop`
- `vitality_sub_temporal`
  - `sales_time_entropy`, `floating_time_entropy`, `sales_quarter_stability`, `floating_quarter_stability`
- `vitality_sub_stability`
  - diversity axis: `diversity_index`
  - continuity axis: `operating_months_rel_seoul`, `survival_3y`
  - final subindex: pooled-z diversity axis와 pooled-z continuity axis의 동일가중 평균

그리고 보조 composite로 아래를 만든다.

- `vitality_index_base`
- `vitality_index_entropy`
- `vitality_index_pca`

표준화 기준은 전체 `2019Q1~2025Q4 adm_cd-yq` 패널 표본이다. `07_build_vitality_index.R`는 개별 component를 pooled z-score로 표준화해 하위지수를 만들고, 하위지수도 다시 pooled z-score로 맞춘 뒤 composite를 계산한다. 분기별 cross-section 표준화는 active workflow에서 사용하지 않는다.

### 2.8 `01_build_spatial_weights.R`: 공간가중행렬 구축

이 단계는 2020 기준 서울시 행정동 경계를 이용해 공통 spatial contract를 구축한다.

- main W: `Queen`
- robustness W: `Rook`, `kNN6`, `kNN8`

모든 모델과 지도 시각화는 같은 `adm_cd` ordering과 same-boundary contract를 공유해야 한다.

### 2.9 `02_run_esda.R`: 분기 단위 공간진단

ESDA는 모형 추정 이전에 공간 패턴의 존재를 확인하는 단계다.

- latest quarter cross-section을 중심으로 분포 지도와 LISA를 저장한다.
- Global Moran's I는 재현 가능한 permutation p-value를 사용하며, 대안 W 민감도도 같은 방식으로 계산한다.
- LISA quadrant는 univariate의 경우 `z(x)`와 `W z(x)`, bivariate의 경우 `z(x)`와 `W z(y)`의 부호를 기준으로 분류한다.
- bivariate LISA 지도는 계산된 `age60_resident_share`/`age60_floating_share`와 활력지표 전체 조합을 저장한다.
- quarterly sequence를 사용해 EHSA를 계산한다. EHSA는 `sfdep::emerging_hotspot_analysis()`의 Gi* 관례에 맞춰 queen contiguity에 self-neighbor를 포함한 `queen_include_self` weights를 사용한다.
- 핵심 변수는 `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, `vitality_index_base`다.

### 2.10 `01_run_twfe_main.R`: quarterly TWFE baseline

TWFE는 비공간 기준선과 residual Moran diagnostic을 제공한다.

- 입력: `panel_main.parquet`, `W_queen.rds`
- 기본식: `y_it ~ age60_resident_share + controls_it | adm_cd + yq`
- 표준오차: `cluster = ~ adm_cd`
- 종속변수: `vitality_sub_*`, `vitality_index_base`

필수 산출물은 아래와 같다.

- `twfe_main_models.csv`
- `twfe_main_controls_used.csv`
- `twfe_main_diagnostics.csv`
- `twfe_main_residual_moran.csv`
- `twfe_main_residual_moran_by_yq.csv`

### 2.11 `02_run_spdm_main.R`: quarterly SPDM main model

SPDM은 active design의 main global model이다.

- 입력: `panel_main.parquet`, `W_queen.rds`
- main exposure: `age60_resident_share`
- specification: `y_it = rho W y_it + X_it beta + W X_it theta + adm_cd FE + yq FE + e_it`
- implementation: `W age60_resident_share`와 `W controls`를 `yq`별로 직접 생성하고, `splm::spml(lag=TRUE, spatial.error="none", model="within", effect="twoways")`로 추정한다.
- main output: `direct / indirect / total effects`
- impact: `S = (I - rho W)^(-1)`와 `S(beta I + theta W)` 기반의 true SDM matrix impact를 사용한다.
- 표준오차: coefficient와 spatial parameter는 `splm::spml()`의 model-based asymptotic ML `vcov`를 사용하고, impact SE/CI는 같은 `vcov`에서 simulation으로 계산한다. 이 출력은 robust SE가 아니라 model-based inference로 보고한다.

핵심 산출물은 아래와 같다.

- `spdm_main_models.csv`
- `spdm_impacts.csv`
- `spdm_controls_used.csv`
- `spdm_main_diagnostics.csv`

### 2.12 `03_run_spdm_channel_path.R`: canonical SPDM channel path model

이 단계는 `age60_resident_share -> age60_floating_share -> commercial vitality` 경로를 quarterly Queen SDM 위에서 검정하는 canonical mediation-oriented channel model이다. `age60_resident_share`를 `X`, `age60_floating_share`를 mediator `M`으로 고정하고, 각 활력 outcome별 동일 balanced sample에서 total-effect equation, mediator equation, outcome equation을 모두 추정한다.

- total-effect equation: `Y_it = rho W Y_it + X_it beta_c + W X_it theta_c + controls + W controls + FE + e_it`
- mediator equation: `M_it = rho W M_it + X_it beta_a + W X_it theta_a + controls + W controls + FE + e_it`
- outcome equation: `Y_it = rho W Y_it + X_it beta_c' + M_it beta_b + W X_it theta_c' + W M_it theta_b + controls + W controls + FE + e_it`
- channel outcome: `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, `vitality_index_base`
- excluded outcome: `vitality_sub_social`은 유동인구 source와 직접 겹치므로 channel path의 단독 outcome에서 제외한다. 다만 종합 활력지수는 연구의 네 차원 구성 의미를 유지하기 위해 사회적 활성도를 포함한 `vitality_index_base`를 사용하고, mediator source overlap caveat를 함께 기록한다.
- indirect effect: `a*b` product effect를 `direct`, `indirect`, `total` scale별로 기록하고, `c - c'` 직접효과 약화 진단을 함께 저장한다.
- inference: 기본값은 행정동 단위 wild residual bootstrap이다. bootstrap이 비활성화되었거나 유효 draw가 부족하면 `a`와 `b` impact estimate의 독립을 가정한 `delta_independent_approx`를 fallback으로 사용한다.
- runtime default: channel impact simulation은 `SPDM_CHANNEL_IMPACT_SIM_R=1000`, bootstrap 반복은 `SPDM_CHANNEL_BOOTSTRAP_R=1000`, bootstrap 실행은 `RUN_SPDM_CHANNEL_BOOTSTRAP=TRUE`가 기본이다.
- parallel runtime: 기본 core 수는 `SPDM_CHANNEL_IMPACT_CORES=4`, `SPDM_CHANNEL_BOOTSTRAP_CORES=4`이다. macOS/Linux/GCP에서는 impact simulation draw와 bootstrap draw를 병렬 처리하며, Windows에서는 안전하게 순차 실행으로 fallback한다.

핵심 산출물은 아래와 같다.

- `spdm_channel_models.csv`
- `spdm_channel_impacts.csv`
- `spdm_channel_controls_used.csv`
- `spdm_channel_path_effects.csv`
- `spdm_channel_bootstrap_draws.csv`
- `spdm_channel_diagnostics.csv`

### 2.13 `01_run_spdm_w_robustness.R`: W 민감도 점검

이 단계는 `queen`, `rook`, `knn6`, `knn8`에서 같은 resident-only quarterly SDM contract를 반복 추정한다. 목적은 W 선택에 따른 민감도를 점검하는 것이다.

### 2.14 `05_run_spdm_family_comparison_sidecar.R`: spatial family comparison

이 단계는 appendix용 manual sidecar다. main SPDM의 quarterly Queen sample과 selected control contract를 그대로 재구성한 뒤 `TWFE`, `SLX`, `SAR`, `SDM`, `SEM`, `SDEM`, `SARAR/SAC`, `GNS`를 같은 조건에서 비교한다. `SLX`와 `SDEM`의 효과는 endogenous `W y` feedback multiplier가 없는 `W X` 효과로 보고하며, `direct=beta`, `indirect=theta`, `total=beta+theta`로 저장한다. `GNS`는 `W y`, `W X`, spatial error를 모두 포함한 가장 일반적인 appendix sensitivity family이며, 평균효과는 SDM matrix impact 방식으로 기록한다.

### 2.15 `01_run_gtwr_main.R`: optional quarterly local sidecar

GTWR main은 quarterly resident-only local sidecar다.

- 실행 조건: `RUN_GTWR_MAIN_SIDECAR=TRUE`
- 입력: `panel_main.parquet`, 2020 기준 서울시 행정동 경계
- 해석 수준: local heterogeneity description
- 실행 방식: outcome-exposure spec 단위로 계산하며, `GTWR_PARALLEL_SPECS`만큼 병렬 worker를 사용한다.
- 재개 방식: spec별 RDS cache를 `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/`에 저장하고, 중단 후 재실행하면 유효한 완료 spec은 재사용한다.
- control set: 기본값은 `GTWR_CONTROL_SET=lean`이다. `lean`은 주민등록인구 기반 `ln_resident_pop`, `ln_official_land_price`만 사용한다. `extended`는 여기에 `transit_accessibility`를 추가한다.
- bandwidth 방식: 기본값은 `GTWR_BANDWIDTH_STRATEGY=fixed`, `GTWR_ST_BW=480`이다. `adaptive=TRUE` 기준으로 각 추정점 주변 시공간 이웃 480개를 사용해 outcome 간 비교 가능성과 extended control set의 추정 가능성을 함께 유지한다. `RUN_GTWR_BANDWIDTH_SENSITIVITY=TRUE`이면 `GTWR_BANDWIDTH_SENSITIVITY_GRID`의 기본값 `240,360,480,600,720`을 같은 outcome-control-spec에 반복 적용하고, baseline 480 대비 beta correlation, 절대변화, sign flip, local condition-number 변화를 `gtwr_bandwidth_sensitivity_<control_set>.csv`에 저장한다. `full_panel_bw_gtwr`와 `anchor_quarter_bw_gtwr`는 명시적으로 선택한 별도 진단 실행에서만 사용한다.
- lamda 민감도: `RUN_GTWR_LAMDA_SENSITIVITY=TRUE`일 때만 실행한다. `GTWR_LAMDA_SENSITIVITY_GRID`의 각 값을 같은 outcome-control-spec에 적용해 GTWR를 재추정하고, baseline latest-quarter beta 대비 상관, 절대변화, sign flip, local condition-number 변화를 `gtwr_lamda_sensitivity_<control_set>.csv`에 저장한다.
- local CN 진단: `GWmodel::gwr.collin.diagno()`의 local_CN 계산 관례를 따르되, GTWR에서 사용한 `st.dist`/`gw.weight` 기반 시공간 가중치를 적용한다.

GTWR의 핵심 운영 원칙은 아래와 같다.

1. quarterly sample만 사용한다.
2. main control pool은 `GTWR_CONTROL_SET`으로 선택한다. 기본 `lean`은 상주인구 규모와 지가 통제만 사용하고, `extended`는 대중교통 접근성 composite를 추가한다.
3. main bandwidth는 fixed `GTWR_ST_BW=480`으로 통일한다. fixed bandwidth grid 민감도는 opt-in 보조 진단으로만 실행하고, full-panel 또는 anchor-quarter `bw.gtwr()` 탐색은 명시적 진단 실행에서만 사용한다.
4. main raw/output surface는 latest quarter local beta를 기준으로 만든다.
5. earliest-to-latest delta는 `gtwr_delta_*` 보조 reporting table에서만 파생한다.
6. final CSV bundle은 매 실행마다 전체 spec cache를 다시 집계해 갱신한다.
7. lamda와 bandwidth 민감도는 계산비용이 크므로 opt-in 보조 진단으로만 해석한다.
8. global causal claim을 대체하지 않는다.

추가 GTWR appendix sidecar는 main GTWR와 같은 quarterly panel, `GWmodel::gtwr()` 실행 경로, `GTWR_CONTROL_SET` 계약, fixed bandwidth 기본값을 공유한다. 단, 각각 별도 실행 플래그와 별도 spec/bandwidth cache namespace를 사용한다.

- `02_run_gtwr_floating_only.R`: `RUN_GTWR_FLOATING_SIDECAR=TRUE`일 때 main outcomes x `age60_floating_share`를 추정한다.
- `03_run_gtwr_age_band.R`: `RUN_GTWR_AGE_BAND_SIDECAR=TRUE`일 때 configured resident/floating domain x age20~age50 exposure x main outcomes를 추정한다. 주민 domain은 행정안전부 주민등록인구 기반 age share와 same-domain total control `ln_resident_pop`을 사용하고, floating domain은 종속변수 구성요소와 겹치는 `ln_floating_pop`을 추가하지 않는다.
- `04_run_gtwr_sector_share.R`: `RUN_GTWR_SECTOR_SHARE_SIDECAR=TRUE`일 때 sector-share outcomes에서 resident-only와 floating-only exposure family를 추정한다.
- `01_make_tables_figures.R`는 sidecar raw local coefficient가 있을 때 latest-minus-earliest delta summary/rankings를 파생한다.

### 2.16 `02_run_robustness.R`와 reporting

`02_run_robustness.R`는 outcome-definition, sample-window, W-Moran 민감도를 quarterly contract 위에서 점검한다. `01_make_tables_figures.R`는 본문/부록용 표·그림을 묶고, 본분석 변수의 Pearson 상관행렬과 pairwise 상관표를 함께 발행한다. reporting은 source input이 있는 optional artifact만 선택적으로 붙인다.

## 3. Active QC 규칙

### 3.1 데이터 계약 QC

- key duplication: `adm_cd x yq` 0건
- horizon: `2019Q1~2025Q4`
- shared panel에서 `year`, `quarter`, `yq`, `quarter_index` 유지
- quarterly publication/as-of coverage와 aggregation rule 점검
- 구조 카운트 음수 검출 시 `FAIL`
- 활력지수 핵심 구성변수 부재 시 `FAIL`

### 3.2 모델 계약 QC

- ESDA, TWFE, SPDM은 모두 `panel_main.parquet` 기준으로 동작해야 한다.
- TWFE residual Moran output은 필수다.
- SPDM은 direct / indirect / total effects를 보고해야 한다.
- SPDM channel path는 `a`, `b`, `c'`, `a*b` effects와 diagnostics를 보고해야 한다.
- GTWR는 optional sidecar이며, absence 자체를 failure로 해석하지 않는다.

### 3.3 처리 산출물 무결성 점검

- `method_dataset_contract_check.csv`
- `processed_parquet_inventory.csv`
- `processed_parquet_schema.csv`
- `processed_parquet_missing_summary.csv`
- `processed_parquet_qc_checks.csv`

이 로그들은 quarterly contract를 기준으로 판정해야 한다.
