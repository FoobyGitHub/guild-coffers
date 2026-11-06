# Changelog

All notable changes to Guild Coffers are recorded here.

## v0.4.3-beta (2026-11-06)

First public version (beta).

### Tax
- Takes your chosen share of gold you earn: looted gold (including your share of group loot), quest rewards, vendor sales and auction house sales. Trades, mail from players (including your own characters), auction outbid refunds and bank withdrawals are not taxed.
- Tax rate 10% by default. Officers can set a guild rate by writing `[coffers:N]` in the guild info text; members follow it unless they choose their own rate.
- Deposits what you owe automatically when you open the guild bank, once you owe at least the minimum deposit (1g by default). "Deposit now" deposits any amount. Deposits you make by hand while the guild bank is open are credited too.
- Spending money: gold you keep for playing; a deposit never takes you below it.
- Optional, where the game has an account (Warband) bank: deposit there instead, privately. Forever has no account bank yet, so the option stays hidden until it does.
- "Reset amount owed" (two clicks to confirm).

### Guild
- Leaderboard of every guild member: verified Paid in and Taken out from the guild bank log, their ratio as a percentage, and each addon user's rate and reported total.
- Donation history from the guild bank log, shared between guildmates so it builds up beyond what the game's log holds. Verified when you saw it yourself or two guildmates reported it. Limits on how much any one guildmate can add.
- Officers: a Promotions list of members whose deposits (seen by you, or reported by three guildmates) reach an amount and time window you choose, each with a one-click Promote button. Nothing is promoted automatically.

### Interface
- Settings in the game's AddOns options (`/coffers`), an on-screen counter of what to keep aside, and an optional chat summary (one line per vendor or mailbox visit).
- `/coffers debug`, `/coffers log` and `/coffers watch` for bug reports.
