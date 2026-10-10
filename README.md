# 乐划锁屏桌面同步 (Pictorial Home Sync)

Magisk 模块：将真我 / OPPO / 一加「乐划锁屏」换图同步到桌面壁纸。

作者：封刀隱

## 安装

1. 下载 Releases 中的 `PictorialHomeSync-Magisk-vX.Y.Z.zip`
2. 用 Magisk / Magisk Alpha 安装并重启
3. 模块默认开启；可在 Magisk 模块页左下角操作按钮开关同步

## 目录

- 模块本体：仓库根目录（`module.prop` / `service.sh` / `common/`）
- 辅助 App 源码：`helper-app/`

## 版本

当前：v1.3.2

## ColorOS 17 说明

ColorOS 17 起，乐划换图不再稳定写入 SystemUI 的 `pictorialWallpaperCache.dat`。
模块跟随乐划状态：
- 灭屏 / 亮屏当下：同步 `next_light`（你亮屏时看到的锁频图），并记为 HOLD
- 解锁后 `next_light` 变成再下一张时：冻结 HOLD，桌面保持刚看过的锁频图
- 下次灭屏：再预同步新的 `next_light`
- 锁频内滑动：`show_num` 变化且 `next_light` 未变时跟滑
