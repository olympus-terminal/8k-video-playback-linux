# 8k-video-playback-linux

Notes and a small benchmark from working out why an 8K AV1 HDR video played badly
on a Linux laptop (RTX 4080 Laptop GPU, mpv 0.37). Everything here was measured on
one machine; treat the numbers as an example, not a general result.

## Why 8K is hard to play

The test file was an 8K walking video from YouTube:

| Property | Value |
|---|---|
| Codec | AV1 (Main profile) |
| Resolution | 7680x4320 |
| Pixel format | yuv420p10le (10-bit) |
| Colour | BT.2020 primaries, SMPTE 2084 (PQ / HDR10-style) |
| Frame rate | 59.94 fps |
| Bitrate | about 54 Mbps (62 GB for about 2.5 hours) |

Per second that is about 2 billion pixels to decode (7680 x 4320 x 59.94), in 10-bit
AV1, plus HDR tone mapping and downscaling when the screen is smaller than the video.
A 3840x1080 display shows only a fraction of those pixels.

## What I found

1. **The default player setup used CPU decoding.** `open FILE` -> `xdg-open` -> mpv
   with no config file. mpv's default is `hwdec=no`, so AV1 is decoded in software
   by dav1d. You can see this with `mpv -v FILE 2>&1 | grep -i decoder`
   (`Opening decoder libdav1d`).
2. **Decode speed was close to the frame rate, and load changed the result.**
   Marginal decode speed with `--vo=null --untimed` (see `bench_decode.sh`):

   | hwdec | busy machine | quiet machine |
   |---|---|---|
   | `no` (dav1d, CPU) | about 42 fps | 68.6, 74.9, 60.2 fps |
   | `nvdec-copy` | about 37 fps | 59.9, 61.7 fps |
   | `nvdec` (zero-copy) | about 48 fps | 71.7, 59.3, 55.9 fps |

   Needed: 59.94 fps. "Busy" meant several CPU-heavy background jobs and a download
   writing to the same USB spinning disk; "quiet" meant those had finished. The busy
   column was a single run with slightly different frame counts.
3. **GPU decode did not clearly beat CPU decode** in these headless runs. During one
   `nvdec-copy` run the GPU decoder was only 21-50% busy
   (`nvidia-smi dmon -s um`, `dec` column), so it was not the limit; copying 8K
   frames back to system memory probably is.
4. **Playback was later reported as smooth**, but the flags used and the machine
   load at that moment were not recorded. So I can't say whether GPU decode,
   less background load, or both fixed it.

## What was not measured

- Real on-screen playback: no window, HDR output, tone mapping, or scaling in the
  benchmark. Dropped-frame counts from an actual `mpv` window would be the better
  test (`--vo=gpu-next`, then check the `Dropped:` counter in the stats overlay,
  shortcut `I`).
- Other players, other GPUs, other AV1 encoders.
- Thermal throttling. The laptop GPU was at 65 C and idle P-state before testing.

## Things worth trying

```bash
# GPU decode, zero-copy, display-synced
mpv --hwdec=nvdec --vo=gpu-next --video-sync=display-resample FILE

# add if frames still drop
mpv --profile=fast ...
```

- Close other heavy jobs, and don't play from a disk that something is writing to.
- If the screen is 4K or smaller, download or play a 4K version instead.
- Re-encoding 8K to 4K is not a shortcut: the 8K stream still has to be decoded once.

## Reproduce the benchmark

Needs `mpv`, `ffprobe`, `bc`.

```bash
./bench_decode.sh FILE [START_SECONDS] [MODES...]
# example
./bench_decode.sh video.mp4 600 no nvdec-copy nvdec
```

Each mode is run twice (200 and 800 frames, starting at `START_SECONDS`) and the
speed is `(800 - 200) / (t800 - t200)`, which removes startup and seek time.
Run it when the machine is idle, and repeat it: results above varied by 10+ fps
between runs.

## Hardware and software used

NVIDIA GeForce RTX 4080 Laptop GPU (12 GB, 80 W), Intel UHD iGPU, 32 threads,
display 3840x1080, driver 580.178.04, mpv 0.37.0 (libplacebo 6.338.2),
Ubuntu-based Linux, video on a USB spinning disk (exFAT).

## License

MIT, see `LICENSE`.
