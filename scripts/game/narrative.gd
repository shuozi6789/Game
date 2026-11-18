class_name Narrative
## All Chinese text of the walk. Edit freely — the game reads only these tables.
##
## Beat formats (arrays of dictionaries):
##   line   {"t":"line", "who":"npc"|"me", "text":"..."}
##   choice {"t":"choice", "prompt":"...", "options":[{"text":"...", "weight":1|-1, "reply":[line...]}, ...]}
##          A mid-conversation choice. The hidden weight feeds the silent
##          judgement at the end of the conversation (see result_lines()).
##          There is deliberately NO final 「are you this kind of person?」
##          question: the game infers the answer from the three choices.

const COLORS := {
	"red": {"name": "红", "trait": "热情直率", "color": Color(0.86, 0.30, 0.26, 1.0), "axis": "outward", "pole": "a"},
	"blue": {"name": "蓝", "trait": "冷静责任", "color": Color(0.30, 0.52, 0.85, 1.0), "axis": "outward", "pole": "b"},
	"yellow": {"name": "黄", "trait": "理性求知", "color": Color(0.93, 0.76, 0.28, 1.0), "axis": "logic", "pole": "a"},
	"green": {"name": "绿", "trait": "温和共情", "color": Color(0.45, 0.70, 0.38, 1.0), "axis": "logic", "pole": "b"},
	"purple": {"name": "紫", "trait": "浪漫理想", "color": Color(0.62, 0.45, 0.85, 1.0), "axis": "vision", "pole": "a"},
	"orange": {"name": "橙", "trait": "务实当下", "color": Color(0.85, 0.55, 0.28, 1.0), "axis": "vision", "pole": "b"},
	"teal": {"name": "青", "trait": "秩序计划", "color": Color(0.28, 0.62, 0.58, 1.0), "axis": "order", "pole": "a"},
	"pink": {"name": "粉", "trait": "随性自由", "color": Color(0.88, 0.55, 0.68, 1.0), "axis": "order", "pole": "b"},
}

## Four paired personality axes (our own neutral wording, MBTI-like structure).
const AXES := [
	{"id": "outward", "label": "能量", "a": "red", "b": "blue", "a_label": "向外", "b_label": "向内"},
	{"id": "logic", "label": "判断", "a": "yellow", "b": "green", "a_label": "讲理", "b_label": "讲情"},
	{"id": "vision", "label": "目光", "a": "purple", "b": "orange", "a_label": "看向远方", "b_label": "看重脚下"},
	{"id": "order", "label": "步调", "a": "teal", "b": "pink", "a_label": "守序", "b_label": "随性"},
]

## Short essence per colour, used to compose pair / multi-colour endings.
const ITEMS := {
	"red": {"name": "没寄出的信", "desc": "信封边角磨旧了，收信人一栏空着。", "color": "red"},
	"yellow": {"name": "停摆的怀表", "desc": "指针停在某个下午，表盖内侧刻着一行小字。", "color": "yellow"},
	"green": {"name": "花种纸包", "desc": "写着「春天再打开」的种子包，纸袋上有泥土味。", "color": "green"},
	"blue": {"name": "旧提灯", "desc": "灯罩擦得很亮，灯芯只剩很短一截。", "color": "blue"},
	"purple": {"name": "晚霞画片", "desc": "一张没画完的晚霞，边缘留着铅笔线。", "color": "purple"},
	"orange": {"name": "木雕小马", "desc": "边角磨圆的木头小马，鬃毛刻得很细。", "color": "orange"},
	"pink": {"name": "风筝线轴", "desc": "缠着一段旧线，线头系着一小片风筝纸。", "color": "pink"},
	"teal": {"name": "手抄书签", "desc": "一片窄窄的书签，背面抄着一行旧诗。", "color": "teal"},
	"creek_chime": {"name": "溪畔风铃", "desc": "三块石头依次亮起后，从石阵中央取下的旧风铃；铃声很轻。", "color": "teal"},
}

static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

const COLOR_LINES := {
	"red": "红：想到就出发的急。",
	"yellow": "黄：非弄明白不可的执。",
	"green": "绿：先看见别人的软。",
	"blue": "蓝：把该守的守住的稳。",
	"purple": "紫：相信远处有东西的梦。",
	"orange": "橙：先把眼前做好的实。",
	"teal": "青：让日子有始有终的序。",
	"pink": "粉：跟着风走的自由。",
}

