# Mayhem Pocket

Mayhem Pocket is a free, compact, ad-free desktop companion for League of Legends ARAM Mayhem. It displays current OP.GG recommendations in an interface designed to stay quick and out of the way.

## Open source app

The source for both desktop versions is available in this repository:

- [macOS app source](app-source/macos) — Swift and SwiftUI
- [Windows app source](app-source/windows) — Electron, JavaScript, HTML, and CSS

The app reads publicly accessible OP.GG recommendation pages and Riot Data Dragon artwork. It does not require a Riot login and does not access or modify the League game client. OP.GG page changes can affect data loading because this is an unofficial community app.

The website source is in the repository root. Release downloads are built from the desktop source and attached to GitHub Releases.

The downloadable Mac and Windows applications are attached to GitHub Releases rather than committed directly to the repository. This keeps the repository small and lets the page link to stable filenames.

## Release asset filenames

- `Mayhem-Pocket-v1.4.dmg`
- `Mayhem-Pocket-Windows-x64-Portable.zip`

## Website publishing

GitHub Pages should publish from the repository's root on the `main` branch.
