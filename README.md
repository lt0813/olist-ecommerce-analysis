# Olist 电商经营诊断

巴西 Olist 电商公开数据集的端到端经营分析项目：收入、履约、客户价值和卖家风险。

技术栈：MySQL + Python(pandas) + Power BI

## 核心结果

- 成交订单量：96,478
- GMV：15,422,605.23 BRL
- 客单价：159.86 BRL
- 复购客户率：3.00%
- 延迟率：8.11%
- 差评率：12.85%
- 风险卖家：22 家，涉及 GMV 1,384,771.19 BRL

## 目录结构

```text
.
├── data/README.md          # 数据来源和下载方式，不提交原始 CSV
├── sql/                    # 建库、导入、质检、视图、指标 SQL
├── python/                 # RFM、cohort、复购分析脚本与关键输出
├── powerbi/                # PBIP 报表源码、主题和建模脚本
├── docs/                   # 指标字典、阶段性发现、业务结论
└── README.md
```

## 数据来源

数据来自公开的 Brazilian E-Commerce Public Dataset by Olist。

- Kaggle: `olistbr/brazilian-ecommerce`
- 和鲸社区搜索 `Olist`

原始 CSV 不提交到仓库，下载和导入说明见 `data/README.md`。

## 使用步骤

1. 创建 MySQL 数据库并导入数据
2. 依次执行 `sql/` 中的脚本
3. 安装 Python 依赖并运行 `python/run_customer_analysis.py`
4. 打开 `powerbi/Olist电商五页看板.pbip` 查看报表
