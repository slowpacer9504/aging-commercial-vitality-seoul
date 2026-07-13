# 변수 정의서

## 1) 키 변수

- `adm_cd`
  - 10자리 행정동 코드
- `year`
  - 연도 식별자
- `quarter`
  - 분기 식별자, `1`~`4`
- `yq`
  - canonical 분기 식별자, 예: `2019Q1`
- `quarter_index`
  - `2019Q1`부터 시작하는 정수형 분기 순서
- `covid_period`
  - `2020Q1~2022Q2` 표본을 표시하는 appendix interaction flag

## 1A) 지역 reference metadata

- `adm_nm`
  - 2020 기준 행정동명
- `adstrd_nm`
  - 2020 기준 행정동 경계 원천 행정동명
- `gu_name`
  - 자치구명
- `living_area`
  - 서울 5대 권역생활권명
- `gu_prefix`
  - `adm_cd` 앞 6자리 자치구 식별 prefix

위 변수들은 `adm_region_lookup.parquet`의 정적 metadata이며, 모형의 설명변수가 아니라 주민등록인구 행정동명 매핑, GTWR 권역별 요약, QC, 보고 산출물에서 사용한다.

## 2) 핵심 독립변수

- `main exposure`
  - `age60_resident_share`
- `supporting exposure`
  - `age60_floating_share`
  - `age60_sales_share`
- `descriptive raw-scale support`
  - `age60_resident_share`
  - `age60_floating_share`
  - `age60_sales_share`
  - `ln_age60_sales_amount`

## 3) 종속변수

- `primary vitality outcomes`
  - `vitality_sub_economic`
  - `vitality_sub_social`
  - `vitality_sub_temporal`
  - `vitality_sub_stability`
- `supplementary composite`
  - `vitality_index_base`
- `robustness composites`
  - `vitality_index_entropy`
  - `vitality_index_pca`
- `ESDA support outcomes`
  - `ln_total_sales`
  - `ln_floating_pop`
  - `diversity_index`

## 4) 핵심 통제변수

- `lag4_ln_resident_pop`
- `lag4_ln_land_price_adjusted`
- `lag4_transit_accessibility`
- `lag4_ln_workplace_worker_pop`

위 4개는 TWFE/SPDM 기본 control candidate pool이며, 각각 `ln_resident_pop`, `ln_land_price_adjusted`, `transit_accessibility`, `ln_workplace_worker_pop`의 4분기 시차값이다. usable subset은 finite-count와 collinearity 점검을 거쳐 확정한다. `ln_land_price_adjusted`는 연간 공시지가 수준에 한국부동산원 월별 지가지수의 분기 평균 보정계수를 적용한 지가지수 보정 토지가격 변수다. `ln_workplace_worker_pop`은 서울시 사업체현황 종사자규모별 동별 통계에서 행정동별 총 종사자 수를 2020 기준 행정동으로 정합한 직장인구 로그다. `ln_floating_pop`은 사회적 활력 구성요소이므로 메인 통제변수로 사용하지 않는다. `ln_official_land_price`, `ln_apartment_household_count`, `hospital_count_aux_core`, `mall_count_aux_core`는 `panel_main`에 진단/지원 변수로 유지하지만 active TWFE/SPDM/GTWR 통제변수로 사용하지 않는다.

GTWR는 별도 control set을 사용한다.

- `lean`
  - `lag4_ln_resident_pop`
  - `lag4_ln_land_price_adjusted`
- `extended`
  - `lag4_ln_resident_pop`
  - `lag4_ln_land_price_adjusted`
  - `lag4_transit_accessibility`
  - `lag4_ln_workplace_worker_pop`

GTWR extended에서는 `bus_stop_count_aux`와 `subway_station_count_aux`를 직접 투입하지 않고, 두 변수를 표준화 평균한 `lag4_transit_accessibility`와 직장인구 규모 통제인 `lag4_ln_workplace_worker_pop`을 추가 통제변수로 투입한다.
`bus_stop_count_aux`는 혼합주기 snapshot source다. 2019, 2020, 2025처럼 단일 snapshot만 있는 해는 해당 연도 4개 분기에 반복하고, 2021년 1월~2024년 4월 월별 snapshot 구간은 분기말 이전 최신 snapshot을 사용한다. `subway_station_count_aux`는 station master에 개통일 규칙을 부여한 뒤 `open_date <= quarter_end`인 역을 분기별로 count한다.

## 5) Appendix Sidecar 변수

- COVID interaction appendix
  - `covid_period`
- TWFE/SPDM resident age-population appendix
  - `ln_young_resident_pop`
  - `ln_middle_resident_pop`
  - `ln_old_resident_pop`
  - `lag4_ln_resident_pop` retained as lagged resident scale control
