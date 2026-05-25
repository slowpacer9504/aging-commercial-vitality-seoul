# 모델 명세서

## 0) Canonical vs Supplementary Surface

- active canonical model surface는 `02_run_esda.R -> 01_run_twfe_main.R -> 02_run_spdm_main.R -> 01_run_spdm_w_robustness.R -> 02_run_robustness.R -> 01_make_tables_figures.R`이다.
- 모든 active canonical model과 reporting은 `2019Q4~2025Q4` 분석 표본을 사용한다. `2019Q1~2019Q3`는 panel 구축 및 rolling/lag warm-up 구간으로만 유지한다.
- `80_optional/**`의 TWFE, SPDM, GTWR, optional preprocessing scripts는 default run과 required test plan에서 제외되는 manual direct-run surface다. 파일을 직접 실행하면 별도 `RUN_*` 실행 플래그 없이 실제 작업을 수행한다.
- TWFE channel, interaction, age-mix, sector-share, selection, family-comparison, SPDM channel path, GTWR local appendix 계열은 supplementary/manual 또는 appendix sidecar로 취급한다. SPDM channel path는 `02_Code/80_optional/spdm/07_run_spdm_channel_path.R`를 직접 실행한다.

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
  - latest quarter cross-section에서 `age60_floating_share`, `age60_resident_share`, `vitality_index_base`, `vitality_sub_*` distribution map을 먼저 저장한다.
  - `Global Moran's I`, `Global Bivariate Moran's I`, `Univariate LISA`, `Bivariate LISA`, `EHSA`를 quarterly sequence 기준으로 재현 가능하게 실행한다.
  - Global Moran's I의 p-value는 deterministic seed를 둔 permutation 방식으로 계산한다.
  - LISA quadrant는 univariate의 경우 `z(x)`와 `W z(x)`, bivariate의 경우 `z(x)`와 `W z(y)`의 부호를 기준으로 분류한다.
  - bivariate LISA 지도는 계산된 aging 변수와 활력지표의 전체 조합을 저장한다.
  - EHSA는 `sfdep::emerging_hotspot_analysis()`의 Gi* 관례에 맞춰 queen contiguity에 self-neighbor를 포함한 `queen_include_self` weights를 사용한다.
  - `age60_resident_share`, `age60_floating_share`, `vitality_sub_*`, `vitality_index_base`가 중심 변수다.

## 3) TWFE 메인 모형

- 입력: `panel_main.parquet`, `W_queen.rds`
- 기본식: `y_it ~ lag4_age60_resident_share + lag4_controls_it | adm_cd + yq`
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
  - `twfe_main_residual_moran_by_yq.csv`
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
- 기간 플래그: `covid_period = 1`은 `2020Q1~2022Q2` 분기 표본이다.
- 식 구조:
  - `M4`: `Y_it ~ lag4_age60_resident_share + lag4_age60_resident_share:covid_period + controls | adm_cd + yq`

## 3A) TWFE Channel Models

- appendix TWFE channel family
- 입력: `panel_main.parquet`, `twfe_main_controls_used.csv`
- 출력:
  - `twfe_channel_models.csv`
  - `twfe_channel_controls_used.csv`
- 구현 원칙:
  - `lag4_age60_resident_share`와 `lag2_age60_floating_share`를 함께 두는 quarterly appendix contract다.
  - `x_to_m`과 `y_with_channels`를 같은 분기 패널 계약에서 분리 저장한다.
  - `y_with_channels`는 outcome별 메인 TWFE control contract를 상속하고, `x_to_m`은 `twfe_main_controls_used.csv`에서 모든 메인 outcome에 공통으로 선택된 control set을 상속한다.

## 3C) TWFE Age-Mix Experiment

- appendix TWFE age-mix family
- 실행 조건: `80_optional/twfe/03_run_twfe_age_mix_experiment.R` 직접 실행
- 입력: `panel_main.parquet`, `registered_resident_population.parquet`
- 출력:
  - `twfe_age_mix_experiment_models.csv`
  - `twfe_age_mix_experiment_controls_used.csv`
  - `twfe_age_mix_experiment_diagnostics.csv`
