#!/usr/bin/env python3
"""背景動画 assets/video/bg_loop.ogv を、外部素材なしで一から生成する。

夜空のグラデーション・月・ゆっくり流れる雲・またたく星・時々走る流れ星を numpy で描き、
同梱の小さな C エンコーダ（tools/bg_video/yuv2theora.c、libtheora を使う）で Ogg Theora にする。
Godot 4 が再生できる動画は Ogg Theora だけで、ffmpeg に libtheora が無い環境でも作れるようにするため。

シームレスなループの作り方: 動きはすべて「ループの長さ（SECONDS 秒）の周期」にする。
  - 雲: ちょうど 1 周ぶん（レイヤーの幅だけ）左へ動かし、はみ出しは反対側から戻す
  - 星のまたたき: 周期が SECONDS の約数になる正弦波
  - 流れ星: すべて SECONDS の内側で始まり、終わる（境目をまたがない）
  最後のコマの次が最初のコマになるので、継ぎ目で値が飛ばない。

必要なもの: python3 + numpy、clang、libtheora と libogg（macOS は brew install theora）。
使い方: python3 tools/bg_video/generate_bg_video.py [--out assets/video/bg_loop.ogv] [--bitrate 800000]
生成物のバイナリは build/bgvideo/ に置く（git に入れない）。
"""
import argparse
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

WIDTH, HEIGHT, FPS, SECONDS = 1080, 1920, 25, 20
FRAMES = FPS * SECONDS
ROOT = Path(__file__).resolve().parents[2]
ENCODER_SRC = ROOT / "tools" / "bg_video" / "yuv2theora.c"
ENCODER_BIN = ROOT / "build" / "bgvideo" / "yuv2theora"


def build_encoder() -> None:
    """C エンコーダを clang でビルドする（ヘッダとライブラリの場所は brew の既定。環境変数で変えられる）。"""
    import os

    prefix = os.environ.get("THEORA_PREFIX", "/opt/homebrew")
    ENCODER_BIN.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "clang", "-O2", "-Wall", f"-I{prefix}/include", f"-L{prefix}/lib",
        str(ENCODER_SRC), "-ltheoraenc", "-ltheoradec", "-logg", "-o", str(ENCODER_BIN),
    ]
    subprocess.run(cmd, check=True)


def lerp_gradient(stops, t):
    """縦位置 t（0..1 の配列）に対して、色の停止点（位置, RGB）を線形補間する。"""
    pos = [s[0] for s in stops]
    return np.stack([np.interp(t, pos, [s[1][c] for s in stops]) for c in range(3)], axis=-1)


def disc(xx, yy, cx, cy, r, aa=1.5):
    """円の被覆率（0..1）。縁を aa ピクセルぶんぼかして滑らかにする。"""
    d = np.hypot(xx - cx, yy - cy) - r
    return np.clip(0.5 - d / aa, 0.0, 1.0)


def make_base(rng):
    """静止している背景（グラデーション + 月と光のにじみ + 細かいディザ）を作る。"""
    ys = np.linspace(0.0, 1.0, HEIGHT)
    grad = lerp_gradient(
        [(0.0, (36, 32, 68)), (0.35, (48, 50, 98)), (0.7, (66, 92, 128)), (1.0, (122, 146, 164))], ys
    )
    img = np.repeat(grad[:, None, :], WIDTH, axis=1).astype(np.float32)

    # 月（三日月 = 円から少しずらした円を引く）と、まわりの光のにじみ
    yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float32)
    mx, my, r = 0.78 * WIDTH, 0.115 * HEIGHT, 125.0
    glow = np.exp(-(np.hypot(xx - mx, yy - my) / (r * 1.7)) ** 2) * 0.28
    img += glow[..., None] * np.array([150, 150, 190], np.float32)
    moon = np.clip(disc(xx, yy, mx, my, r) - disc(xx, yy, mx - r * 0.42, my - r * 0.12, r * 0.92), 0, 1)
    img = img * (1 - moon[..., None]) + moon[..., None] * np.array([250, 250, 255], np.float32)

    # 縞（バンディング）を目立たなくする静止ディザ
    img += rng.normal(0.0, 0.6, size=img.shape).astype(np.float32)
    return img


