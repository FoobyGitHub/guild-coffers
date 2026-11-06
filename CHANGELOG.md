# Changelog

All notable changes to Guild Coffers are recorded here.

## [Unreleased]

First public version.

### Tax
- Takes your chosen share of gold you genuinely earn: looted gold (including your share of group loot), vendor sales and auction house sales. Trades, mail from players (including your own characters), auction outbid refunds, quest rewards and bank withdrawals are not taxed.
- Tax rate 10% by default. Officers can set a guild rate by writing `[coffers:N]` in the guild info text; members follow it unless they choose their own rate.
- Deposits what you owe automatically when you open the guild bank, once you owe at least the minimum deposit (1g by default). "Deposit now" deposits any amount. Deposits you make by hand while the guild bank is open are credited too.
- "Always keep": a deposit never takes you below an amount you choose.
- Optional: deposit to your own bank (the Warband bank) instead. Private: nothing is shared with the guild.
- "Reset amount owed" (two clicks to confirm).

### Guild
- Leaderboard of every guild member: verified Paid in and Taken out from the guild bank log, their ratio, and each addon user's rate and reported total.
- Donation history from the guild bank log, shared between guildmates so it builds up beyond what the game's log holds. Verified when you saw it yourself or two guildmates reported it. Limits on how much any one guildmate can add.
- Officers: a Promotions list of members whose deposits (seen by you, or reported by three guildmates) reach an amount and time window you choose, each with a one-click Promote button. Nothing is promoted automatically.

### Interface
- Settings in the game's AddOns options (`/coffers`), an on-screen counter of what to keep aside, and an optional chat summary (one line per vendor or mailbox visit).
- `/coffers debug`, `/coffers log` and `/coffers watch` for bug reports.
