from data_preprocessing import load_and_clean
from feature_engineering import create_features
from plots import *

DATASETS = {
    "2024": {
        "file": "../../../BusDataStadtwerk/06.10.2024_19.10.2024_ITCS.csv",
        "oth_start": "2024-10-07",
        "oth_end": "2024-10-14",
        "mix_start": "2024-10-15"
    },
    "2023": {
        "file": "../../../BusDataStadtwerk/08.10.2023_21.10.2023_ITCS.csv",
        "oth_start": "2023-10-09",
        "oth_end": "2023-10-13",
        "mix_start": "2023-10-16"
    }
}


def split_dataset(df, cfg):
    df_oth = df[
        (df["date"] >= cfg["oth_start"]) &
        (df["date"] <= cfg["oth_end"])
        ].copy()

    df_uni = df[df["date"] >= cfg["mix_start"]].copy()

    return df_oth, df_uni


def process_all():
    results = {}

    for year, cfg in DATASETS.items():
        file_path = cfg["file"]

        df = load_and_clean(file_path)
        df = create_features(df)

        df_oth, df_uni = split_dataset(df, cfg)

        results[year] = {
            "oth": df_oth,
            "uni": df_uni
        }

    return results


data = process_all()

df_oth_2024 = data["2024"]["oth"]
df_uni_2024 = data["2024"]["uni"]

df_oth_2023 = data["2023"]["oth"]
df_uni_2023 = data["2023"]["uni"]

for year in ["2023", "2024"]:

    visualize_transit_data(data[year]["oth"])
    visualize_transit_data(data[year]["uni"])

    visualise_delay_weekday(data[year]["oth"])
    visualise_delay_weekday(data[year]["uni"])

    visualise_delay_time(data[year]["oth"])
    visualise_delay_time(data[year]["uni"])

    find_rush_time(data[year]["oth"])
    find_rush_time(data[year]["uni"])

"""
df_full = find_the_bus(df2024)
visualise_nearby_distribution(df2024)
visualise_delay_vs_nearby(df2024)
visualise_line_congestion_effect(df2024)"""
