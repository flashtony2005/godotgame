extends RefCounted

## 原版 Cinderwatch 的数据表（数值与 github.com/kevintngo/cinderwatch 保持一致）
## 这里只做 Godot 侧的重排：塔、怪物、生物群系、刷怪权重。

const TOWER_KINDS := ["archer", "bombard", "spire", "guard"]

const TOWER := {
	"archer": {
		"name": "弓手塔", "cost": [70, 90, 140],
		"range": [6.2, 6.8, 7.4], "dmg": [9.0, 11.0, 14.0],
		"rate": [0.85, 0.78, 0.70], "count": [1, 2, 3],
		"air": true, "ground": true,
		"tip": "快速火箭，能打空中。",
	},
	"bombard": {
		"name": "臼炮", "cost": [120, 130, 190],
		"range": [7.4, 8.0, 8.6], "min_range": 2.3,
		"dmg": [36.0, 60.0, 98.0], "splash": [1.55, 1.80, 2.10],
		"rate": [2.9, 2.7, 2.5],
		"air": false, "ground": true,
		"tip": "慢速炮弹，落点溅射。只打地面。",
	},
	"spire": {
		"name": "雷塔", "cost": [110, 120, 180],
		"range": [5.5, 6.0, 6.5], "dmg": [17.0, 25.0, 35.0],
		"jumps": [3, 4, 6], "rate": [2.3, 2.1, 1.9],
		"slow": [0.36, 0.42, 0.48], "slow_t": [1.3, 1.5, 1.7],
		"air": true, "ground": true,
		"tip": "链电，附带减速。能打空中。",
	},
	"guard": {
		"name": "哨所", "cost": [80, 90, 150],
		"range": [3.4, 3.7, 4.0], "count": [2, 3, 3],
		"hp": [62.0, 90.0, 135.0], "dmg": [7.0, 10.0, 15.0],
		"rate": [7.0, 6.0, 5.0],
		"air": false, "ground": true,
		"tip": "步兵下场挡路，近身缠斗。",
	},
}

