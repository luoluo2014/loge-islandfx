#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
卡通版「灵动岛」插件图标生成器 —— 落格Loge·灵动岛 v2.0

设计：粉彩渐变背景上，一枚黑色药丸「灵动岛」化成小可爱——
两只圆滚滚的大眼睛（视线投向岛内的白色播放三角）、腮红、微笑，
周围点缀四角星。既点题「灵动岛」，又暗示「背景视频」。
圆角按 iOS squircle（超椭圆 n=5）烘焙进 PNG，四角全透明。

产物（写入 LogeIslandPrefs/Resources/）：
  icon@2x.png   120x120 / icon@3x.png 180x180 / header.png 240x240 / icon-1024.png
"""
import numpy as np
from PIL import Image

S = 1024

# ---------- 工具 ----------

def norm(v):
    n = np.linalg.norm(v)
    return v / n if n > 0 else v

def lerp(a, b, t):
    return a + (b - a) * t

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)

yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)

def gaussian(cx, cy, sx, sy, amp=1.0, rot=0.0):
    if rot:
        c, s = np.cos(rot), np.sin(rot)
        dx, dy = xx - cx, yy - cy
        u = c * dx + s * dy
        v = -s * dx + c * dy
    else:
        u, v = xx - cx, yy - cy
    return amp * np.exp(-(u ** 2 / (2 * sx ** 2) + v ** 2 / (2 * sy ** 2)))

def disc(cx, cy, r, soft=2.0):
    return smoothstep(r + soft, r - soft, np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2))

def ring(cx, cy, r, w, soft=2.0):
    d = np.abs(np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) - r)
    return smoothstep(w / 2 + soft, w / 2 - soft, d)

# ---------- 1) 背景：粉彩渐变 + 柔焦光斑 ----------
g = np.clip(yy / S, 0, 1)
c_top = np.array([0xA9, 0xC6, 0xFF])   # 晴空蓝
c_bot = np.array([0xD8, 0xC0, 0xFF])   # 薰衣草紫
bg = c_top[None, None, :] * (1 - g[..., None]) + c_bot[None, None, :] * g[..., None]
# 几枚半透明装饰圆，增加层次
bg += gaussian(S * 0.18, S * 0.16, S * 0.16, S * 0.16, 1.0)[..., None] * np.array([255.0, 255.0, 255.0]) * 0.16
bg += gaussian(S * 0.86, S * 0.24, S * 0.12, S * 0.12, 1.0)[..., None] * np.array([255.0, 236.0, 250.0]) * 0.20
bg += gaussian(S * 0.80, S * 0.86, S * 0.18, S * 0.14, 1.0)[..., None] * np.array([180.0, 220.0, 255.0]) * 0.18

# ---------- 2) 灵动岛药丸 ----------
PX, PY = S * 0.500, S * 0.470          # 药丸中心
PW, PH = S * 0.560, S * 0.204          # 药丸宽高
PR = PH / 2                             # 全圆角
# 圆角矩形距离场（药丸 = 两端半圆的矩形）
qx = np.clip(np.abs(xx - PX) - (PW / 2 - PR), 0, None)
qy = np.abs(yy - PY) - (PH / 2 - PR)
pill_d = np.sqrt(qx ** 2 + qy ** 2)
pill = smoothstep(PR + 2.5, PR - 2.5, pill_d)

PILL_BODY = np.array([0x10, 0x10, 0x14])     # 近黑
PILL_EDGE = np.array([0x3A, 0x3A, 0x46])     # 边缘略亮
pill_col = lerp(PILL_EDGE[None, None, :], PILL_BODY[None, None, :],
                smoothstep(0.55, 1.0, pill_d / PR)[..., None])

# 顶部一道亮边（玻璃感高光）
top_edge = np.exp(-((yy - (PY - PH / 2 + PR * 0.30)) ** 2) / (2 * (PR * 0.16) ** 2)) \
          * (np.abs(xx - PX) < PW / 2 - PR * 0.6)
pill_col += top_edge[..., None] * np.array([255.0, 255.0, 255.0]) * 0.14

# 投影
shadow = gaussian(PX, PY + PH / 2 + S * 0.035, PW * 0.46, S * 0.045, 1.0) * 0.30

# ---------- 3) 小脸 ----------
EYE_R = S * 0.052
PUPIL_R = S * 0.026
EX_L, EX_R = PX - S * 0.118, PX + S * 0.118
EY = PY - S * 0.018

eye_l = disc(EX_L, EY, EYE_R, soft=2.5)
eye_r = disc(EX_R, EY, EYE_R, soft=2.5)

# 视线：微微右下（看向播放三角）
GAZE = norm(np.array([0.35, 0.55]))
gx, gy = GAZE[0] * EYE_R * 0.38, GAZE[1] * EYE_R * 0.38
pupil_l = disc(EX_L + gx, EY + gy, PUPIL_R, soft=2.0)
pupil_r = disc(EX_R + gx, EY + gy, PUPIL_R, soft=2.0)
# 瞳孔里的高光点
spark_l = disc(EX_L + gx - PUPIL_R * 0.34, EY + gy - PUPIL_R * 0.38, PUPIL_R * 0.30, soft=1.2)
spark_r = disc(EX_R + gx - PUPIL_R * 0.34, EY + gy - PUPIL_R * 0.38, PUPIL_R * 0.30, soft=1.2)

# 腮红（柔粉，低透明）
blush_l = gaussian(EX_L - EYE_R * 0.1, EY + EYE_R * 1.25, EYE_R * 0.95, EYE_R * 0.55, 1.0)
blush_r = gaussian(EX_R + EYE_R * 0.1, EY + EYE_R * 1.25, EYE_R * 0.95, EYE_R * 0.55, 1.0)
BLUSH = np.array([255.0, 138.0, 158.0])

# 微笑：一小段弧线（圆环下半 = ∪）
smile_cx, smile_cy = PX, EY + EYE_R * 1.30
smile_r = S * 0.046
smile = ring(smile_cx, smile_cy, smile_r, S * 0.011, soft=2.0) \
      * (yy > smile_cy)                                    # 取圆的下半弧 = 微笑
smile = smile * smoothstep(S * 0.15, S * 0.09, np.abs(xx - smile_cx))

# ---------- 4) 播放三角（岛内右侧，「正在播放」的小Hint） ----------
TX, TY = PX + S * 0.175, PY + S * 0.004
TW, TH = S * 0.028, S * 0.034
u = (xx - TX) / TW
v = (yy - TY) / TH
tri = ((np.abs(v) <= 1.0) & (u >= -0.55) & (u <= 1.05) & (u - 1.05 <= 1.53 * np.abs(v)))
tri = tri.astype(np.float64) * pill

# ---------- 5) 四角星点缀 ----------
def star(cx, cy, r, amp, phase=0.0):
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    a = np.arctan2(yy - cy, xx - cx) + phase
    # 四角星半径轮廓：r * (0.42 + 0.58 * |cos(2a)|^1.5)
    rr = r * (0.40 + 0.60 * np.abs(np.cos(2 * a)) ** 1.4)
    return amp * smoothstep(rr + 2.5, rr - 2.5, d) + amp * 0.55 * np.exp(-(d ** 2) / (2 * (r * 0.16) ** 2))

stars = star(S * 0.170, S * 0.335, S * 0.036, 1.0, 0.5) \
      + star(S * 0.845, S * 0.360, S * 0.026, 0.9, 0.0) \
      + star(S * 0.760, S * 0.145, S * 0.020, 0.8, 0.9) \
      + star(S * 0.230, S * 0.800, S * 0.024, 0.75, 0.3)
STAR_COL = np.array([255.0, 250.0, 224.0])

# ---------- 6) 合成 ----------
img = bg.copy()
img = img * (1 - shadow[..., None]) + np.array([0x4A, 0x46, 0x78])[None, None, :] * shadow[..., None] * 0.5
img = img * (1 - pill[..., None]) + pill_col * pill[..., None]
# 脸（画在药丸内）
for layer, col, op in ((eye_l, np.array([255.0, 255.0, 255.0]), 1.0),
                       (eye_r, np.array([255.0, 255.0, 255.0]), 1.0)):
    img = img * (1 - (layer * pill * op)[..., None]) + col[None, None, :] * (layer * pill * op)[..., None]
for layer in (pupil_l, pupil_r):
    img = img * (1 - (layer * pill)[..., None]) + np.array([0x18, 0x1C, 0x28])[None, None, :] * (layer * pill)[..., None]
for layer in (spark_l, spark_r):
    img = img * (1 - (layer * pill)[..., None]) + np.array([255.0, 255.0, 255.0])[None, None, :] * (layer * pill)[..., None]
img += (blush_l + blush_r)[..., None] * BLUSH[None, None, :] * 0.34 * pill[..., None]
img = img * (1 - (smile * pill)[..., None]) + np.array([0x18, 0x1C, 0x28])[None, None, :] * (smile * pill)[..., None]
img = img * (1 - (tri * 0.95)[..., None]) + np.array([255.0, 255.0, 255.0])[None, None, :] * (tri * 0.95)[..., None]
img += stars[..., None] * STAR_COL[None, None, :]
img = np.clip(img, 0, 255)

# ---------- 7) squircle 蒙版 ----------
m = np.mgrid[0:S, 0:S].astype(np.float64)
mu = (m[1] - S / 2) / (S / 2)
mv = (m[0] - S / 2) / (S / 2)
r = (np.abs(mu) ** 5 + np.abs(mv) ** 5) ** (1.0 / 5)
mask = np.clip((1.0 - r) * S * 0.9, 0, 1)

master = Image.fromarray(np.dstack([img, np.full((S, S), 255.0) * mask]).astype(np.uint8), "RGBA")

out = "/workspace/LogeIsland/LogeIslandPrefs/Resources"
master.resize((120, 120), Image.LANCZOS).save(f"{out}/icon@2x.png")
master.resize((180, 180), Image.LANCZOS).save(f"{out}/icon@3x.png")
master.resize((240, 240), Image.LANCZOS).save(f"{out}/header.png")
master.save(f"{out}/icon-1024.png")
print("OK: cartoon island icon exported")