- 구현 원칙:
  - 행정안전부 주민등록인구현황에서 만든 분기 평균 연령대별 주민등록인구를 청년(20~30대), 중년(40~50대), 노년(60세 이상)으로 묶고 `log1p` 변환한 `ln_young_resident_pop`, `ln_middle_resident_pop`, `ln_old_resident_pop`을 모두 노출로 둔다.
  - 구성비 모형이 아니므로 노년층은 기준범주로 생략하지 않는다.
  - controls는 `twfe_main_controls_used.csv`의 현재 메인 TWFE control contract를 상속하고, lagged resident scale control인 `lag4_ln_resident_pop`도 유지한다.

## 5) SPDM

- 목표: 직접/간접/총효과
- 입력: `panel_main.parquet`, `W_queen.rds`
- 메인 노출변수: `lag4_age60_resident_share`
- 출력:
  - `spdm_main_models.csv`
  - `spdm_impacts.csv`
  - `spdm_controls_used.csv`
  - `spdm_main_diagnostics.csv`
- 구현 원칙:
  - main SPDM은 resident-only exposure로 TWFE 메인 사양과 정렬한다.
  - active main specification은 `y_it = rho W y_it + X_it beta + W X_it theta + adm_cd FE + yq FE + e_it`의 true SDM이다.
  - `W X` 항은 `W lag4_age60_resident_share`와 outcome별 selected controls의 공간시차항을 quarterly panel에서 직접 생성한다.
  - 결과 해석의 중심은 direct / indirect / total effects다.
  - impact는 `S = (I - rho W)^(-1)`와 `S(beta I + theta W)` 행렬식으로 계산하고, simulation 기반 표준오차와 신뢰구간을 저장한다.
  - coefficient와 spatial parameter의 표준오차는 `splm::spml()` fitted object의 model-based asymptotic ML `vcov`에서 온다. impact SE/CI는 같은 `vcov`를 이용한 simulation 기반 추론이며, active SPDM 산출물에서는 이를 robust SE로 명명하지 않는다.
  - `ln_floating_pop`은 종속변수 구성요소이므로 main SPDM control contract에 포함하지 않는다.

## 5B) SPDM Interaction Models

- appendix resident SDM COVID interaction family
- 입력: `panel_main.parquet`, `W_queen.rds`, `spdm_main_controls_used.csv`
- 기간 플래그: `covid_period = 1`은 `2020Q1~2022Q2` 분기 표본이다.
- 식 구조:
  - `M4`: `Y_it ~ lag4_age60_resident_share + lag4_age60_resident_share:covid_period + controls`

## 5A) SPDM Optional Channel Path Sidecar

- optional/manual SPDM path family
- 실행 조건: `02_Code/80_optional/spdm/07_run_spdm_channel_path.R` 직접 실행
- 입력: `panel_main.parquet`, `W_queen.rds`
- 출력:
  - `spdm_channel_models.csv`
  - `spdm_channel_impacts.csv`
  - `spdm_channel_controls_used.csv`
  - `spdm_channel_path_effects.csv`
  - `spdm_channel_bootstrap_draws.csv`
  - `spdm_channel_diagnostics.csv`
