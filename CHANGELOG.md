# Changelog

All notable changes to Guild Coffers are recorded here.

## [Unreleased]

### Added
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
- Guild contributor list, guildmate sync and bank-log verification.
