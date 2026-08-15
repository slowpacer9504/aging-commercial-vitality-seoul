import { useEffect, useMemo, useRef, useState, useCallback, useImperativeHandle, type Ref } from "react";
import Map, { Source, Layer, NavigationControl, type MapRef, type MapLayerMouseEvent } from "react-map-gl/maplibre";
import "maplibre-gl/dist/maplibre-gl.css";

import { useAppStore } from "@/state/store";
import { getCoefficients, getMeta } from "@/api/endpoints";
import { colorFor } from "@/map/colorScale";
import { LIVING_AREA_CENTERS, LIVING_AREA_GUS } from "@/state/constants";
import { HoverTooltip } from "./HoverTooltip";
import { Legend } from "./Legend";
import { MapSpecOverlay } from "./MapSpecOverlay";
import type {
  CoefficientFeature,
  CoefficientFeatureCollection,
  CoefficientFeatureProps,
  MetaResponse,
} from "@/types/api";

const INITIAL_VIEW = {
  longitude: 126.978,
  latitude: 37.5665,
  zoom: 10.8,
  pitch: 0,
  bearing: 0,
};

// Constrain viewport strictly around Seoul metropolitan area [minLng, minLat, maxLng, maxLat]
const SEOUL_BOUNDS: [number, number, number, number] = [126.50, 37.30, 127.40, 37.85];

const MIN_ZOOM = 9.8; // Maximum zoom out: Full Seoul metropolitan view
const MAX_ZOOM = 14.5; // Maximum zoom in: Detailed view of 2-3 neighborhood dongs

const GU_CENTERS: Record<string, [number, number]> = {
  강남구: [127.0473, 37.5172],
  강동구: [127.1238, 37.5301],
  강북구: [127.0255, 37.6396],
  강서구: [126.8495, 37.5509],
  관악구: [126.9515, 37.4784],
  광진구: [127.0822, 37.5385],
  구로구: [126.8874, 37.4954],
  금천구: [126.9023, 37.4568],
  노원구: [127.0563, 37.6542],
  도봉구: [127.0471, 37.6688],
  동대문구: [127.0398, 37.5744],
  동작구: [126.9368, 37.5124],
  마포구: [126.9018, 37.5638],
  서대문구: [126.9368, 37.5791],
  서초구: [127.0324, 37.4837],
  성동구: [127.0368, 37.5633],
  성북구: [127.0175, 37.5891],
  송파구: [127.1058, 37.5145],
  양천구: [126.8665, 37.5169],
  영등포구: [126.8963, 37.5264],
  용산구: [126.9799, 37.5326],
  은평구: [126.9291, 37.6027],
  종로구: [126.9790, 37.5730],
  중구: [126.9979, 37.5636],
  중랑구: [127.0927, 37.6065],
};

const BASEMAP_LIGHT = "https://basemaps.cartocdn.com/gl/positron-nolabels-gl-style/style.json";
const BASEMAP_DARK = "https://basemaps.cartocdn.com/gl/dark-matter-nolabels-gl-style/style.json";

const SEOUL_GU_URL = `${import.meta.env.BASE_URL ?? "/"}data/geojson/seoul_gu.geojson`.replace(/\/{2,}/g, "/");

export interface MapViewHandle {
  getMapRef: () => MapRef | null;
  flyTo: (center: [number, number], zoom: number) => void;
}

interface Props {
  ref?: Ref<MapViewHandle>;
  isSidebarOpen?: boolean;
}

