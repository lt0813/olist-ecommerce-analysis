# Olist 指标字典

记录日期：2026-09-21

本字典用于统一 SQL、Python 和 Power BI 的口径。执行任何分析前，先确认指标口径没有变化。

## 1. 分析范围

- 成交订单：`orders.order_status = 'delivered'`。
- 时间趋势：按下单时间 `order_purchase_timestamp` 归属月份，不按送达月份。
- 客户身份：订单客户使用 `customer_id`，跨订单复购使用 `customer_unique_id`。
- 货币单位：原始数据金额为巴西雷亚尔 BRL，不在此阶段换算人民币或美元。
- 金额口径：总 GMV 使用支付金额；类目、地区和卖家金额使用商品价格加运费。

## 2. 核心指标

| 指标 | 指标键 | 口径 | 分母或说明 |
|---|---|---|---|
| GMV | `gmv` | 已送达订单的 `order_payments.payment_value` 求和；无支付记录时使用商品金额加运费兜底 | 仅 1 笔已送达订单缺少支付记录，兜底后保留 `payment_total` 供审计 |
| 商品成交额 | `item_value_with_freight` | 已送达订单的 `price + freight_value` 求和 | 用于类目、地区、卖家拆解 |
| 运费收入 | `freight_value` | 已送达订单的 `freight_value` 求和 | 属于商品成交额的一部分 |
| 成交订单量 | `delivered_orders` | 已送达订单去重计数 | `COUNT(*)`，订单粒度视图已去重 |
| 成交客户数 | `delivered_customers` | 有已送达订单的 `customer_unique_id` 去重计数 | 跨订单按自然人标识 |
| 客单价 | `average_order_value` | GMV / 成交订单量 | 使用支付金额 |
| 月度 GMV | `monthly_gmv` | 按下单月份汇总已送达订单支付金额 | 首月和末月可能不完整 |
| 类目 GMV | `category_gmv` | 已送达订单商品金额加运费，按商品类目汇总 | 多类目订单会分别计入多个类目 |
| 类目延迟率 | `category_late_order_rate_pct` | 订单在含有该类目的前提下，延迟订单数除以有送达时间的订单数 | 先聚合到订单粒度，再按类目统计 |
| 类目差评率 | `category_bad_review_rate_pct` | 订单在含有该类目的前提下，差评订单数除以有评价订单数 | 先聚合到订单粒度，再按类目统计 |
| 地区 GMV | `region_gmv` | 已送达订单支付金额，按客户 `customer_state` 汇总 | 订单粒度汇总 |
| 复购客户 | `repeat_customers` | 同一 `customer_unique_id` 至少有 2 个已送达订单 | 不把 `customer_id` 当作自然人 |
| 复购率 | `repeat_customer_rate_pct` | 复购客户数 / 成交客户数 | 百分比 |
| 复购客户 GMV 占比 | `repeat_customer_gmv_share_pct` | 复购客户 GMV / 全部客户 GMV | 排除仅浏览未成交客户 |
| 复购间隔 | `average_days_to_second_order` | 第二笔已送达订单下单时间减首笔下单时间 | 仅统计至少两笔订单的客户 |

## 3. 履约指标

| 指标 | 指标键 | 口径 |
|---|---|---|
| 支付审核时长 | `approval_days` | `order_approved_at - order_purchase_timestamp` |
| 卖家处理时长 | `seller_handling_days` | `order_delivered_carrier_date - order_approved_at` |
| 运输配送时长 | `carrier_delivery_days` | `order_delivered_customer_date - order_delivered_carrier_date` |
| 总履约时长 | `total_delivery_days` | `order_delivered_customer_date - order_purchase_timestamp` |
| 预计送达偏差 | `estimated_delay_days` | `order_delivered_customer_date - order_estimated_delivery_date` |
| 延迟订单 | `late_orders` | 实际送达时间晚于预计送达时间 |
| 延迟率 | `late_order_rate_pct` | 延迟订单数 / 同时有实际和预计送达时间的已送达订单数 |

