"""Tests for render-dashboards. Run: python3 scripts/test_render_dashboards.py"""
import copy, os, sys

from importlib import import_module
r = import_module("render-dashboards".replace("-", "_")) if False else None

import importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("rd", os.path.join(HERE, "render-dashboards.py"))
rd = importlib.util.module_from_spec(spec); spec.loader.exec_module(rd)

DASH = {
    "uid": "t", "title": "T", "templating": {"list": [
        {"name": "prom_retention", "type": "textbox", "current": {"text": "7d", "value": "7d"}, "query": "7d"},
    ]},
    "panels": [
        {"id": 1, "type": "row",  "title": "R", "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}},
        {"id": 2, "type": "stat", "title": "keep-a", "x-requires": ["prometheus"],
         "gridPos": {"h": 6, "w": 6, "x": 0, "y": 1}},
        {"id": 3, "type": "stat", "title": "drop",   "x-requires": ["audit.postgres"],
         "gridPos": {"h": 6, "w": 6, "x": 6, "y": 1}},
        {"id": 4, "type": "stat", "title": "keep-b", "x-requires": ["prometheus"],
         "gridPos": {"h": 6, "w": 6, "x": 12, "y": 1}},
    ],
}

def test_filters_unsupported_panels():
    out = rd.render(copy.deepcopy(DASH), {"prometheus"}, {})
    titles = [p["title"] for p in out["panels"] if p["type"] != "row"]
    assert titles == ["keep-a", "keep-b"], titles

def test_repacks_gridpos_left_to_right():
    out = rd.render(copy.deepcopy(DASH), {"prometheus"}, {})
    xs = [p["gridPos"]["x"] for p in out["panels"] if p["type"] != "row"]
    assert xs == [0, 6], f"expected no hole at x=6, got {xs}"

def test_keeps_panel_when_all_caps_present():
    out = rd.render(copy.deepcopy(DASH), {"prometheus", "audit.postgres"}, {})
    assert len([p for p in out["panels"] if p["type"] != "row"]) == 3

def test_injects_retention_default():
    out = rd.render(copy.deepcopy(DASH), {"prometheus"}, {"prom_retention": "30d"})
    v = [v for v in out["templating"]["list"] if v["name"] == "prom_retention"][0]
    assert v["current"]["value"] == "30d" and v["query"] == "30d", v

def test_drops_row_left_empty():
    d = copy.deepcopy(DASH)
    d["panels"] = [d["panels"][0], d["panels"][2]]  # row + only a droppable panel
    out = rd.render(d, {"prometheus"}, {})
    assert out["panels"] == [], out["panels"]

def test_skips_dashboard_left_with_only_text_panels():
    """A dashboard reduced to nothing but its explanatory text is not a dashboard.

    Shipping one would put an empty board in the nav that looks like a broken
    install rather than an unsupported one.
    """
    d = {"uid": "t2", "title": "T2", "templating": {"list": []}, "panels": [
        {"id": 1, "type": "text", "title": "note", "x-requires": [],
         "gridPos": {"h": 4, "w": 24, "x": 0, "y": 0}},
        {"id": 2, "type": "stat", "title": "data", "x-requires": ["accessGraph"],
         "gridPos": {"h": 6, "w": 6, "x": 0, "y": 4}},
    ]}
    assert rd.has_data_panels(rd.render(copy.deepcopy(d), {"prometheus"}, {})) is False
    assert rd.has_data_panels(rd.render(copy.deepcopy(d), {"accessGraph"}, {})) is True


def test_filters_panels_nested_inside_collapsed_rows():
    """Collapsed rows carry their children in row["panels"], not at top level."""
    d = {"uid": "t3", "title": "T3", "templating": {"list": []}, "panels": [
        {"id": 1, "type": "row", "title": "R", "collapsed": True,
         "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}, "panels": [
            {"id": 2, "type": "stat", "title": "keep", "x-requires": ["prometheus"],
             "gridPos": {"h": 6, "w": 6, "x": 0, "y": 1}},
            {"id": 3, "type": "stat", "title": "drop", "x-requires": ["accessGraph"],
             "gridPos": {"h": 6, "w": 6, "x": 6, "y": 1}},
         ]},
    ]}
    out = rd.render(copy.deepcopy(d), {"prometheus"}, {})
    nested = [p["title"] for p in out["panels"][0]["panels"]]
    assert nested == ["keep"], nested

def test_strips_links_to_dashboards_the_profile_skipped():
    """A surviving panel may still link to a dashboard that was skipped.

    The executive board's links currently sit on Access-Graph panels that get
    dropped alongside their target, so this never bites today. That is a
    coincidence of layout, not a guarantee -- a Prometheus panel linking to
    Identity Security would survive and dangle.
    """
    d = {"uid": "a", "panels": [
        {"id": 1, "type": "stat", "title": "survives",
         "links": [{"title": "gone", "url": "/d/skipped-board/x"},
                   {"title": "ok", "url": "/d/still-here/y"}],
         "gridPos": {"h": 6, "w": 6, "x": 0, "y": 0}},
    ]}
    removed = rd.strip_dangling_links(d, {"a", "still-here"})
    urls = [l["url"] for l in d["panels"][0]["links"]]
    assert removed == 1, removed
    assert urls == ["/d/still-here/y"], urls


def test_removes_links_key_entirely_when_all_dangle():
    d = {"uid": "a", "panels": [
        {"id": 1, "type": "stat", "title": "s",
         "links": [{"title": "gone", "url": "/d/skipped/x"}],
         "gridPos": {"h": 6, "w": 6, "x": 0, "y": 0}},
    ]}
    rd.strip_dangling_links(d, {"a"})
    assert "links" not in d["panels"][0]

if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                fn(); print(f"  PASS {name}")
            except AssertionError as e:
                fails += 1; print(f"  FAIL {name}: {e}")
    print(f"\n{fails} failure(s)")
    sys.exit(1 if fails else 0)
