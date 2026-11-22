# Windows migration audit (21 November 2026)

This audit compares `xynk-desktop` with the existing `windows_app` and Android client. It separates code presence, live API checks, and visual checks.

## Verified

- Demo sign-in and the account/library/room/social read endpoints returned HTTP 200.
- In a disposable demo room: create, join, watch state, queue, participants, chat, members, LiveKit media token, queue add, queue play, and chat send succeeded. The room was removed after the test.
- The packaged Windows app opened the YouTube site in its provider area. Clicking a result created a room and played the stream with XYNK controls. Play resumed the video and advanced the clock.
- TypeScript type checking, Vite bundling, and Electron packaging passed. The rebuilt app restored the signed-in session and visually opened Settings, the own profile, and the edit profile dialog.

## Present in desktop source, pending multi-client visual tests

- Room privacy and queue mode settings, member permissions, host/co-host leadership, invites, skip vote, queue voting.
- LiveKit microphone, speaker, speaking indicators, per-person listening, and screen source selection/share.
- Google and X login, provider session persistence, profile edit/avatar, library history/likes/gallery, direct chat and friends.
- Public MP4/HLS selection. HLS now uses Shaka instead of a native `<video>` source.

## Not yet at feature parity

- Personal queue reorder and removal controls are absent from the React UI though the backend routes exist.
- Block/unblock controls, social notification inbox, direct-message file attachments, and profile connections/interests editing are absent.
- Generic Web media detection is less complete than the old Windows capture script for embedded players and sites whose stream is hidden behind player interaction.
- Crunchyroll episode selection, URL queueing, device-local token and license requests, and Shaka room playback are implemented. Actual protected video frames still require signed-in, visual verification on Windows. Netflix and Prime Video open in provider browsing, but their room playback is not implemented.
- The `npm run lint` script cannot run because ESLint is not installed/configured. TypeScript type checking passes.

No claim of complete Windows/Android parity should be made until the missing controls and two-client voice/screen-share tests are completed.
