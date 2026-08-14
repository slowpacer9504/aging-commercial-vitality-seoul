import type { FC } from "react";
import { useAppStore } from "@/state/store";

export interface MobileBottomNavProps {
  onOpenControls: () => void;
  onOpenScatter: () => void;
  onStartTour: () => void;
  isSidebarOpen: boolean;
}

export const MobileBottomNav: FC<MobileBottomNavProps> = ({
  onOpenControls,
  onOpenScatter,
  onStartTour,
  isSidebarOpen,
}) => {
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);

  const handleMapClick = () => {
    if (selectedAdmCd) {
      selectAdmCd(null);
    }
  };

  return (
    <nav className="mobile-bottom-nav" aria-label="Mobile Bottom Navigation">
      <button
        type="button"
        className={`mobile-nav-btn ${!isSidebarOpen && !selectedAdmCd ? "is-active" : ""}`}
        onClick={handleMapClick}
        aria-label="Map view"
      >
        <span className="mobile-nav-icon" aria-hidden="true">🗺️</span>
        <span className="mobile-nav-label">Map</span>
      </button>

      <button
        type="button"
        className={`mobile-nav-btn ${isSidebarOpen ? "is-active" : ""}`}
        onClick={onOpenControls}
        aria-label="Open model and spatial controls"
      >
        <span className="mobile-nav-icon" aria-hidden="true">🎛️</span>
        <span className="mobile-nav-label">Controls</span>
      </button>

      <button
        type="button"
        className="mobile-nav-btn"
        onClick={onOpenScatter}
        aria-label="Open dynamics scatter trajectory plot"
      >
        <span className="mobile-nav-icon" aria-hidden="true">📈</span>
        <span className="mobile-nav-label">Dynamics</span>
      </button>

      <button
        type="button"
        className="mobile-nav-btn"
        onClick={onStartTour}
        aria-label="Start key findings story tour"
      >
        <span className="mobile-nav-icon" aria-hidden="true">💡</span>
        <span className="mobile-nav-label">Tour</span>
      </button>
    </nav>
  );
};
