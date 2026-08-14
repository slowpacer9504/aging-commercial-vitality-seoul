import { useState, useRef, useEffect, type FC } from "react";
import { useAppStore } from "@/state/store";
import { exportFeaturesToCsv, generateCoeffCsvFilename } from "@/utils/exportUtils";
import { getCoefficients } from "@/api/endpoints";

interface Props {
  onExportMapPng?: () => void;
}

export const ExportMenu: FC<Props> = ({ onExportMapPng }) => {
  const outcome = useAppStore(s => s.outcome);
  const controlSet = useAppStore(s => s.controlSet);
  const view = useAppStore(s => s.view);
  const selectedYq = useAppStore(s => s.selectedYq);

  const selectedGu = useAppStore(s => s.selectedGu);

  const [isOpen, setIsOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [isExportingCsv, setIsExportingCsv] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleCopyLink = async () => {
    try {
      await navigator.clipboard.writeText(window.location.href);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback if clipboard API is blocked
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
      setIsExportingCsv(true);
      const fc = await getCoefficients(
        controlSet,
        outcome,
        view,
        view === "quarter" ? selectedYq : undefined,
      );
      const filename = generateCoeffCsvFilename(outcome, controlSet, view, selectedYq, selectedGu);
      exportFeaturesToCsv(fc.features, filename);
    } catch (err) {
      console.error("Failed to export CSV:", err);
    } finally {
      setIsExportingCsv(false);
      setIsOpen(false);
    }
  };

  return (
    <div className="export-menu-wrap" ref={menuRef}>
      <button
        type="button"
        className="export-trigger-btn"
        onClick={() => setIsOpen(!isOpen)}
        aria-expanded={isOpen}
        aria-haspopup="true"
      >
        <span className="export-icon" aria-hidden="true">📤</span>
        <span>Share & Export</span>
      </button>

      {isOpen && (
        <div className="export-dropdown-card" role="menu">
          <div className="dropdown-section">
            <span className="dropdown-label">Collaboration</span>
            <button
              type="button"
              className="dropdown-item"
              onClick={handleCopyLink}
              role="menuitem"
            >
              <span className="item-icon">{copied ? "✓" : "🔗"}</span>
              <div className="item-text">
                <span className="item-title">{copied ? "Link Copied to Clipboard!" : "Copy Shareable Link"}</span>
                <span className="item-desc">Includes current variables, dong & quarter state</span>
              </div>
            </button>
          </div>

          <div className="dropdown-section">
            <span className="dropdown-label">Data & Media Export</span>
            {onExportMapPng && (
              <button
                type="button"
                className="dropdown-item"
                onClick={() => {
                  onExportMapPng();
                  setIsOpen(false);
                }}
                role="menuitem"
              >
                <span className="item-icon">📷</span>
                <div className="item-text">
                  <span className="item-title">Export Map as PNG</span>
                  <span className="item-desc">High-resolution map image for paper/slides</span>
                </div>
              </button>
            )}

            <button
              type="button"
              className="dropdown-item"
              onClick={handleExportCsv}
              disabled={isExportingCsv}
              role="menuitem"
            >
              <span className="item-icon">📊</span>
              <div className="item-text">
                <span className="item-title">
                  {isExportingCsv ? "Preparing CSV…" : "Export Coefficients (CSV)"}
                </span>
                <span className="item-desc">425 dong spatial estimates (Excel compatible)</span>
              </div>
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