延迟区间固定为：

- 准时：实际送达时间不晚于预计送达时间；
- 延迟 1 至 3 天；
- 延迟 4 至 7 天；
- 延迟 8 天及以上。

## 4. 评价指标

| 指标 | 指标键 | 口径 |
|---|---|---|
| 有评价订单数 | `reviewed_orders` | 至少有一条评价记录的已送达订单数 |
| 订单评价分 | `avg_review_score` | 同一订单多条评价先求平均 |
| 差评订单 | `bad_review_orders` | 同一订单的最低评分小于等于 2 分 |
| 差评率 | `bad_review_rate_pct` | 差评订单数 / 有评价订单数 |

没有评价的订单不进入差评率分母，避免把“未评价”等同于“满意”。

## 5. 客户分层与留存指标

RFM 的观察截止日为数据集中最后一笔已送达订单日期加 1 天。

| 分值 | 最近购买 R | 购买频次 F | 消费金额 M |
|---|---|---|---|
| 5 | 90 天以内 | 4 次及以上 | 金额排名前 20% |
| 4 | 91 至 180 天 | 3 次 | 金额排名 60% 至 80% |
| 3 | 181 至 270 天 | 2 次 | 金额排名 40% 至 60% |
| 2 | 271 至 365 天 | 不适用 | 金额排名 20% 至 40% |
| 1 | 超过 365 天 | 1 次 | 金额排名后 20% |

客户分层规则按以下优先级依次判断：

1. 高价值活跃：`R >= 4`、`F >= 4`、`M >= 4`；
2. 近期一次购买：`R >= 4`、`F = 1`；
3. 复购成长：`R >= 3`、`F >= 3`；
4. 高价值流失风险：`R <= 2`、`F >= 4`；
5. 流失客户：`R <= 2`、`F <= 2`；
6. 高消费待激活：`M >= 4`；
7. 一般客户：其余客户。

cohort 留存率定义：

- 每个客户的 cohort 为其首笔已送达订单所在月份；
- 月份 0 表示首购月份；
- 月份 N 留存客户数表示该 cohort 中在首购后第 N 个月再次产生已送达订单的客户数；
- 留存率 = 月份 N 留存客户数 / 该 cohort 的首购客户数。

复购间隔定义：

- 仅统计至少有两笔已送达订单的客户；
- 复购间隔 = 第二笔订单下单时间 - 第一笔订单下单时间；
- 同一自然日多笔订单会产生 0 天间隔，需要结合业务场景单独核查。

## 6. 卖家指标

| 指标 | 指标键 | 口径 |
|---|---|---|
| 卖家 GMV | `seller_gmv` | 已送达订单中该卖家商品金额加运费 |
| 卖家成交订单量 | `seller_delivered_orders` | 该卖家参与的已送达订单去重计数 |
| 卖家集中度 | `top_n_pct_seller_gmv_share_pct` | 按卖家 GMV 降序排名后，前 1%、5%、10% 卖家的 GMV 占比 |

卖家服务质量判断应设置最低订单量门槛。当前 SQL 的总体集中度和 Top 10 名单不设门槛，后续做风险分层时再补充最低订单量条件。

## 7. 已知口径差异

1. GMV 使用支付金额，类目、地区和卖家金额使用商品金额加运费。两者不能直接跨粒度相加。
2. 一个订单可以包含多个商品、卖家、支付记录和评价。订单级视图先聚合到订单粒度，避免一对多连接重复计算。
3. 多类目订单会让各分类目 GMV 之和高于订单支付 GMV，这是分类归属造成的正常重复，不是重复计算错误。
4. 月度趋势使用下单月份。若关心收入确认时间，应另建按送达月份归属的指标，不能与当前指标混用。
5. 延迟和差评只能说明相关，不能仅凭观察数据证明因果。
