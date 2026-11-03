# Guild Coffers

A passive guild tax addon for **World of Warcraft: Forever**. You choose a percentage of the gold you receive, and the addon deposits it into the guild bank when you next open it. A shared guild list shows who contributes, how much, and when.

> **Status: early development.** This repository currently contains the project scaffold only. Planned features are listed below and are not built yet.

## Planned features

- Per-player tax rate, set in the addon's own window
- Automatic tracking of gold received, including inside instances
- Automatic deposit when the guild bank is opened
- Guild contributor list: who runs the addon, their rate, total donated, last donation
- Background sync between guildmates over the guild addon channel (paused while in an instance)
- Donation totals verified against the guild bank's money log; self-reported figures shown as unverified

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
