import { useEffect, useState, useRef, type FC } from "react";
import { getMeta } from "@/api/endpoints";
import { useAppStore } from "@/state/store";

export const QuarterSelector: FC = () => {
  const view = useAppStore(s => s.view);
  const setView = useAppStore(s => s.setView);
  const selectedYq = useAppStore(s => s.selectedYq);
  const setSelectedYq = useAppStore(s => s.setSelectedYq);

  const [quarters, setQuarters] = useState<string[]>([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const playTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    let cancelled = false;
    getMeta()
      .then(m => {
        if (!cancelled && Array.isArray(m.panel_quarters)) {
          setQuarters(m.panel_quarters);
        }
      })
      .catch(() => {
        // Fallback default quarters if meta fails
        setQuarters([
          "2019Q4", "2020Q1", "2020Q2", "2020Q3", "2020Q4",
          "2021Q1", "2021Q2", "2021Q3", "2021Q4",
          "2022Q1", "2022Q2", "2022Q3", "2022Q4",
          "2023Q1", "2023Q2", "2023Q3", "2023Q4",
          "2024Q1", "2024Q2", "2024Q3", "2024Q4",
          "2025Q1", "2025Q2", "2025Q3", "2025Q4",
        ]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const currentIndex = quarters.indexOf(selectedYq);
  const activeIndex = currentIndex >= 0 ? currentIndex : quarters.length - 1;

  // Auto-play effect
  useEffect(() => {
    if (isPlaying) {
      playTimerRef.current = setInterval(() => {
        useAppStore.setState(s => {
          const idx = quarters.indexOf(s.selectedYq);
          const nextIdx = idx >= 0 && idx < quarters.length - 1 ? idx + 1 : 0;
          return { selectedYq: quarters[nextIdx] ?? s.selectedYq, view: "quarter" };
        });
      }, 1100);
    } else {
      if (playTimerRef.current) {
        clearInterval(playTimerRef.current);
        playTimerRef.current = null;
      }
    }
    return () => {
      if (playTimerRef.current) clearInterval(playTimerRef.current);
    };
  }, [isPlaying, quarters]);

  // Stop playing if user switches to latest or delta
  useEffect(() => {
    if (view !== "quarter" && isPlaying) {
      setIsPlaying(false);
    }
  }, [view, isPlaying]);

  const handlePrev = () => {
    if (activeIndex > 0) {
      setSelectedYq(quarters[activeIndex - 1]!);
      if (view !== "quarter") setView("quarter");
    }
  };

  const handleNext = () => {
    if (activeIndex < quarters.length - 1) {
      setSelectedYq(quarters[activeIndex + 1]!);
      if (view !== "quarter") setView("quarter");
    }
  };

  const handleSliderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const idx = parseInt(e.target.value, 10);
    const q = quarters[idx];
    if (q) {
      setSelectedYq(q);
      if (view !== "quarter") setView("quarter");
    }
  };

  const togglePlay = () => {
    if (!isPlaying) {
      if (view !== "quarter") setView("quarter");
      setIsPlaying(true);
    } else {
      setIsPlaying(false);
    }
  };

  return (
    <div
      className={`control timeline-selector ${view === "quarter" ? "is-focused" : ""}`}
      role="group"
      aria-labelledby="quarter-label"
    >
      <div className="control-header">
        <label id="quarter-label" className="control-label">
          Spatiotemporal Timeline
        </label>
        <span className="quarter-current-badge">{selectedYq}</span>
      </div>

      <div className="timeline-controls">
        <button
          type="button"
          className={`timeline-btn play-btn ${isPlaying ? "is-playing" : ""}`}
          onClick={togglePlay}
          aria-label={isPlaying ? "Pause animation" : "Play timeline animation"}
        >
          {isPlaying ? "⏸ Pause" : "▶ Play (2019-2025)"}
        </button>
        <div className="timeline-nav-group">
          <button
            type="button"
            className="timeline-step-btn"
            onClick={handlePrev}
            disabled={activeIndex <= 0}
            aria-label="Previous quarter"
          >
            ◀
          </button>
          <button
            type="button"
            className="timeline-step-btn"
            onClick={handleNext}
            disabled={activeIndex >= quarters.length - 1}
            aria-label="Next quarter"
          >
            ▶
          </button>
        </div>
      </div>

      <div className="timeline-slider-wrap">
        <input
          type="range"
          min={0}
          max={Math.max(0, quarters.length - 1)}
          value={activeIndex}
          onChange={handleSliderChange}
          className="timeline-slider"
          aria-label="Quarter slider"
        />
        <div className="timeline-ticks">
          <span>2019Q4</span>
          <span>2022Q4</span>
          <span>2025Q4</span>
        </div>
      </div>
    </div>
  );
};
