# Changelog

All notable changes to Guild Coffers are recorded here.

## [Unreleased] (alpha)

### Added
- The deposit destination is now a dropdown ("The guild bank" / "My own bank (private)"), so exactly one is selected and switching back is one step. If a client cannot build the dropdown, two linked options are shown instead. "Share my donations" sits below it.
- Opening the guild bank while set to your own bank now prints a reminder instead of doing nothing.
- Fixed: "Share my donations" and "Deposit to my own bank" could both look ticked. In own-bank mode the share box is now greyed out and unticked, and your choice returns when you switch back to the guild bank.
- Choose where tax is deposited: the guild bank (default) or your own bank (the Warband bank), with a tick box or `/coffers dest guild|bank`. Own-bank savings are tracked separately, are not guild donations, and nothing is shared with the guild while it is on.
- `/coffers log`: at the guild bank, reports how many entries its money log holds and of what kind, so the history feature can be designed around real data.
- Fixed: the leaderboard opened behind the Options window when started from the settings panel. It now opens on top.
- Guild leaderboard (`/coffers board` or the Leaderboard button): guildmates running the addon share their rate and donation totals over the guild addon channel, and the guild bank money log is read to mark players whose deposits it shows as Verified. Totals without a matching log entry are shown as Unverified. Sharing can be turned off (`/coffers share`).
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

### Not yet included
- Shared donation and withdrawal history from the guild bank log (needs a guild to test; `/coffers log` is the first step).
- Officer-only "Ready for promotion" list with a one-click promote, using a verified-deposit amount set in the UI (0 = any verified donation).
- Guild roster view, so non-donors show on the leaderboard.
