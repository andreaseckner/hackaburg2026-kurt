#!/usr/bin/env python3
"""
Generate GTFS shapes.txt by querying OSRM for road geometry between consecutive stops.

Usage:
    pip install requests
    python generate_shapes.py

Reads: routes.txt, stops.txt, trips.txt, stop_times.txt
Writes: shapes.txt, trips_with_shapes.txt, segment_cache.json (cache)
"""

import csv
import json
import math
import os
import sys
import time
from collections import defaultdict

try:
    import requests
except ImportError:
    print("Please install requests: pip install requests")
    sys.exit(1)

GTFS_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_FILE = os.path.join(GTFS_DIR, "segment_cache.json")
OSRM_BASE = "http://router.project-osrm.org/route/v1/driving"
REQUEST_DELAY = 0.5  # seconds between OSRM requests


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

def haversine(lat1, lon1, lat2, lon2):
    """Return distance in meters between two lat/lon points."""
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def load_cache():
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE, "r") as f:
            return json.load(f)
    return {}


def save_cache(cache):
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f)


def segment_key(stop_a, stop_b):
    return f"{stop_a}|{stop_b}"


# ---------------------------------------------------------------------------
# GTFS parsing
# ---------------------------------------------------------------------------

def read_stops():
    """Return {stop_id: (lat, lon)}."""
    stops = {}
    with open(os.path.join(GTFS_DIR, "stops.txt"), "r", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            stops[row["stop_id"]] = (float(row["stop_lat"]), float(row["stop_lon"]))
    return stops


def read_trips():
    """Return list of dicts with trip fields."""
    trips = []
    with open(os.path.join(GTFS_DIR, "trips.txt"), "r", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            trips.append(dict(row))
    return trips


def read_stop_times():
    """Return {trip_id: [(stop_sequence, stop_id), ...]} sorted by sequence."""
    trip_stops = defaultdict(list)
    with open(os.path.join(GTFS_DIR, "stop_times.txt"), "r", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            trip_stops[row["trip_id"]].append((int(row["stop_sequence"]), row["stop_id"]))
    for tid in trip_stops:
        trip_stops[tid].sort()
    return trip_stops


# ---------------------------------------------------------------------------
# Shape deduplication
# ---------------------------------------------------------------------------

def build_unique_shapes(trips, trip_stops):
    """
    Group trips by their ordered stop-id tuple.
    Returns:
        shapes: {shape_id: [stop_id, ...]}
        trip_shape_map: {trip_id: shape_id}
    """
    seq_to_shape = {}
    shapes = {}
    trip_shape_map = {}
    shape_counter = 0

    for trip in trips:
        tid = trip["trip_id"]
        if tid not in trip_stops:
            continue
        stop_seq = tuple(sid for _, sid in trip_stops[tid])
        if stop_seq not in seq_to_shape:
            shape_id = f"shape_{shape_counter}"
            shape_counter += 1
            seq_to_shape[stop_seq] = shape_id
            shapes[shape_id] = list(stop_seq)
        trip_shape_map[tid] = seq_to_shape[stop_seq]

    return shapes, trip_shape_map


# ---------------------------------------------------------------------------
# OSRM querying
# ---------------------------------------------------------------------------

def fetch_segment_geometry(lat1, lon1, lat2, lon2):
    """Query OSRM and return list of [lat, lon] coordinate pairs."""
    url = f"{OSRM_BASE}/{lon1},{lat1};{lon2},{lat2}?geometries=geojson&overview=full"
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    if data.get("code") != "Ok" or not data.get("routes"):
        # Fallback: straight line
        return [[lat1, lon1], [lat2, lon2]]
    coords = data["routes"][0]["geometry"]["coordinates"]  # [[lon, lat], ...]
    return [[c[1], c[0]] for c in coords]  # convert to [lat, lon]


def fetch_all_segments(segments, stops, cache):
    """
    segments: set of (stop_a, stop_b) tuples
    Fetches missing segments from OSRM, updates cache in-place.
    """
    total = len(segments)
    to_fetch = [s for s in segments if segment_key(*s) not in cache]
    print(f"Total unique segments: {total}, cached: {total - len(to_fetch)}, to fetch: {len(to_fetch)}")

    for i, (sa, sb) in enumerate(to_fetch):
        lat1, lon1 = stops[sa]
        lat2, lon2 = stops[sb]
        key = segment_key(sa, sb)
        try:
            coords = fetch_segment_geometry(lat1, lon1, lat2, lon2)
            cache[key] = coords
        except Exception as e:
            print(f"  WARN: segment {sa}->{sb} failed ({e}), using straight line")
            cache[key] = [[lat1, lon1], [lat2, lon2]]

        if (i + 1) % 50 == 0 or (i + 1) == len(to_fetch):
            print(f"  Fetched {i + 1}/{len(to_fetch)} segments")
            save_cache(cache)

        time.sleep(REQUEST_DELAY)

    save_cache(cache)


# ---------------------------------------------------------------------------
# shapes.txt generation
# ---------------------------------------------------------------------------

def write_shapes(shapes, stops, cache):
    out_path = os.path.join(GTFS_DIR, "shapes.txt")
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence", "shape_dist_traveled"])

        for shape_id, stop_ids in shapes.items():
            pts = []
            for i in range(len(stop_ids) - 1):
                key = segment_key(stop_ids[i], stop_ids[i + 1])
                seg_coords = cache.get(key)
                if seg_coords is None:
                    # fallback to straight line
                    seg_coords = [list(stops[stop_ids[i]]), list(stops[stop_ids[i + 1]])]
                # Avoid duplicating the junction point
                if pts and seg_coords:
                    pts.extend(seg_coords[1:])
                else:
                    pts.extend(seg_coords)

            # If only one stop (shouldn't happen but safe)
            if not pts and stop_ids:
                lat, lon = stops[stop_ids[0]]
                pts = [[lat, lon]]

            dist = 0.0
            for seq, (lat, lon) in enumerate(pts):
                if seq > 0:
                    dist += haversine(pts[seq - 1][0], pts[seq - 1][1], lat, lon)
                writer.writerow([shape_id, f"{lat:.7f}", f"{lon:.7f}", seq, f"{dist:.1f}"])

    print(f"Wrote {out_path} ({len(shapes)} shapes)")


def write_updated_trips(trips, trip_shape_map):
    out_path = os.path.join(GTFS_DIR, "trips_with_shapes.txt")
    fieldnames = list(trips[0].keys())
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for trip in trips:
            row = dict(trip)
            row["shape_id"] = trip_shape_map.get(trip["trip_id"], row.get("shape_id", ""))
            writer.writerow(row)
    print(f"Wrote {out_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Reading GTFS files...")
    stops = read_stops()
    trips = read_trips()
    trip_stops = read_stop_times()
    print(f"  {len(stops)} stops, {len(trips)} trips, {len(trip_stops)} trip stop-sequences")

    print("Building unique shapes...")
    shapes, trip_shape_map = build_unique_shapes(trips, trip_stops)
    print(f"  {len(shapes)} unique shapes from {len(trip_shape_map)} trips")

    # Collect unique segments
    segments = set()
    for stop_ids in shapes.values():
        for i in range(len(stop_ids) - 1):
            segments.add((stop_ids[i], stop_ids[i + 1]))
    print(f"  {len(segments)} unique stop-to-stop segments")

    # Fetch from OSRM
    cache = load_cache()
    fetch_all_segments(segments, stops, cache)

    # Write outputs
    print("Writing shapes.txt...")
    write_shapes(shapes, stops, cache)

    print("Writing updated trips...")
    write_updated_trips(trips, trip_shape_map)

    print("Done!")


if __name__ == "__main__":
    main()

