class_name TarotCard
extends Resource

enum cardCategory{
	NORMAL,
	SUPER
}

@export_group("Identity")
@export var card_id:StringName
@export var card_name: String
@export_multiline var description: String

@export_group("Classification")
@export var category:cardCategory = cardCategory.NORMAL

@export_group("Effect")
@export var effect: TarotEffect
