import { useEffect, type FC } from "react";
import { useAppStore } from "@/state/store";
import { TOUR_SCENES } from "./storyTourData";

interface Props {
  onMoveCamera?: (center: [number, number], zoom: number) => void;
}

export const StoryTourBanner: FC<Props> = ({ onMoveCamera }) => {
  const tourStep = useAppStore(s => s.tourStep);
  const setTourStep = useAppStore(s => s.setTourStep);
  const setOutcome = useAppStore(s => s.setOutcome);
  const setView = useAppStore(s => s.setView);
  const setSelectedYq = useAppStore(s => s.setSelectedYq);
  const setSelectedLivingArea = useAppStore(s => s.setSelectedLivingArea);
  const setSelectedGu = useAppStore(s => s.setSelectedGu);
  const selectAdmCd = useAppStore(s => s.selectAdmCd);

  const currentScene = tourStep != null ? TOUR_SCENES[tourStep] : null;

  // Apply scene settings to store and camera when tourStep changes
  useEffect(() => {
    if (!currentScene) return;

    setOutcome(currentScene.outcome);
    setView(currentScene.view);
    setSelectedYq(currentScene.selectedYq);
    setSelectedLivingArea(currentScene.selectedLivingArea ?? null);
    setSelectedGu(currentScene.selectedGu);
    selectAdmCd(currentScene.selectedAdmCd);

    if (onMoveCamera) {
      onMoveCamera(currentScene.camera.center, currentScene.camera.zoom);
    }
  }, [
    currentScene,
    setOutcome,
    setView,
    setSelectedYq,
    setSelectedLivingArea,
    setSelectedGu,
    selectAdmCd,
    onMoveCamera,
  ]);

  if (tourStep == null || !currentScene) return null;

  const isFirst = tourStep === 0;
  const isLast = tourStep === TOUR_SCENES.length - 1;

  const handleNext = () => {
    if (isLast) {
      setTourStep(null);
      setSelectedLivingArea(null);
      setSelectedGu(null);
      selectAdmCd(null);
    } else {
      setTourStep(tourStep + 1);
    }
  };

  const handlePrev = () => {
    if (!isFirst) {
      setTourStep(tourStep - 1);
    }
  };

  const handleExit = () => {
    setTourStep(null);
    setSelectedLivingArea(null);
    setSelectedGu(null);
    selectAdmCd(null);
  };

  return (
    <div className="story-tour-banner-wrap" role="region" aria-label="Interactive Research Tour">
      <div className="story-tour-card">
        <div className="tour-header">
          <div className="tour-badge-row">
            <span className="tour-live-dot">●</span>
            <span className="tour-badge">Key Findings Guided Tour</span>
            <span className="tour-step-indicator">
              Scene {tourStep + 1} of {TOUR_SCENES.length}
            </span>
          </div>
          <button
            type="button"
            className="tour-exit-btn"
            onClick={handleExit}
            aria-label="Exit story tour"
            title="Exit tour"
          >
            ✕ Exit Tour
          </button>
        </div>

        <div className="tour-body">
          <h3 className="tour-title">{currentScene.title}</h3>
          <p className="tour-desc">{currentScene.description}</p>
        </div>

        <div className="tour-footer">
          <div className="tour-dots">
            {TOUR_SCENES.map((_, idx) => (
              <span
                key={idx}
                className={`tour-dot ${idx === tourStep ? "is-active" : ""}`}
                onClick={() => setTourStep(idx)}
              />
            ))}
          </div>

          <div className="tour-nav-btns">
            <button
              type="button"
              className="tour-btn secondary"
              onClick={handlePrev}
              disabled={isFirst}
            >
              ◀ Previous
            </button>
            <button
              type="button"
              className="tour-btn primary"
              onClick={handleNext}
            >
              {isLast ? "Finish Tour ✓" : "Next Scene ▶"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
