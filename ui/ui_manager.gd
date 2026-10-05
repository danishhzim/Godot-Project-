extends Control
## Mandarin Conquest UI shell: splash → auth/guest → welcome → app with bottom nav.
## No gameplay, vocabulary decks, or real backend auth.

enum FlowScreen { TITLE, AUTH, WELCOME, APP }
enum AppTab { MENUS, PLAY, PROFILE, LEADERBOARDS }

const SESSION_PATH := "user://session.cfg"
const VOCABULARY_PATH := "res://data/vocabulary.csv"
const WELCOME_SECONDS := 1.35
const QUESTIONS_PER_ROUND := 10

const WHITE := Color("FFFFFF")
const CHARCOAL := Color("1A1A1A")
const MUTED := Color("5C5C5C")
const YELLOW := Color("F5D33D")
const YELLOW_PRESS := Color("E8C12A")
const ORANGE := Color("F27A1A")
const TEAL := Color("1A9BB0")
const NAV_YELLOW := Color("F4D03F")
const CARD := Color("FFF8E8")
const JADE := Color("2E8B74")
const JADE_PRESS := Color("1F6B58")

var _auth_is_sign_up := true
var _welcome_running := false
var _vocabulary: Array[Dictionary] = []
var _round_cards: Array[Dictionary] = []
var _question_index := 0
var _score := 0
var _answer_locked := false

@onready var _title_card: Control = %TitleCard
@onready var _auth_screen: Control = %AuthScreen
@onready var _welcome_screen: Control = %WelcomeScreen
@onready var _app_shell: Control = %AppShell
@onready var _menus_page: Control = %MenusPage
@onready var _play_page: Control = %PlayPage
@onready var _profile_page: Control = %ProfilePage
@onready var _leaderboards_page: Control = %LeaderboardsPage


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_apply_theme()
	_load_vocabulary()
	_build_topic_buttons()
	_connect_signals()
	_set_auth_mode(true)
	show_flow(FlowScreen.TITLE)


func show_flow(screen: FlowScreen) -> void:
	_title_card.visible = screen == FlowScreen.TITLE
	_auth_screen.visible = screen == FlowScreen.AUTH
	_welcome_screen.visible = screen == FlowScreen.WELCOME
	_app_shell.visible = screen == FlowScreen.APP
	if screen == FlowScreen.APP:
		show_app_tab(AppTab.PLAY)


func show_app_tab(tab: AppTab) -> void:
	_menus_page.visible = tab == AppTab.MENUS
	_play_page.visible = tab == AppTab.PLAY
	_profile_page.visible = tab == AppTab.PROFILE
	_leaderboards_page.visible = tab == AppTab.LEADERBOARDS
	_refresh_nav_visuals(tab)
	if tab == AppTab.PROFILE:
		_refresh_profile()


