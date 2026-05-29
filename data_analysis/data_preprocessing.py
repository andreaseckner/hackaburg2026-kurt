import pandas as pd


def load_and_clean(filepath):
    df = pd.read_csv(filepath, encoding='utf-16')

    df = df.rename(columns={
        "Unnamed: 10": "street_name_start",
        "Unnamed: 12": "street_name_end",
        "Unnamed: 14": "bus_stop"
    })

    df = df.drop(columns=["Unnamed: 17"], errors="ignore")
    df = df.drop(columns=["Unnamed: 19"], errors="ignore")

    time_cols = [
        "Ankunft Haltestelle (Tür)",
        "Ankunft Haltestelle (Halt)",
        "Ankunft PLAN (Haltestelle)",
        "Abfahrt Haltestelle (Tür)",
        "Abfahrt Haltestelle (Halt)",
        "Abfahrt PLAN (Haltestelle)"
    ]

    for c in time_cols:
        if c in df.columns:
            df[c] = pd.to_datetime(df[c],
                                   format="%d.%m.%Y %H:%M:%S",
                                   errors="coerce")

    df["Ankunft produktiv"] = df["Ankunft produktiv"].replace({'Ja': 1, 'Nein': 0})
    df["Abfahrt produktiv"] = df["Abfahrt produktiv"].replace({'Ja': 1, 'Nein': 0})

    num_cols = df.select_dtypes(include="number").columns
    cat_cols = df.select_dtypes(exclude="number").columns

    df[num_cols] = df[num_cols].fillna(df[num_cols].mean())
    df[cat_cols] = df[cat_cols].fillna("missing")

    return df
