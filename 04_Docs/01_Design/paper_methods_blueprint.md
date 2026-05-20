# 논문용 통합 연구과정 요약서

## 1. 문서 목적과 사용법

이 문서는 현재 프로젝트의 연구과정을 논문 집필 관점에서 한 번에 읽을 수 있도록 정리한 통합 요약서다. 목적은 세 가지다.

1. 각 코드 단계가 연구 전체 흐름에서 어떤 역할을 하는지 설명한다.
2. 각 분석 단계가 논문의 어떤 방법, 결과, 표, 그림으로 이어지는지 연결한다.
3. 집필자가 `research_plan.md`, `research_procedure.md`, codebook, 실제 코드 사이를 반복해서 오가지 않아도 Methods/Results 초안을 구성할 수 있게 돕는다.

이 문서는 실행 계약서가 아니라 집필 지원용 브리지 문서다. active 실행 계약은 `research_procedure.md`와 codebook이 담당한다.

## 2. 한눈에 보는 연구 흐름

### 2.1 연구 질문과 실증 흐름

이 프로젝트의 핵심 연구 질문은 세 가지다.

- `RQ1. 직접효과와 전역적 관계`
  - 거주 기반 고령화(`age60_resident_share`)는 근린 상업 활력과 어떤 방향과 크기의 관계를 가지는가.
- `RQ2. 공간의존과 파급효과`
  - 고령화와 상업 활력의 관계는 지역 내부에만 머무는가, 아니면 인접 지역으로 확산되는가.
- `RQ3. 국지적 이질성`
  - 전역 평균효과가 모든 지역에서 비슷하게 나타나는가, 아니면 지역별로 반응 강도와 방향이 다른가.

이 질문에 답하는 실증 흐름은 아래와 같다.

1. **분기 패널 구축**
   - 서울시 상권 raw의 분기 변동을 보존해 분기 base로 정리하고, 저주기 보조 공공데이터와 서울생활인구 외부 유입 인구를 `adm_cd-yq` contract로 정리한 뒤 `panel_main_pre_vitality`까지 결합한다.
2. **활력지수 구성**
   - 활력의 네 하위 차원과 보조 종합지수를 계산하고 최종 shared panel인 `panel_main`을 발행한다.
3. **공간 구조 확인**
   - 공간가중행렬을 만들고 ESDA로 분포, 전역 자기상관, 국지 cluster, hotspot 패턴을 확인한다.
4. **비공간 기준선 추정**
   - quarterly TWFE로 baseline을 추정하고 residual Moran으로 공간모형 필요성을 점검한다.
5. **공간모형 추정**
   - SPDM으로 direct / indirect / total effects를 추정한다.
6. **민감도 및 부가 분석**
   - W robustness, outcome-definition/sample-window robustness, appendix family를 수행한다.
7. **국지 이질성 확인**
   - GTWR opt-in sidecar로 지역별 계수 패턴을 보조적으로 시각화한다.

### 2.2 핵심 데이터와 변수 구조

논문 집필 관점에서 먼저 고정해야 할 것은 “무슨 데이터를 어떤 층으로 썼는가”와 “무슨 변수를 어떤 역할로 썼는가”다.

- 원천 자료
  - 서울시 상권분석서비스 raw
  - 보조 공공데이터
  - 2020 기준 행정동 경계
- 분석 데이터 레이어
  - `seoul_quarter_base`
  - `aux_covariates`
  - `registered_resident_population`
  - `panel_merged_base`
  - `panel_main_pre_vitality`
  - `panel_main`

변수 구조는 아래처럼 읽으면 된다.

- main exposure
  - `age60_resident_share`
  - 행정안전부 주민등록인구현황 5세별 월별 자료에서 산출한 주민등록 상주 고령비중
- supporting exposures
  - `age60_floating_share`
  - `age60_sales_share`
- primary outcomes
  - `vitality_sub_economic`
  - `vitality_sub_social`
  - `vitality_sub_temporal`
  - `vitality_sub_stability`
- supplementary composite
  - `vitality_index_base`
- robustness composites
  - `vitality_index_entropy`
  - `vitality_index_pca`
- shared control candidate pool
  - `ln_resident_pop`
  - `ln_land_price_adjusted`
  - `transit_accessibility`
- GTWR local sidecar control pool
  - lean: `ln_resident_pop`, `ln_land_price_adjusted`
  - extended: lean + `transit_accessibility`

### 2.3 Main Text와 Appendix의 경계

- **Main text**
  - quarterly panel 구축 논리
  - 활력지수와 핵심 변수 정의
  - ESDA 핵심 결과
  - TWFE baseline과 residual Moran
  - SPDM main impacts
  - 필요 시 GTWR 요약 지도 1~2개

- **Appendix**
  - interaction / age-mix / sector-share family
  - W robustness 상세표
  - GTWR 추가 sidecar
  - 세부 QC inventory

## 3. 단계별 연구과정 요약

### 3.1 데이터 구축 단계

