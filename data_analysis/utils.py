import matplotlib as plt
import seaborn as sns


def line_stops(df, line): # find the list of stops for the line
    stops = (
        df[df["Linie"].astype(str) == line]
        .sort_values("Ankunft Haltestelle (Halt)")
        ["bus_stop_full"]
        .dropna()
        .drop_duplicates()
        .sort_values()
        .tolist()
    )
    return stops


def stop_lines(df, stop): # find the list of lines that contain the stop
    lines = (
        df[df["Haltestelle"].astype(str) == stop]["Linie"]
        .dropna()
        .drop_duplicates()
        .sort_values()
        .tolist()
    )
    return lines


def bottleneck_check(df): # discover, if delays cause bottlenecks and delays for the route stack over time
    df = df.sort_values(["Linie", "Richtung", "Haltestelle"])
    df["dist_m"] = df["CUMSUM(Distanz PLAN) {m}"]
    df["time_s"] = df["CUMSUM(Fahrzeit IST) {s}"]
    group_cols = ["Linie", "Richtung", "Umlauf"]

    df["dist_delta"] = df.groupby(group_cols)["dist_m"].diff()
    df["time_delta"] = df.groupby(group_cols)["time_s"].diff()

    df["speed_mps"] = df["dist_delta"] / df["time_delta"]
    df["route_delay"] = df.groupby(group_cols)["delay"].cumsum()
    bottlenecks = df[df["speed_mps"] < df["speed_mps"].quantile(0.1)]

    stop_analysis = df.groupby("Haltestelle").agg(
        avg_speed=("speed_mps", "mean"),
        avg_delay=("delay", "mean"),
    ).reset_index()
    worst_stops = stop_analysis.sort_values("avg_delay", ascending=False)

    print(worst_stops)

    plt.figure(figsize=(12, 6))
    df_filtered = df[df["CUMSUM(Distanz PLAN) {m}"] > 50].copy()

    sns.lineplot(data=df_filtered, x="dist_m", y="route_delay", marker="o")
    plt.title("Cumulative Delay over Trip Distance")
    plt.xlabel("Distance (meters)")
    plt.ylabel("Cumulative Delay (seconds)")
    plt.grid(True)
    plt.show()


def get_time_period(hour): # generalize hours of the day
    if 5 <= hour < 12:
        return "morning"
    elif 12 <= hour < 17:
        return "afternoon"
    elif 17 <= hour < 22:
        return "evening"
    else:
        return "night"
