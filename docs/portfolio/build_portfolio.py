"""Build the WEASHION portfolio from repository assets, without changing the app.

Run: python3 docs/portfolio/build_portfolio.py
Requires: reportlab, Pillow, fonttools (already present in the creation environment).
Output: WEASHION-Portfolio.pdf next to this file.

Evidence: README.md; Views/WEASHIONSceneView.swift; Models/BodyPreviewRenderer.swift;
Views/EditorialStyle.swift; Views/EditorialFonts.swift; Packages/ClothPhysics/README.md;
the existing EditorialDesignTests, FittingLibraryTests and WeatherServiceTests.
Screenshots are crops of the repository's Korean iPad App Store submission images,
not new captures of the current working tree. Screenshot values are examples.
The App Store listing was checked on 2026-11-10; no adoption metrics are inferred.
"""

from html import escape
from pathlib import Path
from tempfile import TemporaryDirectory

from fontTools.ttLib import TTFont as SourceFont
from fontTools.varLib.instancer import instantiateVariableFont
from PIL import Image
from reportlab.graphics import renderPDF
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.lib.colors import HexColor
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path(__file__).with_name("WEASHION-Portfolio.pdf")
FONTS = ROOT / "weashion/weashion/Resources/Fonts"
SCREENS = ROOT / "AppStoreScreenshots/ko/ipad13_2064x2752"
STORE = "https://apps.apple.com/kr/app/weashion/id6828449533"
W, H = 1280, 720
PAPER = "#FAF9F6"
INK = "#202B30"
MUTED = "#626B67"
ACCENT = "#9F3548"
STOCK = "#EAE7E0"
STUDIO = "#ECEDEA"
RULE = "#D3D4D0"


def register_fonts(directory):
    instances = [
        ("Sans", "PretendardVariable.ttf", {"wght": 400}),
        ("Strong", "PretendardVariable.ttf", {"wght": 650}),
        ("Display", "BodoniModa-Variable.ttf", {"wght": 400, "opsz": 72}),
        ("Italic", "BodoniModa-Italic-Variable.ttf", {"wght": 400, "opsz": 36}),
    ]
    for name, filename, axes in instances:
        with SourceFont(FONTS / filename) as original:
            instance = instantiateVariableFont(original, axes, inplace=False)
            # ReportLab identifies font faces by PostScript name, not registration alias.
            for record in instance["name"].names:
                if record.nameID in (4, 6):
                    record.string = f"WEASHION-{name}".encode(record.getEncoding())
            path = Path(directory) / f"{name}.ttf"
            instance.save(path)
            instance.close()
        pdfmetrics.registerFont(TTFont(name, str(path)))
    pdfmetrics.registerFont(TTFont("Myeongjo", str(FONTS / "NanumMyeongjo-Bold.ttf")))


