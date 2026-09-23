$ErrorActionPreference = "Stop"

$powerBiBin = "D:\powerbi\bin"
$tabularAssembly = Join-Path $powerBiBin "Microsoft.PowerBI.Tabular.dll"

if (-not (Test-Path -LiteralPath $tabularAssembly)) {
    throw "Power BI Tabular assembly not found: $tabularAssembly"
}

$msmdProcess = Get-Process -Name "msmdsrv" -ErrorAction SilentlyContinue |
    Sort-Object StartTime -Descending |
    Select-Object -First 1

if (-not $msmdProcess) {
    throw "Power BI model process is not running. Open Power BI Desktop first."
}

try {
    $port = Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Where-Object {
            $_.OwningProcess -eq $msmdProcess.Id -and
            $_.LocalAddress -in @("127.0.0.1", "::1")
        } |
        Select-Object -First 1 -ExpandProperty LocalPort
}
catch {
    $port = netstat -ano -p tcp |
        ForEach-Object {
            if ($_ -match '^\s*TCP\s+(.+):(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$' -and
                [int]$Matches[3] -eq $msmdProcess.Id -and
                $Matches[1] -in @("127.0.0.1", "[::1]")) {
                [int]$Matches[2]
            }
        } |
        Select-Object -First 1
}

if (-not $port) {
    throw "Cannot find the local Power BI model port."
}

[System.Reflection.Assembly]::LoadFrom($tabularAssembly) | Out-Null

function Get-ModelColumn {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Table,
        [Parameter(Mandatory = $true)]
        [string[]]$CandidateNames
    )

    foreach ($name in $CandidateNames) {
        $column = $Table.Columns | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($column) {
            return $column
        }
    }

    throw "Column not found in table '$($Table.Name)': $($CandidateNames -join ', ')"
}

function Get-ModelTable {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Model,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $Model.Tables |
        Where-Object {
            $_.Name -eq $Name -or
            $_.Name.EndsWith(" $Name", [System.StringComparison]::OrdinalIgnoreCase)
        } |
        Select-Object -First 1
}

function Ensure-ColumnName {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Table,
        [Parameter(Mandatory = $true)]
        [string]$SourceName,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $column = $Table.Columns | Where-Object { $_.Name -eq $DisplayName } | Select-Object -First 1
    if (-not $column) {
        $column = $Table.Columns | Where-Object { $_.Name -eq $SourceName } | Select-Object -First 1
    }
    if (-not $column) {
        return $null
    }

    $column.Name = $DisplayName
    return $column
}

function Hide-ColumnIfExists {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Table,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $column = $Table.Columns | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($column) {
        $column.IsHidden = $true
    }
}

function Ensure-Measure {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Table,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Expression,
        [string]$FormatString = ""
    )

    $measure = $Table.Measures | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $measure) {
        $measure = New-Object Microsoft.AnalysisServices.Tabular.Measure
        $measure.Name = $Name
        $Table.Measures.Add($measure)
    }

    $measure.Expression = $Expression
    if ($FormatString) {
        $measure.FormatString = $FormatString
    }
}

$server = New-Object Microsoft.AnalysisServices.Tabular.Server
$server.Connect("localhost:$port")

