# 工具链与运行环境

## 结论先说

- **正式仿真/综合在虚拟机 `IC`（10.156.34.6）里做**：VCS 做 RTL 仿真，Design Compiler 做综合。
- 本机（Windows）只用来**写代码、跑 Python 参考模型、生成测试向量**；
  本机的 Icarus Verilog 只是"没有 VCS 时的兜底"。
- **虚拟机里没有 git**（见 `VM-IC-SSH连接指南.md`），代码用 scp/tar 同步。

## 0. 虚拟机实测结论（2026-09-28 已验证）

| 项 | 实测值 |
|---|---|
| 主机/用户 | `IC` / `7902_13`（与文档一致，主机指纹 MD5:09:76:...:8d:9a） |
| 免密公钥 | **失效**（publickey 被拒）；改用文档附录 A 的 **SSH_ASKPASS 密码认证可用** |
| EDA 环境 | `source /etc/profile.d/eda.sh` —— 一次性设置 Synopsys/Cadence/Mentor/KeySight |
| VCS | `$VCS_HOME=/opt/Synopsys/VCS2014`，`vcs -ID` → **VCS-MX I-2014.03**，License 可用 |
| 其它 | ICC2016、PrimeTime2015、Formality2016、StarRC2015、Verdi2015、Calibre2015、Innovus15、ModelSim |
| 工程目录 | `/home/7902_13/beidou`（已创建） |
| 实测用例 | `make TEST=tb_carrier_lut` → **PASS**（VCS 编译+仿真） |

**VCS 2014 注意事项**（已写进 Makefile）：
1. `-debug_access+all` 在 2014 版属 LCA 特性，会报 `LCA_FEATURES_NEED_OPTION`，默认不要加；
   需要波形时用 `make VCSFLAGS=-debug_pp`（或按手册加 `-lca`）。
2. testbench 路径要按名字解析到 `tb/unit/` 或 `tb/system/`，不能写死 `tb/xxx.sv`。

**同步方式**（虚拟机无 git）：

```powershell
tar -czf $env:TEMP\beidou.tgz -C <repo> --exclude=.git --exclude=tmp --exclude=.scratch --exclude='*.pdf' .
scp -o HostKeyAlgorithms=+ssh-rsa $env:TEMP\beidou.tgz 7902_13@10.156.34.6:/home/7902_13/
ssh 7902_13@10.156.34.6 "cd /home/7902_13/beidou && tar xzf ../beidou.tgz"
```

## 1. 虚拟机侧（VCS / DC）

| 项 | 说明 |
|---|---|
| 登录 | `ssh vm-ic`（免密）或 `ssh -o HostKeyAlgorithms=+ssh-rsa 7902_13@10.156.34.6` |
| 家目录 | `/home/7902_13`（多人共用，建议各自建子目录） |
| Python | 系统自带 **2.6.6** —— 仓库里的脚本需要 Python 3，请在本地跑 |
| git | **没有** —— 用 `scp -r` 或 `tar` 同步 |
| 仿真 | Synopsys VCS；回归入口是仓库根目录的 `make` |
| 综合 | Design Compiler；入口是 `dc_shell -f scripts/dc_synth.tcl` |

### 同步代码到虚拟机

```powershell
# Windows（本机）——整目录推上去
scp -r -o HostKeyAlgorithms=+ssh-rsa . 7902_13@10.156.34.6:/home/7902_13/beidou/
```

```bash
# 虚拟机侧（RHEL 6.7，老 tar 用法保守一点）
cd /home/7902_13/beidou && ls
```

### 跑回归

```bash
cd /home/7902_13/beidou
make                 # 编译并运行全部 testbench（VCS）
make list            # 列出用例
make TEST=tb_tracking_channel
make clean
```

每个用例要在**仓库根目录**执行（testbench 用相对路径读 `tb/vectors/`）。
`make` 会把编译日志与运行日志写到 `reports/sim/`。

### 综合

```bash
dc_shell -f scripts/dc_synth.tcl -output_log_file reports/synth/dc.log
```

跑之前必须先在 `scripts/dc_synth.tcl` 里填 `target_library` / `link_library`，
并冻结 `constraints/b1i_rx.sdc` 里的时钟（当前 100 MHz 是占位值）。

## 2. 本机侧（写代码与生成向量）

| 工具 | 用途 |
|---|---|
| Python 3.12 | 参数校验、定点预算、参考模型、生成 `tb/vectors/` |
| matplotlib | 架构图 |
| Icarus Verilog（可选） | 没有 VCS 时的兜底仿真，脚本自动定位 |

```powershell
python scripts\run_all.py            # 全部检查（有 Icarus 时含 RTL 用例）
python scripts\run_all.py --quick    # 跳过绘图与 RTL 用例
python scripts\gen_track_vectors.py  # 重新生成 tb/vectors/
```

## 3. 版本记录要求（REQ-IMPL-007 / REQ-DOC-002）

每个报告必须能回答"哪份 RTL、什么工具、什么版本、什么配置"。
在 `docs/status.md` 里记录：VCS 版本（`vcs -ID`）、DC 版本（`dc_shell -version`）、
`git rev-parse HEAD`（本地）、以及输入向量的 SHA256（`tb/vectors/track_meta.json`）。
