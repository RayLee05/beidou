# configs/ —— 运行期配置

| 文件 | 用途 |
|---|---|
| `b1i_default.json` | 默认配置：输入参数、捕获搜索范围、环路系数、同步超时、输出历元、debug 开关 |

约定：

- 配置字段含义与取值范围见 `docs/INTERFACES.md` 第 4 节。
- 与 `sw/b1i_ref/params.py` 重叠的字段由 `scripts/check_params_consistency.py` 强制一致。
- 禁止把验收门槛写死在配置里冒充已冻结值；未冻结项必须带 `*_note` 说明。