## 怪物：hp / spd / rad / bounty / lives / dmg / atk_t 与原版一致
const MON := {
	"skel": {"name": "骷髅", "hp": 34.0, "spd": 1.35, "rad": 0.27, "bounty": 6, "lives": 1, "dmg": 6.0, "atk_t": 0.95, "body": "humanoid", "top": 1.45, "scale": 1.0, "tip": "最普通的骨头兵。"},
	"rat": {"name": "巨鼠", "hp": 13.0, "spd": 2.65, "rad": 0.20, "bounty": 3, "lives": 1, "dmg": 3.0, "atk_t": 0.6, "body": "quad", "top": 0.5, "scale": 1.0, "cat": "swarm", "tip": "又快又脆，成群出现。"},
	"slime": {"name": "史莱姆", "hp": 95.0, "spd": 0.82, "rad": 0.42, "bounty": 9, "lives": 1, "dmg": 8.0, "atk_t": 1.2, "body": "blob", "top": 0.75, "scale": 1.0, "split": ["slimelet", 2], "tip": "死亡时分裂成两只。"},
	"slimelet": {"name": "小史莱姆", "hp": 30.0, "spd": 1.2, "rad": 0.26, "bounty": 3, "lives": 1, "dmg": 4.0, "atk_t": 1.0, "body": "blob", "top": 0.48, "scale": 0.58, "cat": "swarm"},
	"knight": {"name": "骷髅骑士", "hp": 118.0, "spd": 1.0, "rad": 0.30, "bounty": 15, "lives": 1, "dmg": 11.0, "atk_t": 1.05, "body": "humanoid", "top": 1.6, "scale": 1.08, "armor": 0.35, "cat": "armor", "tip": "护甲挡掉大部分箭矢。"},
	"bat": {"name": "蝙蝠", "hp": 20.0, "spd": 2.3, "rad": 0.22, "bounty": 6, "lives": 1, "dmg": 0.0, "atk_t": 1.0, "body": "bat", "top": 0.35, "scale": 1.25, "fly": true, "cat": "air", "alt": [2.9, 3.8], "tip": "飞越道路，只有弓手和雷塔够得着。"},
	"ghoul": {"name": "食尸鬼", "hp": 40.0, "spd": 1.85, "rad": 0.27, "bounty": 7, "lives": 1, "dmg": 9.0, "atk_t": 0.7, "body": "humanoid", "top": 0.95, "scale": 0.92, "frenzy": 0.55, "tip": "越伤跑得越快。"},
	"spider": {"name": "洞穴蛛", "hp": 20.0, "spd": 2.25, "rad": 0.24, "bounty": 3, "lives": 1, "dmg": 4.0, "atk_t": 0.6, "body": "bug", "top": 0.45, "scale": 1.0, "slip": true, "cat": "swarm", "tip": "能从步兵身边溜过去。"},
	"scarab": {"name": "圣甲虫", "hp": 9.0, "spd": 2.5, "rad": 0.15, "bounty": 1, "lives": 1, "dmg": 2.0, "atk_t": 0.6, "body": "bug", "top": 0.28, "scale": 0.5, "slip": true, "cat": "swarm"},
	"wolf": {"name": "恐狼", "hp": 38.0, "spd": 2.7, "rad": 0.30, "bounty": 7, "lives": 1, "dmg": 12.0, "atk_t": 0.7, "body": "quad", "top": 0.85, "scale": 1.0, "cat": "swarm", "tip": "快，而且咬得狠。"},
	"bomber": {"name": "爆破兵", "hp": 38.0, "spd": 1.55, "rad": 0.27, "bounty": 8, "lives": 2, "dmg": 0.0, "atk_t": 1.0, "body": "humanoid", "top": 1.55, "scale": 1.0, "explode": {"r": 1.7, "dmg": 46.0, "men": 30.0}, "tip": "背的药桶会炸伤敌我。"},
	"wraith": {"name": "怨灵", "hp": 58.0, "spd": 1.3, "rad": 0.28, "bounty": 11, "lives": 1, "dmg": 0.0, "atk_t": 1.0, "body": "ghost", "top": 1.5, "scale": 1.0, "ghost": [1.7, 3.0], "tip": "虚化时箭和刀都打空。"},
	"toad": {"name": "沼泽蟾", "hp": 78.0, "spd": 1.0, "rad": 0.38, "bounty": 9, "lives": 1, "dmg": 9.0, "atk_t": 1.0, "body": "toad", "top": 0.75, "scale": 1.0, "hop": [1.2, 2.5], "tip": "大跳前进，一跳一段路。"},
	"wisp": {"name": "鬼火", "hp": 10.0, "spd": 3.0, "rad": 0.14, "bounty": 2, "lives": 1, "dmg": 0.0, "atk_t": 1.0, "body": "wisp", "top": 0.3, "scale": 1.0, "fly": true, "cat": "air", "alt": [1.3, 2.3], "glow": 8.0, "tip": "很快的飞行体，难抓。"},
	"drummer": {"name": "战鼓手", "hp": 92.0, "spd": 1.15, "rad": 0.30, "bounty": 14, "lives": 1, "dmg": 6.0, "atk_t": 1.0, "body": "humanoid", "top": 2.35, "scale": 1.05, "aura": [3.4, 0.3], "tip": "让附近所有怪物加速。"},
	"gargoyle": {"name": "石像鬼", "hp": 90.0, "spd": 1.6, "rad": 0.32, "bounty": 13, "lives": 1, "dmg": 0.0, "atk_t": 1.0, "body": "bat", "top": 0.6, "scale": 1.35, "fly": true, "armor": 0.5, "cat": "air", "alt": [2.4, 3.1], "tip": "会飞，而且箭矢打不疼它。"},
	"necro": {"name": "死灵法师", "hp": 105.0, "spd": 0.85, "rad": 0.30, "bounty": 18, "lives": 1, "dmg": 5.0, "atk_t": 1.2, "body": "humanoid", "top": 1.8, "scale": 1.08, "summon": {"type": "skel", "n": 2, "every": 7.5, "max": 3, "hp": 0.6}, "tip": "边走边召骷髅。"},
	"mummy": {"name": "木乃伊", "hp": 135.0, "spd": 0.9, "rad": 0.30, "bounty": 14, "lives": 1, "dmg": 12.0, "atk_t": 1.1, "body": "humanoid", "top": 1.55, "scale": 1.1, "split": ["scarab", 3], "tip": "倒下时炸出一群圣甲虫。"},
	"brute": {"name": "巨魔", "hp": 360.0, "spd": 0.82, "rad": 0.50, "bounty": 30, "lives": 2, "dmg": 24.0, "atk_t": 1.4, "body": "humanoid", "top": 1.95, "scale": 1.5, "regen": 0.035, "cat": "armor", "tip": "没人一直打它就回血。"},
	"golem": {"name": "石魔", "hp": 470.0, "spd": 0.62, "rad": 0.50, "bounty": 34, "lives": 2, "dmg": 26.0, "atk_t": 1.5, "body": "golem", "top": 2.1, "scale": 1.5, "armor": 0.35, "slow_res": 0.5, "cat": "armor", "tip": "箭矢打不动，也很难减速。"},
	"brood": {"name": "巢母", "hp": 230.0, "spd": 0.92, "rad": 0.55, "bounty": 24, "lives": 2, "dmg": 14.0, "atk_t": 1.0, "body": "bug", "top": 1.05, "scale": 2.3, "split": ["spider", 5], "cat": "armor", "tip": "死亡时炸出一群蜘蛛。"},
	"giant": {"name": "白骨巨人", "hp": 1250.0, "spd": 0.88, "rad": 0.92, "bounty": 200, "lives": 5, "dmg": 46.0, "atk_t": 1.7, "body": "humanoid", "top": 4.0, "scale": 2.7, "boss": true, "cat": "armor", "tip": "又慢又大，把火力都砸上去。"},
	"ogre": {"name": "食人魔", "hp": 1400.0, "spd": 0.8, "rad": 1.0, "bounty": 200, "lives": 5, "dmg": 52.0, "atk_t": 1.8, "body": "humanoid", "top": 3.4, "scale": 2.6, "boss": true, "cat": "armor", "tip": "一掌拍飞步兵。"},
	"jotun": {"name": "霜巨人", "hp": 1150.0, "spd": 0.8, "rad": 1.0, "bounty": 200, "lives": 5, "dmg": 52.0, "atk_t": 1.8, "body": "humanoid", "top": 3.6, "scale": 2.75, "boss": true, "stomp": {"every": 10.0, "r": 5.2, "stun": 1.8}, "cat": "armor", "tip": "踏地冻结附近塔。"},
	"queen": {"name": "巢后", "hp": 1150.0, "spd": 0.85, "rad": 1.1, "bounty": 200, "lives": 5, "dmg": 40.0, "atk_t": 1.5, "body": "bug", "top": 2.0, "scale": 2.2, "boss": true, "summon": {"type": "spider", "n": 2, "every": 8.0, "max": 99, "hp": 1.0}, "cat": "armor", "tip": "不停孵蜘蛛。"},
	"colossus": {"name": "熔岩巨像", "hp": 1250.0, "spd": 0.7, "rad": 1.05, "bounty": 200, "lives": 5, "dmg": 60.0, "atk_t": 2.0, "body": "golem", "top": 4.3, "scale": 3.0, "boss": true, "armor": 0.85, "slow_res": 0.3, "enrage": [0.3, 1.25], "cat": "armor", "tip": "快死时暴走加速。"},
	"king": {"name": "葬王", "hp": 1250.0, "spd": 0.86, "rad": 0.92, "bounty": 200, "lives": 5, "dmg": 46.0, "atk_t": 1.7, "body": "humanoid", "top": 4.2, "scale": 2.7, "boss": true, "summon": {"type": "mummy", "n": 1, "every": 9.0, "max": 99, "hp": 0.7}, "cat": "armor", "tip": "带着木乃伊一起走。"},
}

