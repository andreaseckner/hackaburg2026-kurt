import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split

from data_preprocessing import load_and_clean
from feature_engineering import create_features
from plots import visualise_model_results, visualise_feature_importance


def prepare_dataset(df):
    drop_cols = [
        "Ankunft Haltestelle (Tür)",
        "Ankunft Haltestelle (Halt)",
        "Ankunft PLAN (Haltestelle)",
        "Abfahrt Haltestelle (Tür)",
        "Abfahrt Haltestelle (Halt)",
        "Abfahrt PLAN (Haltestelle)",
        "street_name_start",
        "street_name_end",
        "bus_stop",
        "Haltepunkt",
        "Haltestelle",
        "Fahrtbeginn (Soll-Haltestelle)",
        "Fahrtende (Soll-Haltestelle)",
        "arrival_delay",
        "departure_delay",
        "Fahrplan-Abw. Ankunft (Tür) AVG {s}",
        "Fahrplan-Abw. Abfahrt (Tür) AVG  {s}",
        "date"
    ]

    df = df.drop(columns=drop_cols, errors="ignore")

    x = df.drop(columns=["delay"])
    y = df["delay"]

    return x, y, df


def evaluate(model, x, y):
    preds = model.predict(x)

    mae = mean_absolute_error(y, preds)
    rmse = np.sqrt(mean_squared_error(y, preds))
    r2 = r2_score(y, preds)

    print(f"MAE: {mae:.3f} minutes")
    print(f"RMSE: {rmse:.3f} minutes")
    print(f"R2 Score: {r2:.3f}")

    visualise_model_results(y, preds)


def xgboost(x_train, y_train, x_val, y_val):
    for depth in [20, 25, 30, 35]:
        temp_model = RandomForestRegressor(max_depth=depth,
                                           random_state=67,
                                           n_jobs=-1,
                                           verbose=2)
        temp_model.fit(x_train, y_train)

        val_preds = temp_model.predict(x_val)
        mae = mean_absolute_error(y_val, val_preds)
        print(f"Max Depth {depth}: Validation MAE = {mae:.3f}")


def train():
    df = load_and_clean("../../../BusDataStadtwerk/23.04.2025_09.05.2025_ITCS_nur_UniLinien.csv")
    df = create_features(df)

    df = df.sort_values("Ankunft Haltestelle (Tür)").reset_index(drop=True)
    df = pd.get_dummies(
        df,
        columns=[
            "Linie",
            "Richtung",
            "weekday",
            "time_period",
            "Betriebstag",
            "hour",
        ],
        drop_first=True
    )

    x, y, df = prepare_dataset(df)

    print(list(df.columns))
    print(df.dtypes)
    df.to_csv("Cleaned_nur_UniLinien.csv", index=False)

    x_train, x_val, y_train, y_val = train_test_split(
        x, y,
        test_size=0.2,
        shuffle=False
    )

    model = RandomForestRegressor(
        n_estimators=200,
        max_depth=30,
        random_state=67,
        n_jobs=-1,
        verbose=2
    )

    model.fit(x_train, y_train)

    visualise_feature_importance(model, x_train)

    evaluate(model, x_val, y_val)
    # evaluate(model, x_test, y_test)


if __name__ == "__main__":
    train()