- 구현 원칙:
  - `X = lag4_age60_resident_share`, `M = lag2_age60_floating_share`로 고정한다.
  - `lag2_age60_floating_share`는 2018 floating source가 없으므로 2019Q1~2019Q2가 warm-up 결측이고, active channel path complete-case sample은 `2019Q4` 이후 분석 표본에서 형성된다.
  - total-effect equation은 `Y ~ X + controls + W X + W controls`와 spatial lagged outcome을 quarterly Queen SDM으로 추정한다.
  - mediator equation은 `M ~ X + controls + W X + W controls`와 spatial lagged mediator를 quarterly Queen SDM으로 추정한다.
  - outcome equation은 `Y ~ X + M + controls + W X + W M + W controls`와 spatial lagged outcome을 quarterly Queen SDM으로 추정한다.
  - channel outcome은 `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, `vitality_index_base`이다.
  - `vitality_sub_social`은 유동인구 source와 직접 겹치므로 channel path 단독 outcome에서 제외한다. 단, 종합 활력지수는 네 하위차원 구성 의미를 유지하기 위해 사회적 활성도를 포함한 `vitality_index_base`를 사용하고 mediator source overlap caveat를 기록한다.
  - `c`, `a`, `b`, `c_prime`의 direct/indirect/total effects와 `a*b` product indirect effect, `c - c_prime` direct attenuation diagnostic을 저장한다.
  - 기본 `a*b` inference는 행정동 단위 wild residual bootstrap이다. bootstrap이 비활성화되었거나 유효 draw가 부족하면 `delta_independent_approx`를 fallback으로 사용하되, 결과는 완전매개 자동 판정이 아니라 mediation-oriented channel inference로 해석한다.
  - runtime default는 `RUN_SPDM_CHANNEL_BOOTSTRAP=TRUE`, `SPDM_CHANNEL_BOOTSTRAP_R=1000`, `SPDM_CHANNEL_BOOTSTRAP_CORES=4`, `SPDM_CHANNEL_IMPACT_SIM_R=1000`, `SPDM_CHANNEL_IMPACT_CORES=4`다. macOS/Linux/GCP에서는 병렬 실행, Windows에서는 순차 fallback을 사용한다.

## 5C) SPDM Age-Mix Experiment

- appendix SPDM age-mix family
- 실행 조건: `80_optional/spdm/02_run_spdm_age_mix_experiment.R` 직접 실행
- 출력:
  - `spdm_age_mix_experiment_models.csv`
  - `spdm_age_mix_experiment_impacts.csv`
  - `spdm_age_mix_experiment_controls_used.csv`
  - `spdm_age_mix_experiment_diagnostics.csv`
- 구현 원칙:
  - 행정안전부 주민등록인구현황에서 만든 분기 평균 연령대별 주민등록인구를 청년(20~30대), 중년(40~50대), 노년(60세 이상)으로 묶고 `log1p` 변환한 `ln_young_resident_pop`, `ln_middle_resident_pop`, `ln_old_resident_pop`을 모두 노출로 둔다.
  - 구성비 모형이 아니므로 노년층은 기준범주로 생략하지 않는다.
  - controls는 current SPDM main control candidate를 상속하고, lagged resident scale control인 `lag4_ln_resident_pop`도 유지한다.
  - age-mix appendix도 `sample_min_yq`, `sample_max_yq`를 갖는 quarterly impact schema를 쓴다.

## 5D) SPDM Sector-Share Experiment

- appendix SPDM sector-share family
- 실행 조건: `80_optional/spdm/03_run_spdm_sector_share_experiment.R` 직접 실행
- 출력:
  - `spdm_sector_share_experiment_models.csv`
  - `spdm_sector_share_experiment_impacts.csv`
  - `spdm_sector_share_experiment_controls_used.csv`
  - `spdm_sector_share_experiment_diagnostics.csv`
  - `spdm_sector_share_experiment_exposure_relations.csv`
- 구현 원칙:
  - resident-only, floating-only exposure family를 contemporaneous quarterly contract에서 비교한다.
  - same-domain total control retention 여부를 diagnostics에 남긴다.

## 5E) SPDM W Robustness

- 목표: `queen`, `rook`, `knn6`, `knn8`에서 같은 resident-only quarterly SDM 계약을 재추정해 W 민감도를 점검한다.
- 표준오차 계약은 main SPDM과 같다. coefficient/spatial parameter는 model-based asymptotic ML SE, impact는 model-based `vcov` simulation SE로 보고한다.
- 출력:
  - `spdm_w_robustness_models.csv`
  - `spdm_w_robustness_impacts.csv`
  - `spdm_w_robustness_controls_used.csv`
  - `spdm_w_robustness_diagnostics.csv`

## 5G) SPDM Family Comparison Sidecar

- appendix용 manual sidecar이며 main SPDM을 대체하지 않는다. 목적은 같은 quarterly Queen sample과 같은 control contract에서 공간패널 family 선택 민감도를 비교하는 것이다.
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
  - 모든 family는 main SPDM의 balanced quarterly sample과 `2019Q4~2025Q4` active analysis horizon을 그대로 재구성해 추정한다.
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
  - SEM, SAR, SDM selection diagnostics를 main queen sample과 같은 quarterly control contract에서 비교한다.
  - 가족별 비교표는 `sample_min_yq`, `sample_max_yq`를 함께 저장한다.

## 6) Robustness

- 목표: outcome-definition, sample-window, W-Moran 민감도 점검
- 출력:
  - `robustness_summary.csv`
  - `robustness_compare.png`
- 구현 원칙:
  - canonical shared panel은 동시점 source 변수와 등록된 model lag 변수만 유지한다.
  - 미등록 lag/lead family는 만들지 않는다.
  - sample-window는 `full`(`2019Q4~2025Q4`)과 `pre2025` quarterly window를 비교한다.

## 7) GTWR Main Optional Sidecar

- 목표: resident-only local heterogeneity 설명
- 입력: `panel_main.parquet`, `2020 기준 서울시 행정동 경계`
- 실행 조건: `80_optional/gtwr/01_run_gtwr_main.R` 직접 실행
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
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/main/*.rds`
- 구현 원칙:
  - quarterly sample 기준으로 실행한다.
  - `GTWR_CONTROL_SET=lean`을 기본 통제 사양으로 사용한다.
  - lean control pool은 `lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted` 두 개다.
  - `GTWR_CONTROL_SET=extended`는 lean control에 `lag4_transit_accessibility`와 `lag4_ln_workplace_worker_pop`을 추가한다.
  - GTWR extended에서 버스정류장 수와 지하철역 수는 별도 통제변수로 투입하지 않고 `lag4_transit_accessibility` composite로 투입하며, 직장인구 규모는 `lag4_ln_workplace_worker_pop`으로 통제한다.
  - GTWR spatiotemporal weight 기반 local condition-number를 진단으로 기록한다.
  - local condition-number는 `GWmodel::gwr.collin.diagno()`의 local_CN 계산 관례를 GTWR의 `st.dist`/`gw.weight` 기반 시공간 가중치에 맞춰 적용한다.
  - 기본 bandwidth는 fixed `GTWR_ST_BW=480`으로 통일한다.
  - `adaptive=TRUE` 기준에서 480은 각 추정점 주변 시공간 이웃 관측치 480개를 의미한다.
  - `01_run_gtwr_main.R`는 `GTWR_BANDWIDTH_STRATEGY`가 fixed가 아니어도 `bw.gtwr()`를 실행하지 않는다.
  - `bw.gtwr()` full-panel/anchor-quarter 탐색, fixed bandwidth grid 민감도, lamda grid 민감도는 각각 `07_select_gtwr_bandwidth.R`, `08_run_gtwr_bandwidth_sensitivity.R`, `09_run_gtwr_lamda_sensitivity.R`에서만 실행한다.
  - main summary와 local coefficient table은 latest-quarter local beta를 `estimate_type=latest`로 저장한다.
  - latest-quarter coefficient coverage를 `latest_missing_n`, `latest_coverage_share`로 기록한다.
  - earliest-to-latest 변화량은 `gtwr_delta_*` 보조 reporting table로만 파생한다.
  - outcome-exposure spec별 cache를 먼저 저장하고, final raw GTWR bundle과 control trace는 전체 cache를 집계해 생성한다.
  - `GTWR_PARALLEL_SPECS`로 병렬 worker 수를 제한하며, `GTWR_RESUME_SPECS=TRUE`일 때 완료 spec cache를 재사용한다.
  - reporting용 downstream delta table은 horizon-aligned raw output이 있을 때만 파생된다.

