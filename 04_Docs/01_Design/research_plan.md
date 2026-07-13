# 고령화가 근린 상업 활력에 미치는 영향: 서울시 빅데이터를 이용한 시공간 분석

## 1. 연구 배경과 문제의식

인구 고령화는 단순히 미래의 인구 구조적 전망을 넘어, 도시 공간과 지역 경제의 지형을 전면 재편하는 중요한 구조적 전환점이다. WHO(2007)와 OECD(2025) 등 주요 기관들이 고령화와 도시화를 미래 도시를 형성하는 핵심 축으로 지목했듯, 이제 고령화는 단편적인 복지 의제를 넘어 근린의 소비 생태계를 재편하는 핵심 연구 과제로 다뤄져야 한다. 고령층은 상대적으로 이동 반경이 좁아 거주지 인접 생활권에 대한 의존도가 매우 높으며, 식료품 구매, 의료 및 돌봄 등 일상적이고 필수적인 소비를 반복하는 행동 특성을 지닌다. 이는 고령화가 단순히 전체 상권 매출 규모를 축소시키는 일방적인 쇠퇴 압력에 그치는 것이 아니라, 소비가 발생하는 시공간적 패턴과 업종 선호를 다각도로 재조정하는 '구조적 재편 요인'으로 작용할 수 있음을 의미한다.

따라서 근린 상권의 활력 역시 단편적인 매출이나 점포 수 위주의 단일 경제 지표에 의존하기보다, 유동인구와 외부 유입(사회적 활성도), 특정 시간대에 편중되지 않는 이용 안정성(시간적 지속성), 업종 다양성 및 점포 존속성(구조적 안정성) 등을 아우르는 다차원적 개념으로 접근해야 한다. 그러나 기존 연구들은 고령친화도시나 지역사회 계속 거주(Aging in Place) 관련 논의에서 주거지 인근 물리적 환경에 편중되어 실제 상권 변동과의 결합이 부족했고, 반대로 전통적 상권 연구들은 인구구조 변화를 직접적인 핵심 변수로 다루지 않은 채 단기 단면 자료나 전역적 평균 효과 분석에 치우친 경향이 있었다. 이러한 한계를 보완하기 위해서는 고령화가 상업활력의 하위 차원들에 미치는 다각적인 직접효과, 인접 지역 간의 상호작용을 통한 공간파급효과(Spatial Spillover), 그리고 배후 환경에 따라 다르게 나타나는 국지적 시공간 이질성을 통합적으로 실증해내야 한다.

본 프로젝트의 active canonical design은 이와 같은 미시적 시공간 변동을 촘촘하게 추정하기 위해 **연도 패널에서 분기 패널로 전환**되었다. 전환 목적은 상권 매출·점포·유동인구의 분기 변동을 보존하고, 연도·정적 자료는 quarter-end as-of 규칙으로 붙여 단기 시공간 변화를 더 촘촘하게 추정하는 것이다. 따라서 본 연구의 active 분석 단위는 `adm_cd x yq`이며, `year`, `quarter`, `yq`, `quarter_index`를 공통 시간 키로 유지한다.

이 문서는 현재 프로젝트의 active design anchor다. 실행 순서, 출력 계약, QC 규칙은 `research_procedure.md`와 codebook에서 구체화한다.

## 2. 연구 목적

본 연구의 목적은 서울시 근린 상권을 고령화와 공간의존의 관점에서 설명 가능한 실증 구조로 정리하는 것이다. 구체적 목적은 다음과 같다.

1. 거주 기반 고령화가 근린 상업 활력과 어떤 전역적 관계를 가지는지 추정한다.
2. 거주 기반 고령화가 고령 유동인구 구성을 통해 상업 활력으로 이어지는 경로를 검정한다.
3. 특정 지역의 고령화와 활력 변화가 주변 지역에 미치는 공간 파급효과를 추정한다.
4. 전역모형으로 충분히 설명되지 않는 지역별 계수 차이를 국지적 시공간 패턴으로 확인한다.

본 연구는 상업 활력을 하나의 수치로 환원하지 않는다. 경제적 활력, 사회적 활력, 시간적 활력, 안정성의 네 차원을 우선 해석하고, 종합지수는 보조 요약치로 사용한다.

