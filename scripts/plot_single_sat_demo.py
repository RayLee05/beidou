"""Draw two small acceptance aids from actual RTL CSV and exported WLF values."""
from pathlib import Path
import csv
import json
import os
import shutil
import subprocess
from reportlab.graphics.shapes import Drawing, String, Line
from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.charts.lineplots import LinePlot
from reportlab.graphics import renderSVG, renderPDF
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import fitz

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'reports/sim/single_sat_demo'
OUT=ROOT/'单星捕获验收/图'
EVIDENCE=ROOT/'单星捕获验收/验证资料'
FONT='DemoChinese'


def export_wave_segments(result):
    """Read the same real WLF that run_demo.ps1 just opened in ModelSim."""
    waveform=Path(result['waveform'])
    if not waveform.is_file():
        raise FileNotFoundError('Run 单星捕获验收/run_demo.ps1 before drawing figures')
    candidates=[shutil.which('vsim.exe')]
    if os.environ.get('MODELSIM_HOME'):
        base=Path(os.environ['MODELSIM_HOME'])
        candidates += [str(base/'vsim.exe'),str(base/'win64/vsim.exe'),str(base/'bin/vsim.exe')]
    candidates += [r'D:\modeltech64_10.5\win64\vsim.exe',r'D:\modeltech64_2020.4\win64\vsim.exe']
    simulator=next((p for p in candidates if p and Path(p).is_file()),None)
    if simulator is None:
        raise FileNotFoundError('Set MODELSIM_HOME to extract the recorded waveform')
    output=SOURCE/'wave_segments.csv'
    script=SOURCE/'export_segments.do'
    script.write_text('''onerror {quit -code 1 -f}
dataset open {@WAVEFORM@} demo
set out [open {@OUTPUT@} w]
puts $out {segment,sample,signal_code,local_code,energy,capture,result_phase}
foreach {segment base} {wrong 5400000000 aligned 11400000000} {
  for {set n 0} {$n < 192} {incr n} {
    set t [expr {$base + $n*61094}]
    set values [list $segment $n]
    foreach field {signal_code local_code energy capture result_phase} {
      lappend values [examine -radix unsigned -time ${t}ps demo:/tb_single_sat_capture/$field]
    }
    puts $out [join $values ,]
  }
}
close $out
puts {WAVE_DATA_EXPORTED}
quit -f
'''.replace('@WAVEFORM@',waveform.as_posix()).replace('@OUTPUT@',output.as_posix()),encoding='ascii')
    completed=subprocess.run([simulator,'-c','-do',f'do {{{script.as_posix()}}}'],
                             cwd=ROOT,capture_output=True,text=True,timeout=30)
    (SOURCE/'wave_export.log').write_text(completed.stdout+completed.stderr,encoding='utf-8')
    if completed.returncode or 'WAVE_DATA_EXPORTED' not in completed.stdout:
        raise RuntimeError('Waveform export failed; see reports/sim/single_sat_demo/wave_export.log')


def save(drawing,name):
    OUT.mkdir(exist_ok=True)
    renderSVG.drawToFile(drawing,str(OUT/(name+'.svg')))
    pdf=fitz.open(stream=renderPDF.drawToString(drawing),filetype='pdf')
    pdf[0].get_pixmap(matrix=fitz.Matrix(2,2),alpha=False).save(OUT/(name+'.png'))


