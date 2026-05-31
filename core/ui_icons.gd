## Semantic icon path constants.
## Maps verb/action names to pre-built icon PNGs in assets/ui/icons/.

extends RefCounted

# --- Actions ---
const ICON_SEND: String = "res://assets/ui/icons/action_send.png"
const ICON_ADD: String = "res://assets/ui/icons/action_add.png"
const ICON_REMOVE: String = "res://assets/ui/icons/action_remove.png"
const ICON_EDIT: String = "res://assets/ui/icons/action_edit.png"
const ICON_DELETE: String = "res://assets/ui/icons/action_delete.png"
const ICON_COPY: String = "res://assets/ui/icons/action_copy.png"
const ICON_CHECK: String = "res://assets/ui/icons/action_check.png"
const ICON_DOWNLOAD: String = "res://assets/ui/icons/action_download.png"
const ICON_UPLOAD: String = "res://assets/ui/icons/action_upload.png"
const ICON_REFRESH: String = "res://assets/ui/icons/action_refresh.png"
const ICON_SHARE: String = "res://assets/ui/icons/action_share.png"

# --- Chat / NPC ---
const ICON_TALK: String = "res://assets/ui/icons/chat_bubble.png"
const ICON_MAIL: String = "res://assets/ui/icons/chat_mail.png"
const ICON_NOTIFICATION: String = "res://assets/ui/icons/chat_notification.png"
const ICON_USER: String = "res://assets/ui/icons/chat_user.png"
const ICON_USERS: String = "res://assets/ui/icons/chat_users.png"

# --- Content ---
const ICON_BOOKMARK: String = "res://assets/ui/icons/content_bookmark.png"
const ICON_CAMERA: String = "res://assets/ui/icons/content_camera.png"
const ICON_FILE: String = "res://assets/ui/icons/content_file.png"
const ICON_FOLDER: String = "res://assets/ui/icons/content_folder.png"
const ICON_HEART: String = "res://assets/ui/icons/content_heart.png"
const ICON_IMAGE: String = "res://assets/ui/icons/content_image.png"
const ICON_LINK: String = "res://assets/ui/icons/content_link.png"
const ICON_STAR: String = "res://assets/ui/icons/content_star.png"

# --- Media ---
const ICON_FULLSCREEN: String = "res://assets/ui/icons/media_fullscreen.png"
const ICON_MUTE: String = "res://assets/ui/icons/media_mute.png"
const ICON_PAUSE: String = "res://assets/ui/icons/media_pause.png"
const ICON_PLAY: String = "res://assets/ui/icons/media_play.png"
const ICON_SKIP_NEXT: String = "res://assets/ui/icons/media_skip_next.png"
const ICON_SKIP_PREV: String = "res://assets/ui/icons/media_skip_prev.png"
const ICON_STOP: String = "res://assets/ui/icons/media_stop.png"
const ICON_VOLUME: String = "res://assets/ui/icons/media_volume.png"

# --- Navigation ---
const ICON_BACK: String = "res://assets/ui/icons/nav_back.png"
const ICON_CLOSE: String = "res://assets/ui/icons/nav_close.png"
const ICON_DOWN: String = "res://assets/ui/icons/nav_down.png"
const ICON_FORWARD: String = "res://assets/ui/icons/nav_forward.png"
const ICON_HOME: String = "res://assets/ui/icons/nav_home.png"
const ICON_MENU: String = "res://assets/ui/icons/nav_menu.png"
const ICON_SEARCH: String = "res://assets/ui/icons/nav_search.png"
const ICON_UP: String = "res://assets/ui/icons/nav_up.png"

# --- Status ---
const ICON_BATTERY: String = "res://assets/ui/icons/status_battery.png"
const ICON_CLOUD: String = "res://assets/ui/icons/status_cloud.png"
const ICON_LOADING: String = "res://assets/ui/icons/status_loading.png"
const ICON_LOCATION: String = "res://assets/ui/icons/status_location.png"
const ICON_SUCCESS: String = "res://assets/ui/icons/status_success.png"
const ICON_WIFI: String = "res://assets/ui/icons/status_wifi.png"

# --- System ---
const ICON_ERROR: String = "res://assets/ui/icons/sys_error.png"
const ICON_HELP: String = "res://assets/ui/icons/sys_help.png"
const ICON_INFO: String = "res://assets/ui/icons/sys_info.png"
const ICON_LOCK: String = "res://assets/ui/icons/sys_lock.png"
const ICON_SETTINGS: String = "res://assets/ui/icons/sys_settings.png"
const ICON_UNLOCK: String = "res://assets/ui/icons/sys_unlock.png"
const ICON_WARNING: String = "res://assets/ui/icons/sys_warning.png"
const ICON_SLOTH: String = "res://assets/ui/icons/brand_sloth_avatar.png"


func get_verb_icon(verb: String) -> String:
	match verb:
		"examine", "look":
			return ICON_SEARCH
		"talk":
			return ICON_TALK
		"use":
			return ICON_PLAY
		"take", "grab":
			return ICON_ADD
		"inventory":
			return ICON_FOLDER
		"go", "walk":
			return ICON_FORWARD
		"settings":
			return ICON_SETTINGS
		_:
			return ICON_SEND