## 7A) GTWR Floating-Only Appendix

- manual quarterly GTWR appendix sidecar
- 실행 조건: `80_optional/gtwr/02_run_gtwr_floating_only.R` 직접 실행
- 출력:
  - `gtwr_floating_models_<control_set>.csv`
  - `gtwr_floating_local_beta_panel_<control_set>.csv`
  - `gtwr_floating_local_coefficients_<control_set>.csv`
  - `gtwr_floating_controls_used_<control_set>.csv`
  - `gtwr_floating_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/floating/*.rds`
- 구현 원칙:
  - main outcomes x `age60_floating_share` spec을 `GWmodel::gtwr()`로 실제 추정한다.
  - control pool은 main GTWR와 같은 `GTWR_CONTROL_SET` 계약을 따른다.
  - default `run_all.R`과 required test plan에서는 제외되므로 raw output 부재를 failure로 보지 않는다.

## 7B) GTWR Age-Band Appendix

- manual quarterly GTWR appendix sidecar
- 실행 조건: `80_optional/gtwr/03_run_gtwr_age_band.R` 직접 실행
- 출력:
  - `gtwr_age_band_models_<control_set>.csv`
  - `gtwr_age_band_local_beta_panel_<control_set>.csv`
  - `gtwr_age_band_local_coefficients_<control_set>.csv`
  - `gtwr_age_band_controls_used_<control_set>.csv`
  - `gtwr_age_band_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/age_band/*.rds`
