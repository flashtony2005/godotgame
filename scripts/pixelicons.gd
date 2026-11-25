extends RefCounted
## 原版 70-pixelfont.js 的像素图标，逐像素还原（HUD 建造卡片用）。

const PAL := {
	"G": "#e8b04a",
	"g": "#a8742a",
	"Y": "#ffe2a0",
	"B": "#e9dfc8",
	"b": "#b9ad93",
	"E": "#ff8a3c",
	"e": "#c9481e",
	"d": "#7a2a14",
	"C": "#8fc7ff",
	"c": "#4f86c6",
	"S": "#9aa3b0",
	"s": "#5b6472",
	"k": "#353b49",
	"W": "#8a6a48",
	"w": "#5a4330",
	"o": "#0b0d14",
}

const ICONS := {
	"coin": [
		"..oooo..",
		".oYYGGo.",
		"oYGGGGgo",
		"oYGgGGgo",
		"oGGgGGgo",
		"oGGGGggo",
		".oGgggo.",
		"..oooo..",
	],
	"archer": [
		"...WW........",
		"...bWWW......",
		"...b..WW.....",
		"...b...WW....",
		"...b....W.E..",
		"...b....WEYE.",
		"bBSSSSSSSSYYE",
		"...b....WEYE.",
		"...b....W.E..",
		"...b...WW....",
		"...b..WW.....",
		"...bWWW......",
		"...WW........",
	],
	"bombard": [
		".............",
		"...........S.",
		".........Sso.",
		".......SSSso.",
		".E...SSSSsks.",
		".e.SSSSsssk..",
		".SSSSssss....",
		"sSSssssww....",
		"sssssooowww..",
		".sswoWWWowww.",
		"...woWSWowww.",
		"....oWWWo....",
		".....ooo.....",
	],
	"spire": [
		".....C.......",
		"....CCc......",
		"....CCc....C.",
		".....c....CC.",
		".........CC..",
		"....sSk.CCCC.",
		"....sSk...Cc.",
		"....sCk..Cc..",
		"....sSk..c...",
		"...ssSkk.....",
		"...sSSSk.....",
		"..ssSSSkk....",
		"..sssskkk....",
	],
	"guard": [
		"..........oB.",
		".sssssss.oBBo",
		".sCCCCCCoBBo.",
		".sCCCCCoBBo..",
		".sCCccoBBo.s.",
		".sCCcoBBocCs.",
		".sCo.BBocCCs.",
		".sGGoBocCCCs.",
		"..GGGocCCCs..",
		".oGoGGoCCCs..",
		"oGo.sGocCs...",
		".o...sscs....",
		"......ss.....",
	],
	"star": [
		"..Y..",
		"YGGGG",
		".GGG.",
		"GG.Gg",
		"G...g",
	],
	"upgrade": [
		"....Y....",
		"...YGG...",
		"..YG.GG..",
		".YG...GG.",
		"....G....",
		"...GGg...",
		"..GG.gg..",
		".GG...gg.",
		".........",
	],
	"sell": [
		"..ooooo..",
		".oYYGGGo.",
		".oYGgGGo.",
		".oGGgGgo.",
		".oGGGggo.",
		"..ooooo..",
		"..EEEEE..",
		"...EeE...",
		"....e....",
	],
}

static func rows(name: String) -> PackedStringArray:
	if not ICONS.has(name):
		return PackedStringArray()
	return PackedStringArray(ICONS[name])


static func make_texture(name: String) -> ImageTexture:
	var rs := rows(name)
	if rs.is_empty():
		return null
	var h := rs.size()
	var w := 0
	for r in rs:
		w = maxi(w, r.length())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var line: String = rs[y]
		for x in line.length():
			var ch := line[x]
			if ch == "." or ch == " ":
				continue
			var hex: String = PAL.get(ch, "")
			if hex == "":
				continue
			img.set_pixel(x, y, Color.html(hex))
	return ImageTexture.create_from_image(img)


static func icon_size(name: String) -> Vector2i:
	var rs := rows(name)
	var h := rs.size()
	var w := 0
	for r in rs:
		w = maxi(w, r.length())
	return Vector2i(w, h)

