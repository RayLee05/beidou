"""笔记本侧反向通道：虚拟机主动连入后，逐条执行命令并把输出写入 reports/vm_backchannel.txt。

虚拟机控制台执行：
  bash -c 'exec 3<>/dev/tcp/10.129.86.41/22222; while IFS= read -r c <&3; do [ "$c" = QUIT ] && break; eval "$c" >&3 2>&1; echo __END__ >&3; done'
"""
import socket
import sys

HOST, PORT = "10.129.86.41", 22222
LOG = r"E:\code\eda\reports\vm_backchannel.txt"

CMDS = [
    "ls /opt/Synopsys 2>/dev/null; find /opt /home/7902_13 -name '*.db' 2>/dev/null | head -40",
    "source /etc/profile.d/eda.sh && cd /home/7902_13/beidou && make TEST=tb_acquisition > reports/sim/tb_acquisition.log 2>&1; echo DONE:$?; grep -E '\\[PASS\\]|\\[FAIL\\]|Error-' reports/sim/tb_acquisition.log | tail -20",
]


def main() -> None:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(1)
    srv.settimeout(300)
    print(f"LISTEN {HOST}:{PORT}", flush=True)
    conn, addr = srv.accept()
    print(f"FROM {addr}", flush=True)
    conn.settimeout(1800)
    chunks = []
    for cmd in CMDS:
        print(f"CMD {cmd[:80]}", flush=True)
        conn.sendall((cmd + "\n").encode())
        buf = b""
        while b"__END__\n" not in buf:
            part = conn.recv(65536)
            if not part:
                break
            buf += part
        text = buf.decode("utf-8", "replace")
        chunks.append(f"$ {cmd}\n{text}\n")
        open(LOG, "w", encoding="utf-8").write("\n".join(chunks))
        sys.stdout.buffer.write(text.encode("utf-8", "replace") + b"\n")
        sys.stdout.buffer.flush()
    conn.sendall(b"QUIT\n")
    open(LOG, "w", encoding="utf-8").write("\n".join(chunks))
    print(f"LOG {LOG}", flush=True)


if __name__ == "__main__":
    main()
