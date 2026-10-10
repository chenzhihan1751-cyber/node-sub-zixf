# 免费节点订阅 · 每 6 小时自动更新（V2rayN / Clash / Mihomo）

> 全自动的**免费 v2ray / clash 节点订阅**：每 6 小时聚合 9 个公开源，自动**清洗广告节点、去重、TCP 存活检测**，
> 输出可直接导入 **V2rayN / v2rayNG / Clash / Mihomo / sing-box** 的订阅链接。
> Free v2ray & clash nodes subscription, auto-updated every 6 hours by GitHub Actions.

## 订阅地址（复制即用）

**V2rayN / v2rayNG / Shadowrocket（base64 订阅）**

```
https://raw.githubusercontent.com/chenzhihan1751-cyber/node-sub-zixf/main/sub/base64.txt
```

**明文节点列表**（想手动挑几条时看这个）

```
https://raw.githubusercontent.com/chenzhihan1751-cyber/node-sub-zixf/main/sub/v2ray.txt
```

**国内直连 raw 不稳时的镜像**（路径不变，只换域名）

```
https://hk.gh-proxy.com/https://raw.githubusercontent.com/chenzhihan1751-cyber/node-sub-zixf/main/sub/base64.txt
```

```
https://gh-proxy.com/https://raw.githubusercontent.com/chenzhihan1751-cyber/node-sub-zixf/main/sub/base64.txt
```

## 怎么用

**V2rayN / v2rayNG**：`订阅 → 订阅分组 → 添加订阅` 填上面的链接 → `更新订阅（含节点）` →
`设置 → 参数设置 → 订阅` 勾「自动更新订阅」，间隔填 `360` 分钟，之后就不用管了。

**Clash / Mihomo 用户**：本项目的产出是 v2ray 系协议（vless / vmess / trojan / ss / hysteria2），
Clash 系客户端可用 [subconverter](https://github.com/tindy2013/subconverter) 之类工具转换，或直接用支持 v2ray 的客户端。

## 它比"随手找个免费订阅"好在哪

| 处理 | 说明 |
|---|---|
| **清洗** | 丢掉 remark 里带「剩余流量 / 到期 / 机场 / 加群 / 订阅」等字样的引流假节点，以及指向内网段、`127.0.0.1` 的无效地址 |
| **去重** | 按 `协议 + 服务器 + 端口 + 凭据` 计算指纹；同一个 `host:port` 最多保留 2 条，防止某个源刷屏 |
| **存活检测** | 每个节点做一次 TCP 连接测试（3 秒超时、192 并发），只保留连得上的 —— 这一步行情通常能砍掉 **60%～70%** 的死节点 |
| **安全阀** | 检测后节点数异常少时自动退回未检测结果；最终少于 20 个则整个任务失败、不提交，订阅永远停在上一版可用状态 |

实测一轮：**11439 条原始 → 清洗去重 4886 条 → 存活检测后 2000+ 条**，全程约 45 秒。

## 自动化

由 GitHub Actions 驱动（`.github/workflows/update.yml`），每 6 小时跑一次，也在 `sources.txt` 变更时触发：

```
sources.txt ──抓取──▶ 解码(base64/明文) ──▶ 清洗 ──▶ 去重 ──▶ TCP 存活检测 ──▶ sub/*
```

| 文件 | 内容 |
|---|---|
| `sub/base64.txt` | **base64 订阅（客户端填这个）** |
| `sub/v2ray.txt` | 明文节点列表 |
| `sub/stats.json` | 本次抓取统计：每个源成功几条、剔除多少死节点 |
| `sources.txt` | 上游源列表，一行一个 |
| `fetch-nodes.mjs` | 聚合脚本，零第三方依赖（Node 18+） |

## 常见问题

**节点质量怎么样？** 免费节点普遍寿命短、限速、时好时坏 —— 这是所有免费源的共同问题，不只是本项目。
订阅里节点很多，**建议导入后自己在客户端里跑一遍「测试真连接延迟」再挑**（TCP 通不代表真能代理）。

**为什么有的节点连不上？** 免费节点由陌生人运营，随时可能下线或被封；TCP 检测只能证明"端口开着"，
代理是否真能用需要客户端实测。

**更新频率**：每 6 小时一次。别人拉取时走的是 GitHub 的 CDN，本项目没有服务器，也不消耗维护者带宽。

## 免责声明

本项目仅自动聚合互联网上**已公开**的节点信息，不生产、不销售、不运营任何节点，也不对可用性作任何保证。
所有节点均来自第三方公开源，使用者需自行判断合规性并承担风险。**请勿在公共免费节点上登录网银、主邮箱等重要账号。**

## License

MIT
