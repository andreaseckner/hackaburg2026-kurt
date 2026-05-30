from collections import Counter

import numpy as np
import pandas as pd

from utils import get_time_period


def create_features(df):  # Find additional information in the data
    df = df.copy()
    df = df.sort_values(["Umlauf", "Ankunft Haltestelle (Halt)"])

    df["weekday"] = df["Ankunft Haltestelle (Tür)"].dt.day_name()
    df["hour"] = df["Ankunft Haltestelle (Tür)"].dt.hour
    df["time_period"] = df["hour"].apply(get_time_period)

    df["arrival_delay"] = (
            (df["Ankunft Haltestelle (Halt)"] -
             df["Ankunft PLAN (Haltestelle)"])
            .dt.total_seconds() / 60
    )
    df["departure_delay"] = (
            (df["Abfahrt Haltestelle (Halt)"] -
             df["Abfahrt PLAN (Haltestelle)"])
            .dt.total_seconds() / 60
    )

    df["delay"] = df[["arrival_delay", "departure_delay"]].max(axis=1)
    df = df[df["delay"].between(-30,
                                30)]  # if bus doesn't arrive at the bus stop within 1 hour interval, it's either skipped or has been cancelled
    df = df.dropna(subset=["delay"])

    df["weekday"] = df["Ankunft Haltestelle (Tür)"].dt.day_name()
    df["hour"] = df["Ankunft Haltestelle (Tür)"].dt.hour
    df["date"] = pd.to_datetime(
        df["Ankunft Haltestelle (Tür)"],
        format="%d.%m.%Y %H:%M:%S",
        errors="coerce"
    )

    return df


def combine_datasets(bus_df, weather_df): # to combine any data with weather dataset
    weather_df["time"] = pd.to_datetime(weather_df["time"])
    bus_df = bus_df.sort_values("Ankunft Haltestelle (Tür)")
    weather_df = weather_df.sort_values("time")

    df = pd.merge_asof(
        bus_df,
        weather_df,
        left_on="Ankunft Haltestelle (Tür)",
        right_on="time",
        direction="backward"
    )
    return df


def find_nearby_bus(data): # count the buses that share a bus stop within a certain time window
    data = data.copy()

    data["Ankunft PLAN (Haltestelle)"] = pd.to_datetime(
        data["Ankunft PLAN (Haltestelle)"],
        format="%d.%m.%Y %H:%M:%S",
        errors="coerce"
    )

    data = data.dropna(subset=["Ankunft PLAN (Haltestelle)", "Haltestelle", "Umlauf"])

    data = data.sort_values(["Haltestelle", "Ankunft PLAN (Haltestelle)"])

    data["nearby_bus_count"] = 0
    window = np.timedelta64(1, "m")

    for stop, group in data.groupby("Haltestelle", sort=False):
        times = group["Ankunft PLAN (Haltestelle)"].values

        left = np.searchsorted(times, times - window, side="left")
        right = np.searchsorted(times, times + window, side="right")

        counts = (right - left) - 1

        data.loc[group.index, "nearby_bus_count"] = counts

    return data


def find_the_bus_with_links(data, window_minutes=1): # discover the relation between a bus that causes delay to other buses
    data = data.copy()

    data["Ankunft PLAN (Haltestelle)"] = pd.to_datetime(
        data["Ankunft PLAN (Haltestelle)"],
        format="%d.%m.%Y %H:%M:%S",
        errors="coerce"
    )

    data = data.dropna(subset=["Ankunft PLAN (Haltestelle)", "Haltestelle", "Linie"])
    data = data.sort_values(["Haltestelle", "Ankunft PLAN (Haltestelle)"])

    window = np.timedelta64(window_minutes, "m")

    data["nearby_bus_count"] = 0

    cause_map = {}
    victim_map = {}

    for stop, group in data.groupby("Haltestelle", sort=False):
        group = group.copy()

        times = group["Ankunft PLAN (Haltestelle)"].values
        lines = group["Linie"].values

        for i, t in enumerate(times):
            left = np.searchsorted(times, t - window, side="left")
            right = np.searchsorted(times, t + window, side="right")

            neighbors = list(range(left, right))
            if i in neighbors:
                neighbors.remove(i)

            current_line = lines[i]

            data.loc[group.index[i], "nearby_bus_count"] = len(neighbors)

            if current_line not in cause_map:
                cause_map[current_line] = set()

            for j in neighbors:
                neighbor_line = lines[j]

                if neighbor_line == current_line:
                    continue

                cause_map[current_line].add(neighbor_line)

                if neighbor_line not in victim_map:
                    victim_map[neighbor_line] = set()

                victim_map[neighbor_line].add(current_line)

    cause_map = {k: list(v) for k, v in cause_map.items()}
    victim_map = {k: list(v) for k, v in victim_map.items()}

    cause_score = Counter()
    victim_score = Counter()

    for k, v in cause_map.items():
        cause_score[k] += len(v)

    for k, v in victim_map.items():
        victim_score[k] += len(v)

    df = pd.DataFrame({
        "causes_others": pd.Series(cause_score),
        "affected_by_others": pd.Series(victim_score)
    }).fillna(0)

    df["net_influence"] = df["causes_others"] - df["affected_by_others"]

    return df