## 3. 주요 연구질문

- `RQ1. 직접효과와 전역적 관계`
  - `age60_resident_share`은 서울시 행정동의 근린 상업 활력과 어떤 방향과 크기의 관계를 가지는가.
  - 그 관계는 `economic`, `social`, `temporal`, `stability` 차원에서 서로 다르게 나타나는가.
  - `lag4_age60_resident_share -> lag2_age60_floating_share -> vitality` 경로에서 고령 유동인구 구성은 매개 채널로 작동하는가.

- `RQ2. 공간의존과 spillover`
  - 고령화와 상업 활력은 공간 자기상관을 보이는가.
  - 비공간 기준선의 잔차에 공간의존이 남는가.
  - 공간모형에서 직접효과, 간접효과, 총효과는 각각 어떤 패턴을 보이는가.

- `RQ3. 국지적 시공간 이질성`
  - 전역 평균효과가 모든 지역에서 비슷하게 나타나는가.
  - 지역별 계수의 크기와 방향은 어떤 공간적 패턴을 보이는가.

`aging x covid_period` 상호작용, 대체 활력지수, 추가 age-mix와 sector-share 가족은 appendix 또는 robustness로 다룬다. 본문 실증서사의 중심 질문은 위 세 가지다.
`80_optional/**`의 appendix/sidecar 코드는 기본 `run_all.R` 밖에 두며, 해당 파일을 직접 실행하면 별도 실행 플래그 없이 수행되는 manual surface로 관리한다.

## 4. 분석 단위와 범위

### 4.1 공간 단위

- 분석 단위는 **서울시 2020년 기준 행정동(`adm_cd`)** 이다.
- 공간가중행렬과 지도 시각화도 같은 경계를 사용한다.
- geometry 처리 기준 좌표계는 `EPSG:5179`다.

행정동 수준은 생활권 상권과 주민구성의 상호작용을 비교적 촘촘하게 관찰할 수 있고, 보조 공공데이터와 결합 가능하며, 공간모형에서 해석 가능한 인접 구조를 제공한다.

### 4.2 시간 단위와 범위

- canonical panel 구축 범위는 **2019Q1 ~ 2025Q4** 이고, active 분석기간은 **2019Q4 ~ 2025Q4** 이다.
- active 분석 단위는 `adm_cd x yq` 분기 패널이다.
- active 시간 키는 `year`, `quarter`, `yq`, `quarter_index`다.
- canonical model timing contract는 **시차 적용 분기 계약** 이다. 독립변수와 통제변수는 `t-4` 값을 사용한다. Optional SPDM channel path sidecar의 매개변수는 `t-2` 값을 사용한다.
- 2018년 주민등록인구, 버스정류소, 공시지가 source는 2019년 active panel의 4분기 시차 계산을 위한 lag-support 범위로만 사용한다.
- 2019Q1~2019Q3는 rolling 4-quarter 활력지표와 시차 변수 검증을 위한 warm-up 구간이며, 본문 ESDA/TWFE/SPDM/GTWR와 reporting 표본에는 포함하지 않는다.

분기 자료는 active shared panel의 시간축이다. 연도·정적 자료는 같은 값이 반복될 수 있음을 명시하되, 반복값 자체를 숨기지 않고 source precision/QC로 추적한다.

### 4.3 데이터 소스

| 구분 | 기간 | 용도 | 상태 |
| --- | --- | --- | --- |
| 서울시 상권분석서비스 | 2019Q1~2025Q4 | 분기 base 구축의 핵심 source | active |
| 행정안전부 주민등록인구현황 | 2018~2025 | 상주인구 규모와 고령 상주인구 비중, 2018은 lag-support | active |
| 보조 공공데이터 | 2018~2025 가용 연도 | 통제변수, 물리·입지 보조정보, 2018은 lag-support | active |
| 2020 기준 행정동 경계 | static | 공간 단위, W 구축 | active |

