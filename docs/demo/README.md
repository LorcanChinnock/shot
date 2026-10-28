# Demo app

Acme Support is a made-up support and analytics app. Shot's screenshots and recordings in `docs/media/` show it, so they need no real data, people or brands. It isn't part of Shot: `make build`, `make test` and `make lint` don't touch it.

```sh
cd docs/demo
swift run ShotDemo --scene ticket,chat --appearance light
```

- `--scene` opens one window per scene, `ticket` if you leave it out, left to right, with the group centred on the main screen:
  - `ticket`: a support ticket with an order to point at and a customer email to redact. Assign opens a picker, and Reply shows a toast.
  - `dashboard`: a revenue report. The chart grows in and the order list fills in. Tickets in the sidebar opens a ticket list and Reports comes back, so a recording has a detour to cut.
  - `chat`: a `#checkout` channel to paste a screenshot or text into. Click the message box, press ⌘V, then Return.
  - `article`: a help centre article several screens tall, with a toolbar that stays at the top, the sidebar at the left and a floating button over the text, to scroll through for the Capture Scrolling Area media.
- `--appearance light` or `dark` overrides the system appearance. Shot's own windows follow Settings › General › Appearance, so set it to match.
- `--clock HH:MM` moves every time in the scenes so the message you send in the chat is at that time. Pass the current time, such as `--clock $(date +%H:%M)`, so the times match the capture's file name. Without it, the message is at 09:54.
- ⌘R replays the animations.

The windows have fixed sizes (960×600 pt, and 380×600 pt for chat) and the data is fixed, with no clocks or randomness, so a re-shoot lines up with the last one.
