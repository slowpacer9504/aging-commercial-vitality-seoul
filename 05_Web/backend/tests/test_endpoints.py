"""Smoke tests for the GTWR explorer backend endpoints (synchronous)."""
from __future__ import annotations


def test_health(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    j = r.json()
    assert j["ok"] is True
    m = j["manifest"]
    assert int(m["geojson_features"]) == 425
    assert float(m["csv_adm_cd_match_percent"]) == 100.0
    assert m["crs_out"] == "EPSG:4326"


def test_meta(client):
    r = client.get("/api/meta")
    assert r.status_code == 200
    j = r.json()
    assert j["outcomes"] == [
        "vitality_index_base",
        "vitality_sub_economic",
        "vitality_sub_social",
        "vitality_sub_stability",
        "vitality_sub_temporal",
    ]
    assert j["control_sets"] == ["lean", "extended"]
    assert j["focal_var"] == ["lag4_age60_resident_share"]
    assert j["target_yq"] == ["2025Q4"]
    assert j["n_locations"] == 425
    assert j["coverage_percent"] == 100.0
    assert j["crs"] == "EPSG:4326"
    assert len(j["estimate_breaks"]) == 9
    assert 0.0 in j["estimate_breaks"]


def test_coefficients_valid(client):
    r = client.get("/api/coefficients/lean/vitality_index_base")
    assert r.status_code == 200
    j = r.json()
    assert j["type"] == "FeatureCollection"
    assert len(j["features"]) == 425
    f = j["features"][0]
    assert f["type"] == "Feature"
    assert f["geometry"]["type"] in {"Polygon", "MultiPolygon"}
    p = f["properties"]
    assert p["outcome"] == "vitality_index_base"
    assert p["control_set"] == "lean"
    assert p["target_yq"] == "2025Q4"
    assert "estimate" in p
    assert isinstance(p["collinearity_warn_flag"], bool)
    assert p["adm_nm"]


def test_coefficients_invalid_outcome(client):
    r = client.get("/api/coefficients/lean/not_a_real_outcome")
    assert r.status_code == 422
    assert isinstance(r.json()["detail"], dict)
    assert r.json()["detail"]["code"] == "invalid_outcome"


def test_coefficients_extended(client):
    r = client.get("/api/coefficients/extended/vitality_sub_economic")
    assert r.status_code == 200
    j = r.json()
    assert len(j["features"]) == 425
    assert all(f["properties"]["control_set"] == "extended" for f in j["features"])


def test_panel_returns_25_quarters(client):
    r = client.get(
        "/api/panel/0011110515",
        params={"outcome": "vitality_sub_economic", "control_set": "lean"},
    )
    assert r.status_code == 200
    j = r.json()
    assert j["adm_cd"] == "0011110515"
    assert j["adm_nm"] == "청운효자동"
    assert j["gu_name"] == "종로구"
    assert j["outcome"] == "vitality_sub_economic"
    assert j["control_set"] == "lean"
    assert len(j["points"]) == 25
    assert j["points"][0]["yq"] == "2019Q4"
    assert j["points"][-1]["yq"] == "2025Q4"


def test_panel_unknown_adm_cd_returns_404(client):
    r = client.get("/api/panel/9999999999", params={"outcome": "vitality_index_base"})
    assert r.status_code == 404
    assert r.json()["detail"]["code"] == "unknown_adm_cd"


def test_panel_q_window(client):
    r = client.get(
        "/api/panel/0011110515",
        params={
            "outcome": "vitality_index_base",
            "control_set": "lean",
            "q_start": "2022Q1",
            "q_end": "2023Q4",
        },
    )
    assert r.status_code == 200
    j = r.json()
    assert len(j["points"]) == 8
    assert j["points"][0]["yq"] == "2022Q1"
    assert j["points"][-1]["yq"] == "2023Q4"


def test_summary_lean(client):
    r = client.get("/api/summary/lean")
    assert r.status_code == 200
    j = r.json()
    assert j["control_set"] == "lean"
    assert len(j["summaries"]) == 5
    outs = {s["outcome"] for s in j["summaries"]}
    assert "vitality_index_base" in outs


def test_assets_geojson(client):
    r = client.get("/assets/seoul_adm_dong.geojson")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("application/geo+json")
    g = r.json()
    assert g["type"] == "FeatureCollection"
    assert len(g["features"]) == 425


def test_coefficients_has_view_field(client):
    r = client.get("/api/coefficients/lean/vitality_index_base")
    assert r.status_code == 200
    j = r.json()
    assert all(f["properties"]["view"] == "latest" for f in j["features"])


def test_coefficients_quarter_view(client):
    r = client.get(
        "/api/coefficients/lean/vitality_index_base",
        params={"view": "quarter", "yq": "2023Q2"},
    )
    assert r.status_code == 200
    j = r.json()
    assert len(j["features"]) == 425
    assert all(f["properties"]["view"] == "quarter" for f in j["features"])
    assert all(f["properties"]["target_yq"] == "2023Q2" for f in j["features"])
    # Some dongs may lack a panel row for this quarter -> estimate None allowed.
    estimates = [f["properties"]["estimate"] for f in j["features"]]


def test_coefficients_delta_view(client):
    r = client.get(
        "/api/coefficients/lean/vitality_index_base",
        params={"view": "delta"},
    )
    assert r.status_code == 200
    j = r.json()
    assert len(j["features"]) == 425
    assert all(f["properties"]["view"] == "delta" for f in j["features"])
    # delta == latest - earliest (spot-check one dong).
    f0 = j["features"][0]["properties"]
    expected = None
    if f0["latest_estimate"] is not None and f0["earliest_estimate"] is not None:
        expected = f0["latest_estimate"] - f0["earliest_estimate"]
    assert f0["estimate"] == expected


def test_coefficients_quarter_requires_yq(client):
    r = client.get(
        "/api/coefficients/lean/vitality_index_base",
        params={"view": "quarter"},
    )
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "missing_yq"


def test_coefficients_invalid_view(client):
    r = client.get(
        "/api/coefficients/lean/vitality_index_base",
        params={"view": "bogus"},
    )
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "invalid_view"


def test_coefficients_invalid_yq(client):
    r = client.get(
        "/api/coefficients/lean/vitality_index_base",
        params={"view": "quarter", "yq": "1999Q1"},
    )
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "invalid_yq"


def test_meta_exposes_delta_fields(client):
    r = client.get("/api/meta")
    assert r.status_code == 200
    j = r.json()
    assert len(j["delta_breaks"]) == 9
    assert 0.0 in j["delta_breaks"]
    assert j["delta_earliest_yq"] == "2019Q4"
    assert j["delta_latest_yq"] == "2025Q4"
    assert len(j["panel_quarters"]) == 25
