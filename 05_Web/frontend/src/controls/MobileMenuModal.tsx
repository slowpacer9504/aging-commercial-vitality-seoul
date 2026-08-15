import { useState, type FC } from "react";
import { useAppStore } from "@/state/store";
import { exportFeaturesToCsv, generateCoeffCsvFilename } from "@/utils/exportUtils";
import { getCoefficients } from "@/api/endpoints";

export interface MobileMenuModalProps {
  isOpen: boolean;
  onClose: () => void;
  onStartTour: () => void;
  onOpenScatter: () => void;
  onExportMapPng: () => void;
  onOpenGuide: () => void;
}

export const MobileMenuModal: FC<MobileMenuModalProps> = ({
  isOpen,
  onClose,
  onStartTour,
  onOpenScatter,
  onExportMapPng,
  onOpenGuide,
}) => {
  const theme = useAppStore(s => s.theme);
  const setTheme = useAppStore(s => s.setTheme);
  const controlSet = useAppStore(s => s.controlSet);
  const outcome = useAppStore(s => s.outcome);
  const selectedYq = useAppStore(s => s.selectedYq);
  const selectedGu = useAppStore(s => s.selectedGu);
  const view = useAppStore(s => s.view);

  const [copied, setCopied] = useState(false);

  if (!isOpen) return null;

  const handleToggleTheme = () => {
    setTheme(theme === "light" ? "dark" : "light");
  };

  const handleCopyLink = async () => {
    try {
      await navigator.clipboard.writeText(window.location.href);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      const input = document.createElement("input");
      input.value = window.location.href;
      document.body.appendChild(input);
      input.select();
      document.execCommand("copy");
      document.body.removeChild(input);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleExportCsv = async () => {
    try {
      const fc = await getCoefficients(
        controlSet,
        outcome,
        view,
        view === "quarter" ? selectedYq : undefined,
      );
      const filename = generateCoeffCsvFilename(outcome, controlSet, view, selectedYq, selectedGu);
      exportFeaturesToCsv(fc.features, filename);
      onClose();
    } catch (e) {
      alert("Failed to export coefficient data: " + String(e));
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose} role="dialog" aria-modal="true">
      <div
        className="mobile-settings-sheet"
        onClick={e => e.stopPropagation()}
        aria-label="Settings and Tools Menu"
      >
        <div className="sheet-drag-handle-wrap" aria-hidden="true">
          <div className="sheet-drag-handle" />
        </div>

        <header className="mobile-settings-header">
          <div className="settings-header-title">
            <span className="settings-icon">⚙️</span>
            <h3>Settings & Tools</h3>
          </div>
          <button
            type="button"
            className="drawer-close-btn"
            onClick={onClose}
            aria-label="Close settings menu"
          >
            ✕
          </button>
        </header>

        <div className="mobile-settings-content">
          {/* Section 1: Appearance */}
          <div className="settings-section">
            <div className="settings-section-title">Appearance</div>
            <div className="settings-action-row theme-toggle-row">
              <div className="setting-info">
                <span className="setting-icon">{theme === "dark" ? "🌙" : "☀️"}</span>
                <div className="setting-texts">
                  <span className="setting-name">Dark Mode</span>
                  <span className="setting-desc">
                    {theme === "dark" ? "Dark Carto Basemap" : "Light Positron Basemap"}
                  </span>
                </div>
              </div>
              <button
                type="button"
                className={`theme-switch-btn ${theme === "dark" ? "is-dark" : ""}`}
                onClick={handleToggleTheme}
                aria-label="Toggle dark mode"
              >
                <div className="switch-knob" />
              </button>
            </div>
          </div>

          {/* Section 2: Interactive Exploration */}
          <div className="settings-section">
            <div className="settings-section-title">Interactive Analysis</div>
            <button
              type="button"
              className="settings-action-row"
              onClick={() => {
                onClose();
                onStartTour();
              }}
            >
              <div className="setting-info">
                <span className="setting-icon">💡</span>
                <div className="setting-texts">
                  <span className="setting-name">Key Findings Tour</span>
                  <span className="setting-desc">5-scene guided academic walkthrough</span>
                </div>
              </div>
              <span className="setting-arrow">›</span>
            </button>

            <button
              type="button"
              className="settings-action-row"
              onClick={() => {
                onClose();
                onOpenScatter();
              }}
            >
              <div className="setting-info">
                <span className="setting-icon">📈</span>
                <div className="setting-texts">
                  <span className="setting-name">Dynamics Scatter Plot</span>
                  <span className="setting-desc">Earliest (2019Q4) vs Latest (2025Q4) Trajectory</span>
                </div>
              </div>
              <span className="setting-arrow">›</span>
            </button>
          </div>

          {/* Section 3: Share & Export */}
          <div className="settings-section">
            <div className="settings-section-title">Share & Export</div>
            <button
              type="button"
              className="settings-action-row"
              onClick={() => {
                onClose();
                onExportMapPng();
              }}
            >
              <div className="setting-info">
                <span className="setting-icon">📸</span>
                <div className="setting-texts">
                  <span className="setting-name">Export Map View (PNG)</span>
                  <span className="setting-desc">High-resolution publication image with legend</span>
                </div>
              </div>
              <span className="setting-arrow">›</span>
            </button>

            <button
              type="button"
              className="settings-action-row"
              onClick={handleExportCsv}
            >
              <div className="setting-info">
                <span className="setting-icon">📊</span>
                <div className="setting-texts">
                  <span className="setting-name">Download Active Layer (CSV)</span>
                  <span className="setting-desc">425 dong estimates ({controlSet.toUpperCase()}, {view})</span>
                </div>
              </div>
              <span className="setting-arrow">›</span>
            </button>

            <button
              type="button"
              className="settings-action-row"
              onClick={handleCopyLink}
            >
              <div className="setting-info">
                <span className="setting-icon">{copied ? "✅" : "🔗"}</span>
                <div className="setting-texts">
                  <span className="setting-name">
                    {copied ? "Link Copied to Clipboard!" : "Copy Shareable Link"}
                  </span>
                  <span className="setting-desc">Share current specification and view</span>
                </div>
              </div>
              <span className="setting-arrow">{copied ? "✓" : "›"}</span>
            </button>
          </div>

          {/* Section 4: Research Reference */}
          <div className="settings-section">
            <div className="settings-section-title">Documentation</div>
            <button
              type="button"
              className="settings-action-row"
              onClick={() => {
                onClose();
                onOpenGuide();
              }}
            >
              <div className="setting-info">
                <span className="setting-icon">ℹ️</span>
                <div className="setting-texts">
                  <span className="setting-name">Research Guide & Model Spec</span>
                  <span className="setting-desc">Econometric methods, variable codebook & citations</span>
                </div>
              </div>
              <span className="setting-arrow">›</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
