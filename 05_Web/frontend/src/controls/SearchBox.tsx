import { useState, useEffect, useRef, useMemo, type FC } from "react";
import { staticGetLookup } from "@/api/staticFallback";
import { useAppStore } from "@/state/store";
import type { LookupRow } from "@/types/api";

export const SearchBox: FC = () => {
  const selectAdmCd = useAppStore(s => s.selectAdmCd);
  const selectedAdmCd = useAppStore(s => s.selectedAdmCd);

  const [lookup, setLookup] = useState<Record<string, LookupRow>>({});
  const [query, setQuery] = useState("");
  const [isOpen, setIsOpen] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    staticGetLookup()
      .then(setLookup)
      .catch(() => setLookup({}));
  }, []);

  // Close dropdown on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Filter dongs by query
  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    const list = Object.values(lookup);
    return list
      .filter(item => {
        const dong = (item.adm_nm || "").toLowerCase();
        const gu = (item.gu_name || "").toLowerCase();
        const code = item.adm_cd.toLowerCase();
        return dong.includes(q) || gu.includes(q) || code.includes(q);
      })
      .slice(0, 10);
  }, [lookup, query]);

  const handleSelect = (item: LookupRow) => {
    selectAdmCd(item.adm_cd);
    setQuery("");
    setIsOpen(false);
  };

  const selectedDongName = selectedAdmCd && lookup[selectedAdmCd]
    ? `${lookup[selectedAdmCd].adm_nm} (${lookup[selectedAdmCd].gu_name})`
    : null;

  return (
    <div className="search-box-wrap" ref={wrapperRef}>
      <div className="search-input-container">
        <span className="search-icon" aria-hidden="true">🔍</span>
        <input
          type="text"
          className="search-input"
          placeholder="Search dong (e.g. 역삼1동, 연남동, 강남구)…"
          value={query}
          onChange={e => {
            setQuery(e.target.value);
            setIsOpen(true);
          }}
          onFocus={() => {
            if (query.trim()) setIsOpen(true);
          }}
          aria-label="Search administrative dong"
        />
        {query && (
          <button
            type="button"
            className="search-clear-btn"
            onClick={() => {
              setQuery("");
              setIsOpen(false);
            }}
            aria-label="Clear search"
          >
            ×
          </button>
        )}
      </div>

      {isOpen && results.length > 0 && (
        <ul className="search-results-dropdown" role="listbox">
          {results.map(item => (
            <li
              key={item.adm_cd}
              className="search-result-item"
              role="option"
              aria-selected={item.adm_cd === selectedAdmCd}
              onClick={() => handleSelect(item)}
            >
              <div className="res-main">
                <span className="res-dong">{item.adm_nm}</span>
                <span className="res-gu">{item.gu_name}</span>
              </div>
              <span className="res-code">{item.adm_cd}</span>
            </li>
          ))}
        </ul>
      )}

      {selectedDongName && !isOpen && (
        <div className="selected-dong-badge">
          <span>📍 Selected: <strong>{selectedDongName}</strong></span>
          <button
            type="button"
            className="badge-clear"
            onClick={() => selectAdmCd(null)}
            aria-label="Deselect dong"
          >
            ×
          </button>
        </div>
      )}
    </div>
  );
};
