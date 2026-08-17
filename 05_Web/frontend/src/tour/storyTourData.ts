import type { Outcome, ViewMode } from "@/types/api";
import type { LivingArea } from "@/state/constants";

export interface TourScene {
  id: number;
  tag: string;
  title: string;
  description: string;
  outcome: Outcome;
  view: ViewMode;
  selectedYq: string;
  selectedLivingArea: LivingArea | null;
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
    selectedLivingArea: null,
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
      "동북권(노원·도봉·강북·성북·중랑·동대문·광진·성동)에서는 사회적 활력을 제외한 대부분의 활력(경제, 안정성, 시간대별, 종합 활력)에서 거주 고령화의 긍정적 영향(β̂ > 0, 붉은색)이 강하게 나타납니다. 두터운 시니어 정주 인구의 근린 일상 소비와 점포 체류 기반이 상권 활력을 지탱합니다.",
    outcome: "vitality_sub_stability",
    view: "latest",
    selectedYq: "2025Q4",
    selectedLivingArea: "동북권",
    selectedGu: null,
    selectedAdmCd: null,
    camera: {
      center: [127.050, 37.610],
      zoom: 11.3,
    },
  },
  {
    id: 2,
    tag: "Scene 3 / Gangnam Contrast",
    title: "3. Southeast Area: GBD Office vs Outer Residential (동남권의 상반된 양극화)",
    description:
      "동남권(서초·강남·송파·강동)의 경우 GBD(강남 도심 중심 업무지구: 역삼·논현·삼성)는 청년 유동인구 의존도가 높아 거주 고령화 시 활력이 낮아지는 콜드스팟(β̂ < 0, 푸른색)인 반면, 외곽 배후 주거지역(송파·강동)에서는 활력이 높게 나타나는(β̂ > 0, 붉은색) 뚜렷한 권역 내 양극화가 관측됩니다.",
    outcome: "vitality_index_base",
    view: "latest",
    selectedYq: "2025Q4",
    selectedLivingArea: "동남권",
    selectedGu: null,
    selectedAdmCd: null,
    camera: {
      center: [127.085, 37.495],
      zoom: 11.4,
    },
  },
  {
    id: 3,
    tag: "Scene 4 / Downtown Hotspots",
    title: "4. Downtown Area (도심권)",
    description:
      "도심권(종로·중구·용산 등 한양도성 도심 및 전통 상권)에서는 시니어 소비자와 단골 기반을 바탕으로 상권 매출액(경제적 활력)과 더불어 점포 생존율(안정성 활력), 고객 다양성(사회적 활력)에서 긍정적 영향(β̂ > 0, 붉은색)을 보이는 핫스팟이 다수 관측됩니다. 반면, 주야간·분기 영업의 고른 분포를 대변하는 시간대별 활력(Temporal Vitality)은 도심 특성상 음(-)의 영향이 우세하게 나타납니다.",
    outcome: "vitality_sub_economic",
    view: "latest",
    selectedYq: "2025Q4",
    selectedLivingArea: "도심권",
    selectedGu: null,
    selectedAdmCd: null,
    camera: {
      center: [126.985, 37.555],
      zoom: 12.0,
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
    selectedLivingArea: null,
    selectedGu: null,
    selectedAdmCd: null,
    camera: {
      center: [126.978, 37.5665],
      zoom: 10.8,
    },
  },
];