def cloud_alpha(width, y_top, band_h, specs):
    """雲のレイヤー（幅 width、高さ band_h の帯）の被覆率を返す。specs は (中心 x, ベースライン y, 大きさ)。"""
    yy, xx = np.mgrid[0:band_h, 0:width].astype(np.float32)
    alpha = np.zeros((band_h, width), np.float32)
    for cx, base, s in specs:
        by = base - y_top
        # 底が平らな雲: 底に接する大小の円と、その間を埋める長方形の和集合
        circles = [(-0.62, 0.34), (-0.2, 0.52), (0.28, 0.44), (0.66, 0.30)]
        for ox, rr in circles:
            alpha = np.maximum(alpha, disc(xx, yy, cx + ox * s, by - rr * s, rr * s))
        rect_x = np.clip(0.5 - (np.abs(xx - cx - 0.02 * s) - 0.66 * s) / 1.5, 0, 1)
        rect_y = np.clip(0.5 - (np.abs(yy - (by - 0.15 * s)) - 0.15 * s) / 1.5, 0, 1)
        alpha = np.maximum(alpha, rect_x * rect_y)
        # 横に折り返す雲（レイヤー幅をまたぐもの）も自然につながるよう、左右の端で複製を描く
    return alpha


class CloudLayer:
    """1 ループでちょうど 1 周する雲のレイヤー。canvas の幅ぶん動くと元の位置に戻る。"""

    def __init__(self, canvas_w, y_top, band_h, specs, color, opacity):
        self.canvas_w = canvas_w
        self.y_top = y_top
        self.band_h = band_h
        self.color = np.array(color, np.float32)
        # 幅をまたぐ雲を作るため、specs を左右にずらしたものも含めて描く
        wide = [(cx + k * canvas_w, b, s) for k in (-1, 0, 1) for cx, b, s in specs]
        full = cloud_alpha(canvas_w * 3, y_top, band_h, [(cx + canvas_w, b, s) for cx, b, s in wide])
        # 3 枚並べた中の中央 1 枚ぶんを取り出す（両隣の雲のはみ出しが端に入る）
        self.alpha = full[:, canvas_w : 2 * canvas_w] * opacity

    def draw(self, img, t_frac):
        """t_frac（0..1）に応じて左へ動かし、画面の幅（WIDTH）だけ切り出して合成する。"""
        shift = int(round(t_frac * self.canvas_w))
        a = np.roll(self.alpha, -shift, axis=1)[:, :WIDTH]
        region = img[self.y_top : self.y_top + self.band_h]
        region += (self.color - region) * a[..., None]


def draw_dot(img, x, y, radius, intensity, cross=0.0):
    """星 1 つ（ガウス型の点。cross > 0 なら十字のきらめきも足す）を加算で描く。"""
    pad = int(radius * 5 + cross + 2)
    x0, x1 = max(int(x) - pad, 0), min(int(x) + pad + 1, WIDTH)
    y0, y1 = max(int(y) - pad, 0), min(int(y) + pad + 1, HEIGHT)
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = xx - x, yy - y
    v = np.exp(-(dx * dx + dy * dy) / (2 * radius * radius))
    if cross > 0:
        v += 0.6 * (np.exp(-(dy / 1.1) ** 2) * np.exp(-np.abs(dx) / cross) + np.exp(-(dx / 1.1) ** 2) * np.exp(-np.abs(dy) / cross))
    img[y0:y1, x0:x1] += (v * intensity)[..., None] * np.array([235, 238, 255], np.float32) * 0.9


def draw_shooting_star(img, sx, sy, angle, length, travel, u):
    """流れ星 1 本。u（0..1）は進み具合。頭から尾に向かって細く薄くなる線を描く。"""
    dx, dy = math.cos(angle), math.sin(angle)
    hx, hy = sx + dx * travel * u, sy + dy * travel * u
    env = math.sin(math.pi * u)  # 出だしと終わりは淡く
    pad = 8
    xs = [hx, hx - dx * length]
    ys = [hy, hy - dy * length]
    x0, x1 = max(int(min(xs)) - pad, 0), min(int(max(xs)) + pad, WIDTH)
    y0, y1 = max(int(min(ys)) - pad, 0), min(int(max(ys)) + pad, HEIGHT)
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    rx, ry = hx - xx, hy - yy
    along = rx * dx + ry * dy  # 頭からの距離（尾の側が正）
    perp = np.abs(rx * dy - ry * dx)
    v = np.clip(1 - along / length, 0, 1) * (along >= -2) * np.exp(-(perp / 1.7) ** 2)
    img[y0:y1, x0:x1] += (v * env * 0.85)[..., None] * np.array([235, 240, 255], np.float32)


