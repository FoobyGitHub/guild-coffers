# Guild Coffers

A simple, passive guild tax for **World of Warcraft: Forever**. Choose a percentage, and Guild Coffers keeps count of the gold you earn and donates your share to the guild bank when you open it.

> **Beta.** Tested in the live client: tracking, the guild bank deposit, the leaderboard, the promotions view and the bank log. Not yet tested in the live client: quest and auction income, the guild rate, clicking Promote, and history sharing between several players. Please report any problems.

## What it does

- Taxes the gold you **earn**: loot (including your share of group loot), quest rewards, vendor sales and auction house sales. Trades, mail from players (including your own characters), auction outbid refunds and bank withdrawals are not taxed.
- Deposits what you owe when you open the guild bank, and never touches your **spending money**.
- Shows a guild **leaderboard** of who pays in and who takes out, checked against the guild bank's own log.
- Gives officers a **Promotions** list of members whose deposits reach an amount they choose, with a one-click Promote button.

## Settings

Open them with `/coffers`, or ESC → Options → AddOns → Guild Coffers.

| Setting | Default |
|---|---|
| Track gold and tax it | On |
| Tax rate | Your guild's rate if officers set one, otherwise 10% |
| Spending money | None |
| Min. deposit | 1g |
| Show the tax counter on screen | On |
| Lock the counter's position | Off |
| Show tax in chat | Off |

- **Spending money:** gold you keep for playing (training, repairs, travel). A deposit never takes you below it; anything held back stays owed for next time.
- **Min. deposit:** the automatic deposit waits until you owe at least this much, so the guild bank log isn't filled with tiny deposits. "Deposit now" deposits any amount.
- **Guild rate:** officers set it by writing `[coffers:10]` (any number 0-100) in the guild info text. Members follow it unless they change their own rate; "Use guild rate" switches back.
- **Counter:** how much to keep aside, and the gold collected since your last deposit. Drag to move, right-click for settings.
- **Chat:** your tax after each gain; one summary per vendor or mailbox visit.
- **Reset amount owed:** sets what you owe back to zero (click twice). Your donated total is kept.

## Leaderboard and promotions

- **Paid in / Taken out:** from the guild bank log. Everyone who opens the guild bank records what the log shows and shares it with guildmates, so the history builds up beyond what the game keeps. An entry counts once it is **verified**: you saw it yourself, or two guildmates reported it. Repairs are not counted as taken out.
- **Ratio:** paid in as a share of everything they moved. 100% = only paid in, 50% = took out as much as they paid in.
- **Reported:** each player's own addon total. Not verified.
- **Promotions (officers and guild master):** choose "verified deposits of at least" (any, or an amount) and "in the last" (days, or all time). Only deposits you saw yourself or that three guildmates reported count. Promote moves a member up one rank, only when you click it. What each rank can do stays in the guild's own settings.
- **Sharing:** your rate, totals and what the bank log showed you are sent to your guild over the addon channel.

## Commands

| Command | What it does |
|---|---|
| `/coffers` | Open the settings |
| `/coffers rate <0-100>` / `rate guild` | Set your own rate, or follow the guild's |
| `/coffers spending <amount>` | Spending money, e.g. `50g` or `5g 50s` (`0` for none) |
| `/coffers min <amount>` | Minimum automatic deposit, e.g. `1g` (`0` = every time) |
| `/coffers on` / `off` | Turn tracking on or off |
| `/coffers hud` / `chat` | Show or hide the counter / chat summary |
| `/coffers status` | What you owe and have donated |
| `/coffers deposit` | Deposit now (guild bank must be open) |
| `/coffers board` | Guild leaderboard |
| `/coffers promote` | Officers: members ready for promotion |
| `/coffers reset` | Set the amount owed back to zero |
| `/coffers defaults` | Put every setting back to its default |
| `/coffers window` | Settings in their own window |
| `/coffers debug` / `log` / `watch` | Reports for bug reports |

## Installing and reporting problems

Install from CurseForge (choose the **Forever** version), or copy this folder into `Interface/AddOns/GuildCoffers/`. If something goes wrong, please [open an issue](https://github.com/FoobyGitHub/guild-coffers/issues) with any error text and the output of `/coffers debug`.

## Licence

MIT, see [LICENSE](LICENSE). Free, with no ads and no donation requests. No third-party code is used.

*Guild Coffers is an independent addon and is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.*
