#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成宣传海报：竖版 1080x1920 / 横版 1920x1080 / 图标 512。

用法：python3 tool/make_poster.py [输出目录]

默认输出到 /tmp/poster，也接受一个目录参数。
颜色取自 DESIGN.md 的色板（暖白纸底 + 墨蓝强调色），
图标全部用几何图形画出来：系统字体里没有 emoji 字形，直接写会变成豆腐块。

依赖：Pillow、fonts-wqy-zenhei。
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, math, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else '/tmp/poster'
os.makedirs(OUT, exist_ok=True)

PAPER=(250,249,246); CARD=(255,255,255); INK=(26,28,31); BODY=(58,64,72)
SUB=(110,118,129); HAIR=(236,234,228); ACCENT=(51,85,232)
ACCENT_SOFT=(232,236,252); TERM_BG=(18,20,23); TERM_FG=(233,231,225)
TERM_DIM=(92,99,108); GREEN=(63,169,107)

FONT='/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'
def F(s,i=0): return ImageFont.truetype(FONT,s,index=i)

# ---------- 图标（几何绘制） ----------
def icon_clock(d,cx,cy,r,c,w=6):
    d.ellipse([cx-r,cy-r,cx+r,cy+r],outline=c,width=w)
    d.line([cx,cy,cx,cy-r//2],fill=c,width=w); d.line([cx,cy,cx+r//2,cy],fill=c,width=w)
def icon_shield(d,cx,cy,r,c,w=6):
    d.polygon([(cx,cy-r),(cx+r,cy-r*.55),(cx+r*.8,cy+r*.5),(cx,cy+r),
               (cx-r*.8,cy+r*.5),(cx-r,cy-r*.55)],outline=c,width=w)
    d.line([(cx-r*.45,cy),(cx-r*.1,cy+r*.38),(cx+r*.5,cy-r*.35)],fill=c,width=w+1,joint='curve')
def icon_chat(d,cx,cy,r,c,w=6):
    d.rounded_rectangle([cx-r,cy-r*.75,cx+r,cy+r*.35],radius=14,outline=c,width=w)
    d.polygon([(cx-r*.35,cy+r*.3),(cx-r*.05,cy+r*.3),(cx-r*.3,cy+r*.75)],fill=c)
def icon_phone(d,cx,cy,r,c,w=6):
    d.rounded_rectangle([cx-r*.6,cy-r,cx+r*.6,cy+r],radius=12,outline=c,width=w)
    d.line([cx-r*.22,cy+r*.72,cx+r*.22,cy+r*.72],fill=c,width=w-1)
def icon_brain(d,cx,cy,r,c,w=6):
    d.arc([cx-r,cy-r*.8,cx+r*.05,cy+r*.6],60,300,fill=c,width=w)
    d.arc([cx-r*.05,cy-r*.8,cx+r,cy+r*.6],240,120,fill=c,width=w)
    d.line([cx,cy-r*.75,cx,cy+r*.55],fill=c,width=w-1)
def icon_bolt(d,cx,cy,r,c,w=6):
    d.polygon([(cx+r*.25,cy-r),(cx-r*.5,cy+r*.15),(cx-r*.05,cy+r*.15),
               (cx-r*.25,cy+r),(cx+r*.5,cy-r*.15),(cx+r*.05,cy-r*.15)],outline=c,width=w)

def hex_logo(d,cx,cy,r,fill,cut):
    pts=[(cx+r*math.cos(math.radians(-90+i*60)), cy+r*math.sin(math.radians(-90+i*60))) for i in range(6)]
    d.polygon(pts,fill=fill)
    d.line([(cx-r*.32,cy-r*.46),(cx+r*.18,cy),(cx-r*.32,cy+r*.46)],fill=cut,width=max(4,int(r*.2)),joint='curve')

def term_block(img,d,tx0,ty0,tw,th,lines,fs=28,pad=36,ls=42,title='carbide shell'):
    sh=Image.new('RGBA',img.size,(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([tx0,ty0+12,tx0+tw,ty0+th+12],radius=26,fill=(20,24,30,42))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)))
    d=ImageDraw.Draw(img)
    d.rounded_rectangle([tx0,ty0,tx0+tw,ty0+th],radius=26,fill=TERM_BG+(255,))
    for i,c in enumerate([(255,95,86),(255,189,46),(39,201,63)]):
        d.ellipse([tx0+32+i*34,ty0+28,tx0+52+i*34,ty0+48],fill=c)
    d.text((tx0+tw//2,ty0+38),title,font=F(24),fill=TERM_DIM,anchor='mm')
    ly=ty0+86
    for pre,body,col in lines:
        if pre:
            d.text((tx0+pad,ly),pre+' ',font=F(fs),fill=GREEN)
            d.text((tx0+pad+d.textlength(pre+' ',font=F(fs)),ly),body,font=F(fs),fill=col)
        elif body:
            d.text((tx0+pad,ly),body,font=F(fs),fill=col)
        ly+=ls

def caps_row(d,x0,y,items,fs=30,h=66,fill=(255,255,255,48),fg=(255,255,255)):
    x=x0
    for c in items:
        w=int(d.textlength(c,font=F(fs)))+44
        d.rounded_rectangle([x,y,x+w,y+h],radius=h//2,fill=fill)
        d.text((x+22,y+h//2),c,font=F(fs),fill=fg,anchor='lm')
        x+=w+16
    return x

def feature_card(img,d,box,title,sub,ico):
    x0,y0,x1,y1=box
    sh=Image.new('RGBA',img.size,(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([x0,y0+6,x1,y1+6],radius=24,fill=(20,24,30,18))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(24)))
    d=ImageDraw.Draw(img)
    d.rounded_rectangle(box,radius=24,fill=CARD+(255,))
    d.rounded_rectangle([x0+32,y0+34,x0+100,y0+102],radius=20,fill=ACCENT_SOFT+(255,))
    {'clock':icon_clock,'shield':icon_shield,'chat':icon_chat,
     'phone':icon_phone,'brain':icon_brain,'bolt':icon_bolt}[ico](d,x0+66,y0+68,22,ACCENT)
    d.text((x0+124,y0+40),title,font=F(38),fill=INK)
    d.text((x0+124,y0+88),sub,font=F(26),fill=SUB)

TERMLINES=[('$','ssh_exec  hk  uptime',TERM_FG),
           ('','up 12 days · 负载 0.31',GREEN),
           ('','',None),
           ('$','磁盘 91%  →  清理',TERM_FG),
           ('','正在删 /var/log/*.gz …',GREEN),
           ('','清出 2.4 GB，磁盘 41%',GREEN),
           ('','',None),
           ('$','notify "磁盘满了，已清理"',TERM_FG),
           ('','✓ 已发通知到手机',TERM_DIM)]

CARDS=[('自己会动手','定时任务 · 触发器','clock'),('干事前先问','危险操作直接拒','shield'),
       ('聊天即操作','一句话改服务器','chat'),('手机也能用','离线看 · 定时跑','phone'),
       ('记忆与密钥','跨会话记住你','brain'),('纯 Dart 内核','无 Flutter 依赖','bolt')]

# ================= 竖版 1080x1920 =================
def make_vertical():
    W,H=1080,1920
    img=Image.new('RGBA',(W,H),PAPER+(255,)); d=ImageDraw.Draw(img)
    d.rectangle([0,0,W,700],fill=ACCENT+(255,))
    hex_cx,hex_cy,hex_r=182,196,92
    d.ellipse([hex_cx-108,hex_cy-108,hex_cx+108,hex_cy+108],fill=(255,255,255,255))
    hex_logo(d,hex_cx,hex_cy,hex_r,(17,19,21,255),PAPER+(255,))
    d.text((318,118),'Carbide Shell',font=F(74),fill=(255,255,255))
    d.text((322,218),'碳 壳',font=F(58),fill=(219,226,255))
    d.text((76,352),'手机上的服务器 agent',font=F(62),fill=(255,255,255))
    d.text((78,442),'连上你的机器，自己干活',font=F(38),fill=(206,216,255))
    caps_row(d,76,528,['纯 Dart 内核','SSH 远程','定时任务','触发器','自带审批'])
    term_block(img,d,76,630,928,410,TERMLINES)
    cw,ch,gap=440,150,48
    for i,(t,s,ic) in enumerate(CARDS):
        row,col=divmod(i,2)
        y=1104+(ch+28)*row; x=76+(cw+gap)*col
        feature_card(img,d,(x,y,x+cw,y+ch),t,s,ic)
    d.rounded_rectangle([76,1694,1004,1840],radius=32,fill=ACCENT+(255,))
    d.text((540,1726),'开源 · 免费 · 无广告',font=F(46),fill=(255,255,255),anchor='ma')
    d.text((540,1794),'GitHub 搜  dariondong/carbide-shell',font=F(28),fill=(214,222,255),anchor='ma')
    return img

# ================= 横版 1920x1080 =================
def make_horizontal():
    W,H=1920,1080
    img=Image.new('RGBA',(W,H),PAPER+(255,)); d=ImageDraw.Draw(img)
    d.rectangle([0,0,1080,H],fill=ACCENT+(255,))
    hex_cx,hex_cy,hex_r=210,300,116
    d.ellipse([hex_cx-140,hex_cy-140,hex_cx+140,hex_cy+140],fill=(255,255,255,255))
    hex_logo(d,hex_cx,hex_cy,hex_r,(17,19,21,255),PAPER+(255,))
    d.text((104,560),'Carbide Shell',font=F(92),fill=(255,255,255))
    d.text((108,676),'碳 壳',font=F(64),fill=(219,226,255))
    d.text((104,790),'手机上的服务器 agent',font=F(46),fill=(255,255,255))
    d.text((106,862),'连上你的机器，自己干活',font=F(32),fill=(206,216,255))
    caps_row(d,104,940,['纯 Dart 内核','SSH 远程','定时任务','触发器'],fs=28,h=60)
    term_block(img,d,1140,150,720,420,TERMLINES,fs=24,ls=36)
    d.rounded_rectangle([1140,640,1860,790],radius=28,fill=CARD+(255,))
    d.text((1196,690),'开源 · 免费 · 无广告',font=F(40),fill=INK)
    d.text((1196,738),'GitHub  dariondong/carbide-shell',font=F(26),fill=SUB)
    d.rounded_rectangle([1140,820,1860,930],radius=28,fill=ACCENT+(255,))
    d.text((1500,875),'手机 · 电脑 · 都能跑',font=F(36),fill=(255,255,255),anchor='mm')
    return img

# ================= 图标 512 =================
def make_icon():
    S=512
    img=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(img)
    d.rounded_rectangle([0,0,S-1,S-1],radius=112,fill=ACCENT+(255,))
    hex_logo(d,256,256,168,(17,19,21,255),ACCENT+(255,))
    return img

v=make_vertical(); v.convert('RGB').save(f'{OUT}/poster_vertical.jpg',quality=95)
v.convert('RGB').save(f'{OUT}/poster_vertical.png')
h=make_horizontal(); h.convert('RGB').save(f'{OUT}/poster_horizontal.jpg',quality=95)
h.convert('RGB').save(f'{OUT}/poster_horizontal.png')
ic=make_icon(); ic.save(f'{OUT}/poster_icon_512.png')
print('saved all')
