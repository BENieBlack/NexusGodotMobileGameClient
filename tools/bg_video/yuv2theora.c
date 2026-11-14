/*
 * yuv2theora.c: 標準入力の生フレーム（yuv420p）を Ogg Theora（.ogv）に変換する小さなエンコーダ。
 *
 * なぜ要るか: Godot 4 が再生できる動画は Ogg Theora だけだが、開発機の ffmpeg に libtheora が無く、
 * brew の theora も実行ファイル（theora_encoder_example など）を含まない。そこで libtheora の
 * 公式 API を直接使う。背景動画の生成（tools/bg_video/generate_bg_video.py）から呼ばれる。
 *
 * 使い方: yuv2theora 出力.ogv 幅 高さ fps ビットレート(bps)   < 生の yuv420p（1 コマ = 幅*高さ*3/2 バイト）
 * 音声は入れない（背景動画の音は使わない）。
 * ビルド: generate_bg_video.py が clang で行う。
 */
#include <ogg/ogg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <theora/theoraenc.h>

/* 16 の倍数に切り上げる（Theora のフレーム寸法は 16 の倍数。実際の表示範囲は pic_* で指定する） */
static int round16(int v) { return (v + 15) & ~15; }

/* ogg のページを出力ファイルへ書く */
static void write_page(FILE *out, ogg_page *og) {
  fwrite(og->header, 1, og->header_len, out);
  fwrite(og->body, 1, og->body_len, out);
}

/* 1 コマ分の生データを読む。読めたら 1、ファイル終端なら 0 */
static int read_frame(unsigned char *dst, size_t size) {
  return fread(dst, 1, size, stdin) == size;
}

/* 幅・高さ・ストライドが 16 の倍数の板（th_img_plane）へ、元の面をコピーし、右端と下端は端の画素で埋める */
static void copy_plane(th_img_plane *dst, const unsigned char *src, int sw, int sh) {
  for (int y = 0; y < dst->height; y++) {
    const unsigned char *srow = src + (size_t)(y < sh ? y : sh - 1) * sw;
    unsigned char *drow = dst->data + (size_t)y * dst->stride;
    memcpy(drow, srow, sw);
    for (int x = sw; x < dst->width; x++) {
      drow[x] = srow[sw - 1];
    }
  }
}

int main(int argc, char **argv) {
  if (argc != 6) {
    fprintf(stderr, "usage: %s out.ogv width height fps bitrate < yuv420p\n", argv[0]);
    return 2;
  }
  const char *out_path = argv[1];
  int width = atoi(argv[2]);
  int height = atoi(argv[3]);
  int fps = atoi(argv[4]);
  int bitrate = atoi(argv[5]);
  if (width <= 0 || height <= 0 || fps <= 0 || (width & 1) || (height & 1)) {
    fprintf(stderr, "invalid size or fps\n");
    return 2;
  }

  /* --- エンコーダの設定 --- */
  th_info ti;
  th_info_init(&ti);
  ti.frame_width = round16(width);
  ti.frame_height = round16(height);
  ti.pic_width = width;
  ti.pic_height = height;
  ti.pic_x = 0;
  ti.pic_y = 0;
  ti.fps_numerator = fps;
  ti.fps_denominator = 1;
  ti.aspect_numerator = 1;
  ti.aspect_denominator = 1;
  ti.colorspace = TH_CS_UNSPECIFIED;
  ti.pixel_fmt = TH_PF_420;
  ti.target_bitrate = bitrate;
  ti.quality = 40; /* ビットレート指定が無いときの品質（0-63）。通常は bitrate が優先される */
  ti.keyframe_granule_shift = 6;

  /* th_info_clear の後は ti を使わないので、必要な寸法を先に控える */
  int fw = ti.frame_width, fh = ti.frame_height;
  th_enc_ctx *td = th_encode_alloc(&ti);
  th_info_clear(&ti);
  if (!td) {
    fprintf(stderr, "th_encode_alloc failed\n");
    return 1;
  }
  /* 圧縮の手間を最大にして、同じサイズで画質を上げる */
  int splevel_max = 0;
  th_encode_ctl(td, TH_ENCCTL_GET_SPLEVEL_MAX, &splevel_max, sizeof(splevel_max));
  th_encode_ctl(td, TH_ENCCTL_SET_SPLEVEL, &splevel_max, sizeof(splevel_max));

  FILE *out = fopen(out_path, "wb");
  if (!out) {
    perror("fopen");
    return 1;
  }
  ogg_stream_state os;
  ogg_stream_init(&os, 0x4e455855); /* ストリーム番号は任意の固定値 */

  /* --- ヘッダ 3 つ（先頭のヘッダは単独のページにする、が Ogg Theora の決まり） --- */
  th_comment tc;
  th_comment_init(&tc);
  ogg_packet op;
  ogg_page og;
  while (th_encode_flushheader(td, &tc, &op) > 0) {
    ogg_stream_packetin(&os, &op);
    while (ogg_stream_pageout(&os, &og) > 0) {
      write_page(out, &og);
    }
  }
  th_comment_clear(&tc);
  /* 本編のデータが新しいページから始まるように、ヘッダの残りを吐き出す */
  while (ogg_stream_flush(&os, &og) > 0) {
    write_page(out, &og);
  }

  /* --- フレーム --- */
  size_t ysize = (size_t)width * height;
  size_t csize = ysize / 4;
  size_t fsize = ysize + csize * 2;
  unsigned char *cur = malloc(fsize);
  unsigned char *nxt = malloc(fsize);
  /* エンコーダへ渡す、16 の倍数に揃えた各面の領域 */
  th_ycbcr_buffer yb;
  int cw = fw / 2, ch = fh / 2;
  yb[0].width = fw;  yb[0].height = fh;  yb[0].stride = fw;
  yb[1].width = cw;  yb[1].height = ch;  yb[1].stride = cw;
  yb[2].width = cw;  yb[2].height = ch;  yb[2].stride = cw;
  for (int i = 0; i < 3; i++) {
    yb[i].data = malloc((size_t)yb[i].stride * yb[i].height);
  }

  long frames = 0;
  int have = read_frame(cur, fsize);
  while (have) {
    /* 最後のコマかどうか知るため、次のコマを先読みする */
    int more = read_frame(nxt, fsize);
    copy_plane(&yb[0], cur, width, height);
    copy_plane(&yb[1], cur + ysize, width / 2, height / 2);
    copy_plane(&yb[2], cur + ysize + csize, width / 2, height / 2);
    if (th_encode_ycbcr_in(td, yb) != 0) {
      fprintf(stderr, "th_encode_ycbcr_in failed\n");
      return 1;
    }
    while (th_encode_packetout(td, !more, &op) > 0) {
      ogg_stream_packetin(&os, &op);
      while (ogg_stream_pageout(&os, &og) > 0) {
        write_page(out, &og);
      }
    }
    frames++;
    unsigned char *t = cur; cur = nxt; nxt = t;
    have = more;
  }
  while (ogg_stream_flush(&os, &og) > 0) {
    write_page(out, &og);
  }

  fclose(out);
  ogg_stream_clear(&os);
  th_encode_free(td);
  fprintf(stderr, "encoded %ld frames -> %s\n", frames, out_path);
  return frames > 0 ? 0 : 1;
}
