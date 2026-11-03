# Guild Coffers

A passive guild tax addon for **World of Warcraft: Forever**. You choose a percentage of the gold you receive, and the addon deposits it into the guild bank when you next open it. A shared guild list shows who contributes, how much, and when.

> **Status: early test build.** Personal tax tracking and deposits are built but have only been tested against a simulated client so far, not the real Forever client. The guild features are planned and not built yet.

## What works now

- Your own tax rate (default 10%), set in the window or with `/coffers rate <0-100>`
- Tracking of gold received: loot, quests, vendor sales and mail. Trades and bank or guild bank withdrawals are not counted.
- Automatic deposit shortly after you open the guild bank. The addon confirms the gold really left, and warns you if the client blocks the deposit.
- Manual deposits made while the guild bank is open are credited too.
- Window (`/coffers`) showing what you owe, total donated and last donation.

## Commands

| Command | What it does |
|---|---|
| `/coffers` | Open or close the window |
| `/coffers rate <0-100>` | Set your tax percentage |
| `/coffers on` / `off` | Turn tracking on or off |
| `/coffers status` | Show what you owe and have donated |
| `/coffers deposit` | Deposit now (guild bank must be open) |
| `/coffers debug` | Print a compatibility report to include in bug reports |

## Planned features

- Guild contributor list: who runs the addon, their rate, total donated, last donation
- Background sync between guildmates over the guild addon channel (paused while in an instance)
- Donation totals verified against the guild bank's money log; self-reported figures shown as unverified

## Development

The logic is tested against a fake WoW API under Lua 5.1: `pip install lupa` then `python3 tests/run.py`. This catches logic errors but is not a substitute for testing in the real client.

## Compatibility

- WoW: Forever client 1.60.1 (interface 16001). Forever is in beta and its API may change.
- Not a Classic Era or Retail addon.

## Installation

Install from CurseForge (choose the **Forever** version), or copy this folder into `World of Warcraft/_classic_beta_/Interface/AddOns/GuildCoffers/`.

## Reporting problems

Open an issue and include any Lua error text and your client version.

## Licence and policy

MIT licence, see [LICENSE](LICENSE). Free, no premium features, no ads, and no in-game donation requests, in line with Blizzard's UI Add-On Development Policy.

## Credits

No third-party code is used. Other guild tithe addons exist for Retail and Classic and were reviewed for context only; none of their code is reused here.

*Guild Coffers is an independent addon and is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft is a trademark of Blizzard Entertainment, Inc.*