## 刷怪权重表：[造价, 最少, 最多, 间隔, 解锁波次, 权重]
const ROSTER := {
	"skel": [4.0, 3, 6, 0.5, 1, 5.0],
	"rat": [1.7, 5, 9, 0.2, 2, 3.0],
	"bat": [4.2, 3, 5, 0.35, 2, 1.3],
	"ghoul": [5.5, 2, 4, 0.4, 2, 2.0],
	"slime": [9.5, 1, 3, 0.9, 3, 2.0],
	"spider": [3.0, 3, 6, 0.25, 3, 2.0],
	"scarab": [1.9, 5, 8, 0.18, 2, 0.0],
	"knight": [12.5, 1, 3, 0.5, 4, 2.0],
	"wolf": [5.5, 2, 4, 0.35, 4, 1.6],
	"bomber": [6.0, 1, 2, 0.8, 4, 1.2],
	"wraith": [9.0, 1, 3, 0.7, 5, 1.4],
	"toad": [8.0, 1, 3, 0.7, 5, 0.7],
	"wisp": [2.6, 4, 7, 0.22, 5, 0.8],
	"drummer": [13.0, 1, 1, 1.0, 6, 0.9],
	"gargoyle": [11.0, 1, 3, 0.6, 6, 0.9],
	"necro": [18.0, 1, 1, 1.2, 7, 0.9],
	"mummy": [15.0, 1, 2, 0.9, 7, 0.9],
	"brute": [32.0, 1, 1, 2.0, 8, 0.7],
	"golem": [40.0, 1, 1, 2.0, 8, 0.7],
	"brood": [30.0, 1, 1, 2.0, 9, 0.6],
}