- 구현 원칙:
  - resident/floating domain별 age20~age50 exposure family와 main outcomes를 `GWmodel::gtwr()`로 실제 추정한다.
  - output에는 `domain`, `age_band`, `same_domain_total_control`을 함께 저장한다.
  - control pool은 main GTWR와 같은 `GTWR_CONTROL_SET` 계약을 따른다.
  - downstream delta summary/rankings는 raw appendix output이 있을 때만 파생된다.

## 7C) GTWR Sector-Share Appendix

- manual quarterly GTWR appendix sidecar
- 실행 조건: `80_optional/gtwr/04_run_gtwr_sector_share.R` 직접 실행
- 출력:
  - `gtwr_sector_share_models_<control_set>.csv`
  - `gtwr_sector_share_local_beta_panel_<control_set>.csv`
  - `gtwr_sector_share_local_coefficients_<control_set>.csv`
  - `gtwr_sector_share_controls_used_<control_set>.csv`
  - `gtwr_sector_share_frozen_spec_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_spec_cache/<control_set>/sector_share/*.rds`
- 구현 원칙:
  - sector-share outcomes에서 resident-only/floating-only exposure family를 `GWmodel::gtwr()`로 실제 추정한다.
  - output에는 `exposure_family`, `same_domain_total_control`을 함께 저장한다.
  - control pool은 main GTWR와 같은 `GTWR_CONTROL_SET` 계약을 따른다.

## 7D) GWR Delta Appendix

- manual quarterly appendix sidecar
- 출력:
  - `gwr_delta_main_models.csv`
  - `gwr_delta_local_coefficients.csv`
  - `gwr_delta_floating_models.csv`
  - `gwr_delta_floating_local_coefficients.csv`
  - `gwr_delta_controls_used.csv`
- 구현 원칙:
  - delta window는 `2019-2021` 대 `2023-2025`의 `3Y vs 3Y`로 고정한다.
  - raw output schema는 `early_*_year`, `late_*_year`, `window_n_year`를 쓴다.

## 7E) GTWR Bandwidth Selection Diagnostic

- manual quarterly diagnostic
- 실행 조건: `GTWR_BANDWIDTH_STRATEGY=full_panel_bw_gtwr` 또는 `anchor_quarter_bw_gtwr`
- 출력:
  - `gtwr_bandwidth_selection_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_bandwidth_cache/<control_set>/main/*.rds`
- 구현 원칙:
  - resident-only main GTWR spec의 `bw.gtwr()` 탐색 결과만 저장한다.
  - 선택 결과는 main GTWR에 자동 적용하지 않고, 필요한 경우 `GTWR_ST_BW`로 명시 적용한다.

## 7F) GTWR Bandwidth Sensitivity Diagnostic

- manual quarterly diagnostic
- 실행 조건: `80_optional/gtwr/08_run_gtwr_bandwidth_sensitivity.R` 직접 실행
- 출력:
  - `gtwr_bandwidth_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_bandwidth_sensitivity_cache/<control_set>/main/*.rds`
