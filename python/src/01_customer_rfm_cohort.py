from __future__ import annotations

import os
import warnings
from pathlib import Path

import matplotlib
import numpy as np
import pandas as pd
import pymysql

matplotlib.use("Agg")
import matplotlib.pyplot as plt

warnings.filterwarnings(
    "ignore",
    message="pandas only supports SQLAlchemy connectable.*",
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "outputs" / "customer_analysis"


def database_connection() -> pymysql.Connection:
    password = os.getenv("MYSQL_PASSWORD")
    if not password:
        raise SystemExit("MYSQL_PASSWORD is required.")

    return pymysql.connect(
        host=os.getenv("MYSQL_HOST", "127.0.0.1"),
        port=int(os.getenv("MYSQL_PORT", "3306")),
        user=os.getenv("MYSQL_USER", "root"),
        password=password,
        database=os.getenv("MYSQL_DATABASE", "olist"),
        charset="utf8mb4",
        autocommit=True,
    )


def score_recency(days: pd.Series) -> pd.Series:
    return pd.Series(
        np.select(
            [
                days <= 90,
                days <= 180,
                days <= 270,
                days <= 365,
            ],
            [5, 4, 3, 2],
            default=1,
        ),
        index=days.index,
        dtype="int64",
    )


def score_frequency(orders: pd.Series) -> pd.Series:
    return pd.Series(
        np.select(
            [
                orders >= 4,
                orders == 3,
                orders == 2,
            ],
            [5, 4, 3],
            default=1,
        ),
        index=orders.index,
        dtype="int64",
    )


def score_monetary(amount: pd.Series) -> pd.Series:
    percentile_rank = amount.rank(method="first", pct=True)
    return np.ceil(percentile_rank * 5).clip(1, 5).astype("int64")


def assign_segment(row: pd.Series) -> str:
    if row["r_score"] >= 4 and row["f_score"] >= 4 and row["m_score"] >= 4:
        return "高价值活跃"
    if row["r_score"] >= 4 and row["f_score"] == 1:
        return "近期一次购买"
    if row["r_score"] >= 3 and row["f_score"] >= 3:
        return "复购成长"
    if row["r_score"] <= 2 and row["f_score"] >= 4:
        return "高价值流失风险"
    if row["r_score"] <= 2 and row["f_score"] <= 2:
        return "流失客户"
    if row["m_score"] >= 4:
        return "高消费待激活"
    return "一般客户"


def build_rfm(connection: pymysql.Connection) -> tuple[pd.DataFrame, pd.DataFrame]:
    customer_sql = """
        SELECT
          customer_unique_id,
          delivered_orders,
          customer_gmv,
          first_order_at,
          last_order_at
        FROM v_customer_analytics
    """
    customers = pd.read_sql_query(customer_sql, connection)
    customers["first_order_at"] = pd.to_datetime(customers["first_order_at"])
    customers["last_order_at"] = pd.to_datetime(customers["last_order_at"])

    reference_date = customers["last_order_at"].max().normalize() + pd.Timedelta(days=1)
    customers["recency_days"] = (
        reference_date - customers["last_order_at"].dt.normalize()
    ).dt.days
    customers["r_score"] = score_recency(customers["recency_days"])
    customers["f_score"] = score_frequency(customers["delivered_orders"])
    customers["m_score"] = score_monetary(customers["customer_gmv"])
    customers["rfm_score"] = (
        customers["r_score"].astype(str)
        + customers["f_score"].astype(str)
        + customers["m_score"].astype(str)
    )
    customers["segment"] = customers.apply(assign_segment, axis=1)

    segment_summary = (
        customers.groupby("segment", as_index=False)
        .agg(
            customers=("customer_unique_id", "nunique"),
            gmv=("customer_gmv", "sum"),
            average_orders=("delivered_orders", "mean"),
            average_gmv=("customer_gmv", "mean"),
            average_recency_days=("recency_days", "mean"),
        )
        .sort_values("gmv", ascending=False)
    )
    segment_summary["customer_share_pct"] = (
        segment_summary["customers"] / segment_summary["customers"].sum() * 100
    )
    segment_summary["gmv_share_pct"] = (
        segment_summary["gmv"] / segment_summary["gmv"].sum() * 100
    )
    segment_summary = segment_summary.round(
        {
            "gmv": 2,
            "average_orders": 2,
            "average_gmv": 2,
            "average_recency_days": 1,
            "customer_share_pct": 2,
            "gmv_share_pct": 2,
        }
    )

    return customers, segment_summary


def build_cohort(connection: pymysql.Connection) -> tuple[pd.DataFrame, pd.DataFrame]:
    activity_sql = """
        SELECT DISTINCT
          customer_unique_id,
          purchase_month
        FROM v_order_analytics
        WHERE is_delivered = 1
          AND purchase_month IS NOT NULL
    """
    activity = pd.read_sql_query(activity_sql, connection)
    activity["purchase_period"] = pd.to_datetime(
        activity["purchase_month"] + "-01"
    ).dt.to_period("M")

    first_purchase = (
        activity.groupby("customer_unique_id", as_index=False)["purchase_period"]
        .min()
        .rename(columns={"purchase_period": "cohort_month"})
    )
    activity = activity.merge(first_purchase, on="customer_unique_id", how="left")
    activity["cohort_index"] = (
        activity["purchase_period"].astype("period[M]")
        - activity["cohort_month"].astype("period[M]")
    ).map(lambda period: period.n)

    cohort_counts = (
        activity.groupby(["cohort_month", "cohort_index"])["customer_unique_id"]
        .nunique()
        .rename("customers")
        .reset_index()
    )
    cohort_sizes = (
        cohort_counts.loc[cohort_counts["cohort_index"] == 0, ["cohort_month", "customers"]]
        .rename(columns={"customers": "cohort_size"})
    )
    cohort_counts = cohort_counts.merge(cohort_sizes, on="cohort_month", how="left")
    cohort_counts["retention_rate"] = (
        cohort_counts["customers"] / cohort_counts["cohort_size"]
    )

    cohort_pivot = cohort_counts.pivot(
        index="cohort_month",
        columns="cohort_index",
        values="retention_rate",
    )
    cohort_pivot = cohort_pivot.round(4)
    cohort_pivot.index = cohort_pivot.index.astype(str)
    return cohort_counts, cohort_pivot


def build_repurchase_intervals(
    connection: pymysql.Connection,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    interval_sql = """
        WITH ordered_purchases AS (
          SELECT
            customer_unique_id,
            order_id,
            order_purchase_timestamp,
            ROW_NUMBER() OVER (
              PARTITION BY customer_unique_id
              ORDER BY order_purchase_timestamp, order_id
            ) AS purchase_sequence
          FROM v_order_analytics
          WHERE is_delivered = 1
        ),
        first_two_orders AS (
          SELECT
            customer_unique_id,
            MAX(
              CASE
                WHEN purchase_sequence = 1 THEN order_purchase_timestamp
              END
            ) AS first_order_at,
            MAX(
              CASE
                WHEN purchase_sequence = 2 THEN order_purchase_timestamp
              END
            ) AS second_order_at
          FROM ordered_purchases
          WHERE purchase_sequence <= 2
          GROUP BY customer_unique_id
        )
        SELECT
          customer_unique_id,
          TIMESTAMPDIFF(DAY, first_order_at, second_order_at)
            AS days_to_second_order
        FROM first_two_orders
        WHERE second_order_at IS NOT NULL
    """
    intervals = pd.read_sql_query(interval_sql, connection)
    summary = intervals["days_to_second_order"].describe(
        percentiles=[0.25, 0.5, 0.75, 0.9]
    )
    summary_df = summary.rename("days_to_second_order").reset_index()
    summary_df.columns = ["statistic", "days_to_second_order"]
    return intervals, summary_df


def configure_plotting() -> None:
    plt.rcParams["font.sans-serif"] = [
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    plt.rcParams["axes.unicode_minus"] = False


def plot_rfm_segments(segment_summary: pd.DataFrame) -> None:
    figure, axes = plt.subplots(1, 2, figsize=(13, 5.5))
    ordered = segment_summary.sort_values("customers", ascending=True)
    axes[0].barh(ordered["segment"], ordered["customers"], color="#4C78A8")
    axes[0].set_title("客户数")
    axes[0].set_xlabel("客户数")
    axes[0].grid(axis="x", alpha=0.2)

    ordered_gmv = segment_summary.sort_values("gmv_share_pct", ascending=True)
    axes[1].barh(
        ordered_gmv["segment"],
        ordered_gmv["gmv_share_pct"],
        color="#F58518",
    )
    axes[1].set_title("GMV 贡献占比")
    axes[1].set_xlabel("%")
    axes[1].grid(axis="x", alpha=0.2)

    figure.suptitle("Olist RFM 客户分层")
    figure.tight_layout()
    figure.savefig(OUTPUT_DIR / "rfm_segment_summary.png", dpi=180)
    plt.close(figure)


def plot_cohort_retention(cohort_pivot: pd.DataFrame) -> None:
    chart_data = cohort_pivot.copy()
    chart_data = chart_data.loc[chart_data.index.astype(str) >= "2017-01"]

    max_offset = min(12, int(chart_data.columns.max()))
    chart_data = chart_data.loc[:, chart_data.columns <= max_offset]
    values = chart_data.to_numpy(dtype=float) * 100

    figure, axis = plt.subplots(figsize=(14, 8))
    image = axis.imshow(values, aspect="auto", cmap="YlGnBu", vmin=0, vmax=max(25, np.nanmax(values)))
    axis.set_xticks(range(len(chart_data.columns)))
    axis.set_xticklabels(chart_data.columns)
    axis.set_yticks(range(len(chart_data.index)))
    axis.set_yticklabels(chart_data.index)
    axis.set_xlabel("首购后月数")
    axis.set_ylabel("首购月份")
    axis.set_title("客户 Cohort 留存率（样本量至少 100 人）")

    for row_index in range(values.shape[0]):
        for column_index in range(values.shape[1]):
            value = values[row_index, column_index]
            if not np.isnan(value):
                axis.text(
                    column_index,
                    row_index,
                    f"{value:.1f}",
                    ha="center",
                    va="center",
                    fontsize=7,
                )

    figure.colorbar(image, ax=axis, label="留存率 %")
    figure.tight_layout()
    figure.savefig(OUTPUT_DIR / "cohort_retention_heatmap.png", dpi=180)
    plt.close(figure)


def plot_repurchase_intervals(intervals: pd.DataFrame) -> None:
    values = intervals["days_to_second_order"].dropna()
    figure, axis = plt.subplots(figsize=(10, 5.5))
    axis.hist(values, bins=30, color="#54A24B", edgecolor="white")
    axis.axvline(values.median(), color="#E45756", linestyle="--", label=f"中位数 {values.median():.0f} 天")
    axis.set_title("复购客户首购到二购间隔")
    axis.set_xlabel("天数")
    axis.set_ylabel("客户数")
    axis.legend()
    axis.grid(axis="y", alpha=0.2)
    figure.tight_layout()
    figure.savefig(OUTPUT_DIR / "repurchase_interval_distribution.png", dpi=180)
    plt.close(figure)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    configure_plotting()

    with database_connection() as connection:
        rfm_customers, rfm_segments = build_rfm(connection)
        cohort_long, cohort_pivot = build_cohort(connection)
        repurchase_intervals, repurchase_summary = build_repurchase_intervals(connection)

    rfm_customers.to_csv(OUTPUT_DIR / "rfm_customers.csv", index=False, encoding="utf-8-sig")
    rfm_segments.to_csv(
        OUTPUT_DIR / "rfm_segment_summary.csv",
        index=False,
        encoding="utf-8-sig",
    )
    cohort_long.to_csv(
        OUTPUT_DIR / "cohort_retention_long.csv",
        index=False,
        encoding="utf-8-sig",
    )
    cohort_pivot.to_csv(
        OUTPUT_DIR / "cohort_retention_matrix.csv",
        encoding="utf-8-sig",
    )
    repurchase_intervals.to_csv(
        OUTPUT_DIR / "repurchase_intervals.csv",
        index=False,
        encoding="utf-8-sig",
    )
    repurchase_summary.to_csv(
        OUTPUT_DIR / "repurchase_interval_summary.csv",
        index=False,
        encoding="utf-8-sig",
    )

    plot_rfm_segments(rfm_segments)
    plot_cohort_retention(cohort_pivot)
    plot_repurchase_intervals(repurchase_intervals)

    print(f"Customers: {len(rfm_customers):,}")
    print(f"RFM segments: {len(rfm_segments):,}")
    print(f"Cohorts: {len(cohort_pivot):,}")
    print(f"Repeat customers: {len(repurchase_intervals):,}")
    print(f"Outputs: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
