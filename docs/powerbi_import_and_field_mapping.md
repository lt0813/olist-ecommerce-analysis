# Power BI 导入与字段映射

记录日期：2026-09-21

## 1. 先理解长 ID

Power BI 中出现的这些长字符串是数据库关联键，不是给人阅读的业务名称：

- `order_id`：订单唯一编号，用来区分每一笔订单；
- `customer_id`：订单中的客户记录编号，一单一个；
- `customer_unique_id`：同一个自然人跨订单使用的编号，用于计算复购；
- `product_id`：商品唯一编号；
- `seller_id`：卖家唯一编号。

这些 ID 用于建立表关系和去重，不应该直接放到看板卡片、图例或表格中。看板使用地区、类目、日期、金额、订单量等可读字段。

## 2. 不要导入全部原始表

Power BI 初次建模只需要导入：

1. `v_order_analytics`：订单经营事实表；
2. `v_customer_analytics`：客户复购与价值表。

暂时不要导入：

- `geolocation`：约 100 万行，主要给地理编码和地图使用；
- `customers`、`orders`、`order_items`、`order_payments`、`order_reviews` 等原始表；
- `product_category_translation`，因为类目翻译已经可以并入专用视图。

如果已经在 Power BI 中勾选了原始表，在“转换数据”中移除这些查询，或在模型视图中删除对应表，只保留两张分析视图。

## 3. `v_order_analytics` 字段说明

| 英文字段 | Power BI 显示名 | 用途 | 是否隐藏技术字段 |
|---|---|---|---|
| `order_id` | 订单编号 | 订单去重和关联 | 是 |
| `customer_id` | 客户记录编号 | 技术关联 | 是 |
| `customer_unique_id` | 客户唯一编号 | 客户复购、客户维度关联 | 可用于关系，表格中隐藏 |
| `customer_state` | 客户州 | 地区分析 | 否 |
| `order_status` | 订单状态 | 状态筛选 | 否 |
| `purchase_date` | 下单日期 | 日期轴 | 否 |
| `purchase_month` | 下单月份 | 月度趋势 | 否 |
| `order_purchase_timestamp` | 下单时间 | 精确时间分析 | 否，暂时可隐藏 |
| `order_approved_at` | 支付审核时间 | 履约拆分 | 否，暂时可隐藏 |
| `order_delivered_carrier_date` | 交付承运时间 | 履约拆分 | 否，暂时可隐藏 |
| `order_delivered_customer_date` | 客户签收时间 | 履约拆分 | 否，暂时可隐藏 |
| `order_estimated_delivery_date` | 预计送达时间 | 延迟判断 | 否 |
| `payment_count` | 支付记录数 | 数据质量检查 | 是 |
| `payment_total` | 原始支付金额 | 口径校验 | 否，暂时可隐藏 |
| `payment_type_count` | 支付方式数 | 数据质量检查 | 是 |
| `item_count` | 商品行数 | 订单商品数量 | 否 |
| `item_total` | 商品金额含运费 | 商品口径金额 | 否 |
| `freight_total` | 运费金额 | 运费分析 | 否 |
| `seller_count` | 卖家数 | 多卖家订单分析 | 否 |
| `recognized_gmv` | GMV | 经营金额 | 否 |
| `review_count` | 评价记录数 | 差评率分母 | 是 |
| `avg_review_score` | 订单平均评分 | 评价分析 | 否 |
| `min_review_score` | 订单最低评分 | 差评判断 | 是 |
| `is_delivered` | 是否成交 | 1 表示已送达 | 可转换为是/否 |
| `has_delivery_dates` | 是否有履约日期 | 延迟率分母 | 是 |
| `is_late` | 是否延迟 | 1 表示延迟 | 可转换为是/否 |
| `is_bad_review` | 是否差评 | 1 表示最低评分小于等于 2 | 可转换为是/否 |
| `approval_days` | 支付审核天数 | 履约阶段 | 否 |
| `seller_handling_days` | 卖家处理天数 | 履约阶段 | 否 |
| `carrier_delivery_days` | 运输配送天数 | 履约阶段 | 否 |
| `total_delivery_days` | 总履约天数 | 履约分析 | 否 |
| `estimated_delay_days` | 预计送达偏差天数 | 延迟分析 | 否 |

## 4. `v_customer_analytics` 字段说明

| 英文字段 | Power BI 显示名 | 用途 |
|---|---|---|
| `customer_unique_id` | 客户唯一编号 | 客户主键，表格中隐藏 |
| `delivered_orders` | 成交订单数 | 复购次数 |
| `customer_gmv` | 客户累计 GMV | 客户价值 |
| `first_order_at` | 首购时间 | 首购 cohort |
| `last_order_at` | 最近购买时间 | 活跃度、RFM |
| `reviewed_orders` | 有评价订单数 | 客户评价覆盖率 |
| `bad_review_orders` | 差评订单数 | 客户体验 |
| `orders_with_delivery_dates` | 有履约日期订单数 | 延迟率分母 |
| `late_orders` | 延迟订单数 | 客户履约体验 |
| `avg_review_score` | 客户平均评分 | 体验评分 |
| `is_repeat_customer` | 是否复购客户 | 1 表示至少两笔成交订单 |

## 5. Power BI 中的改名方法

在 Power Query 中双击字段标题直接改名，例如：

