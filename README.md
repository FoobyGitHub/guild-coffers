# Guild Coffers

A simple, passive guild tax for **World of Warcraft: Forever**. Choose a percentage, and Guild Coffers keeps count of the gold you receive and donates your share to the guild bank when you open it.

> **Alpha.** The guild bank deposit has been tested in the live client. Donation history sharing, the promotion helper and own-bank deposits have not been tested yet. Please report any problems.

## What it does

- Tracks gold from loot, quests, vendors and mail, and works out your share.
- Deposits what you owe when you open the guild bank (or, if you choose, your own bank). Gold you deposit by hand while it is open is credited too.
- Never takes you below the minimum you set: a deposit stops at your "Always keep" amount and the rest stays owed for next time.
- Shows a guild leaderboard of every member: what they have paid in and taken out of the guild bank (verified from the bank log), the ratio between the two, and each addon user's rate and reported total.
- Keeps a donation history from the guild bank log, shared between guildmates, so it builds up even though the game's log only holds recent entries.
- Officers get a **Promotions** list of members whose verified deposits reach an amount they choose, with a one-click Promote button.
- Ignores trades and gold you take out of a bank.

## Settings

Open them with `/coffers`, or ESC → Options → AddOns → Guild Coffers.

| Setting | Default |
|---|---|
| Track gold and tax it | On |
| Tax rate | 10% (change with -5, -, +, +5) |
| Always keep (minimum gold) | None (buttons, or `/coffers reserve 100g`) |
| Deposit to | The guild bank (or "My own bank") |
| Show the tax counter on screen | On |
| Lock the counter's position | Off |
| Show tax in chat | Off |

- **Always keep:** a deposit never leaves you with less than this. Enter an exact amount in gold, silver or copper, e.g. `/coffers reserve 5g 50s`.
- **Reset amount owed:** sets what you owe back to zero (click twice to confirm). Your lifetime donated total is kept.
- **Own bank:** for players without a guild, or who prefer to save. Tax is deposited into your own bank (the Warband bank) when you open it. It is kept out of the guild leaderboard and nothing is shared while this is on. `/coffers dest guild` or `/coffers dest bank` also switch it.
- **Leaderboard sharing:** when depositing to the guild bank, your tax rate, total donated, number of deposits and last donation date are sent to your guild over the addon channel, so officers can see who contributes. Choose "My own bank" to keep everything private.
- **Counter:** shows how much to keep aside and the gold collected since your last deposit. Drag it to move it, right-click to open settings.
- **Chat:** reports your tax after each gain. At a vendor or mailbox it waits and gives one summary when you close the window.

## Commands

| Command | What it does |
|---|---|
| `/coffers` | Open the settings |
| `/coffers rate <0-100>` | Set your tax percentage |
| `/coffers reserve <amount>` | Gold to always keep, e.g. `100g` or `5g 50s` (`0` for none) |
| `/coffers reset` | Set the amount owed back to zero |
| `/coffers dest guild` / `bank` | Deposit to the guild bank (default) or your own bank |
| `/coffers log` | At the guild bank: report what its money log holds (for bug reports) |
| `/coffers board` | Open the guild leaderboard |
| `/coffers promote` | Officers: members ready for promotion |
| `/coffers defaults` | Put every setting back to its default (guild bank, 10%) |
| `/coffers on` / `off` | Turn tracking on or off |
| `/coffers hud` | Show or hide the counter |
| `/coffers chat` | Show or hide the chat summary |
| `/coffers status` | Show what you owe and have donated |
| `/coffers deposit` | Deposit now (guild bank must be open) |
| `/coffers debug` | Compatibility report, handy for bug reports |

## Leaderboard and promotions

- **Paid in / Taken out:** from the guild bank log. Each player who opens the guild bank records what the log shows and shares it with guildmates, and everyone merges it into one history. An entry counts once it is **verified**: you saw it in the log yourself, or two different guildmates reported it. Repairs are not counted as taken out.
- **Ratio:** paid in divided by taken out (green at 1 or more).
- **Reported:** the total each player's own addon reports. Not verified.
- **History:** starts when the first guildmate runs the addon. If nobody opens the guild bank for a long time, older activity can be missed; the leaderboard says when that may have happened.
- **Promotions (officers and guild master):** set "verified deposits of at least" (any, or an amount) and "in the last" (days, or all time). Members below you who qualify are listed with a Promote button, which moves them up one rank. Nothing is promoted automatically, and what each rank can do stays in the guild's own rank and bank settings.

## Installing and reporting problems

Install from CurseForge (choose the **Forever** version), or copy this folder into your `Interface/AddOns/GuildCoffers/` folder. If something goes wrong, please open an issue with any error text and the output of `/coffers debug`.

## Licence

MIT, see [LICENSE](LICENSE). Free, with no ads and no donation requests. No third-party code is used.

*Guild Coffers is an independent addon and is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.*
