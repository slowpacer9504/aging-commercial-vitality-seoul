# 모델 명세서

## 0) Canonical vs Supplementary Surface

- active canonical model surface는 `02_run_esda.R -> 01_run_twfe_main.R -> 02_run_spdm_main.R -> 03_run_spdm_channel_path.R -> 01_run_spdm_w_robustness.R -> 02_run_robustness.R -> 01_make_tables_figures.R`이다.
- `01_run_gtwr_main.R`는 active design에 포함되지만 `RUN_GTWR_MAIN_SIDECAR=TRUE`일 때만 실행하는 opt-in local sidecar다.
- TWFE channel, interaction, age-mix, sector-share, selection, family-comparison, local appendix 계열은 supplementary/manual 또는 appendix sidecar로 취급한다. SPDM channel path(`03_run_spdm_channel_path.R`)는 예외적으로 canonical surface에 포함한다.

## 1) ESDA

- 목적: 공간의존 존재 여부 확인
- 입력: `panel_main.parquet`, `W_*.rds`
- 출력:
  - `global_morans_i.csv`
  - `global_morans_i_by_w.csv`
  - `global_bivariate_morans_i.csv`
  - `univariate_lisa_summary.csv`
  - `univariate_lisa_local.csv`
  - `bivariate_lisa_summary.csv`
  - `bivariate_lisa_local.csv`
  - `emerging_hotspot_summary.csv`
  - `emerging_hotspot_local.csv`
  - `distribution_map__*.png`
  - `univariate_lisa_map__*.png`
  - `bivariate_lisa_map__*.png`
  - `emerging_hotspot_map__*.png`