서울시 상권분석서비스 원천 중 분기 자료는 `adm_cd-yq` 기준으로 직접 투입한다. 연도·정적 자료는 `adm_cd-year` 또는 `adm_cd` 수준에서 정리한 뒤 해당 분기의 quarter-end as-of 값으로 결합한다. 따라서 본문 해석의 기준 자료는 “분기 단위 상권 변동을 보존하되, 저주기 source의 precision을 명시한 shared panel”이다.

### 4.4 분기화 원칙

분기 단위 전환은 원천 주기별 발행 규칙과 as-of 규칙을 고정하는 작업이다.

1. **additive flow**
   - 매출액, 거래건수처럼 분기 누적 의미가 있는 변수는 분기 합계로 발행한다.
2. **level / stock / share / density**
   - 점포수, 유동인구, 비중, 밀도처럼 수준을 나타내는 변수는 분기 대표값 또는 분모가중 분기 비중으로 발행한다.
   - 월별 source는 분기 내 월평균 또는 분모가중 분기 비중으로 집계한다.
   - 서울시 상권분석서비스의 Q4 업데이트형 구조 source는 관측 가능한 분기값을 우선 사용하고, 연도·정적 source는 quarter-end as-of 규칙으로 결합한다.
   - 상주인구 규모와 고령 상주인구 비중은 행정안전부 주민등록인구현황 5세별 월별 자료를 2020 기준 행정동 경계로 정합한 뒤 분기 내 월별 stock 평균과 분모가중 분기 비중으로 산출한다.
3. **temporal / stability component**
   - 시간대 entropy와 구조 다양성은 분기 단면에서 계산한다.
   - 분기 안정성은 현재 분기까지의 rolling 4-quarter 분포로 계산한다.
4. **annual / static auxiliary**
   - 연도 또는 정적 자료는 `adm_cd-year` 또는 `adm_cd`에서 정리한 뒤 `adm_cd-yq` 패널에 as-of 방식으로 결합하고, source precision을 기록한다.
   - 공시지가는 행정동-연도별 면적가중평균을 만든 뒤 같은 연도의 4개 분기에 동일하게 발행한다.
   - 대중교통 접근성의 버스정류장 source처럼 단일 snapshot과 월별 snapshot이 섞인 자료는 분기별 발행 snapshot과 carry-forward 여부를 QC에 기록한다.

이 원칙은 분기 상권 변동을 보존하면서 저주기 source의 반복값 문제를 명시적으로 관리하기 위한 최소 계약이다. 단, 본 분석 모형의 시간 순서를 분명히 하기 위해 canonical panel에는 등록된 시차 변수만 추가한다. 현재 허용 시차 변수는 `lag4_age60_resident_share`, `lag4_ln_resident_pop`, `lag4_ln_land_price_adjusted`, `lag4_transit_accessibility`, `lag4_ln_workplace_worker_pop`, `lag2_age60_floating_share`다.

## 5. 이론적 해석 틀

본 연구는 고령화와 상권 활력의 관계를 아래 네 층위에서 해석한다.

### 5.1 직접효과

거주 기반 고령화는 지역의 소비 리듬, 업종 수요, 이동 패턴, 체류 시간 구조를 바꿀 수 있다. 이 변화는 매출, 점포구성, 시간대 분산, 생존 안정성에 각기 다른 방식으로 반영될 수 있다.

### 5.2 공간 파급효과

상권은 행정경계 안에서 닫혀 움직이지 않는다. 인접 지역의 소비 구조, 상권 접근성, 생활권 이동은 서로 연결되어 있으므로 특정 지역의 고령화와 활력 변화는 주변 지역으로 확산될 수 있다.

### 5.3 비공간 기준선과 공간 확장모형의 관계

TWFE는 비공간 기준선이다. 지역 고정효과와 분기 고정효과를 통해 불변 특성과 공통 충격을 통제하고, 동일한 quarterly sample 위에서 해석 가능한 baseline을 제공한다. 그러나 잔차에 공간의존이 남는다면 이는 SPDM 도입의 실증적 근거가 된다.

### 5.4 국지적 이질성

GTWR는 전역모형의 평균효과가 지역별로 얼마나 다르게 나타나는지 보여주는 optional local sidecar다. 다만 이는 전역 인과 추정의 대체가 아니라, main resident-only quarterly contract 위에서 국지 패턴을 설명하는 보조 layer다. Floating-only, age-band, sector-share GTWR는 `80_optional/gtwr` 아래의 appendix sidecar로 두며, 해당 스크립트를 직접 실행할 때 실제 `GWmodel::gtwr()`를 수행한다.

