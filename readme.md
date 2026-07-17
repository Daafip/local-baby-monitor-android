# Baby Monitor — spare Android phone + Termux + IP Webcam

Turn a spare Android phone into a Wi-Fi baby monitor with live video, live audio, a real-time
noise meter, and configurable noise alerts — viewable from any browser on your home network.

No cloud, no accounts, no apps on the viewing device. Everything stays on your LAN.

## How it works

```
  Nursery phone (Android)                          Viewing device (any browser)
 ┌──────────────────────────────┐                 ┌────────────────────────────┐
 │  IP Webcam app     :8080     │                 │  http://<phone-ip>:8081/   │
 │    /video  (MJPEG)           │                 │  monitor                   │
 │    /audio.wav|.opus|.aac     │    Wi-Fi LAN    │   • live video + audio     │
 │          ▲                   │ ◄─────────────► │   • noise meter + graph    │
 │          │ localhost         │   http :8081    │   • alerts (beep/vibrate)  │
 │  Termux: nginx     :8081     │                 │   • flash / night vision   │
 │    reverse proxy + CORS      │                 └────────────────────────────┘
 │    serves the monitor page   │
 └──────────────────────────────┘
```

Two things run on the nursery phone:

1. **[IP Webcam](https://play.google.com/store/apps/details?id=com.pas.webcam)** (Play Store) —
   streams MJPEG video and audio over HTTP on port `8080`.
2. **[Termux](https://github.com/termux/termux-app)** running **nginx** on port `8081` — a reverse
   proxy in front of IP Webcam that also serves the monitor web page.

**Why the proxy?** The monitor page analyses the audio stream with the Web Audio API to compute
noise levels. Browsers only expose raw audio data to the page when the stream is served with CORS
headers — which IP Webcam doesn't send. The nginx proxy adds those headers and serves the page from
the same origin as the streams, so the analysis (and therefore the alerts) actually works.

## Features

- **Live video** (MJPEG) and **live audio** (WAV/Opus/AAC, selectable) in any modern browser
- **Noise meter**: RMS level, peak hold, scrolling waveform, and a live frequency spectrum
- **Noise alerts**: when the level stays above an adjustable threshold for a configurable *hold
  time*, the page beeps (optional), vibrates (on phones), flashes the tab title, and glows red.
  A *cooldown* prevents alert spam
- **Loud-time counters**: how much time the noise spent above the threshold in the past
  **1 minute** and **5 minutes** — see at a glance whether fussing is building up or dying down
- **Remote camera control** from the viewer: flashlight (torch), night vision, and brightness
  (night-vision gain)
- **Mute that keeps measuring**: silence the speaker on the viewing device while the analysis and
  alerts keep running

## What you need

- A spare Android phone for the nursery (the "camera phone")
- [IP Webcam](https://play.google.com/store/apps/details?id=com.pas.webcam) from the Play Store
- [Termux](https://github.com/termux/termux-app) — install from F-Droid or the GitHub releases,
  **not** the Play Store (that build is outdated and broken)
- Optional: [Termux:Boot](https://github.com/termux/termux-boot) to auto-start the proxy after a
  reboot (must be from the same source as Termux itself)
- A viewing device (phone/laptop) on the **same Wi-Fi network**

## Setup

All commands below run on the **nursery phone**, inside Termux.

### 1. Configure IP Webcam

1. Install and open IP Webcam.
2. Recommended settings:
   - *Video preferences → Video resolution*: something modest (e.g. 640×480) — saves battery and
     bandwidth; it's a baby monitor, not a cinema.
   - *Audio mode*: enabled (any mode that isn't "disabled").
3. Scroll down and tap **Start server**. Leave the port at the default `8080`.

### 2. Install Termux and get this repo

Install Termux (F-Droid/GitHub APK), open it, then:

```sh
pkg install -y git
git clone https://github.com/Daafip/local-baby-monitor-android.git
cd local-baby-monitor-android
```

(If you downloaded the repo as a ZIP into `Downloads` instead, run `termux-setup-storage` once and
copy it from `/sdcard/Download`.)

### Optional: SSH into the phone from your computer

Typing in Termux on a phone keyboard gets old fast. You can run the remaining steps (and any later
tinkering) from a real keyboard by SSH-ing into Termux.

On the **phone**, in Termux:

```sh
pkg install -y openssh
passwd                    # set a password — Termux has none by default, and sshd refuses logins without one
sshd                      # start the SSH server (Termux uses port 8022, not 22)
ip -4 addr show wlan0     # note the phone's Wi-Fi IP
```

On the **computer** (same Wi-Fi):

```sh
ssh -p 8022 <phone-ip>
```

Termux is single-user, so the username in the login is ignored — whatever your computer sends is
fine. You land in the same shell and home directory as the Termux app itself.

Nice-to-haves:

```sh
# passwordless logins — run on the computer once the password login works:
ssh-copy-id -p 8022 <phone-ip>

# start sshd automatically after a reboot (requires Termux:Boot; run on the phone
# after step 4, which creates this boot script):
echo 'sshd' >> ~/.termux/boot/start-proxy.sh
```

> Security note: sshd only needs to run while you're administering the phone. If you leave it
> running, anyone on the Wi-Fi can try to log in — set a strong password or switch to key-only
> authentication (`PasswordAuthentication no` in `$PREFIX/etc/ssh/sshd_config`).

### 3. Install the monitor page

The nginx config serves the page from `~/www/`, so copy it there:

```sh
mkdir -p ~/www
cp www/baby-monitor-notify.html ~/www/
```

### 4. Start the proxy

```sh
bash termux_run_nginx.sh
```

The script is idempotent (safe to re-run) and does the following:

- installs `nginx` and `termux-api` via `pkg`
- backs up the stock nginx config once, then writes the reverse-proxy config to
  `$PREFIX/etc/nginx/nginx.conf`:
  - `:8081 → 127.0.0.1:8080` with CORS headers and response buffering disabled
    (buffering breaks MJPEG/audio streaming)
  - `GET /monitor` → serves `~/www/baby-monitor-notify.html`
- starts nginx (or reloads it if already running)
- takes a `termux-wake-lock` so Android doesn't kill the proxy
- installs a `~/.termux/boot/start-proxy.sh` script (used by Termux:Boot, if installed)
- prints the phone's Wi-Fi IP and the URL to open

### 5. Open the monitor

On the viewing device, browse to:

```
http://<phone-ip>:8081/monitor
```

Press **Connect**. Video should appear within a second or two and the status line should report
`Audio connected (wav)`.

> Tip: give the nursery phone a fixed IP (DHCP reservation in your router) so the URL never
> changes, and bookmark it / add it to the home screen.

## Using the monitor

| Control | What it does |
|---|---|
| audio format (`wav`/`opus`/`aac`) | Stream container for audio. `wav` is the most compatible; try another if audio fails to start |
| **mute speaker** | Silences playback on the viewing device — noise analysis and alerts keep running |
| **alert threshold** | Noise level that counts as "loud". Shown as the dashed line on the graph — set it just above the room's background noise |
| **reset peak** | Clears the peak-hold value |
| **alarm beep** | Play a triple beep on the viewing device when an alert fires |
| **vibrate** | Vibrate on alert (phones/tablets) |
| **hold time** | The level must stay above the threshold this long before an alert fires — filters out door clicks and coughs |
| **cooldown** | Minimum time between alerts |
| **🔦 flash** | Toggles the camera phone's flashlight (`/enabletorch`, `/disabletorch`) |
| **night vision** | Toggles IP Webcam's night-vision mode (`/settings/night_vision?set=on\|off`) |
| **brightness** | Night-vision gain, 1–10× (`/settings/night_vision_gain?set=…`) — takes effect while night vision is on |
| **loud 1m / 5m** | Time spent above the threshold during the past 1 / 5 minutes (`m:ss`) |

An alert = beep (if enabled) + vibration + flashing tab title + red glow around the video. Alerts
are deliberately kept on-page (no push notifications): browser push requires HTTPS and a service
worker, which is disproportionate for a LAN page — keep the tab open (screen on) on the viewing
device instead.

## Keeping it running all night

- **Plug both phones in.** Streaming video drains a battery fast.
- On the nursery phone, exclude **Termux** and **IP Webcam** from battery optimization
  (Settings → Apps → … → Battery → Unrestricted).
- The setup script already holds a Termux wake-lock.
- Install **Termux:Boot** and reboot once so the proxy auto-starts from then on.
- On the viewing device, keep the tab in the foreground with the screen on — browsers throttle
  background tabs, which delays alerts. A charger and "screen always on while charging"
  (or a guided-access/kiosk mode) works well.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Video placeholder says *video failed* | Is IP Webcam's server started? Is the port `8080`? Can you open `http://<phone-ip>:8081/video` directly? |
| *Audio failed to start* | Try another format in the dropdown (`opus` or `aac`). Check that audio isn't disabled in IP Webcam |
| Status says *Analyser reads pure silence — CORS may still be blocking* | You're probably connected to IP Webcam directly (`:8080`) instead of through the proxy (`:8081`). The proxy must add the CORS headers for analysis to work |
| Alerts never fire | Threshold too high — watch the dashed line against the red waveform and lower it until normal crying crosses it |
| Camera buttons do nothing | They POST to the proxy; check the status log line. Night-vision brightness only has a visible effect while night vision is on |
| Proxy stops after a while | Battery optimization killed Termux — see the section above |
| Config tinkering | nginx config lives at `$PREFIX/etc/nginx/nginx.conf` in Termux; `nginx -s reload` applies changes, `nginx -s stop` stops it |

## Security notes

- Everything is **plain HTTP on your LAN**: anyone on the same Wi-Fi can watch the stream and
  toggle the camera. That's usually fine on a home network — but treat it that way.
- Do **not** port-forward `8080`/`8081` to the internet.
- If you need it off your main network, put both devices on a separate IoT/guest Wi-Fi that can't
  reach the internet-facing side of your LAN.

## Repository layout

```
termux_run_nginx.sh            one-shot setup: nginx reverse proxy + boot script (runs in Termux)
www/baby-monitor-notify.html   the monitor page (single self-contained HTML file, no dependencies)
```
