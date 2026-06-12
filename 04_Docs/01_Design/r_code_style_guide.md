# R 코드 스타일 가이드

이 문서는 현재 active quarterly workflow를 구현하기 위한 프로젝트 전용 R 코드 작성 기준이다. 목적은 세 가지다.

- 문서와 코드의 계약을 맞춘다.
- canonical workflow와 optional/manual surface를 분리한다.
- 재현성과 검증 가능성을 유지한다.

## 1. 설계 정렬 원칙

아래 원칙은 코드에서 흔들리면 안 된다.

1. 공간 단위는 `2020` 기준 서울시 행정동(`adm_cd`)이다.
2. active canonical panel 구축 범위는 `2019Q1~2025Q4`이고, active 분석 표본은 `2019Q4~2025Q4`다.
3. active shared panel의 시간 키는 `year`, `quarter`, `yq`, `quarter_index`이며 유일키는 `adm_cd-yq`다.
4. main exposure는 `lag4_age60_resident_share`다.
5. canonical timing contract는 4분기 시차 노출·통제와 2분기 시차 channel mediator다.
6. 기본 W는 `Queen`이고, `Rook`, `kNN6`, `kNN8`은 robustness다.
7. active method stack은 `ESDA -> TWFE -> SPDM -> GTWR(optional)`이다.
8. TWFE는 baseline / spatial diagnostic layer다.
9. SPDM은 main global model이다.
10. GTWR는 resident-only optional local sidecar다.
11. 분기 raw는 active shared panel의 기본 시간단위로 직접 발행한다. 연도·정적 source는 명시적 as-of 규칙으로 `adm_cd-yq`에 결합한다.

## 2. 프로젝트 구조 해석

디렉터리 구조는 active와 optional surface가 바로 구분되도록 아래처럼 읽는다.

- `00_setup`: active config and package loading
- `01_preprocess`: quarterly panel preprocessing
- `02_esda`: active ESDA and spatial weights
- `03_models`: canonical TWFE and SPDM models
- `04_robustness`: SPDM W robustness and supplementary robustness
- `05_reporting`: tables, figures, presentation, and GTWR artifact builders
- `06_qc`: active QC plus manual audit helpers
- `80_optional`: manual direct-run preprocessing, TWFE, SPDM, and GTWR sidecars
- `R`: shared utilities, including GTWR helper logic used by optional sidecars
- `90_templates`: shared implementation pattern

## 3. 파일명과 스크립트 역할

active canonical surface는 아래 순서를 따른다.

- `01_build_adm_region_lookup.R`
- `02_build_seoul_quarter_base.R`
- `03_build_auxiliary_covariates.R`
- `04_build_golmok_survival_rate.R`
- `05_build_registered_resident_population.R`
- `06_build_analysis_panel.R`
- `07_build_vitality_index.R`
- `01_build_spatial_weights.R`
- `02_run_esda.R`
- `01_run_twfe_main.R`
- `02_run_spdm_main.R`
- `01_run_spdm_w_robustness.R`
- `02_run_robustness.R`
- `01_make_tables_figures.R`
- `01_validate_method_dataset_alignment.R`
- `run_all.R`

optional/manual surface는 `80_optional/**`와 `05_reporting/02_*`, `05_reporting/03_*`,
`06_qc/02_*`, `06_qc/03_*`처럼 폴더와 파일명에서 active canonical surface와 분리한다.
`80_optional/**` 스크립트는 `run_all.R`에서 제외되며, 파일을 직접 실행하면 별도 `RUN_*` 실행 플래그 없이 실제 작업을 수행한다.
SPDM channel path는 `02_Code/80_optional/spdm/07_run_spdm_channel_path.R`에 두는 optional/manual sidecar다.

## 4. 파일 헤더 규칙

모든 스크립트는 아래 메타 정보를 상단에 둔다.

- `Script`
- `Project`
- `Purpose`
- `Author`
- `Created`
- `Type`
- `Inputs`
- `Outputs`
- `DependsOn`

optional/manual script라면 header나 early comment에 그 상태를 분명히 적는다.

## 5. 입력-처리-출력 구조

스크립트는 아래 흐름을 명시적으로 유지한다.

1. setup
2. input validation
3. helper definitions
4. main transformation / model fit
5. output write
6. log append

중간 산출물을 읽을 때는 canonical path registry를 우선 사용한다. 스크립트 내부에서 파일명을 새로 발명하지 않는다.

## 6. 변수명 규칙

- 식별자: `adm_cd`, `year`
- 로그변환: `ln_`
- 표준화: `_z`
- 윈저라이징: `_w`
- 공간시차: `w_`
- 종합지수: `vitality_index_*`

