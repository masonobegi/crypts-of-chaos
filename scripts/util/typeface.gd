class_name Typeface
extends RefCounted
## THE FOUR HANDS THIS GAME IS WRITTEN IN.
##
## Everything else in this project is procedural, and type is the one place
## where that would have been a mistake: a letterform is not a mesh you can
## reason your way to from primitives, and Godot's stock face on every screen
## is the loudest single tell that a game was made in an afternoon. These are
## four OFL-licensed families, redistributable, with their licences beside them
## in `assets/fonts/`.
##
## They are not decoration. The game's premise is that three layers are allowed
## to disagree — what is TRUE, what the RECORD says, and what somebody
## BELIEVES — and the chart is where the player reads all three at once. So the
## record tells you who wrote each line before you have read a word of it:
##
##   HAND   your own scrawl. Only ever your notes and your signature.
##   SANS   a colleague. Legible, neutral, somebody else's pen.
##   ITALIC reported speech — "patient states…". Not an observation.
##   MONO   a machine. A result, a timestamp, a figure, a bed number. Nobody
##          chose how it reads and nobody can argue with it.
##   SERIF  the institution. Letterheads, form titles, the stamp on the review.
##
## `Author.YOU` in handwriting against `Author.MACHINE` in mono is the whole
## game in one glance, and it costs nothing at runtime.
##
## EVERY ACCESSOR TOLERATES A MISSING FILE. `load()` on an absent resource
## prints an error and returns null, and a null font override falls straight
## back to the engine default — so a broken import degrades to the old look
## rather than to a blank screen. `have()` is what the test suite asserts on.

const DIR := "res://assets/fonts/"

const F_SANS := "InstrumentSans-Regular.ttf"
const F_SANS_BOLD := "InstrumentSans-Bold.ttf"
const F_SANS_ITALIC := "InstrumentSans-Italic.ttf"
const F_MONO := "IBMPlexMono-Regular.ttf"
const F_MONO_BOLD := "IBMPlexMono-Bold.ttf"
const F_SERIF := "IBMPlexSerif-Bold.ttf"
const F_HAND := "NothingYouCouldDo-Regular.ttf"

const ALL := [F_SANS, F_SANS_BOLD, F_SANS_ITALIC, F_MONO, F_MONO_BOLD, F_SERIF, F_HAND]

## HANDWRITING IS LIGHTER, NOT SMALLER — and the difference matters, because
## the obvious fix for the wrong one is the wrong fix.
##
## A type specimen rendered on the real manila at the real body size says
## `NothingYouCouldDo`'s x-height band is 8px at 16pt, which is EXACTLY
## Instrument Sans's. What is not the same is the ink: 573 dark pixels against
## the sans's 943, because it is a single-stroke script and the sans is not. So
## a handwritten note at the body size does not read small, it reads FAINT, and
## scaling it for x-height (the first version of this constant said 1.34) would
## have overrun the chart card by a third to fix a problem it does not have.
##
## 19pt puts the hand at 797 pixels of ink against the sans's 943 — close
## enough to sit on the same page without either one shouting. 19/16.
const HAND_SCALE := 1.19

static var _cache := {}

## One file, loaded once. Untyped return: a failed load is null, and a typed
## local would abort the caller rather than yield it (CLAUDE.md 11).
static func face(file: String):
	if _cache.has(file):
		return _cache[file]
	var f = load(DIR + file) if ResourceLoader.exists(DIR + file) else null
	_cache[file] = f
	return f

static func sans(): return face(F_SANS)
static func sans_bold(): return face(F_SANS_BOLD)
static func sans_italic(): return face(F_SANS_ITALIC)
static func mono(): return face(F_MONO)
static func mono_bold(): return face(F_MONO_BOLD)
static func serif(): return face(F_SERIF)
static func hand(): return face(F_HAND)

## Are the faces actually on disk and importable? The suite asserts this, because
## the failure mode is silent: the game looks exactly like it did before.
static func have() -> bool:
	for f in ALL:
		if face(f) == null:
			return false
	return true

## Which face a chart line is written in, from who wrote it. This is the only
## place that mapping lives; the chart, the records screen and the review all
## read it, so a line looks the same wherever it is quoted.
static func for_author(author: int):
	match author:
		ChartEntry.Author.YOU: return hand()
		ChartEntry.Author.PATIENT: return sans_italic()
		ChartEntry.Author.MACHINE: return mono()
	return sans()

## ...and the size that face needs to sit on the same baseline rhythm as the
## body text around it.
static func size_for_author(author: int, base: int) -> int:
	if author == ChartEntry.Author.YOU:
		return int(round(base * HAND_SCALE))
	return base

## THE FALLBACK NET.
##
## Not every control in the game is built by `UIKit`. Godot's own defaults reach
## a LineEdit's placeholder, a RichTextLabel's bold run, a ScrollContainer's
## tooltip, a Window's title bar — and one stock-face control on a screen of
## typeset ones is more obvious than none at all. This theme goes on the scene
## tree root at boot and catches all of it, so `UIKit`'s per-control overrides
## are refinements rather than the only line of defence.
static func theme() -> Theme:
	var t := Theme.new()
	var body = sans()
	if body == null:
		return t
	t.default_font = body
	t.default_font_size = 16
	# RichTextLabel keeps four separate faces and falls back to the stock one
	# per-run, so a [b] inside a paragraph changed typeface mid-sentence.
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", sans_bold())
	t.set_font("italics_font", "RichTextLabel", sans_italic())
	t.set_font("mono_font", "RichTextLabel", mono())
	return t