try {
    $database = $server.Databases | Select-Object -First 1
    if (-not $database) {
        throw "No Power BI model is open."
    }

    $model = $database.Model
    $orders = Get-ModelTable -Model $model -Name "v_order_analytics"
    $customers = Get-ModelTable -Model $model -Name "v_customer_analytics"
    $orderItems = Get-ModelTable -Model $model -Name "v_order_item_analytics"
    $categories = Get-ModelTable -Model $model -Name "v_category_analytics"
    $sellers = Get-ModelTable -Model $model -Name "v_seller_risk_analytics"

    if (-not $orders -or -not $customers) {
        $available = ($model.Tables | ForEach-Object { $_.Name }) -join ", "
        throw "Required views are missing. Import v_order_analytics and v_customer_analytics first. Available tables: $available"
    }

    @(
        @{ Table = $orders; Name = "v_order_analytics" },
        @{ Table = $customers; Name = "v_customer_analytics" },
        @{ Table = $orderItems; Name = "v_order_item_analytics" },
        @{ Table = $categories; Name = "v_category_analytics" },
        @{ Table = $sellers; Name = "v_seller_risk_analytics" }
    ) |
        Where-Object { $_.Table } |
        ForEach-Object { $_.Table.Name = $_.Name }

    Ensure-ColumnName -Table $orders -SourceName "customer_state" -DisplayName "客户州" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "purchase_date" -DisplayName "下单日期" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "purchase_month" -DisplayName "下单月份" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "item_count" -DisplayName "商品行数" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "item_total" -DisplayName "商品金额含运费" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "freight_total" -DisplayName "运费金额" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "total_delivery_days" -DisplayName "总履约天数" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "is_late" -DisplayName "是否延迟" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "is_bad_review" -DisplayName "是否差评" | Out-Null
    Ensure-ColumnName -Table $orders -SourceName "avg_review_score" -DisplayName "订单平均评分" | Out-Null

    Ensure-ColumnName -Table $customers -SourceName "delivered_orders" -DisplayName "成交订单数" | Out-Null
    Ensure-ColumnName -Table $customers -SourceName "customer_gmv" -DisplayName "客户累计消费" | Out-Null
    Ensure-ColumnName -Table $customers -SourceName "first_order_at" -DisplayName "首购时间" | Out-Null
    Ensure-ColumnName -Table $customers -SourceName "last_order_at" -DisplayName "最近购买时间" | Out-Null
    Ensure-ColumnName -Table $customers -SourceName "is_repeat_customer" -DisplayName "是否复购客户" | Out-Null

    if ($orderItems) {
        Ensure-ColumnName -Table $orderItems -SourceName "customer_state" -DisplayName "客户州" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "purchase_date" -DisplayName "下单日期" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "purchase_month" -DisplayName "下单月份" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "category_name" -DisplayName "商品类目" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "seller_state" -DisplayName "卖家州" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "seller_city" -DisplayName "卖家城市" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "price" -DisplayName "商品价格" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "freight_value" -DisplayName "运费金额" | Out-Null
        Ensure-ColumnName -Table $orderItems -SourceName "item_total" -DisplayName "商品金额含运费" | Out-Null
    }

    if ($categories) {
        Ensure-ColumnName -Table $categories -SourceName "category_name" -DisplayName "商品类目" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "delivered_orders" -DisplayName "类目成交订单数" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "item_rows" -DisplayName "商品行数" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "product_count" -DisplayName "商品数" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "category_gmv" -DisplayName "类目GMV" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "product_value" -DisplayName "类目商品金额" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "freight_value" -DisplayName "类目运费金额" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "average_item_price" -DisplayName "类目平均商品价格" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "gmv_share_pct" -DisplayName "类目GMV占比" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "late_order_rate_pct" -DisplayName "类目延迟率" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "bad_review_rate_pct" -DisplayName "类目差评率" | Out-Null
        Ensure-ColumnName -Table $categories -SourceName "average_review_score" -DisplayName "类目平均评分" | Out-Null
    }

    if ($sellers) {
        Ensure-ColumnName -Table $sellers -SourceName "seller_short_id" -DisplayName "卖家简称" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "seller_state" -DisplayName "卖家州" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "seller_city" -DisplayName "卖家城市" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "delivered_orders" -DisplayName "卖家成交订单数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "seller_gmv" -DisplayName "卖家GMV" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "late_orders" -DisplayName "延迟订单数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "orders_with_delivery_dates" -DisplayName "有履约日期订单数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "late_order_rate_pct" -DisplayName "卖家延迟率" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "reviewed_orders" -DisplayName "有评价订单数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "bad_review_orders" -DisplayName "差评订单数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "bad_review_rate_pct" -DisplayName "卖家差评率" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "average_seller_handling_days" -DisplayName "卖家处理天数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "average_carrier_delivery_days" -DisplayName "运输配送天数" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "average_review_score" -DisplayName "卖家平均评分" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "seller_gmv_share_pct" -DisplayName "卖家GMV占比" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "risk_tier" -DisplayName "风险层级" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "risk_reason" -DisplayName "风险原因" | Out-Null
        Ensure-ColumnName -Table $sellers -SourceName "is_risk_candidate" -DisplayName "是否风险卖家" | Out-Null
    }

    @(
        "order_id",
        "customer_id",
        "customer_unique_id",
        "payment_count",
        "payment_total",
        "payment_type_count",
        "review_count",
        "min_review_score",
        "has_delivery_dates",
        "recognized_gmv"
    ) | ForEach-Object { Hide-ColumnIfExists -Table $orders -Name $_ }

    Hide-ColumnIfExists -Table $customers -Name "customer_unique_id"

    if ($orderItems) {
        @(
            "order_id",
            "order_item_id",
            "product_id",
            "seller_id",
            "product_category_name",
            "review_count",
            "has_delivery_dates",
            "is_late",
            "is_bad_review"
        ) | ForEach-Object { Hide-ColumnIfExists -Table $orderItems -Name $_ }
    }

    if ($sellers) {
        @(
            "seller_id",
            "late_orders",
            "orders_with_delivery_dates",
            "reviewed_orders",
            "bad_review_orders"
        ) | ForEach-Object { Hide-ColumnIfExists -Table $sellers -Name $_ }
    }

    $gmvDax = "CALCULATE(SUM('v_order_analytics'[recognized_gmv]), 'v_order_analytics'[is_delivered] = 1)"
    Ensure-Measure -Table $orders -Name "GMV" -Expression $gmvDax -FormatString "#,0.00"

    $orderCountDax = "CALCULATE(DISTINCTCOUNT('v_order_analytics'[order_id]), 'v_order_analytics'[is_delivered] = 1)"
    Ensure-Measure -Table $orders -Name "成交订单量" -Expression $orderCountDax -FormatString "#,0"

    $averageOrderValueDax = "DIVIDE([GMV], [成交订单量])"
    Ensure-Measure -Table $orders -Name "客单价" -Expression $averageOrderValueDax -FormatString "#,0.00"

    $lateRateDax = "DIVIDE(CALCULATE(SUM('v_order_analytics'[是否延迟]), 'v_order_analytics'[is_delivered] = 1), CALCULATE(SUM('v_order_analytics'[has_delivery_dates]), 'v_order_analytics'[is_delivered] = 1))"
    Ensure-Measure -Table $orders -Name "延迟率" -Expression $lateRateDax -FormatString "0.00%"

    $badReviewRateDax = "DIVIDE(CALCULATE(SUM('v_order_analytics'[是否差评]), 'v_order_analytics'[is_delivered] = 1), CALCULATE(COUNTROWS('v_order_analytics'), 'v_order_analytics'[is_delivered] = 1, 'v_order_analytics'[review_count] > 0))"
    Ensure-Measure -Table $orders -Name "差评率" -Expression $badReviewRateDax -FormatString "0.00%"

    $averageDeliveryDaysDax = "CALCULATE(AVERAGE('v_order_analytics'[总履约天数]), 'v_order_analytics'[is_delivered] = 1)"
    Ensure-Measure -Table $orders -Name "平均履约天数" -Expression $averageDeliveryDaysDax -FormatString "#,0.00"

    $customerCountDax = "COUNTROWS('v_customer_analytics')"
    Ensure-Measure -Table $customers -Name "成交客户数" -Expression $customerCountDax -FormatString "#,0"

    $repeatCustomerCountDax = "SUM('v_customer_analytics'[是否复购客户])"
    Ensure-Measure -Table $customers -Name "复购客户数" -Expression $repeatCustomerCountDax -FormatString "#,0"

    $repeatCustomerRateDax = "DIVIDE([复购客户数], [成交客户数])"
    Ensure-Measure -Table $customers -Name "复购客户率" -Expression $repeatCustomerRateDax -FormatString "0.00%"

    $customerAverageSpendDax = "AVERAGE('v_customer_analytics'[客户累计消费])"
    Ensure-Measure -Table $customers -Name "客户平均消费" -Expression $customerAverageSpendDax -FormatString "#,0.00"

    if ($sellers) {
        $riskSellerCountDax = "CALCULATE(COUNTROWS('v_seller_risk_analytics'), 'v_seller_risk_analytics'[是否风险卖家] = 1)"
        Ensure-Measure -Table $sellers -Name "风险卖家数" -Expression $riskSellerCountDax -FormatString "#,0"

        $riskSellerGmvDax = "CALCULATE(SUM('v_seller_risk_analytics'[卖家GMV]), 'v_seller_risk_analytics'[是否风险卖家] = 1)"
        Ensure-Measure -Table $sellers -Name "风险卖家GMV" -Expression $riskSellerGmvDax -FormatString "#,0.00"

        $riskSellerGmvShareDax = "DIVIDE([风险卖家GMV], SUM('v_seller_risk_analytics'[卖家GMV]))"
        Ensure-Measure -Table $sellers -Name "风险卖家GMV占比" -Expression $riskSellerGmvShareDax -FormatString "0.00%"

        $riskSellerLateRateDax = "CALCULATE(AVERAGE('v_seller_risk_analytics'[卖家延迟率]), 'v_seller_risk_analytics'[是否风险卖家] = 1)"
        Ensure-Measure -Table $sellers -Name "风险卖家平均延迟率" -Expression $riskSellerLateRateDax -FormatString "0.00%"

        $riskSellerBadReviewRateDax = "CALCULATE(AVERAGE('v_seller_risk_analytics'[卖家差评率]), 'v_seller_risk_analytics'[是否风险卖家] = 1)"
        Ensure-Measure -Table $sellers -Name "风险卖家平均差评率" -Expression $riskSellerBadReviewRateDax -FormatString "0.00%"
    }

    $existingRelationship = $model.Relationships |
        Where-Object {
            $_.FromColumn -and
            $_.ToColumn -and
            $_.FromColumn.Name -eq "customer_unique_id" -and
            $_.ToColumn.Name -eq "customer_unique_id"
        } |
        Select-Object -First 1

    if (-not $existingRelationship) {
        $relationship = New-Object Microsoft.AnalysisServices.Tabular.SingleColumnRelationship
        $relationship.FromCardinality = [Microsoft.AnalysisServices.Tabular.RelationshipEndCardinality]::Many
        $relationship.ToCardinality = [Microsoft.AnalysisServices.Tabular.RelationshipEndCardinality]::One
        $relationship.FromColumn = Get-ModelColumn -Table $orders -CandidateNames @("customer_unique_id")
        $relationship.ToColumn = Get-ModelColumn -Table $customers -CandidateNames @("customer_unique_id")
        $relationship.CrossFilteringBehavior = [Microsoft.AnalysisServices.Tabular.CrossFilteringBehavior]::OneDirection
        $model.Relationships.Add($relationship)
    }

    $model.SaveChanges() | Out-Null
    $supportingTableCount = (
        @($orderItems, $categories, $sellers) |
            Where-Object { $_ }
    ).Count
    Write-Host "Olist Power BI model setup completed." -ForegroundColor Green
    Write-Host "Created/updated core and seller DAX measures, Chinese field names, hidden technical IDs, and the customer relationship."
    Write-Host "Prepared $supportingTableCount supporting category/item/seller tables."
}
finally {
    if ($server.Connected) {
        $server.Disconnect()
    }
}
