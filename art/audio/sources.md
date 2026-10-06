# Audio sources

Every sound file the game loads has a row here: nothing enters `assets/audio/` without one. Allowed:
Sonniss GDC Game Audio Bundle, Kenney (CC0), Freesound (CC0, or CC-BY credited). Nothing NC, nothing
from BBC Sound Effects, no generated sounds.

**CC-BY rows must also be added to `SoundBank.CREDITS` (`scripts/core/sound_bank.gd`)**, which the
main menu's credits screen shows.

Originals stay outside the repo (`~/Audio/<library>/`); `art/audio/process.sh` turns them into the
OGGs, and `art/audio/batch.txt` lists which original became which file, so all of them can be made
again with `art/audio/process.sh --batch art/audio/batch.txt`.

| File | Origin | Author | Licence | URL |
|---|---|---|---|---|
| sfx/axe_1.ogg | Kenney RPG Audio, `chop.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| sfx/axe_2.ogg | Kenney Impact Sounds, `impactWood_heavy_000.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/axe_3.ogg | Kenney Impact Sounds, `impactWood_heavy_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/axe_4.ogg | Kenney Impact Sounds, `impactWood_heavy_002.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/hammer_1.ogg | Kenney Impact Sounds, `impactWood_light_000.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/hammer_2.ogg | Kenney Impact Sounds, `impactWood_light_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/hammer_3.ogg | Kenney Impact Sounds, `impactWood_light_002.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/hammer_4.ogg | Kenney Impact Sounds, `impactWood_light_003.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/tree_fall_1.ogg | Kenney Impact Sounds, `impactPlank_medium_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/tree_fall_2.ogg | Kenney Impact Sounds, `impactPlank_medium_002.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/goods_down_1.ogg | Kenney Impact Sounds, `impactSoft_medium_000.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/goods_down_2.ogg | Kenney Impact Sounds, `impactSoft_medium_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/goods_down_3.ogg | Kenney Impact Sounds, `impactSoft_medium_002.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| sfx/goods_down_4.ogg | Kenney RPG Audio, `dropLeather.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| sfx/goods_up_1.ogg | Kenney RPG Audio, `handleSmallLeather.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| sfx/goods_up_2.ogg | Kenney RPG Audio, `handleSmallLeather2.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| sfx/build_done.ogg | Kenney Impact Sounds, `impactBell_heavy_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| ui/click.ogg | Kenney Interface Sounds, `click_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| ui/placed.ogg | Kenney Interface Sounds, `drop_002.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| ui/toast.ogg | Kenney Interface Sounds, `bong_001.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| ui/toast_ok.ogg | Kenney Interface Sounds, `maximize_008.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| ui/toast_fail.ogg | Kenney Interface Sounds, `question_004.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| ui/buy.ogg | Kenney RPG Audio, `handleCoins2.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| ui/sell.ogg | Kenney RPG Audio, `handleCoins.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| music/menu_theme.ogg | own composition `art/audio/music/menu_theme.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
| music/menu_theme_b.ogg | own composition `art/audio/music/menu_theme_b.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
| music/morning_rows.ogg | own composition `art/audio/music/morning_rows.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
| music/duck_pond_waltz.ogg | own composition `art/audio/music/duck_pond_waltz.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
| music/long_furrow.ogg | own composition `art/audio/music/long_furrow.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
| music/market_day.ogg | own composition `art/audio/music/market_day.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
| music/evening_barn.ogg | own composition `art/audio/music/evening_barn.abc`, rendered with GeneralUser GS v2.0.3 | Tominek (soundfont: S. Christian Collins) | own; soundfont free for commercial music | https://www.schristiancollins.com |
