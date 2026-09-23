# GitHub 发布说明

## 当前状态

本地仓库位置：`C:\Users\刘涛\Documents\Codex\Olist-GitHub`

已完成：

- Git 仓库初始化，分支为 `main`
- 两个本地提交
- 未提交原始 CSV、`.env`、PBIX 或 PBIP 缓存

## 推送步骤

先在 GitHub 网页创建一个空仓库，不要勾选自动生成 README。
然后把下面的地址替换成你自己的仓库地址并执行：

```powershell
cd C:\Users\刘涛\Documents\Codex\Olist-GitHub
git remote add origin https://github.com/你的用户名/你的仓库名.git
git push -u origin main
```

如果以后修改了文件：

```powershell
git add .
git commit -m "Update project"
git push
```

## 建议仓库设置

- Description: Olist e-commerce analytics with MySQL, Python and Power BI
- Topics: `data-analysis`, `sql`, `python`, `power-bi`, `olist`, `customer-analytics`
- 勾选 README 作为仓库首页说明