- 구현 원칙:
  - baseline `gtwr_main_models_<control_set>.csv`와 `gtwr_local_coefficients_<control_set>.csv`를 먼저 요구한다.
  - fixed bandwidth grid를 spec별로 재추정하고, baseline latest-quarter beta 대비 상관, 절대차이, sign flip, local condition-number 민감도를 저장한다.

## 7G) GTWR Lamda Sensitivity Diagnostic

- manual quarterly diagnostic
- 실행 조건: `80_optional/gtwr/09_run_gtwr_lamda_sensitivity.R` 직접 실행
- 출력:
  - `gtwr_lamda_sensitivity_<control_set>.csv`
  - `03_Output/04_Logs/gtwr_lamda_sensitivity_cache/<control_set>/main/*.rds`
- 구현 원칙:
  - baseline `gtwr_main_models_<control_set>.csv`와 `gtwr_local_coefficients_<control_set>.csv`를 먼저 요구한다.
  - fixed main bandwidth에서 lamda grid를 spec별로 재추정하고, baseline latest-quarter beta 대비 상관, 절대차이, sign flip, local condition-number 민감도를 저장한다.

## 7X) GTWR Experiment Appendix

- manual quarterly appendix sidecar
- 출력:
  - `gtwr_experiment_main_models_<control_set>.csv`
  - `gtwr_experiment_local_beta_panel_<control_set>.csv`
  - `gtwr_experiment_local_coefficients_<control_set>.csv`
  - `gtwr_experiment_controls_used_<control_set>.csv`
  - `gtwr_experiment_controls_used_state_<control_set>.csv`
  - `gtwr_experiment_registry_<control_set>.csv`
  - `gtwr_experiment_ranked_candidates_<control_set>.csv`
- 구현 원칙:
  - bandwidth/control strategy grid를 quarterly local contract에서 정리하는 manual appendix다.
  - canonical pipeline은 이 appendix를 자동 실행하지 않는다.

## 8) Reporting and Presentation

- `01_make_tables_figures.R`
  - always-on descriptive/reporting outputs plus optional appendix tables
  - `descriptive_statistics.csv`는 변수별 확장 기술통계표로 작성한다. aging exposure, vitality outcome, robustness composite, vitality component, main control을 대상으로 유효 관측치, 결측, 평균, 표준편차, 최솟값, p25, 중앙값, p75, 최댓값, 유효 분기 범위, 행정동 수를 보고한다.
  - `main_variable_correlation_matrix.csv`와 `main_variable_correlation_pairs.csv`는 SPDM/GTWR 등 본분석 변수의 Pearson 상관을 `2019Q4~2025Q4` active analysis 관측치 기준으로 계산한다. 포함 범위는 main exposure, channel mediator, supporting aging exposure, primary/supplementary outcome, TWFE/SPDM/GTWR control pool이다.
  - GTWR reporting은 latest summary/rankings를 main surface로 쓰고 delta summary/rankings는 appendix diagnostic으로만 쓴다.
- `02_Code/05_reporting/02_build_presentation_artifacts.R`
  - presentation-only sidecar that derives slide-ready artifacts from canonical outputs
  - publishes `presentation_spdm_channel_path_diagram.csv` and `presentation_spdm_channel_path_diagram.png` as a slide-left visual when the optional `lag4_age60_resident_share -> lag2_age60_floating_share -> commercial vitality` channel path outputs exist
- `02_Code/05_reporting/03_build_gtwr_level_artifacts.R`
  - optional quarterly GTWR level reporting sidecar
  - reads existing `gtwr_local_beta_panel_<control_set>.csv` and related GTWR tables without rerunning GTWR
  - builds artifacts for both available `extended` and `lean` GTWR source families by default; `GTWR_LEVEL_CONTROL_SET=lean` or `extended` can force one family
  - writes reporting artifacts with strict `lean` or `extended` suffixes only; legacy mode tags are not accepted
  - publishes early/latest/delta triptych maps, quarterly local-beta trajectories, living-area/gu regional summaries, sign-transition tables, representative district trajectories, and earliest-to-latest delta diagnostics

reporting은 source input이 있는 optional appendix artifact만 선택적으로 붙일 수 있으며, absence 자체를 failure로 해석하지 않는다.