- GTWR age-band appendix
  - `age20_resident_share`
  - `age30_resident_share`
  - `age40_resident_share`
  - `age50_resident_share`
  - `age60_64_resident_share`
  - `age65_74_resident_share`
  - `age75plus_resident_share`
  - `age65plus_resident_share`
  - `age20_floating_share`
  - `age30_floating_share`
  - `age40_floating_share`
  - `age50_floating_share`

## 6) 설계 원칙

- 연령 축은 active design에서 `60+`로 통일한다.
- 메인 노출변수는 `lag4_age60_resident_share`다.
- 상주인구 규모와 상주 고령비중은 서울시 상권분석서비스 상주인구가 아니라 행정안전부 주민등록인구현황 5세별 월별 자료에서 만든다.
- Optional SPDM channel path의 mediator는 `lag2_age60_floating_share`이고, `age60_floating_share`와 `age60_sales_share`는 보조 축이다.
- `vitality_sub_*` 4개를 우선 보고하고 `vitality_index_base`는 보조 종합지수로 둔다.
- Optional SPDM channel path에서는 mediator와 유동인구 source가 겹치는 `vitality_sub_social` 단독 지표를 제외하되, 종합 활력지수는 네 하위차원을 모두 포함하는 `vitality_index_base`를 사용한다.
- `vitality_sub_economic`은 `ln_sales_count`와 `ln_total_sales`의 pooled z-score 평균으로 구성한다.
- 거래 규모 축(`economic_transaction_scale`)은 active 경제 하위지수와 같은 `ln_sales_count`와 `ln_total_sales`의 pooled z-score 평균이다.
- `ln_total_store_count`와 `ln_sales_per_store`는 패널에는 유지하지만, 경제 하위지수 구성요소와 reporting 경제 component에서는 제외한다.
- `vitality_sub_social`은 내부 유동인구 규모(`ln_floating_pop`)와 외부 유입 인구 규모(`ln_external_inflow_pop`)로 구성한다.
- `vitality_sub_temporal`은 일중 시간대 분산(`sales_time_entropy`, `floating_time_entropy`)과 연중 분기 안정성(`sales_quarter_stability`, `floating_quarter_stability`)으로 구성한다.
- `vitality_sub_stability`는 구조적 다양성 축과 점포 존속성 축의 동일가중 평균으로 구성한다.
- 구조적 다양성 축은 `diversity_index`의 pooled z-score다.
- 점포 존속성 축은 `operating_months_rel_seoul`과 신생기업 3년 생존율(`survival_3y`)을 각각 pooled z-score로 표준화한 뒤 평균한다.
- `closure_rate`와 `stability_score = -closure_rate`는 폐업압력 진단용 지원 변수로 유지하되, active 안정성 하위지수에는 투입하지 않는다.
- 활력지수의 component z-score와 하위지수 z-score는 분기별 cross-section이 아니라 active 분석기간인 `2019Q4~2025Q4 adm_cd-yq` 표본 기준의 pooled z-score로 계산한다.
- `ln_floating_pop`은 `vitality_sub_social` 및 종합 활력지수의 구성요소이므로 메인 control pool에 포함하지 않는다.
- active shared panel은 동시점 source 변수와 등록된 model lag 변수만 유지한다.

## 7) 출처 표기 원칙

- 정본 변수 사전은 `02_variable_dictionary.csv`이며, `raw_data_source` 열은 각 변수가 의존하는 원천 데이터 출처를 기록한다.
- 서울시 상권분석서비스 기반 변수는 원천 세부 테이블을 함께 적는다. 예: 길단위인구 유동인구, 추정매출, 점포, 상권변화지표, 아파트.
- 행정안전부 주민등록인구현황 기반 변수는 5세별 월별 주민등록인구, 행정동명-`adm_cd` 매핑, 2020 기준 경계 보정 규칙을 함께 적는다.
- 외부 보조변수는 원천 공공데이터명을 적는다. 예: 공시지가 경계자료, 서울시 버스정류소 위치 정보, 서울시 역사마스터 정보, 서울시 병원/의원 인허가 정보, 서울시 대규모점포 인허가 정보.
- 서울생활인구 변수는 관내이동과 대도시권 내외국인 원천을 구분해 적고, 외부 유입 필터와 시간대 집계 정의를 함께 기록한다.
- 신생기업 생존율 변수는 서울시 상권분석서비스 홈페이지 JSON 응답을 원천으로 적고, 3개년 block 요청과 작은 코호트 결측 정책을 함께 기록한다.
- 파생지수는 최종 산식의 직접 원천을 적는다. 예: `vitality_index_base`는 서울시 상권분석서비스 기반 활력 하위지수에서 파생된다.

## 8) 분기 발행 표기 원칙

