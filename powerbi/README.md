# Power BI 报表

五页看板项目使用 Power BI Project (PBIP) 保存，源码位于本目录。

## 页面

1. 经营总览
2. 类目与地区
3. 履约与评价
4. 客户经营
5. 卖家风险

## 打开方式

直接打开 `Olist电商五页看板.pbip`。

如果希望得到单一 PBIX 文件，可以在 Power BI Desktop 中打开 PBIP 后，使用“另存为”保存为 `*.pbix`。

## 建模脚本

- `Setup_Olist_Model.ps1`：写入中文字段、度量值、关系和隐藏技术列
- `Install_Olist_Model.cmd`：双击调用上述脚本

脚本要求本机 Power BI Desktop 已打开并加载好分析视图。
