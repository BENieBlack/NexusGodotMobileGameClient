# アセット

## 背景動画（自作）

`assets/video/bg_loop.ogv`（タイトル・ログインボーナス・ホームの背景）は自作の動画で、外部の素材は使っていない。夜空のグラデーション・月・横にたなびく霧状の薄い雲（周期的なノイズを重ねた帯を、奥は暗く遅く・手前は明るく速く動かす）・星・流れ星を numpy で描いて生成している（1080x1920・25fps・20 秒・音声なし・シームレスにループ・約 2MB）。

- 生成スクリプト: `tools/bg_video/generate_bg_video.py`（Ogg Theora への変換は同じ場所の `yuv2theora.c`。libtheora を使う小さな C のエンコーダで、スクリプトが clang でビルドする）
- 作り直し: `python3 tools/bg_video/generate_bg_video.py`（numpy・clang・libtheora/libogg が要る。macOS は `brew install theora`）。乱数の種は固定なので、同じ動画になる
- ビルドした実行ファイルは `build/bgvideo/` に出る（git に入れない）
