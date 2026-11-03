# Changelog

All notable changes to Guild Coffers are recorded here.

## [Unreleased]

### Added
- Gold tracking: your tax percentage of gold received (loot, quests, vendor sales, mail) is set aside. Gold from trades and from bank or guild bank withdrawals is not counted.
- Your own tax rate (default 10%), set in the settings window or with `/coffers rate <0-100>`.
- Automatic deposit into the guild bank shortly after you open it, confirmed by watching the gold actually leave.
- Manual deposits made while the guild bank is open are credited too.
- Settings window (`/coffers`) showing what you owe, total donated and last donation.
- `/coffers status`, `/coffers on|off`, `/coffers deposit` and `/coffers debug` (compatibility report for bug reports).
- The guild bank is detected both from game events and by hooking Blizzard's guild bank frame, so the automatic deposit still fires if this client opens the bank differently.
- `/coffers watch` logs guild bank events for 60 seconds, to show what a client does when the bank opens.
- Initial project scaffold for WoW: Forever (interface 16001).

### Not yet included
- Guild contributor list, guildmate sync and bank-log verification.