연구의 출발점은 서울시 행정동 **분기 패널** 을 만드는 일이다. 이 단계에서는 서울시 상권분석서비스 분기 source를 `adm_cd-yq` 단위로 직접 발행하고, 행정안전부 주민등록인구현황·연도·정적 보조 공공데이터는 quarter-end as-of 규칙으로 분기 패널에 결합한다.

집필 시 핵심 문장은 아래 구조면 충분하다.

> 서울시 상권분석서비스 raw의 분기 변동을 보존해 행정동-분기 패널을 구축하고, 행정안전부 주민등록인구현황과 보조 공공데이터는 source precision을 명시한 as-of 규칙으로 결합하여 분석용 shared panel을 구축하였다.

이때 방법론적으로 중요한 점은 다음 두 가지다.

1. 분기 자료는 연도 단위로 합치지 않고 `adm_cd-yq` 분석단위에 직접 투입한다.
2. 연도·정적 자료는 값의 반복 가능성을 숨기지 않고 source precision/QC와 함께 quarter-end as-of 방식으로 결합한다.

### 3.2 활력지수 구성 단계

전처리된 패널 위에서 상업 활력을 네 개의 하위 차원으로 정리하고, 보조 종합지수를 만든다. 본문에서는 하위 차원을 우선 보고하고, 종합지수는 전체 방향을 보조적으로 요약하는 용도로 둔다.

Methods에서는 다음처럼 쓰면 된다.

> 상업 활력은 경제적 활력, 사회적 활력, 시간적 활력, 안정성의 네 하위 차원으로 측정하였으며, 보조적으로 종합지수를 구성하였다.

경제적 활력은 추정매출 건수와 총 추정매출액을 각각 pooled z-score로 표준화한 뒤 동일가중 평균해 측정한다. 총 점포수와 점포당 매출액은 패널에는 유지하되, 경제 하위지수에는 직접 투입하지 않는다.
사회적 활력은 상권 내부 유동인구 규모와 서울생활인구 기반 외부 유입 인구 규모를 함께 반영한다.
시간적 활력은 하루 안의 매출·유동인구 시간대 분산과 1년 안의 매출·유동인구 분기 안정성을 함께 반영한다.
안정성은 업종 다양성으로 측정한 구조적 다양성 축과, 서울 대비 상대 영업월수 및 신생기업 3년 생존율로 측정한 점포 존속성 축을 동일가중으로 결합한다.
각 구성요소와 하위지수는 분기별 상대순위만 남기는 방식이 아니라 active 분석기간인 `2019Q4~2025Q4 adm_cd-yq` 표본을 기준으로 pooled z-score 표준화한다. 따라서 구성요소 간 단위 차이는 제거하면서도 분기 간 서울 전체 활력 수준 변화는 지수에 남긴다.

### 3.3 ESDA 단계

ESDA는 “공간을 고려할 이유가 있는가”를 보여주는 탐색 단계다. 최신 분기 cross-section의 분포 지도, Global Moran's I, Bivariate Moran's I, LISA, EHSA를 통해 고령화와 활력의 공간 패턴을 제시한다.

Results 초반부에서는 다음 순서가 자연스럽다.

1. 분포 지도
2. Global Moran's I
3. LISA 또는 EHSA 대표 그림

### 3.4 TWFE 단계

TWFE는 비공간 기준선이다. 본문에서는 “분기 고정효과와 지역 고정효과를 통제한 baseline”으로 소개하고, 잔차 Moran 결과를 통해 공간모형 도입의 필요성을 연결하면 된다.

핵심 서술 포인트는 아래 세 가지다.

1. FE 구조는 `adm_cd + yq`다.
2. 메인 노출변수는 `age60_resident_share`이다.
3. 잔차 Moran's I가 공간의존 잔존 여부를 보여준다.

### 3.5 SPDM 단계

SPDM은 본 연구의 main global model이다. active specification은 `W y`, `X`, `W X`를 모두 포함하는 true SDM이며, `W age60_resident_share`와 `W controls`는 quarterly panel에서 직접 생성한다. 계수표 자체보다 direct / indirect / total effects 표를 중심으로 해석해야 한다.

본문 결과는 아래 흐름이 가장 안정적이다.

1. 직접효과
2. 간접효과
3. 총효과
4. 차원별 outcome 비교

### 3.6 Robustness와 부가 분석

W robustness와 outcome-definition/sample-window 민감도는 본문에서는 짧게 요약하고, 상세 표는 appendix로 넘기는 편이 좋다. interaction, age-mix, sector-share family도 같은 원칙으로 appendix에 배치한다.

### 3.7 GTWR 단계

GTWR는 전역모형 이후에도 지역별 반응 강도와 방향이 다를 수 있다는 점을 보조적으로 시각화한다. 다만 이는 본문의 핵심 인과 추정이 아니라 local heterogeneity layer다.

분기 단위 개편 이후 GTWR의 집필상 위치는 다음처럼 정리하는 것이 맞다.

- main text: 대표 지도 1~2개 또는 간단한 요약
- appendix: 지역별 계수 분포, local condition number, 추가 local sidecar
- control interpretation: 본문 GTWR는 lean을 기본으로 쓰고, extended는 대중교통 접근성 composite를 추가한 민감도 사양으로 해석한다.