```text
recognized_gmv -> GMV
delivered_orders -> 成交订单数
customer_gmv -> 客户累计GMV
is_repeat_customer -> 是否复购客户
```

名称可以保留英文字段，使用 Power BI 的“属性/名称”功能显示中文友好名称。不要在数据库里为了看板展示而随意修改字段技术名。

## 6. 技术字段处理

在模型视图或报表视图右键字段，选择“在报表视图中隐藏”：

- `order_id`
- `customer_id`
- `payment_count`
- `payment_type_count`
- `review_count`
- `min_review_score`

不要删除用于关系的字段。隐藏只影响报表展示，不会破坏模型关系。

## 7. 关系设置

在模型视图中建立：

```text
v_customer_analytics[1] customer_unique_id
        -> *
v_order_analytics[customer_unique_id]
```

关系方向使用单向，从客户表筛选订单表。不要使用双向关系，除非后续明确需要并验证了筛选传播。

## 8. 第一页只使用这些字段

经营总览页：

- 卡片：GMV、成交订单量、客单价、复购客户率、延迟率、差评率；
- 折线图：下单月份、GMV、成交订单量；
- 条形图：客户州、GMV；
- 类目表：类目名称、GMV、订单量；
- 切片器：下单日期、客户州、订单状态。

## 9. 类目与卖家数据

类目与卖家页使用以下支持视图，不要直接在订单事实表中按商品或卖家汇总：

```text
v_order_item_analytics
v_category_analytics
v_seller_risk_analytics
```

## 10. `v_order_item_analytics` 字段说明

这是一张订单商品明细视图，一行代表一个订单商品行，只包含已送达订单。

| 英文字段 | Power BI 显示名 | 用途 |
|---|---|---|
| `order_id` | 订单编号 | 关联和去重，隐藏 |
| `customer_unique_id` | 客户唯一编号 | 客户关联和去重，隐藏 |
| `customer_state` | 客户州 | 地区与类目交叉分析 |
| `purchase_date` | 下单日期 | 日期切片 |
| `purchase_month` | 下单月份 | 月度趋势 |
| `order_item_id` | 商品行序号 | 技术字段，隐藏 |
| `product_id` | 商品编号 | 技术字段，隐藏 |
| `product_category_name` | 原始类目名 | 技术字段，隐藏 |
| `category_name` | 商品类目 | 类目分析 |
| `seller_id` | 卖家编号 | 技术字段，隐藏 |
| `seller_state` | 卖家州 | 卖家地区 |
| `seller_city` | 卖家城市 | 卖家地区 |
| `price` | 商品价格 | 商品金额拆分 |
| `freight_value` | 运费金额 | 运费分析 |
| `item_total` | 商品金额含运费 | 类目、卖家与地区金额 |

订单级延迟和差评字段在商品明细中会重复出现，因此不直接用这张表计算延迟率或差评率。

## 11. `v_category_analytics` 字段说明

这张视图已经聚合到类目粒度，适合直接制作类目销售和风险表。

| 英文字段 | Power BI 显示名 | 用途 |
|---|---|---|
| `category_name` | 商品类目 | 类目名称 |
| `delivered_orders` | 类目成交订单数 | 类目订单规模 |
| `item_rows` | 商品行数 | 商品明细行数 |
| `product_count` | 商品数 | 类目 SKU 数 |
| `category_gmv` | 类目GMV | 商品金额加运费 |
| `product_value` | 类目商品金额 | 商品价格 |
| `freight_value` | 类目运费金额 | 运费 |
| `average_item_price` | 类目平均商品价格 | 商品价格均价 |
| `gmv_share_pct` | 类目GMV占比 | 占全部类目商品金额比例 |
| `late_order_rate_pct` | 类目延迟率 | 订单级延迟率 |
| `bad_review_rate_pct` | 类目差评率 | 订单级差评率 |
| `average_review_score` | 类目平均评分 | 订单平均评分再平均 |

## 12. `v_seller_risk_analytics` 字段说明

这张视图已经聚合到卖家粒度，并给出风险筛选字段。

| 英文字段 | Power BI 显示名 | 用途 |
|---|---|---|
| `seller_id` | 卖家编号 | 完整技术编号，隐藏 |
| `seller_short_id` | 卖家简称 | 表格展示用 8 位编号 |
| `seller_state` | 卖家州 | 卖家地区 |
| `seller_city` | 卖家城市 | 卖家地区 |
| `delivered_orders` | 卖家成交订单数 | 样本规模 |
| `seller_gmv` | 卖家GMV | 卖家商品金额加运费 |
| `late_order_rate_pct` | 卖家延迟率 | 订单级延迟率 |
| `bad_review_rate_pct` | 卖家差评率 | 订单级差评率 |
| `average_seller_handling_days` | 卖家处理天数 | 履约阶段 |
| `average_carrier_delivery_days` | 运输配送天数 | 履约阶段 |
| `average_review_score` | 卖家平均评分 | 评价体验 |
| `seller_gmv_share_pct` | 卖家GMV占比 | 收入贡献 |
| `risk_tier` | 风险层级 | `high_risk`、`watchlist`、`normal` |
| `risk_reason` | 风险原因 | 延迟率或差评率偏高 |
| `is_risk_candidate` | 是否风险卖家 | 1 表示达到风险筛选门槛 |

风险筛选至少要求 200 笔成交订单，避免小样本卖家因个别订单产生极端比例。