- `source_periodicity`는 원천 자료의 시간 구조를 나타낸다. 예: `quarterly`, `annual_update_q4`, `annual_snapshot`, `permit_records`, `derived`.
- `publication_method`는 분기 또는 원천 record를 `adm_cd-yq` 변수로 발행하는 집계/as-of 방식을 나타낸다. 예: `quarterly_sum_then_log`, `quarterly_mean_then_log`, `denominator_weighted_quarterly_ratio`, `q4_snapshot_asof`, `active_stock_by_year_asof`.
- `publication_formula`는 코드 기준의 실제 분기 발행 산식을 간단히 적는다.
- `publication_note`는 Q4 snapshot as-of, 분모가중 비중, permit active-stock, 파생지수 생성처럼 해석상 중요한 예외를 적는다.
- additive flow는 분기 합계가 기본이다. 예: `ln_total_sales`, `ln_sales_count`, `ln_age60_sales_amount`.
- level 또는 stock은 분기 평균, Q4 snapshot as-of, 또는 승인일 기반 active stock을 쓴다. 예: `ln_floating_pop`은 분기 평균이고, `ln_resident_pop`은 행정안전부 월별 주민등록인구 stock의 분기 평균이며, `ln_total_store_count`는 분기 점포수 stock의 분기 대표값에 `log1p`를 적용한 값이다.
- 주민등록인구 기반 `age60_resident_share`, `age60_64_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, `age65plus_resident_share`는 해당 분기 월별 연령대 인구 합계를 같은 분기 월별 총인구 합계로 나눈 분모가중 분기 비중이다.
- TWFE/SPDM age-mix appendix는 주민등록인구 분기 평균 stock에서 청년(20~30대), 중년(40~50대), 노년(60세 이상) 인구수를 묶고 `log1p` 변환한 `ln_young_resident_pop`, `ln_middle_resident_pop`, `ln_old_resident_pop`을 사용한다. 주민등록인구 age-share 변수(`age20_resident_share`~`age60plus_resident_share`)는 20세 이상 연령구성 분모에서 계산하며 GTWR age-band appendix와 진단용 support로 유지한다.
- 2020년에 `오류제2동`에서 분동된 `항동`은 2019년에 분동 전 `오류제2동`에 포함되어 있었으므로, 2019년 `오류제2동` 원천값을 2020년 `오류제2동`/`항동`의 같은 월·같은 연령대 비율로 배분한다. 이 분동 배분 row는 `registered_boundary_proxy_flag`와 `registered_boundary_proxy_reference_year`로 추적한다.
- 공시지가는 필지 polygon의 내부 대표점으로 행정동을 배정한 뒤 필지 면적을 가중치로 하는 행정동-연도별 면적가중평균을 계산한다. 이 연간 수준값은 원 변수 `ln_official_land_price`로 보존한다.
- active 토지가격 통제변수는 한국부동산원 월별 지역별 지가지수를 이용한 `ln_land_price_adjusted`다. 법정동별 보정계수는 전년도 12월 지수 대비 해당 분기 3개월 지수비의 평균이며, 법정동-행정동 공간교차 면적가중치로 행정동 보정계수 `land_price_lpi_factor`를 만든 뒤 연간 공시지가에 곱한다.
- 서울생활인구 외부 유입 인구는 월별 ZIP의 일자-시간대 시점 인구를 행정동-월 기준으로 평균한 뒤, 같은 분기 월평균을 다시 평균한 분기 평균 시점인구다. 월 내부 일수가 부족한 경우 관측일 기반 월평균을 해당 월 대표값으로 쓰고 manifest에 coverage flag를 남긴다.
- 신생기업 생존율은 서울시 상권분석서비스 JSON의 기준연도 Q4 3개년 block을 행정동-분기 row로 as-of 재구성한다. `survival_3y`는 원천 생존율 값을 그대로 사용하고, 코호트 분모가 0인 row는 임의 보정하지 않고 결측으로 둔다.
- 점포당 매출액은 분기 총매출을 분기 대표 점포수로 나눈 뒤 `log1p`를 적용한다. 예: `ln_sales_per_store`.
- 분기 안정성은 4개 분기 값이 모두 유효하고 분기 평균이 양수일 때 `-log1p(sd(q1:q4) / mean(q1:q4))`로 계산한다. 예: `sales_quarter_stability`, `floating_quarter_stability`.
- 비중 변수는 가능하면 분모가중 분기 비율을 쓴다. 예: `age60_floating_share`, `age60_sales_share`.
- Q4 업데이트형 source는 현재 코드 기준 `q4_snapshot`, `q4_snapshot_ratio`, `q4_snapshot_then_log`, `q4_snapshot_difference`로 표기한다.
- Q4 업데이트형 source에서 Q4 관측값이 없으면 같은 연도 최신분기 값으로 대체하지 않고 결측으로 둔다.
- 활력 하위지수와 종합지수는 원천을 직접 다시 집계하지 않고 분기 발행이 끝난 component에서 파생한다.
- 활력 하위지수와 종합지수의 표준화는 pooled panel standardization을 따른다. 즉 active 분석기간인 `2019Q4~2025Q4 adm_cd-yq` 표본의 평균과 표준편차를 사용하며 분기별 표준화는 active contract가 아니다.