def to_yuv420(rgb):
    """RGB（float, 0..255）を BT.601 の yuv420p（Y 面・U 面・V 面を連結した bytes）にする。"""
    rgb = np.clip(rgb, 0, 255)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 16 + (65.481 * r + 128.553 * g + 24.966 * b) / 255
    u = 128 + (-37.797 * r - 74.203 * g + 112.0 * b) / 255
    v = 128 + (112.0 * r - 93.786 * g - 18.214 * b) / 255

    def sub(p):  # 2x2 平均で色差を半分の解像度に
        return (p[0::2, 0::2] + p[1::2, 0::2] + p[0::2, 1::2] + p[1::2, 1::2]) / 4

    planes = [np.clip(np.rint(y), 16, 235), np.clip(np.rint(sub(u)), 16, 240), np.clip(np.rint(sub(v)), 16, 240)]
    return b"".join(p.astype(np.uint8).tobytes() for p in planes)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "assets" / "video" / "bg_loop.ogv"))
    ap.add_argument("--bitrate", type=int, default=800000, help="目標ビットレート(bps)")
    ap.add_argument("--frames", type=int, default=FRAMES, help="試し撮り用にコマ数を減らすとき（ループにはならない）")
    args = ap.parse_args()

    build_encoder()
    rng = np.random.default_rng(20240607)  # 固定の種: 何度作っても同じ動画になる
    base = make_base(rng)

    # 雲: 奥（小さく淡い・遅い）と手前（大きく明るい・速い）。1 ループで canvas の幅だけ動く
    far = CloudLayer(1080, 0, 850, [(280, 180, 150), (860, 330, 130), (520, 640, 120), (110, 780, 140)], (74, 72, 122), 0.55)
    near = CloudLayer(1620, 100, 800, [(780, 480, 200), (200, 760, 190), (1250, 600, 160), (1480, 380, 150)], (150, 155, 188), 0.72)

    # 星: 位置・大きさ・またたきの周期（SECONDS の約数になるよう整数回）と位相を固定の乱数で決める
    stars = []
    for i in range(70):
        stars.append(dict(
            x=rng.uniform(20, WIDTH - 20), y=rng.uniform(40, HEIGHT * 0.72),
            r=rng.uniform(1.2, 2.2) if i >= 8 else rng.uniform(2.6, 3.4),
            base=rng.uniform(0.45, 0.8), k=int(rng.integers(1, 5)), ph=rng.uniform(0, 2 * math.pi),
            cross=14.0 if i < 8 else 0.0,
        ))

    # 流れ星: (開始秒, 長さ秒, 開始 x, 開始 y, 角度) すべて 0..SECONDS の内側に収める
    shooters = [
        (1.5, 1.0, 900, 300, math.radians(145)),
        (5.0, 0.9, 620, 120, math.radians(140)),
        (9.0, 1.1, 1000, 760, math.radians(150)),
        (13.0, 0.9, 760, 520, math.radians(142)),
        (16.4, 1.0, 960, 180, math.radians(146)),
    ]

    enc = subprocess.Popen([str(ENCODER_BIN), args.out, str(WIDTH), str(HEIGHT), str(FPS), str(args.bitrate)], stdin=subprocess.PIPE)
    for f in range(args.frames):
        t = f / FPS
        frac = f / FRAMES
        img = base.copy()
        for s in stars:
            tw = 0.5 + 0.5 * math.sin(2 * math.pi * s["k"] * frac + s["ph"])
            draw_dot(img, s["x"], s["y"], s["r"], s["base"] * (0.25 + 0.75 * tw), s["cross"] * tw)
        for t0, dur, sx, sy, ang in shooters:
            if t0 <= t < t0 + dur:
                draw_shooting_star(img, sx, sy, ang, 260, 760, (t - t0) / dur)
        far.draw(img, frac)
        near.draw(img, frac)
        enc.stdin.write(to_yuv420(img))
        if f % 50 == 0:
            print(f"frame {f}/{args.frames}", file=sys.stderr)
    enc.stdin.close()
    return enc.wait()


if __name__ == "__main__":
    sys.exit(main())
