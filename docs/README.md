# docs 索引

三类文档的当前权威等级不同，不要混用。

## Canonical / durable

当前事实，实现必须遵守：

- [`PRODUCT-SCOPE.md`](PRODUCT-SCOPE.md) — 产品定位、模式、饰品行为、updater 与 fork 边界的 canonical source。
- [`PLAYER-COSMETICS.md`](PLAYER-COSMETICS.md) — Player cosmetics 的长期 runtime 与行为说明。
- [`UPSTREAM.md`](UPSTREAM.md) — upstream ownership、同步政策与打包装配模型。精确版本 pin 在 `scripts/dependencies.json`，不在文档里。
- [`MANUAL-ACCEPTANCE.md`](MANUAL-ACCEPTANCE.md) — 长期实机验收清单。
- 根目录 `AGENTS.md` — 仓库级 agent 规则；`CONTRIBUTING.md` — 开发与验证入口。

## Historical / dated evidence

`archive/` 保存某一天的审计、某个 CS2 build 的兼容性调查、某次 upstream 版本评审和每一轮的实机回归记录。
它们解释「当时为什么这样决定」，**不是** current truth，也不能当作验收已通过的证据。

- `archive/MAIN-AUDIT-2026-09-23.md`
- `archive/CS2-2026-09-23-COMPATIBILITY.md`
- `archive/UPSTREAM-v1.4.4-REVIEW.md`
- `archive/Local-Arena-v1.4.3.2-richer-cosmetics-compatibility.md`
- `archive/ACCEPTANCE-RECORD-2026-09.md`

## Release notes

`releases/` 按版本保存已发布构建的说明，同样属于历史记录。

- `releases/Local-Arena-v1.4.3.1.md`
- `releases/Local-Arena-v1.4.3.3-CS2SS.md`

## 不属于 docs

`temp/` 是 task-local 的 agent 交接区（implementation plan、start prompt、handoff、并行对比材料），
已被 Git 忽略，不具备任何 canonical 权威。不要把当前任务的计划提升成长期文档，
也不要把阶段性内容写回 `PRODUCT-SCOPE.md`。