- 구현 원칙:
  - latest year cross-section에서 `age60_floating_share`, `age60_resident_share`, `vitality_index_base`, `vitality_sub_*` distribution map을 먼저 저장한다.
  - `Global Moran's I`, `Global Bivariate Moran's I`, `Univariate LISA`, `Bivariate LISA`, `EHSA`를 annual sequence 기준으로 재현 가능하게 실행한다.
  - Global Moran's I의 p-value는 deterministic seed를 둔 permutation 방식으로 계산한다.
  - LISA quadrant는 univariate의 경우 `z(x)`와 `W z(x)`, bivariate의 경우 `z(x)`와 `W z(y)`의 부호를 기준으로 분류한다.
  - bivariate LISA 지도는 계산된 aging 변수와 활력지표의 전체 조합을 저장한다.
  - EHSA는 `sfdep::emerging_hotspot_analysis()`의 Gi* 관례에 맞춰 queen contiguity에 self-neighbor를 포함한 `queen_include_self` weights를 사용한다.
  - `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, `vitality_index_base`가 중심 변수다.

## 3) TWFE 메인 모형

- 입력: `panel_main.parquet`, `W_queen.rds`
- 기본식: `y_it ~ age60_resident_share + controls_it | adm_cd + year`
- 표준오차: `cluster = ~ adm_cd`
- 종속변수:
  - primary: `vitality_sub_economic`, `vitality_sub_social`, `vitality_sub_temporal`, `vitality_sub_stability`
  - supplementary: `vitality_index_base`
- 출력:
  - `twfe_main_models.csv`
  - `twfe_main_models.html`
  - `twfe_main_controls_used.csv`
  - `twfe_main_diagnostics.csv`
  - `twfe_main_residual_moran.csv`
  - `twfe_main_residual_moran_by_year.csv`
  - `twfe_main_residual_moran_summary.csv`
  - `twfe_main_coefplot.png`
  - `twfe_main_coefplot_supplementary.png`
- 구현 원칙:
  - TWFE는 baseline / spatial diagnostic layer다.
  - `ln_floating_pop`은 사회적 활력 구성요소와 종합 활력지수에 포함되므로 메인 통제변수에서 제외한다.
  - residual Moran output은 필수 산출물이며, p-value는 deterministic seed를 둔 permutation 방식(`permutation_two_sided_abs`)을 기본으로 저장한다.

## 3B) TWFE Interaction Models

- appendix resident FE COVID interaction family
- 입력: `panel_main.parquet`, `twfe_main_controls_used.csv`
- 식 구조:
  - `M4`: `Y_it ~ age60_resident_share + age60_resident_share:covid_period + controls | adm_cd + year`

## 3A) TWFE Channel Models

- appendix TWFE channel family
- 입력: `panel_main.parquet`, `twfe_main_controls_used.csv`
- 출력:
  - `twfe_channel_models.csv`
  - `twfe_channel_controls_used.csv`
- 구현 원칙:
  - `age60_resident_share`와 `age60_floating_share`를 함께 두는 annual appendix contract다.
  - `x_to_m`과 `y_with_channels`를 같은 연도 패널 계약에서 분리 저장한다.
  - `y_with_channels`는 outcome별 메인 TWFE control contract를 상속하고, `x_to_m`은 `twfe_main_controls_used.csv`에서 모든 메인 outcome에 공통으로 선택된 control set을 상속한다.

## 3C) TWFE Age-Mix Experiment

- appendix TWFE age-mix family
- 입력: `panel_main.parquet`, `registered_resident_population.parquet`, `seoul_raw_integrated_wide.parquet`
- 출력:
  - `twfe_age_mix_experiment_models.csv`
  - `twfe_age_mix_experiment_controls_used.csv`
  - `twfe_age_mix_experiment_diagnostics.csv`
- 구현 원칙:
  - resident/floating domain별 `age20~age50 share`를 두고 `age60plus`는 기준범주로 생략한다.
  - controls는 `twfe_main_controls_used.csv`의 현재 메인 TWFE control contract를 상속한다.
  - resident age-mix family는 행정안전부 주민등록인구현황에서 만든 `age20_resident_share`~`age60plus_resident_share`를 사용하고, 메인 control에 포함된 `ln_resident_pop`만 same-domain total control로 유지한다.
  - floating age-mix family는 종속변수 구성요소와 겹치는 `ln_floating_pop`을 다시 추가하지 않는다.

## 5) SPDM

- 목표: 직접/간접/총효과
- 입력: `panel_main.parquet`, `W_queen.rds`
- 메인 노출변수: `age60_resident_share`
- 출력:
  - `spdm_main_models.csv`
  - `spdm_impacts.csv`
  - `spdm_controls_used.csv`
  - `spdm_main_diagnostics.csv`
- 구현 원칙:
  - main SPDM은 resident-only exposure로 TWFE 메인 사양과 정렬한다.
  - active main specification은 `y_it = rho W y_it + X_it beta + W X_it theta + adm_cd FE + year FE + e_it`의 true SDM이다.
  - `W X` 항은 `W age60_resident_share`와 outcome별 selected controls의 공간시차항을 annual panel에서 직접 생성한다.
  - 결과 해석의 중심은 direct / indirect / total effects다.
  - impact는 `S = (I - rho W)^(-1)`와 `S(beta I + theta W)` 행렬식으로 계산하고, simulation 기반 표준오차와 신뢰구간을 저장한다.
  - coefficient와 spatial parameter의 표준오차는 `splm::spml()` fitted object의 model-based asymptotic ML `vcov`에서 온다. impact SE/CI는 같은 `vcov`를 이용한 simulation 기반 추론이며, active SPDM 산출물에서는 이를 robust SE로 명명하지 않는다.
  - `ln_floating_pop`은 종속변수 구성요소이므로 main SPDM control contract에 포함하지 않는다.

## 5B) SPDM Interaction Models

- appendix resident SDM COVID interaction family
- 입력: `panel_main.parquet`, `W_queen.rds`, `spdm_main_controls_used.csv`
- 식 구조:
  - `M4`: `Y_it ~ age60_resident_share + age60_resident_share:covid_period + controls`

## 5A) SPDM Canonical Channel Path Model

- canonical SPDM path family
- 입력: `panel_main.parquet`, `W_queen.rds`
- 출력:
  - `spdm_channel_models.csv`
  - `spdm_channel_impacts.csv`
  - `spdm_channel_controls_used.csv`
  - `spdm_channel_path_effects.csv`
  - `spdm_channel_bootstrap_draws.csv`
  - `spdm_channel_diagnostics.csv`
- 구현 원칙:
  - `X = age60_resident_share`, `M = age60_floating_share`로 고정한다.
  - total-effect equation은 `Y ~ X + controls + W X + W controls`와 spatial lagged outcome을 annual Queen SDM으로 추정한다.
  - mediator equation은 `M ~ X + controls + W X + W controls`와 spatial lagged mediator를 annual Queen SDM으로 추정한다.
  - outcome equation은 `Y ~ X + M + controls + W X + W M + W controls`와 spatial lagged outcome을 annual Queen SDM으로 추정한다.
  - channel outcome은 `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, `vitality_index_base`이다.
  - `vitality_sub_social`은 유동인구 source와 직접 겹치므로 channel path 단독 outcome에서 제외한다. 단, 종합 활력지수는 네 하위차원 구성 의미를 유지하기 위해 사회적 활성도를 포함한 `vitality_index_base`를 사용하고 mediator source overlap caveat를 기록한다.
  - `c`, `a`, `b`, `c_prime`의 direct/indirect/total effects와 `a*b` product indirect effect, `c - c_prime` direct attenuation diagnostic을 저장한다.
  - 기본 `a*b` inference는 행정동 단위 wild residual bootstrap이다. bootstrap이 비활성화되었거나 유효 draw가 부족하면 `delta_independent_approx`를 fallback으로 사용하되, 결과는 완전매개 자동 판정이 아니라 mediation-oriented channel inference로 해석한다.
  - runtime default는 `RUN_SPDM_CHANNEL_BOOTSTRAP=TRUE`, `SPDM_CHANNEL_BOOTSTRAP_R=1000`, `SPDM_CHANNEL_BOOTSTRAP_CORES=4`, `SPDM_CHANNEL_IMPACT_SIM_R=1000`, `SPDM_CHANNEL_IMPACT_CORES=4`다. macOS/Linux/GCP에서는 병렬 실행, Windows에서는 순차 fallback을 사용한다.