func _connect_signals() -> void:
	_title_card.gui_input.connect(_on_title_gui_input)
	%AuthPrimaryButton.pressed.connect(_on_auth_primary_pressed)
	%GuestButton.pressed.connect(_on_guest_pressed)
	%AuthSwitchButton.pressed.connect(_on_auth_switch_pressed)
	%NavMenusButton.pressed.connect(show_app_tab.bind(AppTab.MENUS))
	%NavPlayButton.pressed.connect(show_app_tab.bind(AppTab.PLAY))
	%NavProfileButton.pressed.connect(show_app_tab.bind(AppTab.PROFILE))
	%LeaderboardsButton.pressed.connect(show_app_tab.bind(AppTab.LEADERBOARDS))
	%SignOutButton.pressed.connect(_on_sign_out_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%BackToTopicsButton.pressed.connect(_show_topic_picker)
	%NextQuestionButton.pressed.connect(_advance_question)
	%RoundAgainButton.pressed.connect(_restart_round)
	%RoundTopicsButton.pressed.connect(_show_topic_picker)
	for answer_button in %AnswerButtons.get_children():
		(answer_button as Button).pressed.connect(_on_answer_pressed.bind(answer_button))


func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_leave_title_card()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_leave_title_card()


func _leave_title_card() -> void:
	if _has_saved_session():
		_start_welcome()
	else:
		show_flow(FlowScreen.AUTH)


func _on_auth_switch_pressed() -> void:
	_set_auth_mode(not _auth_is_sign_up)


func _set_auth_mode(is_sign_up: bool) -> void:
	_auth_is_sign_up = is_sign_up
	%UsernameRow.visible = is_sign_up
	%AuthPrimaryButton.text = "Sign Up" if is_sign_up else "Sign In"
	%AuthSwitchHint.text = "Already have an account?" if is_sign_up else "New here?"
	%AuthSwitchButton.text = "Sign In" if is_sign_up else "Sign Up"


func _on_auth_primary_pressed() -> void:
	var email_field := %EmailField as LineEdit
	var username_field := %UsernameField as LineEdit
	var password_field := %PasswordField as LineEdit
	var email: String = email_field.text.strip_edges()
	var username: String = username_field.text.strip_edges()
	var password: String = password_field.text
	if email.is_empty() or password.is_empty():
		_set_auth_status("Enter email and password to continue.")
		return
	if _auth_is_sign_up and username.is_empty():
		_set_auth_status("Choose a username to sign up.")
		return
	var display_name: String = username
	if not _auth_is_sign_up:
		display_name = email.get_slice("@", 0)
	if display_name.is_empty():
		display_name = "Player"
	_save_session(display_name, false)
	_set_auth_status("")
	_start_welcome()


func _on_guest_pressed() -> void:
	_save_session("Guest", true)
	_set_auth_status("")
	_start_welcome()


func _start_welcome() -> void:
	if _welcome_running:
		return
	_welcome_running = true
	var session := _load_session()
	var player_name := str(session.get("username", "Guest"))
	if bool(session.get("is_guest", true)):
		%WelcomeTitle.text = "Welcome, Guest"
		%WelcomeSubtitle.text = "Skipping account setup for now."
	else:
		%WelcomeTitle.text = "Welcome, %s" % player_name
		%WelcomeSubtitle.text = "Loading your home screen..."
	show_flow(FlowScreen.WELCOME)
	await get_tree().create_timer(WELCOME_SECONDS).timeout
	_welcome_running = false
	show_flow(FlowScreen.APP)


func _on_sign_out_pressed() -> void:
	_clear_session()
	%EmailField.text = ""
	%UsernameField.text = ""
	%PasswordField.text = ""
	_set_auth_mode(true)
	show_flow(FlowScreen.TITLE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _load_vocabulary() -> void:
	_vocabulary.clear()
	if not FileAccess.file_exists(VOCABULARY_PATH):
		push_error("Vocabulary CSV not found: " + VOCABULARY_PATH)
		return
	var file := FileAccess.open(VOCABULARY_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open vocabulary CSV.")
		return
	var headers := file.get_csv_line()
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.size() < headers.size() or cells[1].strip_edges().is_empty():
			continue
		var entry: Dictionary = {}
		for i in range(headers.size()):
			entry[headers[i].strip_edges()] = cells[i].strip_edges()
		_vocabulary.append(entry)


func _build_topic_buttons() -> void:
	var grid := %TopicGrid as GridContainer
	for child in grid.get_children():
		child.queue_free()
	var categories: Array[String] = []
	for entry in _vocabulary:
		var category := str(entry.get("Category", "")).to_lower()
		if not category.is_empty() and not categories.has(category):
			categories.append(category)
	categories.sort()
	for category in categories:
		var button := Button.new()
		button.text = "%s\n%d words" % [category.capitalize(), _count_category(category)]
		button.custom_minimum_size = Vector2(0, 112)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_button_theme(button, _make_button_style(JADE, Color(0, 0, 0, 0), 18), _make_button_style(JADE, Color(0, 0, 0, 0), 18), _make_button_style(JADE_PRESS, Color(0, 0, 0, 0), 18), 20, WHITE, Vector2(0, 112))
		button.pressed.connect(_start_round.bind(category))
		grid.add_child(button)
	%TopicHint.text = "%d vocabulary words across %d topics" % [_vocabulary.size(), categories.size()]


func _count_category(category: String) -> int:
	var count := 0
	for entry in _vocabulary:
		if str(entry.get("Category", "")).to_lower() == category:
			count += 1
	return count


func _start_round(category: String) -> void:
	var pool: Array[Dictionary] = []
	for entry in _vocabulary:
		if str(entry.get("Category", "")).to_lower() == category:
			pool.append(entry)
	if pool.size() < QUESTIONS_PER_ROUND:
		%TopicHint.text = "This topic needs at least %d words to start a round." % QUESTIONS_PER_ROUND
		return
	pool.shuffle()
	_round_cards = pool.slice(0, QUESTIONS_PER_ROUND)
	_question_index = 0
	_score = 0
	%TopicPicker.visible = false
	%QuizPanel.visible = true
	_show_question()


func _show_topic_picker() -> void:
	%QuizPanel.visible = false
	%RoundCompletePanel.visible = false
	%TopicPicker.visible = true


func _show_question() -> void:
	if _question_index >= _round_cards.size():
		_finish_round()
		return
	_answer_locked = false
	var card: Dictionary = _round_cards[_question_index]
	%QuestionProgress.text = "Question %d of %d     Score: %d" % [_question_index + 1, _round_cards.size(), _score]
	%QuestionPrompt.text = str(card.get("Pinyin", ""))
	%QuestionMandarin.text = str(card.get("Mandarin", ""))
	%QuestionInstruction.text = "Choose the correct English meaning"
	%AnswerFeedback.text = ""
	%NextQuestionButton.visible = false
	var correct_answer := str(card.get("English", ""))
	var choices: Array[String] = [correct_answer]
	var category_distractors: Array[String] = []
	var general_distractors: Array[String] = []
	for entry in _vocabulary:
		var meaning := str(entry.get("English", ""))
		if meaning == correct_answer or meaning.is_empty():
			continue
		if str(entry.get("Category", "")).to_lower() == str(card.get("Category", "")).to_lower():
			if not category_distractors.has(meaning):
				category_distractors.append(meaning)
		elif not general_distractors.has(meaning):
			general_distractors.append(meaning)
	category_distractors.shuffle()
	general_distractors.shuffle()
	var distractors: Array[String] = category_distractors.slice(0, mini(3, category_distractors.size()))
	if distractors.size() < 3:
		var needed := 3 - distractors.size()
		for meaning in general_distractors:
			if not distractors.has(meaning):
				distractors.append(meaning)
				needed -= 1
			if needed == 0:
				break
	if distractors.size() < 3:
		for entry in _vocabulary:
			var meaning := str(entry.get("English", ""))
			if meaning != correct_answer and not meaning.is_empty() and not distractors.has(meaning):
				distractors.append(meaning)
			if distractors.size() == 3:
				break
	choices.append_array(distractors)
	choices.shuffle()
	for i in range(4):
		var button := %AnswerButtons.get_child(i) as Button
		button.visible = i < choices.size()
		if button.visible:
			button.text = choices[i]
			button.disabled = false
			button.modulate = Color.WHITE
			var normal_style := _make_button_style(Color("E8F3ED"), JADE, 14)
			var hover_style := _make_button_style(Color("D4EBDD"), JADE_PRESS, 14)
			button.add_theme_stylebox_override("normal", normal_style)
			button.add_theme_stylebox_override("hover", hover_style)
			button.add_theme_stylebox_override("pressed", hover_style)
			button.set_meta("answer", choices[i])
			button.set_meta("correct", choices[i] == str(card.get("English", "")))


func _on_answer_pressed(selected_button: Button) -> void:
	if _answer_locked:
		return
	_answer_locked = true
	var correct := bool(selected_button.get_meta("correct", false))
	var correct_style := _make_button_style(Color("79C99E"), JADE, 14)
	var incorrect_style := _make_button_style(Color("F2A3A3"), Color("B42318"), 14)
	selected_button.add_theme_color_override("font_color", CHARCOAL)
	selected_button.add_theme_color_override("font_hover_color", CHARCOAL)
	selected_button.add_theme_color_override("font_pressed_color", CHARCOAL)
	selected_button.add_theme_stylebox_override("normal", correct_style if correct else incorrect_style)
	selected_button.add_theme_stylebox_override("hover", correct_style if correct else incorrect_style)
	selected_button.add_theme_stylebox_override("pressed", correct_style if correct else incorrect_style)
	if correct:
		_score += 1
		%AnswerFeedback.text = "Correct!  %s — %s" % [_round_cards[_question_index].get("Mandarin", ""), _round_cards[_question_index].get("English", "")]
	else:
		%AnswerFeedback.text = "Not quite. The answer is %s." % _round_cards[_question_index].get("English", "")
	for child in %AnswerButtons.get_children():
		(child as Button).disabled = true
	%QuestionProgress.text = "Question %d of %d     Score: %d" % [_question_index + 1, _round_cards.size(), _score]
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	_question_index += 1
	_show_question()


func _advance_question() -> void:
	# Kept as a button callback for the scene; progression is automatic after feedback.
	return


func _restart_round() -> void:
	if _round_cards.is_empty():
		_show_topic_picker()
		return
	var category := str(_round_cards[0].get("Category", "")).to_lower()
	_start_round(category)


func _finish_round() -> void:
	%QuizPanel.visible = false
	%RoundCompletePanel.visible = true
	%RoundResult.text = "You scored %d out of %d" % [_score, _round_cards.size()]
	var percent := float(_score) / maxf(1.0, float(_round_cards.size()))
	%RoundMessage.text = "Brilliant work!" if percent >= 0.8 else "Good practice. Try again to improve your score!"


func _set_auth_status(message: String) -> void:
	%AuthStatusLabel.text = message


func _refresh_profile() -> void:
	var session := _load_session()
	var username := str(session.get("username", "Guest"))
	%ProfileNameLabel.text = username
	%ProfileRoleLabel.text = "Guest player" if bool(session.get("is_guest", true)) else "Local account"


func _refresh_nav_visuals(tab: AppTab) -> void:
	var menus_on := tab == AppTab.MENUS
	var profile_on := tab == AppTab.PROFILE
	%NavMenusButton.modulate = Color(1, 1, 1, 1) if menus_on else Color(1, 1, 1, 0.72)
	%NavProfileButton.modulate = Color(1, 1, 1, 1) if profile_on else Color(1, 1, 1, 0.72)
	%NavPlayButton.modulate = Color(1, 1, 1, 1) if tab == AppTab.PLAY else Color(0.96, 0.96, 0.96, 1)


func _has_saved_session() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return false
	return bool(cfg.get_value("session", "signed_in", false))


func _load_session() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return {"username": "Guest", "is_guest": true}
	return {
		"username": str(cfg.get_value("session", "username", "Guest")),
		"is_guest": bool(cfg.get_value("session", "is_guest", true)),
	}


func _save_session(username: String, is_guest: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "signed_in", true)
	cfg.set_value("session", "username", username)
	cfg.set_value("session", "is_guest", is_guest)
	cfg.save(SESSION_PATH)


func _clear_session() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("session.cfg"):
		dir.remove("session.cfg")


func _apply_theme() -> void:
	%Background.color = WHITE
	%HeaderBar.color = YELLOW
	%NavBar.color = NAV_YELLOW
	%AuthPanel.color = WHITE
	%MenusCard.color = CARD
	%PlayCard.color = CARD
	%ProfileCard.color = CARD
	%LeaderboardsCard.color = CARD

	%TitleMandarin.add_theme_color_override("font_color", ORANGE)
	%TitleMandarin.add_theme_font_size_override("font_size", 64)
	%TitleConquest.add_theme_color_override("font_color", TEAL)
	%TitleConquest.add_theme_font_size_override("font_size", 58)
	%ClickToStart.add_theme_color_override("font_color", CHARCOAL)
	%ClickToStart.add_theme_font_size_override("font_size", 22)

	%AuthTitleMandarin.add_theme_color_override("font_color", ORANGE)
	%AuthTitleMandarin.add_theme_font_size_override("font_size", 48)
	%AuthTitleConquest.add_theme_color_override("font_color", TEAL)
	%AuthTitleConquest.add_theme_font_size_override("font_size", 44)
	%AuthSubtitle.add_theme_color_override("font_color", TEAL)
	%AuthSubtitle.add_theme_font_size_override("font_size", 16)
	%AuthStatusLabel.add_theme_color_override("font_color", Color("B42318"))
	%AuthSwitchHint.add_theme_color_override("font_color", CHARCOAL)

	%HeaderMandarin.add_theme_color_override("font_color", ORANGE)
	%HeaderMandarin.add_theme_font_size_override("font_size", 36)
	%HeaderConquest.add_theme_color_override("font_color", TEAL)
	%HeaderConquest.add_theme_font_size_override("font_size", 32)
	%LeaderboardsCaption.add_theme_color_override("font_color", CHARCOAL)
	%PlayHeading.add_theme_color_override("font_color", CHARCOAL)
	%TopicHint.add_theme_color_override("font_color", MUTED)
	%QuestionProgress.add_theme_color_override("font_color", MUTED)
	%QuestionInstruction.add_theme_color_override("font_color", CHARCOAL)
	%QuestionMandarin.add_theme_color_override("font_color", CHARCOAL)
	%QuestionPrompt.add_theme_color_override("font_color", JADE_PRESS)
	%AnswerFeedback.add_theme_color_override("font_color", CHARCOAL)
	%RoundCompleteHeading.add_theme_color_override("font_color", JADE_PRESS)
	%RoundResult.add_theme_color_override("font_color", CHARCOAL)
	%RoundMessage.add_theme_color_override("font_color", MUTED)

	%WelcomeTitle.add_theme_font_size_override("font_size", 36)
	%WelcomeTitle.add_theme_color_override("font_color", CHARCOAL)
	%WelcomeSubtitle.add_theme_color_override("font_color", MUTED)

	_style_line_edit(%EmailField)
	_style_line_edit(%UsernameField)
	_style_line_edit(%PasswordField)

	var outline := _make_button_style(WHITE, CHARCOAL, 18)
	var outline_press := _make_button_style(Color("F0F0F0"), CHARCOAL, 18)
	var yellow_btn := _make_button_style(YELLOW, Color(0, 0, 0, 0), 18)
	var yellow_press := _make_button_style(YELLOW_PRESS, Color(0, 0, 0, 0), 18)
	var jade := _make_button_style(JADE, Color(0, 0, 0, 0), 18)
	var jade_press := _make_button_style(JADE_PRESS, Color(0, 0, 0, 0), 18)
	var play_circle := _make_button_style(WHITE, CHARCOAL, 999)
	var play_circle_press := _make_button_style(Color("FFF4C4"), CHARCOAL, 999)
	var ghost := _make_button_style(Color("F4F4F4"), Color("DDDDDD"), 16)
	var ghost_press := _make_button_style(Color("E4E4E4"), Color("CCCCCC"), 16)

	_apply_button_theme(%AuthPrimaryButton, outline, outline_press, outline_press, 24, CHARCOAL, Vector2(220, 56))
	_apply_button_theme(%GuestButton, jade, jade, jade_press, 20, WHITE, Vector2(0, 52))
	_apply_link_button(%AuthSwitchButton)
	_apply_button_theme(%NavMenusButton, yellow_btn, yellow_btn, yellow_press, 22, CHARCOAL, Vector2(0, 88))
	_apply_button_theme(%NavProfileButton, yellow_btn, yellow_btn, yellow_press, 22, CHARCOAL, Vector2(0, 88))
	_apply_button_theme(%NavPlayButton, play_circle, play_circle, play_circle_press, 22, CHARCOAL, Vector2(108, 108))
	_apply_button_theme(%LeaderboardsButton, ghost, ghost, ghost_press, 14, CHARCOAL, Vector2(88, 88))
	_apply_button_theme(%SignOutButton, outline, outline_press, outline_press, 20, CHARCOAL, Vector2(0, 52))
	_apply_button_theme(%QuitButton, ghost, ghost, ghost_press, 20, CHARCOAL, Vector2(0, 52))

	_apply_button_theme(%NextQuestionButton, yellow_btn, yellow_btn, yellow_press, 20, CHARCOAL, Vector2(0, 54))
	_apply_button_theme(%BackToTopicsButton, outline, outline_press, outline_press, 18, CHARCOAL, Vector2(0, 48))
	_apply_button_theme(%RoundAgainButton, jade, jade, jade_press, 20, WHITE, Vector2(0, 54))
	_apply_button_theme(%RoundTopicsButton, outline, outline_press, outline_press, 18, CHARCOAL, Vector2(0, 48))
	for answer: Button in %AnswerButtons.get_children():
		_apply_button_theme(answer, _make_button_style(Color("E8F3ED"), JADE, 14), _make_button_style(Color("D4EBDD"), JADE_PRESS, 14), _make_button_style(Color("D4EBDD"), JADE_PRESS, 14), 19, CHARCOAL, Vector2(0, 64))

	_style_slider(%MusicVolumeSlider)
	_style_slider(%SfxVolumeSlider)


func _apply_link_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_color_override("font_color", TEAL)
	button.add_theme_color_override("font_pressed_color", JADE_PRESS)
	button.add_theme_font_size_override("font_size", 18)


func _apply_button_theme(
	button: Button,
	normal: StyleBoxFlat,
	hover: StyleBoxFlat,
	pressed: StyleBoxFlat,
	font_size: int,
	font_color: Color,
	min_size: Vector2
) -> void:
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size = min_size


func _make_button_style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	if border.a > 0.01:
		style.border_color = border
		style.set_border_width_all(2)
	return style


func _style_line_edit(field: LineEdit) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = WHITE
	box.border_color = CHARCOAL
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	field.add_theme_stylebox_override("normal", box)
	field.add_theme_stylebox_override("focus", box)
	field.add_theme_color_override("font_color", CHARCOAL)
	field.custom_minimum_size = Vector2(0, 44)


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("E6D9A8")
	track.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = JADE
	fill.set_corner_radius_all(8)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 70
	slider.custom_minimum_size = Vector2(0, 36)
