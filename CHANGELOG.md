# Changelog

All notable changes to Guild Coffers are recorded here.

## [Unreleased] (alpha)

### Added
- Only genuine earnings are taxed: looted gold (including your share of group loot), vendor sales and auction house sales. Gold mailed by players, including your own characters, outbid refunds, trades, quest rewards and other refunds are no longer taxed.
- "Deposit once owed" minimum (default 1g, 0 = every time): the automatic deposit waits until this much is owed, so the guild bank log is not filled with tiny deposits. "Deposit now" ignores it. Also `/coffers min 50s`.
- Guild rate: officers write `[coffers:N]` in the guild info text and members follow it, unless they set their own rate ("Use guild rate" or `/coffers rate guild` to switch back). Members are told when the guild rate changes.
- Donation history: deposits, withdrawals and repairs from the guild bank log are recorded and shared between guildmates, so history builds up beyond what the game's log holds. Entries are matched so the same deposit is never counted twice. An entry is verified when you saw it yourself or two different guildmates reported it. Guildmates who log in later catch up automatically. A possible gap is flagged if a new log does not overlap the history.
- Leaderboard shows every guild member (from the roster), with verified Paid in, Taken out and their Ratio, plus each addon user's rate and reported total. Scroll with the mouse wheel for big guilds.
- Officer-only Promotions view (`/coffers promote`, or the Promotions button on the leaderboard): members below you whose verified deposits reach an amount you set (any, or a gold amount) in a window you set (days, or all time), each with a one-click Promote button. Nothing is promoted automatically.
- Fixed: the leaderboard showed you twice when the guild bank log used your full name ("Leeroy Mcbiff") and the game gave only your first name. Full names now come from the guild roster, where your own entry is found by your character ID (GUID), so this works for every player. Each addon user also sends their full name with their totals (checked against the name the game gives for them, so nobody can claim another player's name). Guildmates sharing a first name stay separate. `/coffers debug` shows the full name found.
- The deposit destination is now a dropdown ("The guild bank" / "My own bank (private)"), so exactly one is selected and switching back is one step. If a client cannot build the dropdown, two linked options are shown instead.
- Opening the guild bank while set to your own bank now prints a reminder instead of doing nothing.
- Sharing with the guild is no longer a separate option: it follows the deposit choice. Depositing to the guild bank (the default) shares your rate and donations for the leaderboard. "My own bank" keeps everything private.
- `/coffers defaults` puts every setting back to its default (guild bank, 10% tax, tracking on). Your tax records are kept.
- Choose where tax is deposited: the guild bank (default) or your own bank (the Warband bank), with a tick box or `/coffers dest guild|bank`. Own-bank savings are tracked separately, are not guild donations, and nothing is shared with the guild while it is on.
- `/coffers log`: at the guild bank, reports how many entries its money log holds and of what kind, so the history feature can be designed around real data.
- Fixed: the leaderboard opened behind the Options window when started from the settings panel. It now opens on top.
- Guild leaderboard (`/coffers board` or the Leaderboard button): guildmates running the addon share their rate and donation totals over the guild addon channel, and the guild bank money log is read to mark players whose deposits it shows as Verified. Totals without a matching log entry are shown as Unverified. Choosing "My own bank" keeps your totals private.
- Hover help on "Always keep" explains how to type an exact amount.
- "Always keep" minimum: a deposit never takes you below an amount you choose (gold, silver or copper), set with buttons or `/coffers reserve 5g 50s`. Anything held back stays owed. Off by default.
- "Reset amount owed" button (two clicks to confirm) and `/coffers reset`; lifetime donated is kept.
- Gold tracking: your tax percentage of gold received (loot, quests, vendor sales, mail) is set aside. Gold from trades and from bank or guild bank withdrawals is not counted.
- Your own tax rate (default 10%), set in the settings window or with `/coffers rate <0-100>`.
- Automatic deposit into the guild bank shortly after you open it, confirmed by watching the gold actually leave.
- Manual deposits made while the guild bank is open are credited too.
- Settings panel in the game's AddOns settings (opened with `/coffers`), with fallbacks for older settings menus and a standalone window (`/coffers window`).
- On-screen tax counter showing how much gold to keep aside and how much has been collected since the last deposit. Drag to move, lock it in settings, right-click to open settings, `/coffers hud` to show or hide it.
- Tracking is on and the rate is 10% by default.
- Amounts under one copper are shown as "<1c" instead of "0c", and the counter shows what has been collected, so tiny early loot is visibly tracked. Fractions build up until a whole copper can be deposited.
- Fixed: the first time the window opened its status lines and tick box were blank.
- The tax rate in the settings panel is now plain text (10% by default) changed with -5, -, +, +5 buttons or `/coffers rate <0-100>`. The typed-in box could appear empty on the real client, so it was removed.
- Optional chat summary of the tax, e.g. "+5c received, tax <1c (total to keep: 3c)". Gold from loot and quests is reported straight away. Gold received while a vendor or mailbox window is open is added up and reported once, when you close the window. Off by default; turn it on in settings ("Show tax in chat") or with `/coffers chat`.
- The settings panel shows the addon version, so testers can tell which build they are running.
- Each interface part is built separately, so one failing piece is reported once and the rest keep working.
- `/coffers status`, `/coffers on|off`, `/coffers deposit` and `/coffers debug` (compatibility report for bug reports).
- The guild bank is detected both from game events and by hooking Blizzard's guild bank frame, so the automatic deposit still fires if this client opens the bank differently.
- `/coffers watch` logs guild bank events for 60 seconds, to show what a client does when the bank opens.
- Initial project scaffold for WoW: Forever (interface 16001).
