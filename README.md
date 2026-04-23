# 🗡️ CRYPTS OF CHAOS
### A Roguelite Dungeon Crawler — Godot 4 | iOS

---

## How to Play

**Objective:** Descend through 10 procedurally generated dungeon floors, slay enemies, collect loot, and get the highest score possible.

### Controls
| Input | Action |
|-------|--------|
| **Swipe** | Move player |
| **Tap adjacent tile** | Move/Attack |
| **D-pad (bottom HUD)** | Move |
| **Center button (•)** | Wait (skip turn) |
| **[F] / Fire button** | Use Fire Scroll |
| **Arrow Keys / WASD** | Move (desktop) |
| **Space** | Wait (desktop) |

---

## The Shard System

Before each run, pick one of **8 Shards** — each gives a completely different starting advantage (like Balatro decks):

| Shard | Advantage | Score Mult |
|-------|-----------|-----------|
| ⚔️ **Iron Shard** | +20 HP, +2 ATK, starts with Sword | ×1.0 |
| 🗡️ **Shadow Shard** | Double gold, +speed, Poison Dagger | ×1.25 |
| 🔥 **Arcane Shard** | 3 Fire Scrolls, +4 ATK, -10 HP | ×1.35 |
| 💰 **Golden Shard** | 80 starting gold, shop -30%, +DEF | ×1.1 |
| 💀 **Cursed Shard** | Rage = damage as HP drops, -15 HP | ×2.5 |
| ✨ **Holy Shard** | Regen 3 HP/floor, +4 HP on level up | ×1.0 |
| 🌀 **Void Shard** | Random stats + bonus item each floor | ×1.5 |
| 📜 **Ancient Shard** | Full map revealed, auto-ID items | ×1.2 |

---

## Enemies

| Enemy | Floor | Special |
|-------|-------|---------|
| `r` Rat | 1+ | Basic chaser |
| `b` Bat | 1+ | Random movement |
| `S` Skeleton | 3+ | Armored |
| `g` Goblin | 3+ | Fast (2 speed) |
| `O` Orc | 5+ | High HP |
| `W` Wraith | 5+ | Phases through walls |
| `T` Troll | 7+ | Regenerates HP |
| `M` Dark Mage | 7+ | Ranged attacks |
| `D` Demon | 9+ | Very strong |
| `&` Dragon | 10 | Boss — fire breath |

---

## Items

| Glyph | Item | Effect |
|-------|------|--------|
| `!` | Health Potion | +10 HP |
| `!` | Greater Potion | +25 HP |
| `/` | Sword / Dagger / Axe | +ATK permanently |
| `[` | Shield / Armor / Plate | +DEF permanently |
| `?` | Fire Scroll | AoE fire damage (range 3) |
| `?` | Ice Scroll | Confuse enemies |
| `$` | Gold / Treasure | Add gold |
| `o` | Power Amulet | +ATK and +DEF |
| `~` | Holy Water | +HP, cures poison |
| `?` | Map Scroll | Reveals entire dungeon |

---

## Scoring

```
Score = (floor × 100) + (kills × 10) + gold_collected
      × Shard Multiplier
```

Top 10 scores saved locally on device (`user://high_scores.json`).

---

## Setup (Godot 4.2+)

1. Open this folder in **Godot 4.2+**
2. Press **F5** to run
3. For iOS export: set up Xcode + iOS export template in Godot Editor

---

## Project Structure

```
scenes/
  Main.tscn          ← Main menu
  ShardSelect.tscn   ← Pick your shard
  Game.tscn          ← Core game
  GameOver.tscn      ← Death/victory screen
  HighScores.tscn    ← Local leaderboard

scripts/
  autoload/
    GameData.gd      ← Global state + shard definitions
    ScoreManager.gd  ← JSON score persistence
  Game.gd            ← Core game loop, AI, combat, rendering
  DungeonGenerator.gd← Procedural dungeon (rooms + corridors)
  Main.gd            ← Main menu
  ShardSelect.gd     ← Shard picker UI
  GameOver.gd        ← Game over screen
  HighScores.gd      ← High score table
```

All graphics drawn programmatically in GDScript — **no external assets required**.
