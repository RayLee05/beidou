"""Generate the current stream-based architecture diagram as SVG and PNG.

The SVG retains text and shapes; Pillow provides a deterministic Word image.
Run with the workspace dependency runtime (Pillow is required).
"""
from pathlib import Path
from html import escape
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports' / 'figures'
W, H = 1800, 760


def main():
    fonts = [Path('C:/Windows/Fonts/msyh.ttc'), Path('/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc')]
    face = next((f for f in fonts if f.exists()), None)
    if face is None:
        raise FileNotFoundError('A Chinese font is required; configure the fonts list in this script.')
    image = Image.new('RGB', (W, H), 'white'); draw = ImageDraw.Draw(image)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
           '<rect width="100%" height="100%" fill="white"/>']
    def text(x, y, value, size=28):
        f = ImageFont.truetype(str(face), size)
        draw.text((x, y), value, font=f, fill='#111111', anchor='mm')
        svg.append(f'<text x="{x}" y="{y}" text-anchor="middle" dominant-baseline="middle" font-family="Microsoft YaHei,Noto Sans CJK SC,sans-serif" font-size="{size}" fill="#111111">{escape(value)}</text>')
    def box(x, y, width, height, lines):
        draw.rectangle((x,y,x+width,y+height),fill='#F5F5F5',outline='#555555',width=2)
        svg.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="#F5F5F5" stroke="#555555" stroke-width="2"/>')
        for i, line in enumerate(lines):
            size = 27
            while ImageFont.truetype(str(face), size).getlength(line) > width - 30:
                size -= 1
            text(x+width/2,y+height/2+(i-(len(lines)-1)/2)*38,line,size)
    def arrow(x1,y1,x2,y2):
        draw.line((x1,y1,x2,y2),fill='#444444',width=3)
        if y1 == y2: points=[(x2,y2),(x2-14,y2-8),(x2-14,y2+8)]
        else: points=[(x2,y2),(x2-8,y2-14),(x2+8,y2-14)]
        draw.polygon(points,fill='#444444')
        svg.append(f'<path d="M{x1} {y1} L{x2} {y2}" stroke="#444444" stroke-width="3"/><polygon points="'+ ' '.join(f'{x},{y}' for x,y in points)+'" fill="#444444"/>')
    text(900,42,'北斗 B1I 接收机当前 RTL 数据流',38)
    text(900,92,'Fs 16.368 MHz　IF 4.092 MHz　32 位传输含 16 样本　最低两位最早',26)
    box(40,150,360,130,['教师 IF2 播放器','文件高位优先 → 总线低位优先'])
    box(480,150,400,130,['teacher_stream_frontend','3 位单样本流与 64 位实际计数'])
    box(980,150,400,130,['acquisition　64 路相关','有限缓存回放、粗细频点搜索'])
    box(1450,150,310,130,['channel_manager','码表装载、分配与移交'])
    arrow(400,215,480,215); arrow(880,215,980,215); arrow(1380,215,1450,215)
    box(480,355,1280,160,['channel_slice × 12　独立通道状态','tracking_channel：载波／码 NCO、E／P／L、track_loop DLL／FLL／PLL',
                          'nh_bit_sync → d1_frame_sync：位同步、BCH 译码、字结束元数据'])
    arrow(680,280,680,355); arrow(1605,280,1605,355)
    text(1085,320,'实际有效样本广播；管理器装载初值',24)
    box(480,590,920,105,['public_record_encoder','跟踪、捕获、导航、公共观测、状态、END；32 字节小端记录'])
    box(1480,590,280,105,['教师工具','独立解码与校验'])
    arrow(1120,515,1120,590); arrow(1400,642,1480,642)
    text(247,412,'valid／ready 背压',26); text(247,459,'样本时间随接受推进',26)
    text(247,506,'末拍 → 排空 → END',26)
    text(900,735,'SRAM／字节入口为保留路径；当前教师入口采用 DIRECT_SAMPLES 与 PUBLIC_RECORDS',24)
    svg.append('</svg>'); OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'architecture.svg').write_text('\n'.join(svg),encoding='utf-8')
    image.save(OUT/'architecture.png')
    dest=ROOT/'deliverables/总体架构方案/03_架构图.png'; image.save(dest)
    print(OUT/'architecture.png'); print(dest)


if __name__ == '__main__': main()