class Portfolio:
    def __init__(self):
        self.canvas = Canvas(
            str(OUTPUT), pagesize=(W, H), pageCompression=1,
            initialFontName="Sans", lang="ko-KR",
        )
        self.canvas.setTitle("WEASHION | 내 몸을 기준으로, 옷의 차이를 읽다")
        self.canvas.setAuthor("WEASHION")
        self.canvas.setSubject("iOS / iPadOS 가상 피팅 앱 프로젝트 포트폴리오")
        self.canvas.setCreator("WEASHION portfolio builder / ReportLab")
        self.page_number = 0

    def rect(self, x, top, width, height, color):
        self.canvas.setFillColor(HexColor(color))
        self.canvas.rect(x, H - top - height, width, height, stroke=0, fill=1)

    def line(self, x, top, width, color=RULE, thickness=0.7):
        self.canvas.setStrokeColor(HexColor(color))
        self.canvas.setLineWidth(thickness)
        self.canvas.line(x, H - top, x + width, H - top)

    def text(self, value, x, top, size=18, font="Sans", color=INK):
        width = pdfmetrics.stringWidth(value, font, size)
        if x < 0 or x + width > W or top < 0 or top + size > H:
            raise ValueError(f"Text outside page: {value!r}")
        self.canvas.setFillColor(HexColor(color))
        self.canvas.setFont(font, size)
        self.canvas.drawString(x, H - top - size * 0.86, value)
        return width

    def para(self, value, x, top, width, size=19, font="Sans", color=INK,
             leading=None, max_height=200):
        style = ParagraphStyle(
            "body", fontName=font, fontSize=size, leading=leading or size * 1.55,
            textColor=HexColor(color), wordWrap="CJK", splitLongWords=True,
        )
        paragraph = Paragraph(escape(value).replace("\n", "<br/>"), style)
        _, height = paragraph.wrap(width, H)
        if height > max_height or x < 0 or x + width > W or top < 0 or top + height > H:
            raise ValueError(f"Paragraph does not fit ({height:.1f}pt): {value!r}")
        paragraph.drawOn(self.canvas, x, H - top - height)
        return top + height

    def start(self, section):
        self.page_number += 1
        self.rect(0, 0, W, H, PAPER)
        self.text("WEASHION", 64, 30, 18, "Display")
        self.text(section, 204, 34, 12.5, "Sans", MUTED)
        self.line(64, 62, 1152)
        self.line(64, 673, 1152)
        self.text("WEASHION  /  iOS · iPadOS", 64, 688, 11.5, color=MUTED)
        self.text("프로젝트 포트폴리오  ·  2026.11", 510, 688, 11.5, color=MUTED)
        self.text(f"{self.page_number:02d} / 08", 1164, 688, 11.5, color=MUTED)
        self.canvas.bookmarkPage(f"page-{self.page_number}")
        self.canvas.addOutlineEntry(section, f"page-{self.page_number}", level=0)

    def end(self):
        self.canvas.showPage()

    def image(self, filename, crop, x, top, width, height):
        with Image.open(SCREENS / filename) as original:
            image = original.crop(crop).convert("RGB")
        image.thumbnail((round(width * 2.5), round(height * 2.5)), Image.Resampling.LANCZOS)
        scale = min(width / image.width, height / image.height)
        draw_w, draw_h = image.width * scale, image.height * scale
        draw_x = x + (width - draw_w) / 2
        draw_top = top + (height - draw_h) / 2
        self.canvas.drawImage(
            ImageReader(image), draw_x, H - draw_top - draw_h, draw_w, draw_h,
        )
        return draw_x, draw_top, draw_w, draw_h

    def link(self, label, x, top, size=18):
        width = self.text(label, x, top, size, "Strong", ACCENT)
        self.line(x, top + size + 5, width, ACCENT, 0.8)
        self.canvas.linkURL(
            STORE, (x, H - top - size - 7, x + width, H - top + 3),
            relative=0, thickness=0,
        )

    def caption(self, value, x, top, width):
        self.para(value, x, top, width, 12.5, color=MUTED, leading=18, max_height=54)

    def qr(self, x, top, size):
        widget = QrCodeWidget(STORE, barLevel="M", barBorder=4)
        x0, y0, x1, y1 = widget.getBounds()
        drawing = Drawing(
            size, size, transform=[size / (x1 - x0), 0, 0, size / (y1 - y0), -x0, -y0],
        )
        drawing.add(widget)
        self.rect(x, top, size, size, "#FFFFFF")
        renderPDF.draw(drawing, self.canvas, x, H - top - size)
        self.canvas.linkURL(
            STORE, (x, H - top - size, x + size, H - top),
            relative=0, thickness=0,
        )

    def cover(self):
        self.start("출시 앱 소개")
        self.text("WEASHION", 60, 110, 93, "Display")
        self.para("내 몸을 기준으로,\n옷의 차이를 읽다.", 64, 252, 600, 39,
                  "Myeongjo", leading=57, max_height=120)
        self.para("신체 치수로 만든 근사 3D 마네킹에서\n옷의 사이즈와 실루엣을 비교하는 앱.",
                  66, 402, 535, 21, color=MUTED, leading=33)
        self.text("iPhone · iPad", 66, 520, 17, "Strong")
        self.text("한국어 · 영어 · 일본어", 66, 552, 16, color=MUTED)
        self.link("App Store에서 WEASHION 보기", 66, 611, 18)
        self.image("02_ipad.png", (312, 850, 1752, 1775), 680, 106, 536, 498)
        self.caption("실제 앱 화면 발췌 · 샘플 의상 / 샘플 날씨", 704, 625, 500)
        self.end()

    def premise(self):
        self.start("문제와 제품의 기준")
        self.para("사이즈표의 숫자를\n내 몸 위에서 이해하도록.", 64, 95, 750,
                  36, "Myeongjo", leading=49, max_height=105)
        self.para(
            "옷의 치수만 보고는 길이와 여유를 상상하기 어렵습니다.\n"
            "WEASHION은 몸을 비교의 기준으로 고정하고, 옷의 치수를 바꿔 봅니다.",
            64, 219, 755, 19, color=MUTED, leading=30,
        )
        self.image("05_ipad.png", (377, 1394, 1004, 2233), 887, 107, 301, 402)
        self.caption("내 체형 화면 발췌 · 신체 스캔이 아닌 근사 모델", 870, 527, 346)
        self.line(64, 332, 741)
        stages = [
            ("01", "체형 설정", "기준 체형을 고르고\n키·몸무게와 치수를 입력"),
            ("02", "의류 기록", "지원 의상 템플릿에\n사이즈별 실측을 저장"),
            ("03", "사이즈 전환", "같은 개인 마네킹에서\n옷의 길이·실루엣을 비교"),
            ("04", "수치 확인", "입력 치수와 여유 지표,\n착장 경고를 함께 확인"),
        ]
        for index, (number, title, description) in enumerate(stages):
            x = 64 + (index % 2) * 389
            top = 365 + (index // 2) * 145
            self.text(number, x, top, 24, "Italic", ACCENT)
            self.text(title, x + 47, top + 2, 21, "Strong")
            self.para(description, x + 47, top + 42, 303, 17, color=MUTED,
                      leading=27, max_height=60)
        self.end()

    def fitting(self):
        self.start("핵심 경험 / 피팅룸")
        self.para("모습과 숫자를,\n한 지면에서 비교합니다.", 64, 96, 790,
                  35, "Myeongjo", leading=48, max_height=100)
        self.text("같은 체형 · 다른 사이즈", 937, 155, 18, "Strong", ACCENT)
        self.image("04_ipad.png", (377, 1015, 1098, 1935), 64, 235, 330, 386)
        self.image("04_ipad.png", (1155, 1015, 1688, 1705), 423, 235, 315, 386)
        self.caption("피팅룸의 3D 뷰어와 사이즈·비교 정보 발췌 · M 사이즈 예시", 64, 632, 730)
        notes = [
            (246, "비교 기준을 유지", "몸을 옷에 맞춰 바꾸지 않고,\n같은 체형에서 사이즈를 전환합니다."),
            (378, "직접 돌리고 확대", "가로 드래그는 회전, 핀치는 확대.\n버튼으로도 같은 시점을 조작합니다."),
            (510, "보기와 해석을 연결", "3D 형상과 치수·경고를 분리해\n화면을 읽는 기준을 명확히 합니다."),
        ]
        for top, title, description in notes:
            self.line(858, top - 13, 358)
            self.text(title, 858, top + 3, 22, "Strong")
            self.para(description, 858, top + 44, 358, 18, color=MUTED,
                      leading=29, max_height=65)
        self.end()

    def measurements(self):
        self.start("정보 설계 / 치수와 정확성")
        self.para("그림보다 먼저,\n비교의 기준을 명확하게.", 64, 94, 770, 35,
                  "Myeongjo", leading=48, max_height=100)
        self.para("항목 · 값 · 단위를 함께 읽게 하고,\n입력 실측과 계산된 여유를 구분합니다.",
                  67, 223, 610, 20, color=MUTED, leading=31)
        self.image("04_ipad.png", (1155, 1800, 1688, 2145), 850, 255, 366, 260)
        self.caption("실제 의류 도식 발췌 · 번호는 치수 항목과 연결", 850, 536, 366)
        self.para("도식은 측정 위치를 설명합니다.\n실제 상품의 비율을 재현한 그림은 아닙니다.",
                  850, 579, 366, 16.5, color=MUTED, leading=25, max_height=60)
        self.text("샘플 의류 M · 화면에 표시된 입력값", 65, 326, 16, "Strong", ACCENT)
        rows = [("총장", "63.0"), ("어깨너비", "53.0"),
                ("가슴단면", "54.5"), ("소매길이", "19.0")]
        for index, (label, value) in enumerate(rows):
            x = 64 + (index % 2) * 350
            top = 365 + (index // 2) * 108
            self.line(x, top - 12, 307)
            self.text(f"{index + 1:02d}", x, top, 18, "Italic", ACCENT)
            self.text(label, x + 34, top, 18)
            self.text(value, x + 137, top + 15, 44, "Display")
            self.text("cm", x + 254, top + 39, 15, "Italic", MUTED)
        self.para(
            "단면 치수와 신체 둘레의 비교는 근사값입니다.\n"
            "실제 착용 가능 여부나 구매할 사이즈를 보장하지 않습니다.",
            64, 598, 732, 16.5, color=MUTED, leading=25, max_height=55,
        )
        self.end()

    def weather(self):
        self.start("시각 언어 / 날씨와 피팅의 관계")
        self.para("날씨는 맥락으로,\n피팅은 중심으로.", 64, 95, 720, 36,
                  "Myeongjo", leading=49, max_height=105)
        self.image("03_ipad.png", (377, 1290, 1688, 2240), 64, 239, 630, 377)
        self.caption("날씨 화면 발췌 · 24°C는 실제 위치와 연결되지 않은 샘플값", 64, 632, 670)
        self.text("상태를 숨기지 않는 날씨", 778, 243, 24, "Strong")
        self.para(
            "현재 위치의 날씨 연결은 선택 사항입니다.\n"
            "연결 없이도 피팅을 사용할 수 있으며,\n"
            "샘플·마지막 수신값·실패를 구분합니다.",
            778, 285, 438, 19, color=MUTED, leading=31, max_height=125,
        )
        self.line(778, 412, 438)
        self.text("앱과 이어지는 편집 언어", 778, 438, 24, "Strong")
        self.para(
            "따뜻한 바탕과 짙은 잉크색을 기본으로,\n"
            "선택과 주요 행동만 버건디로 강조합니다.\n"
            "명조 제목과 산세리프 본문을 구분합니다.",
            778, 480, 438, 19, color=MUTED, leading=31, max_height=110,
        )
        for x, color, label in [
            (779, STOCK, "종이"), (920, INK, "잉크"), (1061, ACCENT, "강조"),
        ]:
            self.rect(x, 606, 35, 20, color)
            self.text(label, x + 47, 607, 15, color=MUTED)
        self.end()

    def architecture(self):
        self.start("구현 / 3D 장면과 계산의 분리")
        self.para("계산과 화면 사이의\n책임을 나눕니다.", 64, 95, 800, 36,
                  "Myeongjo", leading=49, max_height=105)
        stages = [
            (236, "01", "SwiftUI", "입력 · 선택 · 상태 표시", "사용자 치수와 의류 선택을 화면 상태로 연결"),
            (332, "02", "Swift actor", "신체 표면 준비 · 캐시", "BodyPreviewRenderer에서 취소 확인 및 결과 재사용"),
            (428, "03", "RealityKit → SceneKit", "형상과 표시의 연결", "Entity의 mesh·변환·지원 재질을 SCNView로 동기화"),
            (524, "04", "UIKit", "회전 · 확대 제스처", "가로 pan으로 회전하고 pinch 위치를 확대에 반영"),
        ]
        for top, number, name, role, description in stages:
            self.line(64, top - 14, 745)
            self.text(number, 64, top + 5, 24, "Italic", ACCENT)
            self.text(name, 116, top + 3, 23, "Strong")
            self.text(role, 116, top + 38, 17, color=MUTED)
            self.para(description, 451, top + 8, 357, 16.5, color=MUTED,
                      leading=26, max_height=60)
        self.rect(871, 233, 345, 352, STUDIO)
        self.text("의류 보정의 경계", 899, 262, 24, "Strong")
        self.para(
            "Swift 피팅과 C++/Bullet 기반\n"
            "정적 겹침 보정을 사용합니다.\n\n"
            "원단 물성이나 동적 주름을\n"
            "정밀하게 재현하지 않습니다.\n"
            "남은 겹침은 별도로 안내합니다.",
            899, 312, 287, 19, leading=31, max_height=240,
        )
        self.caption(
            "구현 근거: WEASHIONSceneView · BodyPreviewRenderer · ClothPhysics README\n"
            "성능 실측이나 전체 원단 시뮬레이션 구현 완료를 의미하지 않습니다.",
            64, 623, 1152,
        )
        self.end()

    def reliability(self):
        self.start("신뢰성 / 상태와 검증 관점")
        self.para("잘 보이는 화면만큼,\n실패를 설명하는 화면.", 64, 95, 800,
                  36, "Myeongjo", leading=49, max_height=105)
        self.para("기다림·취소·경고를 성공 화면과 구분합니다.", 64, 218, 790,
                  20, color=MUTED)
        states = [
            ("준비 / 계산 중", "준비 상태와 계산 진행 상황을 표시하고 취소 동작을 제공합니다."),
            ("사용자 취소", "완료 상태로 처리하지 않고, 취소 안내와 다시 계산 동작을 보여줍니다."),
            ("경고 / 실패", "보이는 의상이 있으면 경고, 없으면 실패로 구분해 안내합니다."),
        ]
        for index, (title, description) in enumerate(states):
            top = 298 + index * 108
            self.line(64, top - 16, 722)
            self.text(title, 64, top + 3, 22, "Strong")
            self.para(description, 302, top + 1, 484, 18, color=MUTED,
                      leading=29, max_height=65)
        self.text("저장소에 마련된 회귀 테스트", 852, 285, 23, "Strong")
        self.para(
            "빠른 연속 요청의 최신 결과 반영\n"
            "장면·형상 재사용과 캐시 해제\n"
            "잘못된 입력과 저장 실패 처리\n"
            "날씨 권한 거절·실패·재시도\n"
            "동작 줄이기와 언어 전환",
            852, 338, 364, 18, color=MUTED, leading=39, max_height=205,
        )
        self.caption(
            "테스트 항목은 기존 소스에서 확인했습니다.\n"
            "이 PDF 제작 과정에서 앱 테스트를 재실행한 결과는 아닙니다.",
            852, 565, 364,
        )
        self.caption("왼쪽은 현재 코드의 상태 처리 요약이며, 실제 앱 화면 캡처가 아닙니다.",
                     64, 632, 735)
        self.end()

    def closing(self):
        self.start("출시와 다음 단계")
        self.para("비교할 수 있는 경험으로,\n실제로 배포한 앱.", 64, 95, 965,
                  36, "Myeongjo", leading=49, max_height=105)
        self.text("App Store 공개 페이지 확인", 64, 237, 22, "Strong")
        self.para(
            "iPhone · iPad / 한국어 · 영어 · 일본어\n"
            "제공자: JaeHyun Lim · 공개 페이지 확인일: 2026.11.10",
            64, 277, 752, 18, color=MUTED, leading=30,
        )
        self.line(64, 366, 740)
        self.text("다음 검증과 개선", 64, 389, 23, "Strong")
        self.para(
            "실제 의류와 근사 착장의 차이를 비교하고,\n"
            "더 다양한 체형·사이즈 조합에서 품질을 확인합니다.\n"
            "실기기에서 응답성·메모리·접근성을 계속 점검합니다.",
            64, 433, 740, 19, color=MUTED, leading=32, max_height=100,
        )
        self.qr(924, 244, 200)
        self.link("App Store에서 보기", 934, 465, 19)
        self.caption("QR 스캔 또는 링크 클릭", 934, 505, 260)
        self.line(64, 562, 1152)
        self.caption(
            "자료 기준  |  앱 화면은 저장소의 한국어 iPad App Store 제출 이미지에서 발췌했으며, "
            "현재 작업 트리 및 배포 버전과 차이가 있을 수 있습니다. 화면 속 치수·날씨는 예시입니다.",
            64, 579, 1152,
        )
        self.caption(
            "구현 근거  |  README, WEASHIONSceneView, BodyPreviewRenderer, EditorialStyle/Fonts, "
            "ClothPhysics 및 기존 테스트 소스. 사용자 수·정확도·속도 등 미검증 성과 수치는 기재하지 않았습니다.",
            64, 623, 1152,
        )
        self.end()

    def build(self):
        for page in [self.cover, self.premise, self.fitting, self.measurements,
                     self.weather, self.architecture, self.reliability, self.closing]:
            page()
        if self.page_number != 8:
            raise ValueError("The portfolio must have exactly eight pages")
        self.canvas.save()


if __name__ == "__main__":
    with TemporaryDirectory(prefix="weashion-portfolio-fonts-") as directory:
        register_fonts(directory)
        Portfolio().build()
    print(OUTPUT)