## 4. 코드별 연구 역할 표

### 4.1 Canonical Default Flow

| Script | 연구 역할 | 주요 산출물 | 논문 연결 |
| --- | --- | --- | --- |
| `01_build_adm_region_lookup.R` | 행정동-자치구-생활권 lookup 구축 | `adm_region_lookup.parquet`, `adm_region_lookup.csv` | Methods/QC: 공간단위 정합 |
| `02_build_seoul_quarter_base.R` | 서울시 상권 원자료를 분기 base로 정리 | `seoul_quarter_base.parquet`, `seoul_raw_review.parquet` | Methods: 데이터와 분석단위 |
| `03_build_auxiliary_covariates.R` | 보조 공공데이터를 quarterly as-of auxiliary contract로 정리 | `aux_covariates.parquet`, pre-aggregation files | Methods: 통제변수 구축 |
| `04_build_golmok_survival_rate.R` | 서울시 상권분석서비스 신생기업 생존율 JSON을 quarterly as-of contract로 정리 | `golmok_survival_rate.parquet`, `golmok_survival_rate_qc.csv` | Methods: 안정성 구성 |
| `05_build_registered_resident_population.R` | 행정안전부 주민등록인구현황에서 상주인구와 고령 상주비중을 quarterly contract로 정리 | `registered_resident_population.parquet`, mapping/QC logs | Methods: 핵심 독립변수와 인구 통제변수 |
| `06_build_analysis_panel.R` | 기초 패널과 보조변수 및 주민등록인구 layer를 결합하고 shared transform을 완성 | `panel_merged_base.parquet`, `panel_main_pre_vitality.parquet` | Methods: 분석패널 구성 |
| `07_build_vitality_index.R` | 활력 하위차원과 종합지수 구성 | `panel_main.parquet`, `vitality_components.parquet` | Methods: 종속변수 정의 |
| `01_build_spatial_weights.R` | 공간가중행렬 구축 | `W_queen.rds`, `W_rook.rds`, `W_knn6.rds`, `W_knn8.rds` | Methods: 공간구조 정의 |
| `02_run_esda.R` | 공간 자기상관과 분포 확인 | Moran/LISA/EHSA tables and maps | Results 초반: descriptive spatial evidence |
| `01_run_twfe_main.R` | 비공간 기준선 추정과 residual Moran 계산 | TWFE tables, diagnostics, residual Moran outputs | Results: baseline FE + spatial necessity |
| `02_run_spdm_main.R` | main global spatial model 추정 | `spdm_main_models.csv`, `spdm_impacts.csv` | Results 핵심: direct/indirect/total effects |
| `03_run_spdm_channel_path.R` | 고령 상주인구 -> 고령 유동인구 -> 활력 경로 검정 | `spdm_channel_path_effects.csv`, `spdm_channel_diagnostics.csv` | Results: channel path |
| `01_run_spdm_w_robustness.R` | W 민감도 확인 | W-robustness tables and impacts | Results/Appendix: robustness summary |
| `02_run_robustness.R` | outcome, sample-window, W-Moran 민감도 점검 | `robustness_summary.csv`, `robustness_compare.png` | Appendix robustness |
| `01_make_tables_figures.R` | 본문/부록용 표·그림 패키징 | descriptive and reporting outputs | Results tables/figures assembly |

### 4.2 Optional Main-Design Sidecar

| Script | 연구 역할 | 주요 산출물 | 논문 연결 |
| --- | --- | --- | --- |
| `01_build_living_population_inflow.R` | 서울생활인구 월별 ZIP에서 외부 유입 인구를 quarterly contract로 정리 | `living_population_external_inflow.parquet`, inflow manifest/QC | Methods: 사회적 활력 구성 |
| `01_run_gtwr_main.R` | resident-only quarterly local sidecar | `gtwr_main_models_<control_set>.csv`, `gtwr_local_coefficients_<control_set>.csv`, `gtwr_local_beta_panel_<control_set>.csv` | Results 후반 또는 Appendix의 local heterogeneity evidence |

### 4.3 Supplementary and Appendix Flow

| Script | 연구 역할 | 논문 배치 |
| --- | --- | --- |
| `02_run_twfe_interaction_models.R` | COVID interaction FE | Appendix moderation |
| `01_run_spdm_interaction_models.R` | COVID interaction SDM | Appendix moderation |
| `05_run_spdm_family_comparison_sidecar.R` | family comparison | Appendix model comparison |
| `02_build_presentation_artifacts.R` | 발표용 산출물 정리 | 발표자료 및 시각 요약 |

## 5. 집필 시 주의점

1. 본문에서는 분기 단위 전환의 이유와 저주기 source의 as-of 결합 규칙을 분명히 써야 한다.
2. 분석단위는 `adm_cd-yq` 분기 패널이며, 연도·정적 source 반복값은 source precision으로 설명해야 한다.
3. GTWR는 local heterogeneity 설명용 sidecar이지 main causal estimator가 아니다.
4. 종합지수보다 하위 활력 차원의 결과를 우선 서술해야 한다.
