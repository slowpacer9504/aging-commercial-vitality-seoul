import type { Outcome, ViewMode } from "@/types/api";

export interface TourScene {
  id: number;
  tag: string;
  title: string;
  description: string;
  outcome: Outcome;
  view: ViewMode;
  selectedYq: string;
  selectedGu: string | null;
  selectedAdmCd: string | null;
  camera: {
    center: [number, number];
    zoom: number;
  };
}

export const TOUR_SCENES: TourScene[] = [
  {
    id: 0,
    tag: "Scene 1 / Overview",
    title: "1. Spatial Heterogeneity Across Seoul (종합 활력)",
    description:
      "서울시 425개 행정동 전반에서 거주 고령화(60세 이상 주민 비율)는 상권 활력에 공간적으로 뚜렷한 양(+)의 핫스팟(붉은색)과 음(-)의 콜드스팟(푸른색)으로 분화되어 나타납니다.",
    outcome: "vitality_index_base",
    view: "latest",
    selectedYq: "2025Q4",
    selectedGu: null,
    selectedAdmCd: null,
    camera: {
      center: [126.978, 37.5665],
      zoom: 10.8,
    },
  },
  {
    id: 1,
    tag: "Scene 2 / Northeast Pattern",
    title: "2. Northeast Area: High Vitality Across Metrics (동북권)",
    description:
      "동북권(노원·도봉·강북·성북·중랑 등)에서는 사회적 활력을 제외한 대부분의 활력(경제, 안정성, 시간대별, 종합 활력)에서 거주 고령화의 긍정적 영향(β̂ > 0, 붉은색)이 강하게 나타납니다. 두터운 시니어 정주 인구의 근린 일상 소비와 점포 체류 기반이 상권 활력을 지탱합니다.",
    outcome: "vitality_sub_stability",
    view: "latest",
    selectedYq: "2025Q4",
    selectedGu: "노원구",
    selectedAdmCd: "0011350595", // 상계1동
    camera: {
      center: [127.056, 37.645],
      zoom: 12.2,
    },
  },
  {
    id: 2,
    tag: "Scene 3 / Gangnam Contrast",
    title: "3. Gangnam Contrast: GBD Office vs Outer Residential (강남권의 상반된 양극화)",
    description:
      "강남의 경우 GBD(강남 도심 중심 업무지구: 역삼·논현·삼성)는 청년 유동인구 의존도가 높아 거주 고령화 시 대부분의 활력이 낮게 나타나는 콜드스팟(β̂ < 0, 푸른색)인 반면, 외곽 주거지역(송파구 잠실·풍납 및 강동구)에서는 활력이 높게 나타나는(β̂ > 0, 붉은색) 뚜렷한 상반성이 관측됩니다.",
    outcome: "vitality_index_base",
    view: "latest",
    selectedYq: "2025Q4",
    selectedGu: "강남구",
    selectedAdmCd: "0011680640", // 역삼1동
    camera: {
      center: [127.080, 37.515],
      zoom: 12.2,
    },
  },
  {
    id: 3,
    tag: "Scene 4 / Downtown Hotspots",
    title: "4. Downtown Silver Consumption Hotspots (도심권 경제 활력)",
    description:
      "종로·중구 등 한양도성 도심 및 전통 상권에서는 시니어 소비자와 두터운 단골 기반이 상권 매출액과 저녁·주말 영업력(β̂ > 0, 붉은색)을 적극 견인하는 핫스팟이 뚜렷하게 관측됩니다.",
    outcome: "vitality_sub_economic",
    view: "latest",
    selectedYq: "2025Q4",
    selectedGu: "종로구",
    selectedAdmCd: "0011110515", // 청운효자동
    camera: {
      center: [126.979, 37.573],
      zoom: 12.4,
    },
  },
  {
    id: 4,
    tag: "Scene 5 / COVID Dynamics",
    title: "5. COVID-19 Shock & Spatiotemporal Adaptation (시공간 궤적)",
    description:
      "코로나19(2020Q1~2022Q2) 기간 원거리 이동 제한과 생활권 근린 소비 전환으로 인해 고령화 계수의 공간 패턴이 급변하며, 시공간 GTWR 모형을 통해서만 이러한 동태적 구조 변화를 온전히 포착할 수 있습니다.",
    outcome: "vitality_index_base",
    view: "quarter",
    selectedYq: "2021Q3",
    selectedGu: null,
    selectedAdmCd: null,
    camera: {
      center: [126.978, 37.5665],
      zoom: 11.2,
    },
  },
];