## 五张地图：配色 / 光照 / 天气 / 本地怪偏好
const BIOMES := [
	{
		"key": "ashen", "name": "灰烬隘口",
		"earth": Color("3c3f4c"), "earth_d": Color("24272f"), "road": Color("70503f"), "road_d": Color("4c3529"),
		"rock": Color("767a86"), "rock_l": Color("9a8e7c"), "flora": Color("55483e"), "flora_l": Color("6d5c48"),
		"sky": Color("0a0f18"), "fog": Color("141c2a"), "fog_density": 0.012,
		"light": Color("a9c0f6"), "light_e": 1.35, "amb": Color("3a4a70"), "amb_e": 1.0,
		"mobs": {"ghoul": 1.6, "wraith": 1.6, "necro": 1.5}, "early": {"wraith": 3, "necro": 5},
		"boss": ["giant", "ogre"], "decor": ["rock", "tree"],
		"wisp_hex": Color("b090ff"),
	},
	{
		"key": "frost", "name": "霜落原",
		"earth": Color("4b4a50"), "earth_d": Color("2f3038"), "road": Color("7a808c"), "road_d": Color("555a66"),
		"rock": Color("6f7b90"), "rock_l": Color("9aa7b8"), "flora": Color("1d382f"), "flora_l": Color("2c4f42"),
		"sky": Color("0d1620"), "fog": Color("1d2a38"), "fog_density": 0.018,
		"light": Color("c6dcff"), "light_e": 1.25, "amb": Color("4a5f80"), "amb_e": 1.0,
		"mobs": {"wolf": 2.4, "golem": 1.8, "wraith": 1.3, "toad": 0.0, "wisp": 0.5, "slime": 0.6},
		"early": {"wolf": 2, "golem": 6},
		"boss": ["jotun"], "decor": ["pine", "rock"], "weather": "snow",
		"wisp_hex": Color("80c0ff"),
	},
	{
		"key": "fen", "name": "泥沼泽",
		"earth": Color("3b3a28"), "earth_d": Color("24261a"), "road": Color("6c6a56"), "road_d": Color("48483a"),
		"rock": Color("5c6858"), "rock_l": Color("84907a"), "flora": Color("2a4626"), "flora_l": Color("4c6c34"),
		"sky": Color("0a1410"), "fog": Color("16241a"), "fog_density": 0.022,
		"light": Color("a6e6c4"), "light_e": 1.1, "amb": Color("2f6f5a"), "amb_e": 0.95,
		"mobs": {"toad": 3.5, "wisp": 2.4, "spider": 2.0, "brood": 2.0, "slime": 1.6, "mummy": 0.0, "bomber": 0.5},
		"early": {"toad": 2, "wisp": 3, "brood": 6},
		"boss": ["queen"], "decor": ["willow", "rock", "rock"], "water": true,
		"wisp_hex": Color("70ffa0"),
	},
	{
		"key": "ember", "name": "焰痕荒原",
		"earth": Color("2e2728"), "earth_d": Color("1c1819"), "road": Color("5e5652"), "road_d": Color("3c3634"),
		"rock": Color("403c42"), "rock_l": Color("5e5a62"), "flora": Color("15110f"), "flora_l": Color("3a2c24"),
		"sky": Color("12060a"), "fog": Color("2a1212"), "fog_density": 0.016,
		"light": Color("c0b0d0"), "light_e": 1.2, "amb": Color("6a2a18"), "amb_e": 1.0,
		"mobs": {"bomber": 2.4, "gargoyle": 2.0, "golem": 1.8, "toad": 0.0, "slime": 0.5, "wisp": 1.4},
		"early": {"bomber": 2, "gargoyle": 4, "golem": 6},
		"boss": ["colossus"], "decor": ["charred", "rock"], "lava": true,
		"wisp_hex": Color("ff8030"),
	},
	{
		"key": "dunes", "name": "暮台沙海",
		"earth": Color("a88c66"), "earth_d": Color("7c6448"), "road": Color("a89478"), "road_d": Color("786652"),
		"rock": Color("b08e6c"), "rock_l": Color("d4b48c"), "flora": Color("38582e"), "flora_l": Color("66863e"),
		"sky": Color("141426"), "fog": Color("2a2438"), "fog_density": 0.014,
		"light": Color("d6c8ff"), "light_e": 1.3, "amb": Color("6a6fc0"), "amb_e": 1.0,
		"mobs": {"mummy": 3.0, "scarab": 2.4, "spider": 0.6, "bomber": 1.3, "ghoul": 1.3, "toad": 0.0, "slime": 0.4},
		"early": {"mummy": 4, "scarab": 2},
		"boss": ["king"], "decor": ["palm", "rock"], "water": true,
		"wisp_hex": Color("ffc060"),
	},
]

