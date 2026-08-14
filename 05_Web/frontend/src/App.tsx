import { useEffect, useState, useRef } from "react";
import { MapView, type MapViewHandle } from "@/map/MapView";
import { FeaturePopup } from "@/map/popup/FeaturePopup";
import { OutcomeSelector } from "@/controls/OutcomeSelector";
import { ControlSetSelector } from "@/controls/ControlSetSelector";
import { ViewModeSelector } from "@/controls/ViewModeSelector";
import { QuarterSelector } from "@/controls/QuarterSelector";
import { SearchBox } from "@/controls/SearchBox";
import { GuFilterSelector } from "@/controls/GuFilterSelector";
import { ExportMenu } from "@/controls/ExportMenu";
import { ResearchGuideModal } from "@/controls/ResearchGuideModal";
import { StoryTourBanner } from "@/tour/StoryTourBanner";
import { LinkedScatterPlot } from "@/sidebar/LinkedScatterPlot";
import { GlobalSummary } from "@/sidebar/GlobalSummary";
import { useAppStore } from "@/state/store";
import { getMeta } from "@/api/endpoints";
import { exportMapCanvasToPng } from "@/utils/exportUtils";
import type { MetaResponse } from "@/types/api";

export function App() {
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const theme = useAppStore(s => s.theme);
  const setTheme = useAppStore(s => s.setTheme);
  const setTourStep = useAppStore(s => s.setTourStep);

  const [meta, setMeta] = useState<MetaResponse | null>(null);
  const [metaError, setMetaError] = useState<string | null>(null);
  const [isGuideOpen, setIsGuideOpen] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);
  const mapHandleRef = useRef<MapViewHandle>(null);

  useEffect(() => {
    getMeta()
      .then(setMeta)
      .catch(e => setMetaError(String(e?.message ?? e)));
  }, []);

  const handleExportMapPng = () => {
    const mapRef = mapHandleRef.current?.getMapRef();
    if (mapRef) {
      exportMapCanvasToPng(mapRef, "seoul_gtwr_choropleth.png");
    }
  };

  const handleMoveCamera = (center: [number, number], zoom: number) => {
    mapHandleRef.current?.flyTo(center, zoom);
  };

  const toggleTheme = () => {
    setTheme(theme === "light" ? "dark" : "light");
  };

  return (
    <div className={`app-root ${theme === "dark" ? "theme-dark" : "theme-light"}`}>
      {/* Header */}
      <header className="app-header">
        <div className="header-brand">
          <div className="brand-badge-wrap">
            <span className="brand-badge">Academic Explorer</span>
            <span className="brand-badge sub">GTWR Spatiotemporal Model</span>
          </div>
          <h1 className="header-title">Seoul Aging & Commercial Vitality Explorer</h1>
          <p className="header-subtitle">
            Local spatial heterogeneity of residential aging effects (<code>lag4_age60_resident_share</code>) across 425 administrative dongs (2019Q4–2025Q4).
          </p>
        </div>

        <div className="header-actions">
          <button
            type="button"
            className="tour-trigger-btn"
            onClick={() => setTourStep(0)}
            aria-label="Start Key Findings Guided Tour"
            title="Start Key Findings Guided Tour"
          >
            <span className="tour-icon" aria-hidden="true">💡</span>
            <span>Key Findings Tour</span>
          </button>

          <ExportMenu onExportMapPng={handleExportMapPng} />

          <button
            type="button"
            className="guide-trigger-btn"
            onClick={() => setIsGuideOpen(true)}
            aria-label="Open research guide modal"
          >
            <span className="guide-icon" aria-hidden="true">ℹ</span>
            <span>Research Guide</span>
          </button>

          <button
            type="button"
            className="theme-toggle-btn"
            onClick={toggleTheme}
            aria-label={`Switch to ${theme === "light" ? "dark" : "light"} mode`}
            title={`Switch to ${theme === "light" ? "dark" : "light"} mode`}
          >
            {theme === "light" ? "🌙 Dark" : "☀️ Light"}
          </button>
        </div>
      </header>

      {/* Main Workspace Layout */}
      <div className={`app-workspace ${isSidebarOpen ? "sidebar-expanded" : "sidebar-collapsed"}`}>
        {/* Left Sidebar */}
        <aside className="app-sidebar" aria-label="Explorer Controls and Summary">
          <div className="sidebar-top-bar">
            <span className="sidebar-heading">Model & Spatial Controls</span>
            <button
              type="button"
              className="sidebar-collapse-btn"
              onClick={() => setIsSidebarOpen(false)}
              aria-label="Collapse sidebar"
              title="Collapse sidebar"
            >
              ◀
            </button>
          </div>

          <div className="sidebar-scrollable-content">
            <SearchBox />
            <GuFilterSelector />

            <div className="controls-group">
              <OutcomeSelector />
              <ControlSetSelector />
              <ViewModeSelector />
              <QuarterSelector />
            </div>

            <LinkedScatterPlot />

            {meta && (
              <div className="meta-stats-card">
                <div className="meta-stat-row">
                  <span className="meta-k">Study Units</span>
                  <span className="meta-v">{meta.n_locations} Admin Dongs</span>
                </div>
                <div className="meta-stat-row">
                  <span className="meta-k">Boundary Coverage</span>
                  <span className="meta-v">{meta.coverage_percent.toFixed(1)}% Matched</span>
                </div>
                <div className="meta-stat-row">
                  <span className="meta-k">Spatial Projection</span>
                  <span className="meta-v">{meta.crs}</span>
                </div>
              </div>
            )}

            {metaError && (
              <div className="meta-error" role="alert">
                meta: {metaError}
              </div>
            )}

            <GlobalSummary />
          </div>
        </aside>

        {/* Floating Expand Button when Sidebar is Collapsed */}
        {!isSidebarOpen && (
          <button
            type="button"
            className="sidebar-expand-btn"
            onClick={() => setIsSidebarOpen(true)}
            aria-label="Expand sidebar"
            title="Expand sidebar"
          >
            ▶ Control Panel
          </button>
        )}

        {/* Map View & Floating Drawer */}
        <main className="app-main-viewport">
          <MapView ref={mapHandleRef} />
          <StoryTourBanner onMoveCamera={handleMoveCamera} />
          {selectedAdmCd && <FeaturePopup />}
        </main>
      </div>

      {/* Footer */}
      <footer className="app-footer">
        <div className="footer-left">
          <span>Seoul Commercial Vitality & Aging Spatiotemporal GTWR Explorer</span>
        </div>
        <div className="footer-right">
          <span>Data: Seoul Commercial Analysis Service · 425 Administrative Dongs (2019Q4–2025Q4)</span>
        </div>
      </footer>

      {/* Research Guide Modal */}
      <ResearchGuideModal
        isOpen={isGuideOpen}
        onClose={() => setIsGuideOpen(false)}
      />
    </div>
  );
}