def main():
    result=json.loads((SOURCE/'result.json').read_text(encoding='utf-8-sig'))
    assert result['passed'] and result['energy_ratio']>=100
    export_wave_segments(result)
    # The local Windows font keeps the Chinese guide figures legible in PNG/PDF.
    font_file=Path(os.environ.get('WINDIR',r'C:\Windows'))/'Fonts/simsun.ttc'
    pdfmetrics.registerFont(TTFont(FONT,str(font_file),subfontIndex=0))
    with (SOURCE/'capture.csv').open(encoding='utf-8-sig') as f:
        rows=[{k:int(v) for k,v in r.items()} for r in csv.DictReader(f)]
    with (SOURCE/'wave_segments.csv').open(encoding='utf-8-sig') as f:
        traces=list(csv.DictReader(f))
    assert all(r['signal_code']==r['local_code'] for r in traces if r['segment']=='aligned')
    assert any(r['signal_code']!=r['local_code'] for r in traces if r['segment']=='wrong')
    d=Drawing(720,340)
    d.add(String(35,315,'单星捕获：实际电路仿真的相关能量',fontName=FONT,fontSize=16))
    d.add(String(35,291,f"对齐能量 ÷ 最大未对齐能量 = {result['aligned_energy_min']:,} ÷ {result['wrong_energy_max']:,} = {result['energy_ratio']:g} 倍",fontName=FONT,fontSize=11))
    chart=VerticalBarChart();chart.x=65;chart.y=65;chart.width=610;chart.height=200
    chart.data=[[r['energy']/1e9 for r in rows]]
    chart.categoryAxis.categoryNames=[str(r['window']) for r in rows]
    chart.valueAxis.valueMin=0;chart.valueAxis.valueMax=3.6;chart.valueAxis.valueStep=.6
    chart.bars[0].fillColor=colors.HexColor('#286B9A')
    for i in range(10,13):chart.bars[(0,i)].fillColor=colors.HexColor('#B52E34')
    chart.bars.strokeColor=None
    d.add(chart)
    d.add(String(65,277,'能量（十亿）',fontName=FONT,fontSize=10))
    d.add(String(250,36,'已经算完的轮次（每轮 16368 个样本）',fontName=FONT,fontSize=11))
    d.add(String(74,12,'第 1～10 轮未对齐；第 11 轮捕获成功；第 12、13 轮继续复核。',fontName=FONT,fontSize=10))
    save(d,'能量对比')
    d=Drawing(720,395)
    d.add(String(35,371,'从实际仿真波形中导出的两段码线',fontName=FONT,fontSize=16))
    d.add(String(35,348,'蓝色实线：老师信号中的码。红色虚线：我们自己生成的本地码。',fontName=FONT,fontSize=10))
    for key,y,title in [('wrong',222,'未捕获时：5.400 ms 附近'),('aligned',70,'捕获成功后：11.400 ms 附近')]:
        selected=[r for r in traces if r['segment']==key][:128]
        chart=LinePlot();chart.x=65;chart.y=y;chart.width=610;chart.height=80
        chart.xValueAxis.valueMin=0;chart.xValueAxis.valueMax=128;chart.xValueAxis.valueStep=16
        chart.yValueAxis.valueMin=-.15;chart.yValueAxis.valueMax=1.2;chart.yValueAxis.valueSteps=[0,1]
        series=[]
        for field in ('signal_code','local_code'):
            points=[]
            for n,row in enumerate(selected):
                if n:points.append((n,int(selected[n-1][field])))
                points.append((n,int(row[field])))
            series.append(points)
        chart.data=series
        chart.lines[0].strokeColor=colors.HexColor('#286B9A');chart.lines[0].strokeWidth=1.8
        chart.lines[1].strokeColor=colors.HexColor('#B52E34');chart.lines[1].strokeWidth=1
        chart.lines[1].strokeDashArray=[4,2]
        d.add(chart);d.add(String(65,y+100,title,fontName=FONT,fontSize=12))
    d.add(String(220,38,'连续的采样位置（展示 128 个样本）',fontName=FONT,fontSize=11))
    d.add(String(65,14,'对齐后两条线重合；三个完整对齐窗口的 49104 个样本也全部核对一致。',fontName=FONT,fontSize=10))
    save(d,'码对齐对比')
    EVIDENCE.mkdir(exist_ok=True)
    for name in ('capture.csv','result.json','wave_segments.csv'):
        shutil.copy2(SOURCE/name,EVIDENCE/name)
    print('Figures and compact RTL evidence written to',OUT.parent)


if __name__=='__main__':main()