## 每张地图里怪物的额外染色（对应原版 tints），未列出的按原色
const TINTS := {
	"ashen": {"wisp": Color("bf9aff")},
	"frost": {"wolf": Color("d8e4ff"), "golem": Color("9fc0e0"), "wisp": Color("90c8ff"), "gargoyle": Color("b4cce0"), "toad": Color("b0c8e0"), "brute": Color("c8d8ff")},
	"fen": {"golem": Color("9ec080"), "wisp": Color("90ffb0"), "wolf": Color("a8b090"), "gargoyle": Color("a8c8a8")},
	"ember": {"golem": Color("ff8a4a"), "wolf": Color("c08070"), "wisp": Color("ffa040"), "gargoyle": Color("d09070"), "toad": Color("d09070")},
	"dunes": {"golem": Color("f0c890"), "wolf": Color("e0c890"), "wisp": Color("ffd080"), "gargoyle": Color("e8d0a0"), "toad": Color("e0d0a0")},
}

## 基础材质颜色（怪物）
const MON_COL := {
	"bone": Color("d8d2c0"), "bone_d": Color("9a9484"),
	"flesh": Color("8a6a58"), "fur": Color("6a5a4a"), "fur_d": Color("4a3c30"),
	"metal": Color("8a92a0"), "dark": Color("2a2620"), "cloth": Color("6a3a34"),
	"goo": Color("6ac07a"), "bug": Color("4a3a3c"), "rock": Color("7a7a72"),
	"ghost": Color("a8d8d0"), "fire": Color("ff8a3c"), "eye": Color("ff3a20"),
	"sand": Color("d8c090"), "ice": Color("a8d8ff"), "magma": Color("ff5a20"),
}
