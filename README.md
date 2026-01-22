# Kuma 多区域探针（Linux）打包版

这个压缩包用于「多区域探测 + Push 回 Uptime Kuma」的统一部署：
- **每个区域一台 VPS/容器**（同一套脚本）
- **同一台机器运行所有脚本**（`run_all.sh` 自动遍历 `scripts/`）
- **systemd timer** 每分钟自动执行（可修改频率）
- 每台机器只需要改一份 `config.env`（token/节点名/代理等）

---

## 目录结构

```
kuma-probes/
  config.env.example     # 配置模板（复制成 config.env 再修改）
  run_all.sh             # 运行所有脚本（遍历 scripts/*.sh）
  bootstrap.sh           # 一键安装依赖 + 安装 systemd + 启动定时任务
  lib/common.sh          # 公共函数（curl、push、region、计时等）
  scripts/
    claude.sh
    chatgpt.sh
    gemini.sh
    tiktok.sh
    sunlogin.sh
    template.sh          # 新增脚本模板（照着写即可）
  systemd/
    kuma-probes.service
    kuma-probes.timer
```

---

## 1) 在每台 Linux VPS 上部署

### 1.1 解压到 /opt

```bash
sudo mkdir -p /opt
sudo tar -xzf kuma-probes-package.tar.gz -C /opt
sudo mv /opt/kuma-probes /opt/kuma-probes   # 若已在此目录可忽略
```

> 你也可以把目录放在别处，但 systemd unit 默认指向 `/opt/kuma-probes`。

### 1.2 配置 Push URL（每台机器不同）

```bash
cd /opt/kuma-probes
sudo cp -n config.env.example config.env
sudo nano config.env
```

至少需要填：
- `NODE_NAME`：节点名（例如 `SG-1` / `US-1`）
- `KUMA_CLAUDE_PUSH`、`KUMA_CHATGPT_PUSH`、`KUMA_GEMINI_PUSH`、`KUMA_TIKTOK_PUSH`、`KUMA_SUNLOGIN_PUSH`：各脚本对应的 Push URL（每个区域都不同的 token）

### 1.3 一键安装并启动定时任务

```bash
cd /opt/kuma-probes
sudo bash bootstrap.sh
```

> 如果目标目录已存在且非空，脚本会停止以避免误删；如需覆盖，请设置 `PROBE_DIR_FORCE=1`。

查看状态/日志：
```bash
sudo systemctl status kuma-probes.timer --no-pager
sudo journalctl -u kuma-probes.service -n 100 --no-pager
```

---

## 2) systemd timer 使用

常用操作：
```bash
sudo systemctl status kuma-probes.timer --no-pager
sudo systemctl list-timers --all | rg kuma-probes
```

手动执行一次（立即跑一轮探针）：
```bash
sudo systemctl start kuma-probes.service
```

停止/暂停运行（阻止后续触发，并尽量终止当前任务）：
```bash
sudo systemctl stop kuma-probes.timer
sudo systemctl stop kuma-probes.service
```

重新启用：
```bash
sudo systemctl enable --now kuma-probes.timer
```

---

## 3) 修改运行频率（默认 60 秒）
编辑 timer：
```bash
sudo nano /etc/systemd/system/kuma-probes.timer
```

把 `OnUnitActiveSec=60` 改为 `300` 表示 5 分钟一次。

改完后：
```bash
sudo systemctl daemon-reload
sudo systemctl restart kuma-probes.timer
```

---

## 4) 新增脚本
在 `scripts/` 新建 `xxx.sh`，参考 `scripts/template.sh`：
- 从 `config.env` 里取 `KUMA_XXX_PUSH`
- 计算 `status/msg/ping`
- 调用 `push_kuma`

脚本会被 `run_all.sh` 自动执行（无需改 runner）。

---

## 5) Kuma 端建议
- Push Monitor 的 **Heartbeat Interval 建议设 120 秒**（脚本 60 秒一次更稳，避免偶发误报）。
- 通知一般是“状态变化”触发（down↔up），不是每次心跳都发通知。

---

如果你后续要把更多脚本（ChatGPT/Gemini/…）也放进来，只需丢进 `scripts/` 并在 `config.env` 增加对应 `KUMA_XXX_PUSH` 即可。
