# 自建免费节点订阅（每天/每 6 小时自动更新）

一个零依赖的 Node 脚本 + GitHub Actions：定时抓取多个公开免费节点源 → 清洗广告节点 → 去重 →
TCP 存活检测 → 输出一个**固定不变**的订阅链接，导入 V2rayN 后开启自动更新即可。

## 订阅地址（导入 V2rayN）

```
https://raw.githubusercontent.com/chenzhihan1751-cyber/node-sub-zixf/main/sub/base64.txt
```

备用（同一个内容，不同格式）：

| 文件 | 用途 |
|---|---|
| `sub/base64.txt` | **V2rayN / Shadowrocket / v2ray 系客户端订阅**（首选） |
| `sub/v2ray.txt` | 明文节点列表，想手动挑几条时看这个 |
| `sub/stats.json` | 本次抓取统计（每个源成功了几条、剔除了多少死节点） |

> 国内直连 `raw.githubusercontent.com` 不稳时，把域名换成镜像即可，路径不变：
> `https://raw.gitmirror.com/chenzhihan1751-cyber/node-sub-zixf/main/sub/base64.txt`

## V2rayN 里怎么设

1. `订阅 → 订阅分组 → 添加订阅`，地址填上面那条，备注随意，保存。
2. `订阅 → 更新订阅（含节点）`，拉下来后测延迟，挑能用的。
3. `设置 → 参数设置 → 订阅`：勾「自动更新订阅」，间隔填 `360`～`720` 分钟。
   本仓库每 6 小时重算一次，客户端跟着每 6～12 小时拉一次就够。

## 它是怎么工作的

```
sources.txt  ──抓取──▶  解码(base64/明文) ──▶ 清洗 ──▶ 去重 ──▶ TCP 存活检测 ──▶ sub/*
```

- **抓取**：`fetch-nodes.mjs` 读 `sources.txt` 里的地址；直连失败会自动走镜像
  （`raw.gitmirror.com` / `ghproxy.net` / `gh-proxy.com` / `jsDelivr`）。
- **清洗**：丢掉 remark 里带「剩余流量 / 到期 / 机场 / 加群 / 订阅」等字样的引流假节点，
  以及指向 `127.0.0.1`、内网段的无效地址。
- **去重**：按 `协议 + 服务器 + 端口 + 凭据` 计算指纹；同一个 `host:port` 最多留 2 条，防止某个源刷屏。
- **存活检测**：对每个节点做一次 TCP 连接（默认 3 秒超时、192 并发），
  只保留连得上的。若检测后数量异常少，会自动退回未检测的结果，避免把订阅清空。
- **安全阀**：最终节点数低于 `MIN_NODES`（默认 20）时脚本报错退出，
  Actions 不会提交，你的订阅保持上一版可用状态。

## 想改点什么

| 想改 | 改哪 |
|---|---|
| 加/删节点源 | 编辑 `sources.txt`，一行一个地址，提交后会自动跑一次 |
| 更新频率 | `.github/workflows/update.yml` 里的 `cron`（UTC 时间） |
| 跳过存活检测（更快） | workflow 里把 `TCP_CHECK: '1'` 改成 `'0'` |
| 单个节点源限制条数 | workflow 里加 `PER_HOSTPORT_MAX`（默认 2） |
| 手动跑一次 | 仓库 `Actions` 页 → `Update subscription` → `Run workflow` |

## 两个注意事项

1. **Actions 定时任务在仓库 60 天无活动时会被 GitHub 暂停**。本仓库每天都有机器提交，
   天然不会触发；万一哪天停了，去 Actions 页点一次 `Enable workflow` 即可。
2. **`schedule` 不保证准点**，GitHub 高峰期可能延迟几分钟到几十分钟，不影响使用。

## 安全提醒

这些节点来自公开免费源，由陌生人运营：适合查资料、看视频，
**不要在上面登录网银、主邮箱、主账号**。节点运营者能看到你流量的元数据，
未加密的 http 站点内容也在其中。请自行确认使用方式符合你所在地的法律和所访问服务的条款。