## 6. 변수 설계

### 6.1 핵심 독립변수

- **main exposure**
  - `lag4_age60_resident_share`
- **supporting exposures**
  - `age60_resident_share`
  - `age60_floating_share`
  - `age60_sales_share`

`lag4_age60_resident_share`를 메인 노출변수로 두는 이유는 거주 기반 고령화가 생활권 상권의 구조적 수요 기반을 가장 안정적으로 반영하되, 종속변수와의 동시점 반응을 피하기 위해서다. 원천 `age60_resident_share`는 서울시 상권분석서비스의 10세 단위 상주인구가 아니라 행정안전부 주민등록인구현황의 5세 단위 월별 자료에서 산출한다. `age60_floating_share`와 `age60_sales_share`는 활동 및 소비 측면의 보조 축으로 해석하며, optional SPDM channel path sidecar의 mediator는 `lag2_age60_floating_share`를 사용한다.
행정안전부 자료에서는 추후 민감도 분석을 위해 `age60_64_resident_share`, `age65_74_resident_share`, `age75plus_resident_share`, `age65plus_resident_share`도 함께 발행하지만, canonical main exposure는 `lag4_age60_resident_share`로 유지한다.

### 6.2 종속변수

- **primary outcomes**
  - `vitality_sub_economic`
  - `vitality_sub_social`
  - `vitality_sub_temporal`
  - `vitality_sub_stability`
- **supplementary composite**
  - `vitality_index_base`
- **robustness composites**
  - `vitality_index_entropy`
  - `vitality_index_pca`

본문 결과표와 해석의 중심은 네 개의 하위 활력지표다. 종합지수는 전체 방향이 일관적인지 확인하는 보조 요약치로 둔다.
경제적 활력 하위지수는 추정매출 건수와 총 추정매출액을 각각 pooled z-score로 표준화한 뒤 평균해 구성한다. 총 점포수와 점포당 매출액은 패널에는 유지하되, 경제 하위지수 구성요소에서는 제외한다.
사회적 활력 하위지수는 상권 내부 유동인구 규모와 서울생활인구 기반 외부 유입 인구 규모를 함께 반영한다.
시간적 활력 하위지수는 하루 안의 시간대 분포와 1년 안의 분기 안정성을 함께 반영한다.
안정성 하위지수는 구조적 다양성 축과 점포 존속성 축을 동일가중으로 결합한다. 구조적 다양성 축은 업종 다양성 지수의 pooled z-score이고, 점포 존속성 축은 서울 대비 상대 영업월수와 서울시 상권분석서비스 신생기업 3년 생존율(`survival_3y`)을 각각 pooled z-score로 표준화한 뒤 평균한다. `closure_rate`와 `stability_score = -closure_rate`는 폐업압력 진단용 지원 변수로 유지하지만, active 안정성 하위지수 구성요소에서는 제외한다.
활력지수의 개별 구성요소와 하위지수는 분기별 cross-section 기준이 아니라 active 분석기간인 `2019Q4~2025Q4 adm_cd-yq` 표본의 평균과 표준편차를 기준으로 pooled z-score 표준화한다. 이 기준은 구성요소 간 스케일을 맞추되 분기 간 수준 변화 자체는 지수 안에 유지하기 위한 active contract다.

### 6.3 통제변수

메인 TWFE/SPDM의 기본 control candidate pool은 아래 네 개의 4분기 시차 변수다. `ln_floating_pop`은 사회적 활력 구성요소와 종합 활력지수에 포함되므로 메인 통제변수에서는 사용하지 않는다. `ln_apartment_household_count`, `hospital_count_aux_core`, `mall_count_aux_core`는 `panel_main`에 진단/지원 변수로 남기지만 active TWFE/SPDM/GTWR 통제변수로 투입하지 않는다.

- `lag4_ln_resident_pop`
- `lag4_ln_land_price_adjusted`
- `lag4_transit_accessibility`
- `lag4_ln_workplace_worker_pop`

