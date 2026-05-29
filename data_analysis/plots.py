import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

from feature_engineering import find_the_bus_with_links


def visualize_transit_data(df):
    fig, axes = plt.subplots(1, 3, figsize=(16, 5))

    sns.histplot(df["delay"], bins=40, kde=True, ax=axes[0])
    axes[0].axvline(0, linestyle="--")
    axes[0].set_title("Delay Distribution")

    sns.boxplot(data=df, x="Linie", y="delay", ax=axes[1])
    axes[1].set_title("Delay by Line")
    axes[1].tick_params(axis="x", rotation=45)

    top = df.groupby("Haltestelle")["delay"].mean().nlargest(10)
    sns.barplot(x=top.values, y=top.index, ax=axes[2])
    axes[2].set_title("Worst Stops")

    plt.tight_layout()
    return fig


def visualise_delay_weekday(df):
    order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    plt.figure(figsize=(8, 4))

    weekday_mean = df.groupby("weekday")["delay"].mean().reindex(order)

    sns.barplot(x=weekday_mean.index, y=weekday_mean.values)

    plt.axhline(0, linestyle="--")
    plt.title("Average Delay by Weekday")
    plt.xticks(rotation=45)
    plt.ylabel("Delay (min)")
    plt.tight_layout()

    plt.show()


def visualise_model_results(y, preds):
    fig, axes = plt.subplots(1, 2, figsize=(10, 5))
    axes[0].scatter(y, preds, alpha=0.5)

    min_val = min(y.min(), preds.min())
    max_val = max(y.max(), preds.max())

    axes[0].plot([min_val, max_val],
                 [min_val, max_val],
                 linestyle="--")

    axes[0].set_title("Actual vs Predicted")
    axes[0].set_xlabel("Actual Delay (min)")
    axes[0].set_ylabel("Predicted Delay (min)")

    residuals = y - preds

    axes[1].scatter(preds, residuals, alpha=0.5)
    axes[1].axhline(0, linestyle="--")

    axes[1].set_title("Residuals vs Predictions")
    axes[1].set_xlabel("Predicted Delay")
    axes[1].set_ylabel("Residual")

    plt.tight_layout()
    plt.show()


def visualise_feature_importance(model, x, top_n=25):
    importance_df = pd.DataFrame({
        "feature": x.columns,
        "importance": model.feature_importances_
    })

    importance_df = (
        importance_df
        .sort_values("importance", ascending=False)
    )

    print("\nTop Features:")
    print(importance_df.head(top_n))

    plt.figure(figsize=(12, 8))

    sns.barplot(
        data=importance_df.head(top_n),
        x="importance",
        y="feature"
    )

    plt.title(f"Top {top_n} Feature Importances")
    plt.xlabel("Importance")
    plt.ylabel("Feature")

    plt.tight_layout()
    plt.show()

    return importance_df


def visualise_delay_time(data):
    order = ["morning", "afternoon", "evening", "night"]

    plt.figure(figsize=(8, 4))

    period_mean = (
        data.groupby("time_period")["delay"]
        .mean()
        .reindex(order)
    )

    sns.barplot(
        x=period_mean.index,
        y=period_mean.values
    )

    plt.axhline(0, linestyle="--")
    plt.title("Average Delay by Time of Day")
    plt.ylabel("Delay (min)")
    plt.tight_layout()

    plt.show()


def visualie_rush_hour(data):
    plt.figure(figsize=(6, 4))

    rush_mean = (
        data.groupby("rush_hour")["delay"]
        .mean()
    )

    labels = ["Non-Rush Hour", "Rush Hour"]

    sns.barplot(
        x=labels,
        y=rush_mean.values
    )

    plt.axhline(0, linestyle="--")
    plt.title("Average Delay: Rush Hour vs Non-Rush Hour")
    plt.ylabel("Delay (min)")
    plt.tight_layout()

    plt.show()


def visualise_influence(df):
    influence_df = find_the_bus_with_links(df)

    top_causers = influence_df.sort_values("causes_others", ascending=False).head(10)

    plt.figure(figsize=(10, 5))

    sns.barplot(
        x=top_causers.index,
        y=top_causers["causes_others"]
    )

    plt.title("Top 10 Delay Spreaders (Cause Others Most Often)")
    plt.xlabel("Bus ID")
    plt.ylabel("Number of affected buses")

    plt.tight_layout()
    plt.show()


def visualise_nearby_distribution(data):
    plt.figure(figsize=(8, 4))

    sns.histplot(
        data["nearby_bus_count"],
        bins=30,
        kde=True
    )

    plt.title("Distribution of Nearby Buses (±1 min, same stop)")
    plt.xlabel("Nearby buses")
    plt.ylabel("Frequency")

    plt.tight_layout()
    plt.show()


def visualise_delay_vs_nearby(data):
    plt.figure(figsize=(8, 4))

    grouped = (
        data.groupby("nearby_bus_count")["delay"]
        .mean()
        .reset_index()
    )

    sns.lineplot(
        data=grouped,
        x="nearby_bus_count",
        y="delay",
        marker="o"
    )

    plt.title("Average Delay vs Nearby Bus Count")
    plt.xlabel("Nearby buses (±1 min)")
    plt.ylabel("Average delay (min)")

    plt.tight_layout()
    plt.show()


def visualise_line_congestion_effect(data):
    congested_mean = (
        data[data["nearby_bus_count"] > 0]
        .groupby("Linie")["delay"]
        .mean()
    )
    normal_mean = (
        data[data["nearby_bus_count"] == 0]
        .groupby("Linie")["delay"]
        .mean()
    )

    impact = (congested_mean - normal_mean).dropna()

    top10 = impact.sort_values(ascending=False).head(10)

    plt.figure(figsize=(8, 4))

    sns.barplot(
        x=top10.index.astype(str),
        y=top10.values.round(3),
    )

    plt.title("Top 10 Lines Most Affected by Congestion")
    plt.xlabel("Line Number")
    plt.ylabel("Extra delay due to congestion (min)")

    plt.tight_layout()
    plt.show()


def find_rush_time(data):
    plt.figure(figsize=(12, 5))

    hourly_delay = (
        data.groupby("hour")["delay"]
        .mean()
        .sort_index()
    )

    sns.lineplot(
        x=hourly_delay.index,
        y=hourly_delay.values,
        marker="o"
    )

    plt.axhline(0, linestyle="--")

    plt.title("Average Delay by Hour of Day")
    plt.xlabel("Hour")
    plt.ylabel("Average Delay (min)")

    plt.xticks(range(0, 24))

    plt.grid(True)
    plt.tight_layout()

    plt.show()