활력지수 계산에서 `_z`는 active 분석 표본인 `2019Q4~2025Q4 adm_cd-yq`의 평균과 표준편차를 기준으로 하는 pooled z-score를 기본값으로 한다. 분기별 cross-section 표준화가 필요한 보조 분석은 active variable name과 별도 suffix로 분리해야 한다.

active shared panel에는 `year`, `quarter`, `yq`, `quarter_index`를 남긴다. legacy shift/lead suffix와 raw `quarter_code_raw`는 preprocessing 내부 local object에서만 사용하고, quarterly publication 전에 제거한다.

## 7. 주석 기준

주석은 문법 설명이 아니라 계약 설명이어야 한다.

반드시 설명해야 하는 지점:

- canonical source selection
- quarterly publication / as-of rule
- weighted vs unweighted quarterly aggregation choice
- control exclusion rules
- complete-case sample determination
- spatial weights construction and W choice
- TWFE residual Moran diagnostics
- SPDM impacts calculation
- optional GTWR gating

피해야 하는 주석:

- 코드 한 줄을 그대로 번역한 설명
- 현재 설계와 충돌하는 분기 canonical 서술
- GTWR를 global causal model처럼 과장하는 설명

## 8. 전처리 작성 원칙

- `adm_cd-yq` 유일키를 가장 먼저 강제한다.
- additive flow와 level/share를 같은 방식으로 집계하지 않는다.
- annual/static auxiliary는 source precision을 유지한 뒤 quarter-end as-of 규칙으로 결합한다.
- `panel_merged_base.parquet`는 provenance checkpoint로 유지한다.
- `panel_main_pre_vitality.parquet`에는 shared quarterly transform과 동시점 변수만 남긴다.

## 9. 모델 작성 원칙

### TWFE

- baseline model로 취급한다.
- FE 구조는 `| adm_cd + yq`로 고정한다.
- residual Moran output을 필수 산출물로 남긴다.
- outcome과 중복되는 control은 outcome별로 제외한다.

### SPDM

- resident-only main exposure를 기본으로 사용한다.
- true SDM 계약은 `W y`, `X`, `W X`를 모두 포함한다.
- `splm::spml()` 호출에서 Durbin placeholder에 의존하지 말고, `W lag4_age60_resident_share`와 `W controls`를 직접 생성한다.
- coefficient table보다 direct / indirect / total effect 표를 중심으로 저장한다.
- direct / indirect / total effect는 SDM impact matrix로 계산한다.
- alternative W는 별도 robustness family에서 처리한다.

### GTWR

- `80_optional/gtwr` 아래 GTWR 스크립트도 같은 manual direct-run 계약을 따른다.
- quarterly resident-only local heterogeneity analysis에 한정한다.
- `GTWR_CONTROL_SET=lean`을 기본으로 사용하고, extended는 명시적으로 선택할 때만 사용한다.
- lean control은 `lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted` 두 개로 고정한다.
- extended control은 lean control에 `lag4_transit_accessibility`와 `lag4_ln_workplace_worker_pop`을 추가한다.
- `transit_accessibility`는 `bus_stop_count_aux`와 `subway_station_count_aux`의 pooled z-score 평균으로 만들고, 두 원천 count는 모델 통제변수로 직접 투입하지 않는다.
- GTWR spatiotemporal weight 기반 local condition-number를 진단으로 남긴다.
- bandwidth는 main GTWR에서 fixed `GTWR_ST_BW=480`으로 통일한다. `bw.gtwr()` 탐색은 `07_select_gtwr_bandwidth.R`, 고정 grid `240,360,480,600,720` 민감도는 `08_run_gtwr_bandwidth_sensitivity.R`, lamda grid 민감도는 `09_run_gtwr_lamda_sensitivity.R`에서만 실행한다.
- main output의 `estimate`는 latest-quarter local beta이며, delta는 별도 보조 reporting table에서만 계산한다.
- 장시간 실행은 outcome-exposure spec cache를 통해 재개 가능해야 하며, `GTWR_PARALLEL_SPECS`로 worker 수를 제한한다.

## 10. 로그와 QC

- input missing은 즉시 명확한 에러로 중단한다.
- optional source missing은 source-dependent artifact를 비우거나 건너뛰고, active run 전체를 실패시키지 않는다.
- QC는 active quarterly contract 기준으로만 실패를 판정해야 한다. optional/sidecar는 required test plan에서 제외한다.
## 11. 문서 변경 규칙

설계 변경이 생기면 최소한 아래 순서를 같이 본다.

1. `research_plan.md`
2. `research_procedure.md`
3. `00_spec_index.md`
4. 관련 codebook docs
5. `config.R`
6. `run_all.R`
7. QC / reporting

문서 선행 단계에서는 문서가 먼저 quarterly final state를 선언할 수 있다. 다만 다음 코드 단계에서 config, preprocess, model, QC를 같은 계약으로 즉시 따라오게 해야 한다.