## 5C) SPDM Age-Mix Experiment

- appendix SPDM age-mix family
- 출력:
  - `spdm_age_mix_experiment_models.csv`
  - `spdm_age_mix_experiment_impacts.csv`
  - `spdm_age_mix_experiment_controls_used.csv`
  - `spdm_age_mix_experiment_diagnostics.csv`
- 구현 원칙:
  - resident/floating domain별 `age20~age50 share`를 두고 `age60plus`는 기준범주로 둔다.
  - resident domain의 age share는 `registered_resident_population.parquet`에서, floating domain의 age share는 서울시 상권분석서비스 길단위인구에서 annualize한 값을 사용한다.
  - age-mix appendix도 `sample_min_year`, `sample_max_year`를 갖는 annual impact schema를 쓴다.

## 5D) SPDM Sector-Share Experiment

- appendix SPDM sector-share family
- 출력:
  - `spdm_sector_share_experiment_models.csv`
  - `spdm_sector_share_experiment_impacts.csv`
  - `spdm_sector_share_experiment_controls_used.csv`
  - `spdm_sector_share_experiment_diagnostics.csv`
  - `spdm_sector_share_experiment_exposure_relations.csv`
- 구현 원칙:
  - resident-only, floating-only exposure family를 contemporaneous annual contract에서 비교한다.
  - same-domain total control retention 여부를 diagnostics에 남긴다.

## 5E) SPDM W Robustness

- 목표: `queen`, `rook`, `knn6`, `knn8`에서 같은 resident-only annual SDM 계약을 재추정해 W 민감도를 점검한다.
- 표준오차 계약은 main SPDM과 같다. coefficient/spatial parameter는 model-based asymptotic ML SE, impact는 model-based `vcov` simulation SE로 보고한다.
- 출력:
  - `spdm_w_robustness_models.csv`
  - `spdm_w_robustness_impacts.csv`
  - `spdm_w_robustness_controls_used.csv`
  - `spdm_w_robustness_diagnostics.csv`

## 5G) SPDM Family Comparison Sidecar

- appendix용 manual sidecar이며 main SPDM을 대체하지 않는다. 목적은 같은 annual Queen sample과 같은 control contract에서 공간패널 family 선택 민감도를 비교하는 것이다.
- 입력:
  - `panel_main.parquet`
  - `W_queen.rds`
  - `spdm_main_diagnostics.csv`
  - `spdm_controls_used.csv`
- 비교 family:
  - `twfe_common`: main SPDM 표본으로 다시 적합한 공통표본 TWFE 기준선
  - `slx`: `W X`를 포함한 two-way FE panel, direct=`beta`, indirect=`theta`, total=`beta + theta`
  - `sar`: spatial lag panel
  - `sdm`: main SPDM과 같은 manual `W X` true SDM 구현
  - `sem`: spatial error panel, direct/indirect/total impact는 `not_applicable`
  - `sdem`: spatial error panel with manual `W X`, direct=`beta`, indirect=`theta`, total=`beta + theta`
  - `sarar_sac`: spatial lag + spatial error panel
  - `gns`: `W y`, manual `W X`, spatial error를 모두 포함한 GNS/SAC-Durbin family