`ln_land_price_adjusted`는 행정동-연도별 면적가중 공시지가에 한국부동산원 월별 지역별 지가지수의 분기 평균 보정계수를 곱해 만든 지가지수 보정 토지가격 변수다. 법정동 지가지수는 법정동-행정동 공간교차 면적가중치로 행정동 단위에 정합한다. 원 연간 공시지가 로그인 `ln_official_land_price`는 패널에 보존하되 active 통제변수로 쓰지 않는다.
`ln_workplace_worker_pop`은 서울시 사업체현황 종사자규모별 동별 통계의 행정동별 총 종사자 수를 2020 기준 행정동으로 정합한 뒤 `log1p`를 적용한 값이다. 2018~2019년 `항동`은 2020년 `오류2동`/`항동` 종사자 비율로 분동 전 `오류2동` 값을 배분하고, 2025년은 2024년 최신 관측값을 carry-forward한 as-of 값으로 둔다. main model에는 해당 변수의 4분기 시차값을 투입한다.

메인 TWFE/SPDM은 finite observation 수와 추정 가능성에 따라 usable subset을 기록한다.

GTWR main sidecar는 local design matrix의 다중공선성 민감도를 고려해 별도 control contract를 둔다.

- `lean` 기본값
  - `lag4_ln_resident_pop`
  - `lag4_ln_land_price_adjusted`
- `extended` 선택값
  - `lean` 두 변수
  - `lag4_transit_accessibility`
  - `lag4_ln_workplace_worker_pop`

`ln_resident_pop`은 행정안전부 주민등록인구현황의 행정동-월별 총인구 stock을 분기 내 평균한 뒤 `log1p`를 적용한 값이다. `transit_accessibility`는 `bus_stop_count_aux`와 `subway_station_count_aux`의 pooled z-score 평균으로 만든 대중교통 접근성 통제변수이며, main model에는 해당 변수의 4분기 시차 composite를 투입한다. 모든 GTWR control set은 complete-case 표본과 GTWR spatiotemporal weight 기반 local condition-number를 별도 진단으로 기록한다. 이 local CN은 `GWmodel::gwr.collin.diagno()`의 local_CN 계산 관례를 GTWR의 시공간 거리·커널 가중치에 맞춰 적용한 보조 진단이다.

### 6.4 기간 플래그와 보조 변수

- `covid_period`
  - `2020Q1~2022Q2` 분기 범위를 표시하는 appendix interaction flag다.
- 추가 age-mix, 대체 활력지수 정의, 표본창 민감도는 robustness 또는 appendix에서 다룬다.

## 7. 방법론 계층

active methodology stack은 아래와 같다.

### 7.1 ESDA

- 목적: 분포와 공간 자기상관의 존재를 확인한다.
- 역할: 공간의존과 spillover 논의를 시작하기 위한 탐색 단계다.
- 핵심 출력: Global Moran's I, Bivariate Moran's I, LISA, EHSA, 분포 지도

### 7.2 TWFE

- 목적: 비공간 기준선과 공통 quarterly sample baseline을 제공한다.
- 역할: main inferential endpoint가 아니라 baseline / spatial-diagnostic layer다.
- 핵심 추가 기능: 잔차 Moran's I를 통해 공간모형 도입의 정당성을 제시한다.

### 7.3 SPDM

