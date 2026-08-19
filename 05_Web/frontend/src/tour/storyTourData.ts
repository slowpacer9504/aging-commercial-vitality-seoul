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
    title: "1. Spatial Heterogeneity Across Seoul",
    description:
      "Across Seoul's 425 administrative dongs, residential aging (share of residents aged 60+) exhibits marked spatial divergence in commercial vitality, polarizing into distinct positive hotspots (β̂ > 0, red) and negative coldspots (β̂ < 0, blue).",
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
    title: "2. Northeast Area: Neighborhood Vitality Hotspots",
    description:
      "In the Northeast Living Area (Nowon, Dobong, Gangbuk, Seongbuk, Jungnang, Dongdaemun, Gwangjin, Seongdong), residential aging exerts a strong positive impact (β̂ > 0, red) across economic, stability, temporal, and composite vitality. A dense resident senior population underpins local neighborhood consumption and sustained commercial tenure.",
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
    title: "3. Southeast Area: GBD Office vs Outer Residential Divergence",
    description:
      "In the Southeast Living Area (Seocho, Gangnam, Songpa, Gangdong), the Gangnam Business District (GBD: Yeoksam, Nonhyeon, Samseong) forms a negative coldspot (β̂ < 0, blue) due to high youth worker reliance. Conversely, outer residential hinterlands (Songpa and Gangdong) exhibit positive vitality (β̂ > 0, red), revealing sharp intra-regional polarization.",
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
    title: "4. Downtown Area: Multi-Dimensional Vitality Patterns",
    description:
      "In the Downtown Living Area (Jongno, Jung-gu, Yongsan), senior patronage and loyal clientele sustain significant positive hotspots (β̂ > 0, red) in sales revenue (Economic), business survival (Stability), and visitor diversity (Social). Conversely, balanced day-night and quarterly operation (Temporal Vitality) exhibits prevailing negative effects due to central-city depopulation patterns.",
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
    title: "5. COVID-19 Shock & Spatiotemporal Trajectory",
    description:
      "During the pandemic restriction period (2020Q1–2022Q2), mobility constraints and localized neighborhood consumption induced rapid shifts in spatial aging coefficients. The GTWR spatiotemporal model effectively captures these dynamic structural transitions across Seoul.",
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
