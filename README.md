# Vibe Coding Magic Button

Turn your iPhone into a wireless microphone and hotkey trigger for your Mac — over Wi-Fi, with zero apps to install on the phone.

## What It Does

Open a webpage on your iPhone, tap a button, and:
1. **A hardware-level keypress** is sent to your Mac (via Karabiner VirtualHID)
2. **Your phone's microphone audio** streams to your Mac and plays through a USB audio device

This was built to remotely trigger [Typeless](https://typeless.so) (a voice-to-text app) from anywhere in the house — or even remotely via [Tailscale](https://tailscale.com). Typeless only accepts hardware HID keypresses and physical audio devices, so this project uses two tricks to satisfy those requirements.

## How It Works

```
iPhone Safari                          Mac
┌──────────────────┐                  ┌──────────────────────────────┐
│  Web page (HTTPS) │   HTTP POST     │  Node.js Server (:2000)      │
│                  │ ─────────────→   │                              │
│  [🎤 Tap to Talk] │  /key/start     │  vhid_key → Karabiner VHID  │
│                  │  /key/stop       │  → macOS treats as real key  │
│                  │                  │                              │
│  getUserMedia()  │  /audio (PCM)    │  sox → USB sound card output │
│  ScriptProcessor │ ─────────────→   │  → loopback cable            │
│                  │                  │  → USB sound card input      │
│                  │                  │  → macOS treats as real mic  │
└──────────────────┘                  └──────────────────────────────┘
```

### The Key Trick
The Mac-side C helper (`vhid_key`) communicates with Karabiner's VirtualHIDDevice daemon via Unix socket to inject keypresses at the IOKit HID layer. macOS sees these as real hardware keyboard events.

### The Audio Trick
A cheap USB sound card with a 3.5mm loopback cable (output → input) creates a physical audio path. The phone's audio streams as raw PCM over HTTP, gets played to the USB card's output, travels through the cable, and re-enters as the card's microphone input. Apps that reject virtual audio devices (like Typeless) accept this as a legitimate hardware microphone.

## Requirements

### Hardware
- A Mac (tested on Mac mini, macOS Ventura+)
- An iPhone (any model with Safari)
- A USB external sound card with separate 3.5mm output and input jacks (~$5-10)
- A 3.5mm male-to-male aux cable (~$2)

### Software (Mac)
- [Node.js](https://nodejs.org/) (v18+)
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) (for VirtualHID driver)
  ```bash
  brew install --cask karabiner-elements
  ```
  Enable the driver in System Settings → General → Login Items & Extensions → Driver Extensions
- [sox](https://sox.sourceforge.net/) (audio playback)
  ```bash
  brew install sox
  ```
- [mkcert](https://github.com/FiloSottile/mkcert) (local HTTPS certificates — required for Safari microphone access)
  ```bash
  brew install mkcert
  mkcert -install
  ```

### Software (iPhone)
- Nothing. Just Safari.

## Setup

### 1. Clone and install
```bash
git clone https://github.com/youruser/vibe-coding-magic-button.git
cd vibe-coding-magic-button
npm install
```

### 2. Compile the key helper
```bash
cc -O2 -o vhid_key vhid_key.c
```

### 3. Generate HTTPS certificates
```bash
mkdir -p certs
mkcert -cert-file certs/cert.pem -key-file certs/key.pem localhost $(ipconfig getifaddr en0)
```

### 4. Install CA certificate on iPhone
This is needed so Safari trusts the local HTTPS server (required for microphone access).

1. Copy the root CA to the public folder:
   ```bash
   cp "$(mkcert -CAROOT)/rootCA.pem" public/rootCA.pem
   ```
2. Start the server (see below), then on your iPhone open:
   ```
   https://<your-mac-ip>:2000/rootCA.pem
   ```
3. Install the profile: Settings → General → VPN & Device Management
4. Enable trust: Settings → General → About → Certificate Trust Settings → toggle on

### 5. Connect the hardware loopback
Plug the USB sound card into your Mac. Connect a 3.5mm aux cable from the card's **output** jack to its **input** jack.

### 6. Configure your target app
In Typeless (or whatever app you're using), select "USB Audio Device" as the microphone input.

## Usage

### Start the server
```bash
sudo node server.js
```
Root is required for Karabiner VirtualHID socket access.

### On your iPhone
Open `https://<your-mac-ip>:2000` in Safari. Tap the button to start/stop.

### Add to Home Screen
In Safari, tap Share → Add to Home Screen for an app-like experience.

## Configuration

### Change the trigger key
Edit `vhid_key.c` — change `MOD` and `KEY` constants, then recompile:
```c
// Left Option/Alt (default)
const uint8_t MOD = 0x04;
const uint16_t KEY = 0xE2;
```

### Change the port
Edit `server.js`:
```javascript
const PORT = 2000;
```

### Change the audio output device
Edit `server.js` — change the sox output device name:
```javascript
'-', '-t', 'coreaudio', 'USB Audio Device'  // ← your device name here
```
Find your device name with: `system_profiler SPAudioDataType`

## File Structure
```
vibe-coding-magic-button/
├── server.js          # HTTPS server, audio pipeline, key control
├── vhid_key.c         # C helper for Karabiner VirtualHID key injection
├── vhid_key           # Compiled binary
├── public/
│   ├── index.html     # iPhone web UI
│   └── rootCA.pem     # mkcert CA cert (for iPhone trust)
├── certs/
│   ├── cert.pem       # HTTPS certificate
│   └── key.pem        # HTTPS private key
└── package.json
```

## Limitations

- Requires the same Wi-Fi network (or a VPN like Tailscale for remote use)
- iPhone Safari asks for microphone permission on each page load (self-signed cert limitation)
- Audio has slight latency (~200-400ms) due to HTTP chunked transfer
- Server needs root privileges for VirtualHID access
- macOS only (depends on Karabiner and CoreAudio)

## License

MIT
