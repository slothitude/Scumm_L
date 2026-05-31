## Disk cache manager for generated images.
## Saves/loads textures to user://image_cache/{type}/{id}.png

extends RefCounted

const CACHE_SUBDIRS := {
	"icon": "icons",
	"background": "backgrounds",
	"portrait": "portraits",
	"closeup": "closeups",
	"atmosphere": "atmospheres",
	"pixelate": "pixelated",
	"cursor": "cursors",
	"dialogue_frame": "dialogues",
	"tile": "tiles",
	"silhouette": "silhouettes",
}


func _ensure_dirs() -> void:
	var base := GameConsts.IMAGE_CACHE_DIR
	for subdir in CACHE_SUBDIRS.values():
		DirAccess.make_dir_recursive_absolute(base.path_join(subdir))


func _cache_path(img_id: String, img_type: String) -> String:
	var subdir: String = CACHE_SUBDIRS.get(img_type, "icons")
	return GameConsts.IMAGE_CACHE_DIR.path_join(subdir).path_join("%s.png" % img_id)


func is_cached(img_id: String, img_type: String) -> bool:
	return FileAccess.file_exists(_cache_path(img_id, img_type))


func get_cached_texture(img_id: String, img_type: String) -> Texture2D:
	var path := _cache_path(img_id, img_type)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		# Corrupted — delete
		DirAccess.remove_absolute(path)
		return null
	return ImageTexture.create_from_image(img)


func save_to_cache(img_id: String, img_type: String, texture: Texture2D) -> void:
	_ensure_dirs()
	var path := _cache_path(img_id, img_type)
	var img := texture.get_image()
	img.save_png(path)


func invalidate(img_id: String, img_type: String) -> void:
	var path := _cache_path(img_id, img_type)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