- 구현 원칙:
  - main SPDM에서 성공한 `outcome x exposure` 행만 대상으로 한다.
  - `spdm_main_diagnostics.csv`와 `spdm_controls_used.csv`의 selected control contract가 불일치하면 해당 spec은 실패로 기록하고 재추정하지 않는다.
  - 모든 family는 main SPDM의 balanced annual sample과 `2019~2025` horizon을 그대로 재구성해 추정한다.
  - impact가 이론적으로 해석 가능한 `SAR`, `SDM`, `SARAR/SAC`은 가능한 경우 direct/indirect/total을 기록한다.
  - `SLX`와 `SDEM`은 endogenous `W y` feedback multiplier가 없는 `W X` 효과이므로 `SDM`의 feedback-inclusive matrix impact와 구분해 해석한다.
  - `GNS`는 spatial error를 포함하지만 평균효과는 `SDM`과 같은 `S = (I - rho W)^(-1)`, `S(beta I + theta W)` matrix impact로 기록한다.
  - `SEM`은 공간오차 모형이므로 focal coefficient와 error parameter는 비교하되 spatial spillover impact 표기는 하지 않는다.
- 출력:
  - `spdm_family_models.csv`
  - `spdm_family_comparison.csv`
  - `spatial_family_main_table.csv` (`01_make_tables_figures.R` 실행 시 reporting용 축약표)

## 5F) SPDM Selection Sidecar

- appendix selection family
- 출력:
  - `spdm_selection_tests.csv`
  - `spdm_selection_family_comparison.csv`
- 구현 원칙:
  - SEM, SAR, SDM selection diagnostics를 main queen sample과 같은 annual control contract에서 비교한다.
  - 가족별 비교표는 `sample_min_year`, `sample_max_year`를 함께 저장한다.

## 6) Robustness

- 목표: outcome-definition, sample-window, W-Moran 민감도 점검
- 출력:
  - `robustness_summary.csv`
  - `robustness_compare.png`
- 구현 원칙:
  - canonical shared panel은 동시점 annual contract만 유지한다.
  - 추가 lag/lead family는 만들지 않는다.
  - sample-window는 `full`과 `pre2025` annual window를 비교한다.

## 7) GTWR Main Optional Sidecar

- 목표: resident-only local heterogeneity 설명
- 입력: `panel_main.parquet`, `2020 기준 서울시 행정동 경계`
- 실행 조건: `RUN_GTWR_MAIN_SIDECAR=TRUE`
- 출력:
  - `gtwr_main_models_<control_set>.csv`
  - `gtwr_local_beta_panel_<control_set>.csv`
  - `gtwr_local_coefficients_<control_set>.csv`
  - `gtwr_controls_used_<control_set>.csv`
  - `gtwr_main_frozen_spec_<control_set>.csv`
  - `gtwr_latest_summary_table_<control_set>.csv`
  - `gtwr_latest_rankings_table_<control_set>.csv`
  - `gtwr_delta_summary_table_<control_set>.csv`
  - `gtwr_delta_rankings_table_<control_set>.csv`
  - `gtwr_lamda_sensitivity_<control_set>.csv`
  - `gtwr_bandwidth_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/*.rds`
  - `03_Output/04_Logs/gtwr_bandwidth_cache/<control_set>/main/*.rds` when automatic bandwidth search is explicitly enabled
  - `03_Output/04_Logs/gtwr_lamda_sensitivity_cache/<control_set>/main/*.rds`
  - `03_Output/04_Logs/gtwr_bandwidth_sensitivity_cache/<control_set>/main/*.rds`
