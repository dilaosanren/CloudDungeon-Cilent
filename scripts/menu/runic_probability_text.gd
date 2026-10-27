# Journal-only explanations of the current PvP proc and enchantment-stone odds.
extends RefCounted
const Gear = preload("res://scripts/nature/runic_gear.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const WEAPON := {
	"blazing":"每次命中：(L+1)/(L+3)。+0时约33.33%。",
	"chilling":"每次命中：(L+1)/(L+2)。+0为50%，+1约66.67%，+2为75%。",
	"shocking":"每次命中：1/3，约33.33%。",
	"venomous":"每次命中：1/3，约33.33%。",
	"blocking":"每次命中：(L+4)/(L+40)。+0时为10%。",
	"blooming":"每次命中：(L+1)/(L+3)。+0时约33.33%。",
	"elastic":"每次命中：(L+1)/(L+5)。+0时为20%。",
	"projecting":"持续生效，无随机触发判定。",
	"vorpal":"每次命中：1/4，即25%；目标须能流血。",
	"crystal":"每次命中均追加伤害，即100%。近战武器第5次命中完整结算后碎裂；未命中不计数。",
	"grim":"每次命中后：(50%+5%×L)×目标已损生命比例²。按本次普通伤害结算后的目标生命计算；+0、目标半血时为12.5%。",
	"vampiric":"每次命中：5%+25%×自身已损生命比例。自身半血时为17.5%，剩10%生命时为27.5%；目标须与自己阵营不同。",
}
const ARMOR := {
	"swiftness":"3格可通行路径内没有敌人时持续生效，无随机触发判定。",
	"viscosity":"每次受到物理命中均计算储伤，无随机触发判定。无奥术加成时储存比例为(L+1)/(L+6)，向上取整。",
	"potential":"每次受到物理命中：(L+1)/(L+6)。+0时约16.67%。",
	"brimstone":"持续防护燃烧伤害，无随机触发判定。",
	"stone":"每次受到物理命中均按原有闪避能力计算减伤，无随机触发判定。",
	"entanglement":"每次受到物理命中：1/4，即25%。",
	"repulsion":"每次受到物理命中：(L+1)/(L+5)。+0时为20%；攻击者须相邻。",
	"camouflage":"踩入高草时必定生效，即100%；浮空时不触发。",
	"flow":"在水中移动时持续生效，无随机触发判定。",
	"affection":"每次受到物理命中：(L+3)/(L+20)。+0时为15%。",
	"antimagic":"每次受到可防御的魔法伤害均计算减伤，无随机触发判定；减伤数值随机，可能为0。",
	"thorns":"每次受到物理命中：(L+2)/(L+12)。+0时约16.67%；攻击者须能流血且与自己阵营不同。",
}

static func description(family: String, key: String) -> String:
	var notes: Dictionary = ARMOR if family == "armor" else WEAPON
	var result := L10n.text("触发概率：%s") % L10n.text(str(notes[key]))
	result += "\n"+L10n.text("L为装备有效等级。以上按无奥术之戒加成计算；随机触发概率受奥术之戒提升，最高100%。")
	var data := Gear.catalog()
	for tier in data.pools[family].size():
		var pool: Array = data.pools[family][tier]
		if key not in pool: continue
		var chance := "%.2f%%" % (float(data.weights[tier])/pool.size())
		result += "\n\n"+L10n.text("附魔石抽取：%s。") % chance
		result += "\n"+L10n.text("重新附魔不会抽到当前效果；同档其他效果均分该档概率。")
		break
	return result
