# Guild Coffers

A simple, passive guild tax for **World of Warcraft: Forever**. Choose a percentage, and Guild Coffers keeps count of the gold you receive and donates your share to the guild bank when you open it.

> **Alpha.** The guild bank deposit and the vendor/mailbox summary have not been tested in the live client yet. Please report any problems.

## What it does

- Tracks gold from loot, quests, vendors and mail, and works out your share.
- Deposits what you owe when you open the guild bank. Gold you deposit by hand while it is open is credited too.
- Never takes you below the minimum you set: a deposit stops at your "Always keep" amount and the rest stays owed for next time.
- Ignores trades and gold you take out of a bank.

## Settings

Open them with `/coffers`, or ESC → Options → AddOns → Guild Coffers.

| Setting | Default |
|---|---|
| Track gold and tax it | On |
| Tax rate | 10% (change with -5, -, +, +5) |
| Always keep (minimum gold) | None (buttons, or `/coffers reserve 100g`) |
| Show the tax counter on screen | On |
| Lock the counter's position | Off |
| Show tax in chat | Off |

- **Always keep:** a deposit never leaves you with less than this. Enter an exact amount in gold, silver or copper, e.g. `/coffers reserve 5g 50s`.
- **Reset amount owed:** sets what you owe back to zero (click twice to confirm). Your lifetime donated total is kept.
- **Counter:** shows how much to keep aside and the gold collected since your last deposit. Drag it to move it, right-click to open settings.
- **Chat:** reports your tax after each gain. At a vendor or mailbox it waits and gives one summary when you close the window.

## Commands

| Command | What it does |
|---|---|
| `/coffers` | Open the settings |
| `/coffers rate <0-100>` | Set your tax percentage |
| `/coffers reserve <amount>` | Gold to always keep, e.g. `100g` or `5g 50s` (`0` for none) |
| `/coffers reset` | Set the amount owed back to zero |
| `/coffers on` / `off` | Turn tracking on or off |
| `/coffers hud` | Show or hide the counter |
| `/coffers chat` | Show or hide the chat summary |
| `/coffers status` | Show what you owe and have donated |
| `/coffers deposit` | Deposit now (guild bank must be open) |
| `/coffers debug` | Compatibility report, handy for bug reports |

## Planned

A guild list showing who uses the addon, their rate and donations, synced between guildmates.

## Installing and reporting problems

Install from CurseForge (choose the **Forever** version), or copy this folder into your `Interface/AddOns/GuildCoffers/` folder. If something goes wrong, please open an issue with any error text and the output of `/coffers debug`.

## Licence

MIT, see [LICENSE](LICENSE). Free, with no ads and no donation requests. No third-party code is used.

*Guild Coffers is an independent addon and is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.*