- 구현 원칙:
  - annual sample 기준으로 실행한다.
  - `GTWR_CONTROL_SET=lean`을 기본 통제 사양으로 사용한다.
  - lean control pool은 `ln_resident_pop`, `ln_official_land_price` 두 개다.
  - `GTWR_CONTROL_SET=extended`는 lean control에 `ln_apartment_household_count`, `transit_accessibility`, `hospital_count_aux_core`, `mall_count_aux_core`를 추가한다.
  - GTWR extended에서 버스정류장 수와 지하철역 수는 별도 통제변수로 투입하지 않고 `transit_accessibility` composite로 투입한다.
  - GTWR spatiotemporal weight 기반 local condition-number를 진단으로 기록한다.
  - local condition-number는 `GWmodel::gwr.collin.diagno()`의 local_CN 계산 관례를 GTWR의 `st.dist`/`gw.weight` 기반 시공간 가중치에 맞춰 적용한다.
  - 기본 bandwidth는 `GTWR_BANDWIDTH_STRATEGY=fixed`, `GTWR_ST_BW=120`으로 통일한다.
  - `adaptive=TRUE` 기준에서 120은 각 추정점 주변 시공간 이웃 관측치 120개를 의미한다.
  - `RUN_GTWR_BANDWIDTH_SENSITIVITY=TRUE`일 때 `GTWR_BANDWIDTH_SENSITIVITY_GRID`의 기본 fixed bandwidth grid `60,90,120,150,180`을 spec별로 재추정하고, baseline `GTWR_ST_BW=120` latest-year beta 대비 상관, 절대차이, sign flip, local condition-number 민감도를 보조표로 저장한다.
  - `bw.gtwr()` full-panel/anchor-year 탐색은 명시적으로 선택한 민감도 또는 진단 실행에서만 사용한다.
  - main summary와 local coefficient table은 latest-year local beta를 `estimate_type=latest`로 저장한다.
  - latest-year coefficient coverage를 `latest_missing_n`, `latest_coverage_share`로 기록한다.
  - earliest-to-latest 변화량은 `gtwr_delta_*` 보조 reporting table로만 파생한다.
  - outcome-exposure spec별 cache를 먼저 저장하고, final raw GTWR bundle과 control trace는 전체 cache를 집계해 생성한다.
  - `GTWR_PARALLEL_SPECS`로 병렬 worker 수를 제한하며, `GTWR_RESUME_SPECS=TRUE`일 때 완료 spec cache를 재사용한다.
  - `RUN_GTWR_LAMDA_SENSITIVITY=TRUE`일 때 `GTWR_LAMDA_SENSITIVITY_GRID`의 lamda별 GTWR를 재추정하고, baseline latest-year local beta 대비 상관, 절대차이, sign flip, local condition-number 민감도를 보조표로 저장한다.
  - reporting용 downstream delta table은 horizon-aligned raw output이 있을 때만 파생된다.

## 7A) GTWR Floating-Only Appendix

- opt-in annual GTWR appendix sidecar
- 실행 조건: `RUN_GTWR_FLOATING_SIDECAR=TRUE`
- 출력:
  - `gtwr_floating_models_<control_set>.csv`
  - `gtwr_floating_local_beta_panel_<control_set>.csv`
  - `gtwr_floating_local_coefficients_<control_set>.csv`
  - `gtwr_floating_controls_used_<control_set>.csv`
  - `gtwr_floating_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/floating/*.rds`
  - `03_Output/04_Logs/gtwr_bandwidth_cache/<control_set>/floating/*.rds` when automatic bandwidth search is explicitly enabled
- 구현 원칙:
  - main outcomes x `age60_floating_share` spec을 `GWmodel::gtwr()`로 실제 추정한다.
  - control pool은 main GTWR와 같은 `GTWR_CONTROL_SET` 계약을 따른다.
  - 실행 플래그가 꺼져 있으면 raw output 부재를 failure로 보지 않는다.

## 7B) GTWR Age-Band Appendix

- opt-in annual GTWR appendix sidecar
- 실행 조건: `RUN_GTWR_AGE_BAND_SIDECAR=TRUE`
- 출력:
  - `gtwr_age_band_models_<control_set>.csv`
  - `gtwr_age_band_local_beta_panel_<control_set>.csv`
  - `gtwr_age_band_local_coefficients_<control_set>.csv`
  - `gtwr_age_band_controls_used_<control_set>.csv`
  - `gtwr_age_band_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/age_band/*.rds`
  - `03_Output/04_Logs/gtwr_bandwidth_cache/<control_set>/age_band/*.rds` when automatic bandwidth search is explicitly enabled
- 구현 원칙:
  - resident/floating domain별 age20~age50 exposure family와 main outcomes를 `GWmodel::gtwr()`로 실제 추정한다.
  - output에는 `domain`, `age_band`, `same_domain_total_control`을 함께 저장한다.
  - control pool은 main GTWR와 같은 `GTWR_CONTROL_SET` 계약을 따른다.
  - downstream delta summary/rankings는 raw appendix output이 있을 때만 파생된다.

## 7C) GTWR Sector-Share Appendix

