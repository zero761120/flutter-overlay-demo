"""逐幀找懸浮球（藍色圓）的中心，印出 時間、座標、藍色像素數、與上一幀的位移。

用法：python3 -I tools/device-test/track_ball.py <影片.mp4> [y_min]

用來量動畫順不順：位移一路連續遞減是平滑；中間夾著 0 或突然的大跳就是卡頓或瞬移。
- 影片可以用 drag_cases.sh --record 錄，或 adb shell screenrecord
- 只看 y >= y_min（預設 1450）的區域：主 App 上方有藍色按鈕文字，會干擾偵測
- 藍色門檻是照這個 App 的球色調的；n（像素數）突然變少，代表球被別的東西蓋住或正在縮小
- 座標換回影片原始解析度；先縮小 4 倍再掃，純 Python 才跑得動
"""
import subprocess
import sys

SCALE = 4


def main():
    video = sys.argv[1]
    y_min = int(sys.argv[2]) if len(sys.argv) > 2 else 1450
    size = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
         'stream=width,height', '-of', 'csv=p=0', video],
        capture_output=True, text=True, check=True).stdout.strip().split(',')
    w, h = int(size[0]) // SCALE, int(size[1]) // SCALE
    times = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries',
         'frame=pts_time', '-of', 'csv=p=0', video],
        capture_output=True, text=True, check=True).stdout.split()
    raw = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', video, '-fps_mode', 'passthrough',
         '-vf', f'scale={w}:{h}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
        capture_output=True, check=True).stdout
    frame_bytes = w * h * 3
    prev = None
    for i in range(len(raw) // frame_bytes):
        f = raw[i * frame_bytes:(i + 1) * frame_bytes]
        sx = sy = n = 0
        for y in range(y_min // SCALE, h):
            row = y * w * 3
            for x in range(w):
                r, g, b = f[row + x * 3], f[row + x * 3 + 1], f[row + x * 3 + 2]
                if b > 200 and r < 110 and 80 < g < 180:
                    sx += x
                    sy += y
                    n += 1
        t = float(times[i]) if i < len(times) else float('nan')
        if n < 20:
            print(f'{t:7.3f}  --')
            prev = None
            continue
        cx, cy = sx / n * SCALE, sy / n * SCALE
        step = '' if prev is None else f'{((cx - prev[0]) ** 2 + (cy - prev[1]) ** 2) ** 0.5:6.0f}'
        print(f'{t:7.3f}  ({cx:5.0f},{cy:5.0f})  n={n:4d}  step={step}')
        prev = (cx, cy)


main()
