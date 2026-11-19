# Perk Keeper

An iPhone app that makes sure no card perk goes unused: statement credits that reset monthly, quarterly or yearly, and card-linked offers (Amex Offers, Chase Offers, Citi Merchant Offers, BankAmeriDeals, My Wells Fargo Deals, U.S. Bank cash-back deals). Liquid Glass UI on iOS 26, frosted-glass fallback on iOS 17–18.

## What it does

- **Any card.** Pick a card from the built-in list (Amex Platinum and Gold, Chase Sapphire Reserve/Preferred, Venture X, Delta, Hilton and Marriott Amex cards, Robinhood Gold and Platinum, Freedom Flex, Discover it) and its credits are filled in, or add any card and your own credits. Benefits were checked in November 2026 and everything can be edited.
- **Credits.** Each credit knows its reset rule (monthly, quarterly, half-year, calendar year, card year, every few years, one-time) and odd months like Uber Cash's $35 December. Mark it used in one tap, log partial use, see what's left, and get reminded before it resets. Credits you don't use can be hidden from totals and reminders.
- **Offer sync.** Opens your bank's own offers page in a built-in browser where you sign in normally. Perk Keeper reads every offer on the page (merchant, reward, value, minimum spend, expiration, status) and compares it with the last sync:
  - **New** offers are flagged, with a notification after the sync.
  - **To add**: offers you haven't added yet.
  - **Added**: offers on your card you haven't used, with reminders before they expire.
  - **Used**: offers your bank shows as redeemed, plus any you mark used. Added offers that disappear from the bank's added list before they expire are flagged so you can confirm you used them.
- **Add all / auto-add.** One tap presses each offer's own Add button, one at a time at a human pace, going back for you on banks (Chase) that open a page after each add. Turn on auto-add to have every sync add everything new. Skip words (e.g. `lululemon, oura`) leave matching offers alone. It never adds one offer to several cards.
- **Today screen and widget.** What's left to use this period, what resets next, new and expiring offers, and deadlines (sign-up or bank bonuses with a spending goal). The home-screen and lock-screen widget shows the same "use it or lose it" list.
- **Private.** No accounts, no server. Data is one JSON file on the iPhone, with an automatic copy in Files → On My iPhone → Perk Keeper (included in iCloud Backup) and export/restore. Optional Face ID lock.

## About automatic adding and Amex

American Express's Amex Offers terms prohibit adding offers with "automated tools, software, scripts, bots" and say offers obtained that way may not be honored. Add all and auto-add are exactly that, so the app asks before using them on Amex and lets you keep auto-add on for other banks and off for Amex. Reading your offers (the list, new/added/used tracking and reminders) doesn't add anything.

## Why "new offer" alerts come from syncs

Banks don't give apps a way to read card-linked offers in the background, and keeping your bank password on a server to log in for you would be a security risk. So Perk Keeper reminds you to sync every few days (you choose how often), and each sync is quick: sign in (saved passwords and Face ID work), the app reads the page, adds what's new if you want, and tells you what changed.

## How the sync works

- `Resources/offer-engine.js` runs in the built-in browser in an isolated script world, so the bank's own scripts can't see it and it can't see the bank's. It never reads form fields. It finds offer tiles by their Add/Added/Redeemed controls and expiration text, reads each tile, and clicks one Add button only when the app asks.
- `Resources/adapters.json` holds each bank's offers page address, CSS selectors and text patterns. It's data, not code. The app downloads newer versions from this repo (`main` branch), so when a bank changes its website the fix ships by editing this file, without a new build.
- **Page diagnostics** (sync browser → ••• menu) makes an outline of the page with account numbers and emails masked. Paste it into an issue or a chat to get selectors updated.

## Build and install

Every push to `main` runs three jobs on GitHub Actions:

1. **Offer engine tests**: mock Amex, Chase, generic-bank and login pages in Chromium and WebKit (`Tests/engine/run.mjs`).
2. **Build unsigned IPA**: XcodeGen + Xcode 26, published as the latest release. Sign and install it with your sideloading tool. The IPA carries an ad-hoc signature with the App Group entitlement, so tools that keep entitlements give the widget its data.
3. **Simulator screenshots**: runs the app with sample data (`-demo`) and the practice sync page (`-demoSync`), uploaded as the `screenshots` artifact.

Run the engine tests locally with `cd Tests/engine && npm install && npx playwright install chromium && node run.mjs`.

## Links

- `perkkeeper://sync` opens the sync screen (handy for a Shortcuts automation).
- `perkkeeper://offers`, `perkkeeper://credits` open those tabs.