export function MapView({ ref, isSidebarOpen = true }: Props) {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const compareAdmCd = useAppStore(s => s.compareAdmCd);
  const selectedLivingArea = useAppStore(s => s.selectedLivingArea);
  const selectedGu = useAppStore(s => s.selectedGu);
  const theme = useAppStore(s => s.theme);
  const hoveredScatterAdmCd = useAppStore(s => s.hoveredScatterAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const mapRef = useRef<MapRef>(null);

  useImperativeHandle(ref, () => ({
    getMapRef: () => mapRef.current,
    flyTo: (center: [number, number], zoom: number) => {
      mapRef.current?.flyTo({
        center,
        zoom,
        duration: 1000,
      });
    },
  }));

  const [features, setFeatures] = useState<CoefficientFeature[]>([]);
  const [estimateBreaks, setEstimateBreaks] = useState<number[]>([]);
  const [deltaBreaks, setDeltaBreaks] = useState<number[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [hoveredInfo, setHoveredInfo] = useState<{
    x: number;
    y: number;
    admCd: string;
    props: CoefficientFeatureProps;
  } | null>(null);

  useEffect(() => {
    let cancelled = false;
    getMeta()
      .then((meta: MetaResponse) => {
        if (cancelled) return;
        setEstimateBreaks(meta.estimate_breaks);
        setDeltaBreaks(meta.delta_breaks);
      })
      .catch(err => {
        if (!cancelled) setError(`meta: ${String(err?.message ?? err)}`);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      mapRef.current?.resize();
    }, 300);
    return () => clearTimeout(timer);
  }, [isSidebarOpen]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    getCoefficients(controlSet, outcome, view, view === "quarter" ? selectedYq : undefined)
      .then((fc: CoefficientFeatureCollection) => {
        if (cancelled) return;
        setFeatures(Array.isArray(fc.features) ? fc.features : []);
      })
      .catch(err => {
        if (cancelled) return;
        setError(`coefficients: ${String(err?.message ?? err)}`);
        setFeatures([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [outcome, controlSet, view, selectedYq]);

  // Fly to selected district or living area
  useEffect(() => {
    if (selectedGu && GU_CENTERS[selectedGu]) {
      const [lng, lat] = GU_CENTERS[selectedGu]!;
      mapRef.current?.flyTo({
        center: [lng, lat],
        zoom: 12.3,
        duration: 1000,
      });
    } else if (selectedLivingArea && LIVING_AREA_CENTERS[selectedLivingArea]) {
      const [lng, lat, zoom] = LIVING_AREA_CENTERS[selectedLivingArea];
      mapRef.current?.flyTo({
        center: [lng, lat],
        zoom,
        duration: 1000,
      });
    } else if (!selectedGu && !selectedLivingArea && mapRef.current) {
      mapRef.current.flyTo({
        center: [INITIAL_VIEW.longitude, INITIAL_VIEW.latitude],
        zoom: INITIAL_VIEW.zoom,
        duration: 1000,
      });
    }
  }, [selectedGu, selectedLivingArea]);

  const breaks = view === "delta" ? deltaBreaks : estimateBreaks;

  const geojson = useMemo(
    () => ({
      type: "FeatureCollection" as const,
      features: features.map(f => ({
        type: "Feature" as const,
        properties: {
          ...f.properties,
          __fill: colorFor(f.properties.estimate, breaks.length === 9 ? breaks : []),
        },
        geometry:
          f.geometry ?? { type: "Polygon" as const, coordinates: [] as never },
      })),
    }),
    [features, breaks],
  );

  const hasData = geojson.features.length > 0 && breaks.length === 9;

  const onMouseMove = useCallback((e: MapLayerMouseEvent) => {
    const f = (e.features ?? [])[0];
    if (f && f.properties) {
      const props = f.properties as unknown as CoefficientFeatureProps;
      setHoveredInfo({
        x: e.point.x,
        y: e.point.y,
        admCd: props.adm_cd,
        props,
      });
    } else {
      setHoveredInfo(null);
    }
  }, []);

  const onMouseLeave = useCallback(() => {
    setHoveredInfo(null);
  }, []);

  const basemapStyle = theme === "dark" ? BASEMAP_DARK : BASEMAP_LIGHT;

  return (
    <section
      className={`map-view ${theme === "dark" ? "is-dark" : "is-light"}`}
      role="region"
      aria-label="Seoul GTWR coefficient choropleth"
    >
      {error && (
        <div className="map-error" role="alert">
          {error}
        </div>
      )}
      {loading && (
        <div className="map-loading" aria-busy="true">
          <div className="loading-spinner" />
          <span>Updating GTWR spatial estimates…</span>
        </div>
      )}
      <Map
        ref={mapRef}
        initialViewState={INITIAL_VIEW}
        minZoom={MIN_ZOOM}
        maxZoom={MAX_ZOOM}
        maxBounds={SEOUL_BOUNDS}
        mapStyle={basemapStyle}
        style={{ width: "100%", height: "100%" }}
        interactive={true}
        interactiveLayerIds={["gtwr-fill"]}
        attributionControl={false}
        {...({ preserveDrawingBuffer: true } as object)}
        onMouseMove={onMouseMove}
        onMouseLeave={onMouseLeave}
        onClick={e => {
          const f = (e.features ?? [])[0];
          const admCd = f && (f.properties as { adm_cd?: string } | null)?.adm_cd;
          if (admCd) {
            selectAdmCd(admCd);
            if (e.lngLat) {
              mapRef.current?.flyTo({
                center: [e.lngLat.lng, e.lngLat.lat],
                zoom: Math.max(11.8, mapRef.current.getZoom()),
                duration: 800,
              });
            }
          }
        }}
      >
        <NavigationControl position="bottom-left" showCompass={false} />

        <Source
          id="gtwr"
          type="geojson"
          data={geojson as never}
          promoteId="adm_cd"
        />

        {hasData && (
          <>
            {/* Choropleth Fill Layer */}
            <Layer
              id="gtwr-fill"
              type="fill"
              source="gtwr"
              paint={{
                "fill-color": ["get", "__fill"] as never,
                "fill-opacity": selectedGu
                  ? [
                      "case",
                      ["==", ["get", "gu_name"], selectedGu],
                      0.85,
                      0.35, // Dim non-selected districts
                    ]
                  : selectedLivingArea && LIVING_AREA_GUS[selectedLivingArea]
                  ? [
                      "case",
                      ["in", ["get", "gu_name"], ["literal", LIVING_AREA_GUS[selectedLivingArea]]],
                      0.85,
                      0.35, // Dim non-selected living areas
                    ]
                  : 0.78,
              }}
            />

            {/* Base boundary line */}
            <Layer
              id="gtwr-line"
              type="line"
              source="gtwr"
              paint={{
                "line-color": theme === "dark" ? "#475569" : "#cbd5e1",
                "line-width": 0.5,
                "line-opacity": 0.7,
              }}
            />

            {/* Autonomous District (Gu) and Living Area Boundary Highlight Layers */}
            {(selectedGu || selectedLivingArea) && (
              <>
                <Source
                  id="seoul-gu-src"
                  type="geojson"
                  data={SEOUL_GU_URL}
                />

                {/* Living Area Boundary Highlight (Deep Violet / Soft Lilac) */}
                {selectedLivingArea && LIVING_AREA_GUS[selectedLivingArea] && (
                  <Layer
                    id="gtwr-living-area-boundary"
                    type="line"
                    source="seoul-gu-src"
                    filter={["in", ["get", "gu_name"], ["literal", LIVING_AREA_GUS[selectedLivingArea]]]}
                    paint={{
                      "line-color": theme === "dark" ? "#a78bfa" : "#8b5cf6",
                      "line-width": selectedGu ? 1.8 : 3.0,
                      "line-opacity": selectedGu ? 0.65 : 1.0,
                      ...(selectedGu ? { "line-dasharray": [3, 2] } : {}),
                    }}
                  />
                )}

                {/* Specific District (Gu) Outer Perimeter Boundary Highlight (Electric Indigo / Neon Indigo) */}
                {selectedGu && (
                  <Layer
                    id="gtwr-gu-outer-boundary"
                    type="line"
                    source="seoul-gu-src"
                    filter={["==", ["get", "gu_name"], selectedGu]}
                    paint={{
                      "line-color": theme === "dark" ? "#818cf8" : "#6366f1",
                      "line-width": 3.2,
                      "line-opacity": 1.0,
                    }}
                  />
                )}
              </>
            )}

            {/* Scatter Hover Highlight Stroke (Golden Amber) */}
            <Layer
              id="gtwr-scatter-hover-line"
              type="line"
              source="gtwr"
              filter={["==", ["get", "adm_cd"], hoveredScatterAdmCd ?? ""]}
              paint={{
                "line-color": theme === "dark" ? "#fcd34d" : "#f59e0b",
                "line-width": 3.0,
                "line-opacity": 1.0,
              }}
            />

            {/* Mouse Hover highlight stroke */}
            <Layer
              id="gtwr-hover-line"
              type="line"
              source="gtwr"
              filter={["==", ["get", "adm_cd"], hoveredInfo?.admCd ?? ""]}
              paint={{
                "line-color": theme === "dark" ? "#e0e7ff" : "#1e1b4b",
                "line-width": 2.4,
                "line-opacity": 1.0,
              }}
            />

            {/* Primary Selected Dong stroke (Midnight Charcoal / Crystal White) */}
            <Layer
              id="gtwr-selected-line"
              type="line"
              source="gtwr"
              filter={["==", ["get", "adm_cd"], selectedAdmCd ?? ""]}
              paint={{
                "line-color": theme === "dark" ? "#ffffff" : "#0f172a",
                "line-width": 3.0,
                "line-opacity": 1.0,
              }}
            />

            {/* Secondary Comparison Dong stroke (Warm Amber) */}
            <Layer
              id="gtwr-compare-line"
              type="line"
              source="gtwr"
              filter={["==", ["get", "adm_cd"], compareAdmCd ?? ""]}
              paint={{
                "line-color": theme === "dark" ? "#fbbf24" : "#f59e0b",
                "line-width": 3.2,
                "line-opacity": 1.0,
              }}
            />
          </>
        )}
      </Map>

      <MapSpecOverlay isSidebarOpen={isSidebarOpen} />

      <Legend
        view={view}
        breaks={breaks}
        selectedYq={selectedYq}
        features={features}
      />

      {hoveredInfo && !selectedAdmCd && (
        <HoverTooltip
          x={hoveredInfo.x}
          y={hoveredInfo.y}
          props={hoveredInfo.props}
        />
      )}
    </section>
  );
}
