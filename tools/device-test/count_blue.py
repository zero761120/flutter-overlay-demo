"""數截圖某個矩形範圍內「球的藍色」像素有幾個，印出數字。

用法：python3 -I tools/device-test/count_blue.py <截圖.png> <x> <y> <寬> <高>

reopen_reset.sh 拿它判斷畫面上到底畫了什麼：球的視窗裡該是藍色的球；面板開著時「解題」那顆
實心藍按鈕會有大片藍色。藍色門檻與 track_ball.py 相同。
"""
import subprocess
import sys

png, x, y, w, h = sys.argv[1], *map(int, sys.argv[2:6])
raw = subprocess.run(
    ['ffmpeg', '-v', 'error', '-i', png, '-vf', f'crop={w}:{h}:{x}:{y}',
     '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
    capture_output=True, check=True).stdout
n = 0
for i in range(0, len(raw) - 2, 3):
    r, g, b = raw[i], raw[i + 1], raw[i + 2]
    if b > 200 and r < 110 and 80 < g < 180:
        n += 1
print(n)
