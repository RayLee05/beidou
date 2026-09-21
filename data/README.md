# data/ —— 数据目录

| 子目录 | 内容 | 是否入库 |
|---|---|---|
| `input/` | 离线 2 bit 中频样本与同名 metadata | 否（体积大，见 `.gitignore`） |
| `expected/` | 参考模型生成的黄金结果（小体积 JSON/CSV/二进制） | 是 |

输入 metadata 字段与校验规则见 `docs/INTERFACES.md` 第 1 节。
**禁止**把模拟器真值当作测量结果写入本目录的黄金文件。