- 목적: 전역적 직접효과와 간접효과를 동시에 추정한다.
- 역할: active design의 **main global model** 이다.
- 핵심 보고 방식: coefficient보다 **direct / indirect / total effects** 중심
- active 구현은 true SDM/SPDM이다. 즉 `W y`, `X`, `W X`를 함께 포함한다.
- `02_run_spdm_main.R`는 `splm::spml()`의 Durbin placeholder에 의존하지 않고, quarterly panel에서 `W lag4_age60_resident_share`와 `W controls`를 직접 생성한 뒤 추정한다.
- direct / indirect / total effects는 `S = (I - rho W)^(-1)`, `S(beta I + theta W)` 행렬식으로 계산한다.
- coefficient와 spatial parameter의 표준오차는 `splm::spml()` fitted object의 model-based asymptotic ML `vcov`를 사용한다. impact 표준오차와 신뢰구간은 같은 model-based `vcov`에서 `rho`, `beta`, `theta`를 simulation draw로 생성해 계산하며, 이를 robust SE로 부르지 않는다.
- `80_optional/spdm/07_run_spdm_channel_path.R`는 optional mediation-oriented channel path sidecar이다. 같은 quarterly Queen SDM 계약에서 mediator 미포함 `c` 경로, `lag4_age60_resident_share -> lag2_age60_floating_share`의 `a` 경로, `lag2_age60_floating_share -> vitality`의 `b` 경로, mediator를 통제한 `c'` 경로를 같은 outcome별 balanced sample에서 추정하고 `a*b` 간접효과와 `c - c'` 직접효과 약화 진단을 별도 산출물로 기록한다. 기본 추론은 행정동 단위 wild residual bootstrap이며, bootstrap이 비활성화되었거나 유효 draw가 부족할 때만 `delta_independent_approx`를 fallback으로 사용한다.
- channel path outcome은 유동인구 source와 직접 겹치는 `vitality_sub_social` 단독 지표를 제외하고, `vitality_sub_economic`, `vitality_sub_temporal`, `vitality_sub_stability`, `vitality_index_base`를 사용한다. 종합 활력지수는 네 하위지표를 모두 포함하는 기본 정의를 유지하되, 해석에서는 사회적 활력 구성요소가 mediator source와 겹친다는 caveat를 함께 둔다.

### 7.4 GTWR

- 목적: 전역모형 이후 남는 국지적 이질성을 시각화한다.
- 역할: **resident-only quarterly main local sidecar** 이며 기본 pipeline에서는 optional이다. Floating-only, age-band, sector-share local GTWR는 `80_optional/gtwr`의 해당 스크립트를 직접 실행하는 appendix sidecar다.
- 해석 수준: global causal claim이 아니라 local heterogeneity description
- bandwidth: main GTWR는 outcome 간 비교 가능성, local coefficient 안정성, bandwidth-selection 결과, sensitivity 진단을 함께 고려해 fixed adaptive `GTWR_ST_BW=60`을 기본으로 사용한다. `bw.gtwr()` full-panel/anchor-quarter 탐색은 `06_select_gtwr_bandwidth.R`에서만 실행하고, 선택 결과를 main GTWR에 자동 주입하지 않는다. `07_run_gtwr_bandwidth_sensitivity.R`는 고정 adaptive bandwidth grid `30,60,90,120,180`을 같은 spec에 반복 적용해 baseline `60` 대비 latest-quarter beta agreement, sign flip, local condition-number 변화를 보조표로 기록한다.
- lamda sensitivity: `08_run_gtwr_lamda_sensitivity.R`가 `GTWR_LAMDA_SENSITIVITY_GRID`의 값별로 GTWR를 재추정하고, baseline latest-quarter beta와의 상관, 절대변화, sign flip, local condition-number 변화를 보조표로 기록한다.
- control set: 기본값은 `GTWR_CONTROL_SET=lean`이며, `extended`는 대중교통 접근성 composite를 추가하는 민감도/확장 사양으로 사용한다.
- reporting surface: GTWR local coefficient는 latest quarter beta를 기준으로 요약하고, earliest-to-latest delta는 보조 appendix diagnostic으로만 파생한다.

## 8. 본문과 부록의 경계

- **Main text**
  - quarterly panel 구축 논리
  - 활력지수와 핵심 변수 정의
  - ESDA 핵심 결과
  - TWFE baseline과 residual Moran
  - SPDM main impacts
  - 필요 시 GTWR 요약 지도

- **Appendix**
  - interaction family
  - age-mix family
  - SPDM channel path sidecar
  - spatial family comparison (`SLX`, `SAR`, `SDM`, `SEM`, `SDEM`, `SARAR/SAC`, `GNS`)
  - W robustness 상세표
  - GTWR 추가 sidecar
  - 세부 QC inventory

이렇게 두면 본문은 `ESDA -> TWFE -> SPDM main -> GTWR(optional)`의 해석 흐름을 유지하면서도, channel path와 보조 민감도, local sidecar를 부록으로 분리할 수 있다.