const COLOR_ORDER := ["red", "yellow", "green", "blue", "purple", "orange", "teal", "pink"]

const NPCS := {
	"red": {
		"name": "阿燃",
		"sprite": "res://assets/generated/npc_red.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "喂——你走路的样子，不像在赶路。"},
			{"t": "line", "who": "npc", "text": "我在这儿坐了半个钟头，就为了等一个不知道会不会来的人。"},
			{"t": "line", "who": "me", "text": "他拍了拍身边的石头，像是给我留了位置。"},
			{"t": "choice", "prompt": "他忽然凑近了一点：「你往哪儿走？」", "options": [
				{"text": "不知道，往前走就是了。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "对！不知道才要走啊。"},
					{"t": "line", "who": "npc", "text": "知道去哪儿的人，走起来没这么好看。"},
				]},
				{"text": "得先想清楚去哪儿。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "那你想吧。"},
					{"t": "line", "who": "npc", "text": "我在旁边等——我这种人等不了太久。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他从邮包里摸出一封皱巴巴的信，翻过来又翻过去。"},
			{"t": "choice", "prompt": "「你说，写不下的那部分，怎么办？」", "options": [
				{"text": "照写。空白也是内容。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "……你这人有点意思。"},
					{"t": "line", "who": "npc", "text": "我送信从来不拆，可我今天想拆一封看看。"},
				]},
				{"text": "空着就空着，不用非写满。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也行。"},
					{"t": "line", "who": "npc", "text": "有些话没写，收信的人反而懂。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把信塞回包里，站起来活动了一下肩膀。"},
			{"t": "choice", "prompt": "「你要是到了，替我看看那家门牌还在不在？」", "options": [
				{"text": "好，我记着。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那就算你答应了。"},
					{"t": "line", "who": "npc", "text": "我这种人不爱听保证，但我信你这一句。"},
				]},
				{"text": "我不一定走得到那么远。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "哈，老实。"},
					{"t": "line", "who": "npc", "text": "老实人走得慢，但不会走丢。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他没再说什么，只是把包带往肩上一甩。"},
			{"t": "line", "who": "npc", "text": "风把他袖口的颜色吹得晃了一下。"},
		],
	},
	"yellow": {
		"name": "阿衡",
		"sprite": "res://assets/generated/npc_yellow.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "别踩那丛草——我在数它开了几朵花。"},
			{"t": "line", "who": "npc", "text": "……十七朵。昨天是十五。"},
			{"t": "line", "who": "me", "text": "他怀里有一只旧怀表，秒针停在同一个位置。"},
			{"t": "choice", "prompt": "「你走路，是为了到什么地方，还是为了离开什么地方？」", "options": [
				{"text": "因为路在那里。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "嗯。这个理由很干净。"},
					{"t": "line", "who": "npc", "text": "我喜欢干净的理由。"},
				]},
				{"text": "为了离开。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "离开也是一种方向。"},
					{"t": "line", "who": "npc", "text": "只是走久了会发现，带走的和留下的差不多多。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把表翻过来，指腹在表盖上磨了磨。"},
			{"t": "choice", "prompt": "「你有没有想过，有些问题问太久，会把问的人困住？」", "options": [
				{"text": "想过。但还是想弄明白。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那我们是同一种毛病。"},
					{"t": "line", "who": "npc", "text": "我修了七年，也没舍得把它调准。"},
				]},
				{"text": "那就先不问了，走过去再说。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "说得轻巧。"},
					{"t": "line", "who": "npc", "text": "不过……有时候确实该先把表合上。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他抬头看了看天色，又低头看表，像是两个时间对不上。"},
			{"t": "choice", "prompt": "「你身上有带纸笔吗？我想记一句话。」", "options": [
				{"text": "有。你说。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "「慢四分钟的表也是准的，只是准在另一个时间。」"},
					{"t": "line", "who": "npc", "text": "记下来。别弄丢。"},
				]},
				{"text": "没有。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "没关系。"},
					{"t": "line", "who": "npc", "text": "那就麻烦你记在脑子里，虽然脑子也慢四分钟。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把表收回内袋，扣好。"},
			{"t": "line", "who": "npc", "text": "秒针还在原来的位置，谁也没去调它。"},
		],
	},
	"green": {
		"name": "阿禾",
		"sprite": "res://assets/generated/npc_green.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "小心脚下，那些是刚长出来的。"},
			{"t": "line", "who": "npc", "text": "你走了很远吧？嘴唇都干了。"},
			{"t": "line", "who": "me", "text": "她把水壶递过来，没有先问我是谁。"},
			{"t": "choice", "prompt": "「坐下歇会儿吗？这地方，很少有人来。」", "options": [
				{"text": "好，我坐一会儿。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "嗯。"},
					{"t": "line", "who": "npc", "text": "这片花是我种的，种了三年。"},
				]},
				{"text": "不了，我还要赶路。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "那我给你装点水。"},
					{"t": "line", "who": "npc", "text": "路上渴了，别硬撑。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "她蹲下去，把一朵被风吹歪的花扶正。"},
			{"t": "choice", "prompt": "「你路上有没有遇见，需要你停下来的人？」", "options": [
				{"text": "有。我停过。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那就好。"},
					{"t": "line", "who": "npc", "text": "停下来不丢人，丢人的是假装没看见。"},
				]},
				{"text": "还没有。我一直在走。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "一直走也会累的。"},
					{"t": "line", "who": "npc", "text": "累了就找个地方坐坐，花不会跑。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "她把水壶盖拧紧，手指上沾着一点泥。"},
			{"t": "choice", "prompt": "「花要开了。你要不要带一朵走？」", "options": [
				{"text": "带一朵吧。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "挑这朵，今天刚开。"},
					{"t": "line", "who": "npc", "text": "别插太紧，它会疼。"},
				]},
				{"text": "留在这儿更好。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也对。"},
					{"t": "line", "who": "npc", "text": "花在开的地方最好看。你记得回来看。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "她没有问我要去哪儿，只是把围裙上的土拍了拍。"},
			{"t": "line", "who": "npc", "text": "那朵花在风里，轻轻地点了一下头。"},
		],
	},
	"blue": {
		"name": "阿砚",
		"sprite": "res://assets/generated/npc_blue.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "这段路我修了三天。石头是新的，别踩塌了。"},
			{"t": "line", "who": "npc", "text": "山里的路，坏得比人想得快。"},
			{"t": "line", "who": "me", "text": "他把撬棍靠在石头上，指节上全是旧伤痕。"},
			{"t": "choice", "prompt": "他直起腰：「你赶路，会先顾着路，还是先顾着自己要去哪？」", "options": [
				{"text": "先顾路。路不通，谁也走不了。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "嗯。"},
					{"t": "line", "who": "npc", "text": "我这辈子都在修别人要走的路。"},
				]},
				{"text": "先顾自己。自己的路还没走完。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也对。"},
					{"t": "line", "who": "npc", "text": "路是给走的人修的，不是给修的人修的。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把一块歪掉的石头重新垫平，用靴底踩了踩。"},
			{"t": "choice", "prompt": "「前面那段路我修了三天。你觉得，值得吗？」", "options": [
				{"text": "值得。总得有人修。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "听见这话，我这三天就不算白干。"},
					{"t": "line", "who": "npc", "text": "灯我留着，你走的时候带上。"},
				]},
				{"text": "说不好。走的人未必记得。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "是。"},
					{"t": "line", "who": "npc", "text": "可我记得。记得就够了。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "天光又暗了一层，他划了根火柴，把灯芯挑亮。"},
			{"t": "choice", "prompt": "「天黑之前，你会走到哪儿？」", "options": [
				{"text": "尽量往前。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "好。"},
					{"t": "line", "who": "npc", "text": "夜路我熟，别怕。"},
				]},
				{"text": "走到走不动为止。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "那也行。"},
					{"t": "line", "who": "npc", "text": "走不动了就找块平石头坐，别坐在边坡上。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把撬棍收起来，让开了路。"},
			{"t": "line", "who": "npc", "text": "提灯的光落在你脚边，一直照到石阶尽头。"},
		],
	},
	"purple": {
		"name": "阿遥",
		"sprite": "res://assets/generated/npc_purple.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "别动。你站在光里，这个颜色很好。"},
			{"t": "line", "who": "npc", "text": "我在画这条路。画了三天，画不出尽头。"},
			{"t": "line", "who": "me", "text": "他的画布上有一条路，路的尽头是一团没干的紫色。"},
			{"t": "choice", "prompt": "「你信吗？信远处有什么。」", "options": [
				{"text": "信。没见过才值得信。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "哈，你比我还像画画的。"},
					{"t": "line", "who": "npc", "text": "那我把远处画给你看。"},
				]},
				{"text": "我更信看得见摸得着的。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也对。"},
					{"t": "line", "who": "npc", "text": "画布上的东西，摸一摸都是干的。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他退后两步，歪着头看自己的画，笔尖在指间转了一圈。"},
			{"t": "choice", "prompt": "「要是我画的地方根本不存在呢？」", "options": [
				{"text": "不存在也想去看。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "……你这人。"},
					{"t": "line", "who": "npc", "text": "我画了一辈子，第一次有人这么说。"},
				]},
				{"text": "那我就不去了。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "没关系。"},
					{"t": "line", "who": "npc", "text": "画存在过，就够了。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他蘸了一点紫，在画的角落添了一笔，像一扇很小的门。"},
			{"t": "choice", "prompt": "「你胸口的心形凹槽里，有没有一种颜色，是你自己想留下的？」", "options": [
				{"text": "有。只是还不知道叫什么。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那就先别起名字。"},
					{"t": "line", "who": "npc", "text": "名字起早了，颜色就死了。"},
				]},
				{"text": "没有。我还没想清楚。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "没想清楚就继续走。"},
					{"t": "line", "who": "npc", "text": "路会把颜色磨出来的。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他笑了一下，把那幅画转过来给我看。"},
			{"t": "line", "who": "npc", "text": "画上是一条路，路的尽头没有门，只有很淡的一点紫。"},
		],
	},
	"orange": {
		"name": "阿作",
		"sprite": "res://assets/generated/npc_orange.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "别碰那张桌子——腿还没装好。"},
			{"t": "line", "who": "npc", "text": "你从山道那边来的？那边的木头总是受潮。"},
			{"t": "line", "who": "me", "text": "他蹲下来，用拇指抹掉一块木板上的毛刺。"},
			{"t": "choice", "prompt": "「你觉得，东西是修出来的，还是想出来的？」", "options": [
				{"text": "修出来的。想再多，不如先动手。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "对。"},
					{"t": "line", "who": "npc", "text": "我这人不太会想。想多了，木头就凉了。"},
				]},
				{"text": "想清楚了再动手。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也对。"},
					{"t": "line", "who": "npc", "text": "我师父说过，纹路要先看。看太久，手会忘。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他换了把刨子，刨花卷起来，落了一地。"},
			{"t": "choice", "prompt": "「木头有纹路。顺着省力，逆着费劲。你说人有没有纹路？」", "options": [
				{"text": "有。顺着自己的来。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那就别跟自己的手较劲。"},
					{"t": "line", "who": "npc", "text": "做东西和走路一个道理。"},
				]},
				{"text": "人可以改自己的纹路。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "能改。"},
					{"t": "line", "who": "npc", "text": "就是改完会留疤，补起来不好看。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把一块新木板翻了个面，又翻回去。"},
			{"t": "choice", "prompt": "「这块给你。你想拿它做什么？」", "options": [
				{"text": "先做眼前能用的东西。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "稳当。"},
					{"t": "line", "who": "npc", "text": "给你当凳子，还是当垫板？"},
				]},
				{"text": "收着，以后再说。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也行。"},
					{"t": "line", "who": "npc", "text": "木头放久会干，人的念头放久会凉。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他把刨花从围裙上拍掉，没再说什么。"},
			{"t": "line", "who": "npc", "text": "木头和松脂的味道，留在空气里。"},
		],
	},
	"teal": {
		"name": "阿序",
		"sprite": "res://assets/generated/npc_teal.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "别站在那条线上——那是我用来量日影的。"},
			{"t": "line", "who": "npc", "text": "我每天把路过的风、来的客人、走掉的影子都记下来。"},
			{"t": "line", "who": "me", "text": "他翻开册子，纸页边角都被翻得发亮。"},
			{"t": "choice", "prompt": "「你觉得，日子是该记下来，还是该过掉？」", "options": [
				{"text": "记下来。不然会忘。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "对。"},
					{"t": "line", "who": "npc", "text": "忘掉的东西不会自己回来。"},
				]},
				{"text": "过掉。记着太沉。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "也有道理。"},
					{"t": "line", "who": "npc", "text": "我父亲记了一辈子，最后连自己那页都没写。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他用铜尺压住纸页，一笔一笔描着今天日影的边。"},
			{"t": "choice", "prompt": "「如果有一天，你发现自己记错了，会改吗？」", "options": [
				{"text": "会。错了就改。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "好。"},
					{"t": "line", "who": "npc", "text": "纸可以划掉重写，人也可以。"},
				]},
				{"text": "将错就错吧，反正没人知道。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "……我记下了。"},
					{"t": "line", "who": "npc", "text": "这一句我不写进册子。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "他停下笔，抬头看了我一会儿，像是在确认什么。"},
			{"t": "choice", "prompt": "「你叫什么？我记一下。」", "options": [
				{"text": "告诉他名字。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "好。哪两个字？"},
					{"t": "line", "who": "npc", "text": "我写慢一点，免得写错。"},
				]},
				{"text": "不用记我。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "……行。"},
					{"t": "line", "who": "npc", "text": "那这一页，就空着。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "笔尖在纸上停了一瞬，然后继续往下写。"},
			{"t": "line", "who": "npc", "text": "那页纸很薄，透出背面的字。"},
		],
	},
	"pink": {
		"name": "阿游",
		"sprite": "res://assets/generated/npc_pink.png",
		"beats": [
			{"t": "line", "who": "npc", "text": "你抬头看——那只风筝，线在我手里，可它想往哪儿飞，我说了不算。"},
			{"t": "line", "who": "npc", "text": "我从上一个镇子走到这儿，本来只打算借住一晚。"},
			{"t": "line", "who": "me", "text": "她的行囊开着，里面没有地图。"},
			{"t": "choice", "prompt": "「你出门会先想好路线吗？」", "options": [
				{"text": "不会。走到哪儿算哪儿。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那我们可能会走散。"},
					{"t": "line", "who": "npc", "text": "走散了也没关系，风会把人吹到一块儿。"},
				]},
				{"text": "会。想好了才安心。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "哦——"},
					{"t": "line", "who": "npc", "text": "我以前也这样。后来发现，计划里没有风。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "她拽了拽线，风筝在半空打了个转。"},
			{"t": "choice", "prompt": "「你有没有过，走着走着，突然不想去原来的地方了？」", "options": [
				{"text": "有过。然后就改了方向。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "哈，那你得小心。"},
					{"t": "line", "who": "npc", "text": "改方向改多了，会忘记自己本来想去哪。"},
				]},
				{"text": "没有。定了就走到。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "那也挺好。"},
					{"t": "line", "who": "npc", "text": "我羡慕定得下来的人。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "风忽然大了一阵，她笑着眯起眼睛。"},
			{"t": "choice", "prompt": "「风筝要掉了，我得跑两步。你等我吗？」", "options": [
				{"text": "跑吧，我跟着。", "weight": 1, "reply": [
					{"t": "line", "who": "npc", "text": "那你可要跟紧。"},
					{"t": "line", "who": "npc", "text": "我跑起来不看路。"},
				]},
				{"text": "我在这儿等。", "weight": -1, "reply": [
					{"t": "line", "who": "npc", "text": "行。"},
					{"t": "line", "who": "npc", "text": "我跑一圈就回来，线还在你手里呢。"},
				]},
			]},
			{"t": "line", "who": "npc", "text": "她跑出去几步，又回头冲我挥了挥手。"},
			{"t": "line", "who": "npc", "text": "风筝线在风里亮了一下，像一道很细的粉。"},
		],
	},
}

const MONOLOGUES := {
	"s1_morning": [
		{"t": "line", "who": "me", "text": "我从木匠的屋子里出来的时候，草坡上还没有人。"},
		{"t": "line", "who": "me", "text": "胸口是一处心形的空洞，风从那里穿过去，发出很轻的空响。"},
		{"t": "line", "who": "me", "text": "我不知道自己是谁做的，也不知道该往哪里走。"},
		{"t": "line", "who": "me", "text": "但脚已经迈出去了。"},
	],
	"s4_creek": [
		{"t": "line", "who": "me", "text": "溪水很浅，能看见底。"},
		{"t": "line", "who": "me", "text": "水里也有一个人。他不说话，只是随着水走。"},
		{"t": "line", "who": "me", "text": "我蹲下来，他就蹲下来。"},
		{"t": "line", "who": "me", "text": "我站起来，继续走。他也走了。"},
	],
	"s9_woodmill": [
		{"t": "line", "who": "me", "text": "木场里全是新刨开的木头味。"},
		{"t": "line", "who": "me", "text": "这里的每样东西，都像是被人用手摸过、修过、又放下。"},
	],
	"s10_windhill": [
		{"t": "line", "who": "me", "text": "风坡上没有路，只有被风吹倒又站起来的一片草。"},
		{"t": "line", "who": "me", "text": "我忽然不太确定，是我在走，还是风在推我。"},
	],
	"s11_oldsteps": [
		{"t": "line", "who": "me", "text": "旧石阶一级一级往上，每一级都被踩得发亮。"},
		{"t": "line", "who": "me", "text": "我说不清这是多少人走出来的，也不知道自己会不会被记进去。"},
	],
	"s8_summit": [
		{"t": "line", "who": "me", "text": "山顶比我想的冷。"},
		{"t": "line", "who": "me", "text": "回头的时候，看不见来时的路了。"},
		{"t": "line", "who": "me", "text": "我站在这里，想了想一路上遇见的人。"},
		{"t": "line", "who": "me", "text": "然后我低头，看了看胸口那处心形凹槽。"},
	],
}

## Ending key -> { title, lines }. Keys: white / single_<c> / pair_<a>_<b> / multi_3..5
const ENDINGS := {
	"white": {
		"title": "空白",
		"lines": [
			"你谁也没有变成。",
			"木头的本色不是没有颜色，是把它留在了别人那里。",
			"你在山顶站了很久，然后继续往前走。",
		],
	},
	"single_red": {
		"title": "先走的人",
		"lines": [
			"你成了那种想到就出发的人。",
			"风一停你就想动，路一转弯你就兴奋。",
			"你也许会错过很多，但不会错过自己。",
		],
	},
	"single_yellow": {
		"title": "把问题带在身上的人",
		"lines": [
			"你走到哪儿，问题就跟到哪儿。",
			"你不急着知道答案，你急着知道为什么。",
			"有些路你走得很慢，因为你一直在看。",
		],
	},
	"single_green": {
		"title": "会停下来的人",
		"lines": [
			"你总是先看见别人的鞋有没有磨破。",
			"你的路走得不快，但很多人的路因为你而没有断。",
			"你胸口那处心形凹槽很暖。",
		],
	},
	"single_blue": {
		"title": "守夜的人",
		"lines": [
			"你习惯把该做的事做完，再想自己想做什么。",
			"别人睡下的时候，你还醒着。",
			"你不觉得自己伟大，你只是不放心。",
		],
	},
	"single_purple": {
		"title": "往远处走的人",
		"lines": [
			"你相信看不见的地方有东西在等你。",
			"所以你能忍受这里的不如意，也不太在乎这里的好。",
			"你一直往远处走。",
		],
	},
	"single_orange": {
		"title": "把东西做好的人",
		"lines": [
			"你不太谈远方。",
			"你相信把手边这一块木头刨平，比说十句话有用。",
			"你走过的地方，都留下过修好的东西。",
		],
	},
	"single_teal": {
		"title": "把日子装订起来的人",
		"lines": [
			"你把每一天折好、编号、收进册子。",
			"别人觉得你慢，你只是不想漏掉什么。",
			"你走过的地方，都有了来历。",
		],
	},
	"single_pink": {
		"title": "跟着风走的人",
		"lines": [
			"你没有路线，只有天气。",
			"你在哪儿都能待，也哪儿都待不久。",
			"你不是不认真，你只是把认真留给了当下。",
		],
	},
	"pair_red_yellow": {
		"title": "边跑边问的人",
		"lines": [
			"你一边跑一边问，问题比脚步还快。",
			"别人还在犹豫，你已经撞上了答案。",
			"撞疼了也不回头。",
		],
	},
	"pair_red_green": {
		"title": "替别人冲在前面的人",
		"lines": [
			"你不擅长安慰，但你会在别人开口之前，先站到前面去。",
			"你的热心和你的心软，是一起长出来的。",
			"你走得快，但从不独自走。",
		],
	},
	"pair_red_blue": {
		"title": "先扛住，再说话的人",
		"lines": [
			"你把责任和冲动放在一起，居然不打架。",
			"你想去的地方很多，但你总是先把该守的守住。",
			"你胸口那颗心有种让人安心的急。",
		],
	},
	"pair_red_purple": {
		"title": "朝火烧的方向走的人",
		"lines": [
			"你相信远方，并且愿意马上出发。",
			"你的浪漫里有一点莽撞，几乎算勇敢。",
			"你从不问路远不远，只问什么时候动身。",
		],
	},
	"pair_yellow_green": {
		"title": "一边观察一边心疼的人",
		"lines": [
			"你看得清每片叶子的纹路，也看得见叶子被虫咬过的洞。",
			"你不太会转身就走。",
			"你懂得越多，越不忍心。",
		],
	},
	"pair_yellow_blue": {
		"title": "把灯举稳的人",
		"lines": [
			"你习惯先把事情想清楚，再把它做到底。",
			"你的理性，最后都成了别人脚下的路。",
			"你举着灯，自己不觉得亮。",
		],
	},
	"pair_yellow_purple": {
		"title": "给远方画地图的人",
		"lines": [
			"你没有去过那里，但你画得出那里的样子。",
			"你信的东西，都有细节。",
			"你走的每一步，都在验证一个想象。",
		],
	},
	"pair_green_blue": {
		"title": "温柔地守着的人",
		"lines": [
			"你从不喊口号，只是每天把该做的事做完。",
			"你守着的东西从不声张。",
			"很多人因为你，才能安心走远。",
		],
	},
	"pair_green_purple": {
		"title": "把花种在远方的人",
		"lines": [
			"你的心很软，也很大。",
			"你愿意为了一个很远的地方，先照顾好眼前的一朵花。",
			"你相信终点会有花开，也相信路上要有水。",
		],
	},
	"pair_blue_purple": {
		"title": "守着一片还没到的风景的人",
		"lines": [
			"你把远方放在心上，把责任扛在肩上。",
			"你相信总有一天会到。",
			"你不着急，但你一直在走。",
		],
	},
	"multi_3": {
		"title": "杂色的人",
		"lines": [
			"你胸前的心形凹槽里有三种颜色，像打翻的调色盘。",
			"你不是任何一类人，你是很多类人的一部分。",
			"这不算坏事。",
		],
	},
	"multi_4": {
		"title": "万花筒",
		"lines": [
			"你几乎把所有遇见的人都嵌进了心形凹槽里。",
			"每转一下，你都是另一个样子。",
			"你还在找那个不会转的自己。",
		],
	},
	"multi_5": {
		"title": "所有的颜色",
		"lines": [
			"你谁都想成为，最后成了所有人。",
			"空槽被全部颜色填满，看起来反而像深不见底的灰。",
			"你站在山顶，第一次不知道该往哪儿走。",
		],
	},
}

static func ending(ending_key: String) -> Dictionary:
	if ENDINGS.has(ending_key):
		return ENDINGS[ending_key]
	return ENDINGS["white"]

static func npc(npc_id: String) -> Dictionary:
	return NPCS.get(npc_id, {})

static func color_of(npc_id: String) -> Color:
	var entry: Dictionary = NPCS.get(npc_id, {})
	if entry.is_empty():
		return Color.WHITE
	return (COLORS.get(npc_id, {}) as Dictionary).get("color", Color.WHITE)

## One or two inner lines shown right after an NPC conversation, replacing the
## old 「我是这样的人 / 我不是这样的人」 question. The judgement is silent: it is
## derived from the three weighted choices made during the conversation.
static func result_lines(npc_id: String, took: bool) -> Array:
	var entry: Dictionary = COLORS.get(npc_id, {})
	var color_name := str(entry.get("name", ""))
	var trait_text := str(entry.get("trait", ""))
	if took:
		return [
			{"t": "line", "who": "me", "text": "我没有说自己是，也没有说不是。"},
			{"t": "line", "who": "me", "text": "但胸口那处心形凹槽里，多了一点%s——像%s。" % [color_name, trait_text]},
		]
	return [
		{"t": "line", "who": "me", "text": "我没有伸手去接那一点%s。" % color_name},
		{"t": "line", "who": "me", "text": "它留在原地，像一件不属于我的东西。"},
	]

## Ending data for an arbitrary set of accepted colours. The hand-written
## endings cover the original single/pair/multi cases; everything else (new
## colours, 6-8 colours) is composed from COLOR_LINES so every combination
## still reads like the rest of the game.
static func ending_for(ids: Array) -> Dictionary:
	if ids.is_empty():
		return ENDINGS["white"]
	if ids.size() == 1:
		return ENDINGS.get("single_%s" % ids[0], ENDINGS["white"])
	if ids.size() == 2:
		var pair: Array = ids.duplicate()
		pair.sort_custom(func(a, b): return COLOR_ORDER.find(a) < COLOR_ORDER.find(b))
		var key := "pair_%s_%s" % [pair[0], pair[1]]
		if ENDINGS.has(key):
			return ENDINGS[key]
		return _compose_ending(ids, "两种颜色之间")
	if ENDINGS.has("multi_%d" % ids.size()):
		return ENDINGS["multi_%d" % ids.size()]
	return _compose_ending(ids, "很多颜色的人")

static func _compose_ending(ids: Array, title: String) -> Dictionary:
	var lines := PackedStringArray()
	if ids.size() >= 6:
		var names := PackedStringArray()
		for id in ids:
			var entry: Dictionary = COLORS.get(id, {})
			names.append("%s（%s）" % [str(entry.get("name", "")), str(entry.get("trait", ""))])
		lines.append("你胸前的心形凹槽里有 %d 种颜色：%s。" % [ids.size(), "、".join(names)])
		lines.append("你几乎把路上遇到的颜色都带上了。")
		lines.append("它们没有混成一种颜色，而是各自留了一条边。")
		return {"title": title, "lines": Array(lines)}
	for id in ids:
		if COLOR_LINES.has(id):
			lines.append(str(COLOR_LINES[id]))
	if ids.size() == 2:
		lines.append("两种颜色在心形凹槽里并排待着，还没有分出主次。")
	else:
		lines.append("它们在心形凹槽里混在一起，像还没干透的颜料。")
	return {"title": title, "lines": Array(lines)}

## Four-axis portrait derived from the accepted colours.
## Returns { "title": String, "rows": [{label, a_label, b_label, state}], "summary": String }
static func portrait(ids: Array) -> Dictionary:
	var rows: Array = []
	var chosen_words := PackedStringArray()
	var open_lines := PackedStringArray()
	var clear_axes := 0
	for axis in AXES:
		var has_a := ids.has(axis["a"])
		var has_b := ids.has(axis["b"])
		var state := "none"
		if has_a and has_b:
			state = "both"
		elif has_a:
			state = "a"
			clear_axes += 1
			chosen_words.append(str(axis["a_label"]))
		elif has_b:
			state = "b"
			clear_axes += 1
			chosen_words.append(str(axis["b_label"]))
		rows.append({
			"label": str(axis["label"]),
			"a_label": str(axis["a_label"]),
			"b_label": str(axis["b_label"]),
			"state": state,
		})
		match state:
			"a":
				open_lines.append("你把「%s」嵌进了心形凹槽里。" % axis["a_label"])
			"b":
				open_lines.append("你把「%s」嵌进了心形凹槽里。" % axis["b_label"])
			"both":
				open_lines.append("「%s」和「%s」在心形凹槽里拉扯。" % [axis["a_label"], axis["b_label"]])
			_:
				pass
	var title := "还在成形"
	if clear_axes == AXES.size():
		title = " · ".join(chosen_words)
	elif clear_axes >= 3:
		title = "大部分已经清楚"
	var summary := " ".join(open_lines)
	if summary.is_empty():
		summary = "你还没有把自己交给任何一种颜色。"
	else:
		summary += " 有些侧面，你还没有答案。" if clear_axes < AXES.size() else ""
	return {"title": title, "rows": rows, "summary": summary}