- opt-in annual GTWR appendix sidecar
- 실행 조건: `RUN_GTWR_SECTOR_SHARE_SIDECAR=TRUE`
- 출력:
  - `gtwr_sector_share_models_<control_set>.csv`
  - `gtwr_sector_share_local_beta_panel_<control_set>.csv`
  - `gtwr_sector_share_local_coefficients_<control_set>.csv`
  - `gtwr_sector_share_controls_used_<control_set>.csv`
  - `gtwr_sector_share_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/sector_share/*.rds`
  - `03_Output/04_Logs/gtwr_bandwidth_cache/<control_set>/sector_share/*.rds` when automatic bandwidth search is explicitly enabled
- 구현 원칙:
  - sector-share outcomes에서 resident-only/floating-only exposure family를 `GWmodel::gtwr()`로 실제 추정한다.
  - output에는 `exposure_family`, `same_domain_total_control`을 함께 저장한다.
  - control pool은 main GTWR와 같은 `GTWR_CONTROL_SET` 계약을 따른다.

## 7D) GWR Delta Appendix

- manual annual appendix sidecar
- 출력:
  - `gwr_delta_main_models.csv`
  - `gwr_delta_local_coefficients.csv`
  - `gwr_delta_floating_models.csv`
  - `gwr_delta_floating_local_coefficients.csv`
  - `gwr_delta_controls_used.csv`
- 구현 원칙:
  - delta window는 `2019-2021` 대 `2023-2025`의 `3Y vs 3Y`로 고정한다.
  - raw output schema는 `early_*_year`, `late_*_year`, `window_n_year`를 쓴다.

## 7X) GTWR Experiment Appendix

- manual annual appendix sidecar
- 출력:
  - `gtwr_experiment_main_models_<control_set>.csv`
  - `gtwr_experiment_local_beta_panel_<control_set>.csv`
  - `gtwr_experiment_local_coefficients_<control_set>.csv`
  - `gtwr_experiment_controls_used_<control_set>.csv`
  - `gtwr_experiment_controls_used_state_<control_set>.csv`
  - `gtwr_experiment_registry_<control_set>.csv`
  - `gtwr_experiment_ranked_candidates_<control_set>.csv`
- 구현 원칙:
  - bandwidth/control strategy grid를 annual local contract에서 정리하는 manual appendix다.
  - canonical pipeline은 이 appendix를 자동 실행하지 않는다.

## 8) Reporting and Presentation

- `01_make_tables_figures.R`
  - always-on descriptive/reporting outputs plus optional appendix tables
  - `descriptive_statistics.csv`는 변수별 확장 기술통계표로 작성한다. aging exposure, vitality outcome, robustness composite, vitality component, main control을 대상으로 유효 관측치, 결측, 평균, 표준편차, 최솟값, p25, 중앙값, p75, 최댓값, 유효 연도 범위, 행정동 수를 보고한다.
  - `main_variable_correlation_matrix.csv`와 `main_variable_correlation_pairs.csv`는 SPDM/GTWR 등 본분석 변수의 Pearson 상관을 `panel_main` 전체 `adm_cd-year` 관측치 기준으로 계산한다. 포함 범위는 main exposure, channel mediator, supporting aging exposure, primary/supplementary outcome, TWFE/SPDM/GTWR control pool이다.
  - GTWR reporting은 latest summary/rankings를 main surface로 쓰고 delta summary/rankings는 appendix diagnostic으로만 쓴다.
- `02_Code/05_reporting/02_build_presentation_artifacts.R`
  - presentation-only sidecar that derives slide-ready artifacts from canonical outputs
  - publishes `presentation_spdm_channel_path_diagram.csv` and `presentation_spdm_channel_path_diagram.png` as a slide-left visual for the canonical `age60_resident_share -> age60_floating_share -> commercial vitality` channel path
- `02_Code/05_reporting/03_build_gtwr_level_artifacts.R`
  - optional annual GTWR level reporting sidecar
  - reads existing `gtwr_local_beta_panel_<control_set>.csv` and related GTWR tables without rerunning GTWR
  - builds artifacts for both available `extended` and `lean` GTWR source families by default; `GTWR_LEVEL_CONTROL_SET=lean` or `extended` can force one family
  - writes reporting artifacts with strict `lean` or `extended` suffixes only; legacy mode tags are not accepted
  - publishes early/latest/delta triptych maps, annual local-beta trajectories, living-area/gu regional summaries, sign-transition tables, representative district trajectories, and earliest-to-latest delta diagnostics

reporting은 source input이 있는 optional appendix artifact만 선택적으로 붙일 수 있으며, absence 자체를 failure로 해석하지 않는다.
