# 当前有效的 IC 连接方式（2026-11-09 已验证）

> 当日后续：约 16:16 用户确认虚拟机已关闭，SSH 握手超时属于目标未运行。以下为开机时已验证的连接配置，不代表目前在线。运行中的综合不会跨虚拟机关机继续；恢复及已保存结果见 [逻辑综合阶段报告](../逻辑综合/逻辑综合报告_20261109.md)。文末库搜索状态属于连接测试时的历史快照；本次综合已经确认 TSMC28 标准单元与 PAD 库及模型。

## 连接入口

```text
本机 10.129.213.79 -> 实验室 Windows 10.156.34.48:2222
                    -> Linux NAT 192.168.44.128:22
```

实际采用的是将原 eth0 改为 NAT，而不是增加第二张网卡。旧桥接地址 10.156.34.6 不再作为当前入口。VMnet8 的 192.168.44.1 是 Windows 的虚拟网卡地址，不是 Linux 地址。

本机 `%USERPROFILE%\.ssh\config` 中默认 `vm-ic` 和 `vm-ic-nat` 均指向中转路径；旧配置保留为 `vm-ic-bridge`，仅作历史备份，不建议使用。其他 SSH 主机配置和私钥文件保留原状。

```powershell
ssh vm-ic
ssh vm-ic "whoami && hostname && pwd"
python scripts/vm_remote.py doctor
```

期望：7902_13 / IC / /home/7902_13。

## 本次实测

- 严格主机密钥检查成功：RSA SHA256:bqP8OT3RfUYkKJGvlHZVQC2xYxn+YyPTA96QKhyl03c。
- 公钥认证成功，BatchMode=yes，无密码回退。
- 5 次独立 SSH 登录全部成功，均匹配用户/主机和 MAC a4:db:30:35:75:57。
- 单次会话空闲 45 秒后正常返回 KEEPALIVE_END 和远端用户名。
- 约 5 MB 源码快照传输及 SHA256 校验成功。
- 后台 VCS `tb_nh_bit_sync` 成功，phase=13、59 bits checked、TEST PASSED、退出码 0；日志下载成功。
- 修改默认 vm-ic 后，再次验证远端命令成功。

这证明本次短时测试和任务传输/运行链路已通过，不代表无限时间的可用性保证。

本地证据：

```text
reports/remote/stability-20261109-053125.json
reports/remote/inventory-20261109-133116.txt
reports/remote/nat-nh-20261109/manifest.json
reports/remote/nat-nh-20261109/results/job_state/exit_code
reports/remote/nat-nh-20261109/results/reports/sim/tb_nh_bit_sync.run.log
```

## 队友使用

需要从校园网络访问宿主机。宿主机防火墙当前只允许本机来源 10.129.213.79；队友需由管理员为其实际来源 IP 增加同样范围的规则，不关闭防火墙、不放宽为 Any。

每人使用自己的 RSA 密钥，将公钥追加到 Linux ~/.ssh/authorized_keys；不要共享私钥，不要覆盖已有授权。

队友可使用下面配置。首次连接须核对主机密钥指纹，确认后保存到自己的 known_hosts：

```sshconfig
Host vm-ic
    HostName 10.156.34.48
    Port 2222
    User 7902_13
    IdentityFile ~/.ssh/id_rsa_vm_ic
    IdentitiesOnly yes
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
    ServerAliveInterval 20
    ServerAliveCountMax 3
    TCPKeepAlive yes
    ConnectTimeout 12
```

本机另有 HostKeyAlias 10.156.34.6 和 StrictHostKeyChecking yes，是为了复用已核实的原主机密钥。队友没有旧 known_hosts 时，不能直接照搬后以为自动信任；也不要用关闭主机校验来处理警告。

## 长期保持连接所需条件

1. 保持 Windows 宿主机和 VM 开机且不睡眠。
2. 管理员确认宿主机 10.156.34.48 与 VM NAT 192.168.44.128 的地址固定/保留。当前 NAT IP 已可用，但本轮没有改动 DHCP 租约或持久网络配置，重启后的地址仍需核实。不要在未查看 DHCP 池时随意写静态地址。
3. 当前电脑或队友换网络、来源 IP 变化时，重新审核宿主机的来源防火墙规则。
4. 不要关闭防火墙、重启 sshd 或随意更换端口转发目标。Windows portproxy/IP Helper 和现有防火墙规则应保留。
5. DC/VCS 长任务使用后台脚本；网络短暂中断后查询状态，不要直接重复启动。

## 已确认的工具环境

本次读到 4 CPU、9854 MiB 内存、根分区可用约 416 GB；之前 2 CPU/2 GB 是历史配置。

| 工具 | 版本查询结果 |
|---|---|
| VCS | I-2014.03，NH 测试已实际编译并运行 |
| Design Compiler | K-2015.06，旧 channel_slice 示例库综合退出码 0 |
| PrimeTime | K-2015.06 |
| Formality | L-2016.03-SP1 |
| IC Compiler | L-2016.03-SP1 |
| Calibre | v2015.4_16.11 |

Synopsys 许可证服务器与 snpslmd 本次查询为 UP。版本/服务状态不代表所有工具特征已经逐项实际 checkout 或后端签核通过。当前 PATH 未找到 vsim/vlog、innovus、rc、python3、git。库搜索仍主要发现工具自带示例库，课程正式 PDK 尚未确认。
