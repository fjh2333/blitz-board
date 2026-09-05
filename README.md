# ♟️ Blitz Board — Monad 上的 5×5 链上闪电棋

> 完整国际象棋规则引擎无法在一次黑客松内完成。所以我们把棋盘收成 **5×5**，走子全部上链：**每步一笔交易，合约做裁判，吃掉对方王即胜，胜者自动铸造奖杯 NFT。**

**在线演示（公网，无需安装任何东西）**：https://fjh2333.github.io/blitz-board/

**合约（Monad Testnet, Chain 10143）**：`0xE2FaC0807C945118Fc93893ad81b4D477491Aa3D`

---

## 为什么是 Monad

| Monad 特性 | Blitz Board 怎么用 |
|---|---|
| 出块快、确认快 | 每步棋都是一笔交易，「闪电棋」的节奏靠快确认撑起来 |
| 并行执行 | 多桌对局互不共享 storage（不同 `gameId` 独立槽位），天然并行、互不冲突 |
| 按 gas **limit** 收费 | 前端用 `estimateGas` 精算 limit（仅 +15%），绝不写死大数浪费 MON |

## 玩法（60 秒上手）

1. 打开 Demo → 连接 MetaMask（自动切 Monad Testnet）
2. 「创建新局」执白，或从大厅列表一键加入别人的局执黑
3. 点自己的棋子：**绿点 = 可走格，红框 = 可吃子**（前端内置与合约同一套规则，互相校验）
4. 吃掉对方的王 → 对局结束，**奖杯 NFT 自动铸给胜者**（`tokenId` = 对局号，MetaMask 可见）
5. 超时 180 秒未走判负；也可以认输

v1 刻意简化：无将军/将死检测（可以送王，吃王即胜）、兵升变只升后、无易位/过路兵。规则边界写进合约注释与 README，不藏着。

## 架构

```
frontend/index.html      单文件 DApp：内嵌 ethers.js（零 CDN 依赖）、大厅列表、走子提示
        │  MetaMask → Monad Testnet RPC
        ▼
src/BlitzBoard.sol       对局状态机：create / join / move / resign / claimTimeout
  is ERC721              胜者铸奖杯（tokenId = gameId），CEI：先改状态再 mint
  ├─ src/lib/LibBoard.sol   棋盘打包：64 格 × 4bit = 一个 uint256（8×8 布局，v2 预留）
  └─ src/lib/LibMoves.sol   走法合法性：兵马象车后王，滑行射线遇盘外格即墙
```

**关键设计**

- **存储为 v2 冻结**：`squareId = file + rank*8`，64 格 × 4 bit 恰好装满一个 `uint256`。v1 只用 a1–e5，盘外格恒空且禁止落入。升级完整国际象棋时**不改对局账本**，只替换规则模块（`LibCheck` 将军/将死、易位/过路兵等）
- **棋谱不上 storage**：`event MovePlayed(...)` 记录历史，前端 `getLogs` 回放——对比往动态数组无限 `push`，省 gas 且天然可回放
- **双实现互校验**：走法规则在 Solidity（裁判）和 JS（提示）各写一份。实战中正是两边不一致暴露了一个「反斜线滑行」bug（`df==dr` 漏掉 `df==-dr`），已修复并加回归测试
- **对局结构 ≤ 4 个 storage slot**：`board / white / black / packed(lastMoveAt, moveCount, status, toMove)`

## 测试

24 个 Foundry 测试全绿，覆盖：开局编解码 roundtrip、各棋子走法、盘外格即墙、吃王终局 + mint、防重复 mint、超时判定（含过早调用）、认输、升变、反斜线回归。

```bash
forge install && forge test -vv
```

## 本地运行前端

```bash
cd frontend && python3 -m http.server 3000
# 打开 http://localhost:3000（或直接用上面的 GitHub Pages 在线版）
```

前端为单 HTML 文件：ethers.js 已内嵌，无构建步骤、无后端、无 CDN 依赖——现场网络再差也能跑。

## 升级路径

| 版本 | 内容 | 状态 |
|---|---|---|
| v1 | 5×5 迷你棋 + 吃王即胜 + 奖杯 NFT + 多桌并行 | ✅ 本次交付 |
| v2 | 完整 8×8：将军/将死/逼和、易位、过路兵、升变多选 | 存储已预留，替换规则模块即可 |
| v3 | AI 对战 + 观战质押 | 结算合约只读 `status/winner`，不改棋盘 |

## 团队

Monad Blitz @惠州 · 合约 + 前端 + 部署：[@fjh2333](https://github.com/fjh2333)（AI 结对开发）
