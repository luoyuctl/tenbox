# tenboxd — Headless Daemon & Remote Control Plan

This document captures the plan for turning TenBox into a client/server product
with a headless daemon (`tenboxd`) that can run on Linux hosts (including
Raspberry Pi 5), be controlled remotely from desktop managers, a web UI, or a
CLI, and peacefully coexist with user-provided network overlays such as
Tailscale or WireGuard.

The plan is intentionally incremental — each phase is independently useful and
leaves the product in a shippable state.

---

## 1. Motivation

Today TenBox ships as a monolithic desktop app (Win32 manager on Windows,
SwiftUI manager on macOS). The `ManagerService` class already contains all of
the core VM lifecycle logic in a UI-agnostic form; the UI is just a callback
subscriber. This makes it natural to:

1. Run the core on a small headless Linux box (e.g. Raspberry Pi 5) and expose
   it as a network service.
2. Let users control that service from any of: the existing desktop manager,
   a web browser, or a CLI.
3. Support fleet/home-server use cases (AI agent sandboxes kept running 24/7
   on a Pi) without forcing users through a GUI.

This is the same architectural split Docker uses: `dockerd` + multiple
clients. TenBox's equivalent is `tenboxd` + thin clients.

---

## 2. Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Host (Pi 5, Linux PC, or any Linux server)                     │
│                                                                 │
│   tenboxd  (daemon, headless)                                   │
│    ├─ ManagerService (existing code, mostly unchanged)          │
│    ├─ Local RPC:  Unix socket (trusted local clients)           │
│    ├─ Remote RPC: HTTPS + WebSocket (TLS + token auth)          │
│    ├─ Embedded static web UI                                    │
│    └─ Spawns `tenbox-vm-runtime` processes (one per VM)         │
│                                                                 │
│   tenbox-vm-runtime (per VM, unchanged IPC back to tenboxd)     │
└────────────────────────────────┬────────────────────────────────┘
                                 │ TLS + token
                                 │ (routed via LAN / Tailscale / WG)
        ┌────────────────────────┼────────────────────────┐
        ▼                        ▼                        ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  tenbox CLI     │      │ Web UI          │      │ Desktop Manager │
│  (local+remote) │      │ (browser)       │      │ (Win32/SwiftUI) │
└─────────────────┘      └─────────────────┘      └─────────────────┘
```

### 2.1 Process boundary

- `tenboxd` owns VM state, persists `vm.json`, spawns runtimes, holds shared
  memory framebuffers, proxies LLM traffic, and exposes the RPC surface.
- `tenbox-vm-runtime` is unchanged — it still talks to its parent over the
  existing `protocol_v1` IPC (Unix socket on Linux/macOS, named pipe on
  Windows).
- Clients never talk to runtimes directly. Everything flows through `tenboxd`.

### 2.2 Local vs remote transports

| Transport | Endpoint | Auth | Intended use |
|---|---|---|---|
| Unix socket | `$XDG_RUNTIME_DIR/tenbox.sock` (fallback `/var/run/tenbox.sock`) | filesystem permissions | CLI, local desktop manager, local web UI |
| HTTPS + WS | `0.0.0.0:8443` (configurable) | TLS + bearer token | Remote desktop manager, remote browser, CI |

Both transports serve the **same** RPC schema.

### 2.3 Non-goals

- **TenBox does not implement its own NAT traversal.** Tailscale / WireGuard /
  Cloudflare Tunnel / frp already solve this better than we ever could. We aim
  to be a good citizen on top of those overlays, not compete with them.
- **No multi-tenant permissions in v1.** Single-admin token. Multi-user and
  quotas are a future consideration only if the product goes that direction.

---

## 3. RPC Design

### 3.1 Protocol choice: HTTP + WebSocket

Chosen over gRPC for these reasons:

- Browser-native, no `grpc-web` + Envoy proxy required for the web UI.
- Trivial to debug with `curl` and browser devtools.
- Standard TLS / bearer-token stack; no custom auth middleware.
- Desktop clients can use any mature WS library (libwebsockets, IXWebSocket,
  `URLSessionWebSocketTask` on Apple platforms).

We explicitly keep the door open to swap in gRPC later if strong typing across
many clients becomes a pain point; the RPC schema will be defined in a single
source of truth (JSON schema / OpenAPI) regardless.

### 3.2 Surface sketch

REST-ish HTTP for request/response operations:

```
GET    /v1/vms                    # list VMs
POST   /v1/vms                    # create VM
GET    /v1/vms/{id}               # get VM
PATCH  /v1/vms/{id}               # edit mutable patch
DELETE /v1/vms/{id}               # delete
POST   /v1/vms/{id}:start
POST   /v1/vms/{id}:stop
POST   /v1/vms/{id}:reboot
POST   /v1/vms/{id}:shutdown
POST   /v1/vms/{id}/shared-folders
POST   /v1/vms/{id}/port-forwards
GET    /v1/settings
PATCH  /v1/settings
GET    /v1/system                 # hypervisor availability, versions, capabilities
```

WebSocket for event streams and high-rate / bidirectional channels. One WS
connection can multiplex many channels, mirroring the existing `ipc::Channel`
split:

```
WS /v1/ws
  subscribe { channel: "state",    vm_id?: "..." }
  subscribe { channel: "console",  vm_id: "..." }
  subscribe { channel: "display",  vm_id: "..." }   # frames
  subscribe { channel: "input",    vm_id: "..." }   # client -> server
  subscribe { channel: "audio",    vm_id: "..." }
  subscribe { channel: "clipboard",vm_id: "..." }
  subscribe { channel: "events" }                   # global: VM lifecycle, PF errors, GA state
```

### 3.3 Authentication

- **Local Unix socket**: trust by filesystem permissions (0600, owner only).
- **Remote HTTPS**:
  - Bearer token via `Authorization: Bearer <token>` header (and
    `?token=...` query param for WS when headers are awkward in browsers).
  - Token persisted at `$XDG_CONFIG_HOME/tenbox/auth.token` (mode 0600).
  - First-run UX: daemon prints an "access URL" with the token embedded,
    identical to Jupyter's `?token=...` pattern.
  - Self-signed TLS cert auto-generated on first run; users can drop in their
    own cert/key via `--tls-cert` / `--tls-key`.

### 3.4 Discovery & context switching

- CLI stores named contexts in `$XDG_CONFIG_HOME/tenbox/contexts.json`:
  `{ name, url, token, tls_ca? }`. `tenbox context use <name>` switches.
- Desktop manager shows a "Hosts" picker (analogous to Docker Desktop's
  context switcher). A context can be "Local" (unix socket) or a named remote.

---

## 4. Display Transport (the hard problem)

The desktop managers currently receive raw RGBA frames via shared memory. That
obviously cannot traverse the network. The plan:

| Phase | Method | Tradeoffs |
|---|---|---|
| First remote-capable release | **JPEG/WebP frame push over WS** (noVNC-style) | Easy to implement; ~5–20 Mbps for 30 fps desktop; acceptable latency |
| Later | **WebRTC + H.264 (hardware encoded on Pi 5)** | Lower bitrate, lower latency; significant implementation complexity |
| Optional | **SPICE over WebSocket** with `spice-html5` | Reuses existing SPICE vdagent investment; less control over codec choices |

Design principles:

- Keep shared-memory path for local same-host clients (zero-copy, no encode).
- Encoder lives inside `tenboxd`, not in the runtime — runtime stays simple.
- Frame deltas: we already have dirty-rect information in the display pipeline;
  use it to send only changed tiles where possible.
- Input events (keyboard/pointer/wheel/resize) travel back over the same WS
  channel.

Pi 5 hardware notes: BCM2712 has a hardware H.264 encoder accessible via V4L2
(`/dev/video11`). We will evaluate using it in the WebRTC phase.

---

## 5. Web UI

Scope for v1:

- VM list, create/edit/delete dialogs (parity with desktop managers' forms).
- VM detail: info, console (xterm.js), display (JPEG canvas initially), shared
  folders, port forwards.
- Settings: LLM proxy config, image sources, auth token rotation.
- System dashboard: hypervisor status, resource usage, daemon version/uptime.

Tech choices (initial proposal):

- **React + Vite + TypeScript** for the frontend.
- **TanStack Query** for the REST layer, thin WS client for streams.
- **shadcn/ui** or **Mantine** for components — both have serious a11y and
  dark-mode out of the box.
- Built assets embedded into `tenboxd` via a resource file (no separate web
  server to deploy).

The web UI lives under `website-app/` (separate from the existing marketing
`website/`). Build output is copied into `src/daemon/embedded_web/` at build
time.

---

## 6. Desktop Manager Refactor

The goal is for Win32 and SwiftUI managers to become thin clients over the
same RPC as the web UI.

Plan:

1. Extract a pure C++ `tenbox_client` library that wraps HTTP+WS calls and
   exposes the same callback-based API as today's `ManagerService`. The UI
   layer is callback-driven, so ideally it does not know whether it is talking
   to an in-process `ManagerService` or a remote `tenboxd`.
2. Keep the "embedded" mode on Windows/macOS for v1: the manager can still
   spawn a `tenboxd` child process and connect to it over Unix socket / named
   pipe. This gives us a single code path internally.
3. Add a "Hosts" switcher in the UI with:
   - "Local" (embedded daemon, default)
   - user-added remote hosts (URL + token, optionally imported from a CLI
     context)

Windows note: Unix domain sockets are supported on Windows 10 1803+, so the
same "local socket" transport can work cross-platform. Named pipes remain a
fallback.

---

## 7. CLI

A single static binary (`tenbox`) suitable for shipping alongside the daemon.

Initial commands (Docker-inspired, adjusted to our domain):

```
tenbox context ls | use | add | rm
tenbox vm ls
tenbox vm create --name ... --kernel ... --disk ... --memory 4096
tenbox vm start | stop | reboot | shutdown  <id>
tenbox vm rm [--force] <id>
tenbox vm inspect <id>
tenbox vm console <id>          # interactive
tenbox vm logs <id>
tenbox vm exec <id> -- <cmd>    # via guest_agent, later
tenbox image ls | pull | rm
tenbox system info | version
tenbox auth print | rotate
```

Language: C++ to share the client library with the desktop managers.
(Go would be tempting for a static single-binary, but re-implementing the
client in two languages is not worth it yet.)

---

## 8. Repository Layout Impact

Proposed additions:

```
src/
├── daemon/                # NEW: tenboxd entry point
│   ├── main.cpp
│   ├── rpc/
│   │   ├── http_server.{h,cpp}
│   │   ├── ws_server.{h,cpp}
│   │   ├── auth.{h,cpp}
│   │   ├── tls.{h,cpp}
│   │   └── handlers/      # REST + WS handlers, thin shims over ManagerService
│   ├── display_encoder/
│   │   ├── jpeg_encoder.{h,cpp}
│   │   └── frame_delta.{h,cpp}
│   └── embedded_web/      # build-time copy of web UI assets
├── client/                # NEW: shared C++ RPC client library
│   ├── tenbox_client.{h,cpp}
│   ├── http_client.{h,cpp}
│   └── ws_client.{h,cpp}
├── cli/                   # NEW: `tenbox` CLI binary
│   └── main.cpp
├── platform/
│   └── linux/             # NEW: see Linux/KVM plan (separate but related)
└── manager/ and manager-macos/  # refactored to use src/client
website-app/               # NEW: web UI source (React/TS)
```

### 8.1 Relationship to the Linux / KVM port

The daemon work is logically independent from adding a Linux platform backend
(KVM for aarch64 on Pi 5, optionally KVM for x86_64 later), but the two are
the most natural to do **together** because:

- `tenboxd` is most interesting on Linux (Pi 5 / home servers).
- The existing `ManagerService` is already portable; the missing piece on
  Linux is `src/platform/linux/hypervisor/*` (KVM backend).
- Doing them in the same push avoids writing throwaway scaffolding.

See the phase plan below for ordering.

---

## 9. Phased Delivery

### Phase 0 — Prep (no behavior change)

- Audit `ManagerService` for any residual platform-specific bits (Win32
  `HANDLE`, libuv usage, process spawn on Windows) and factor them behind an
  abstraction so the class compiles cleanly on Linux.
- Lock down an RPC schema document (`docs/rpc-v1.md` or OpenAPI YAML). Single
  source of truth before any handler is written.

### Phase 1 — Linux runtime + local-only daemon

- Add `src/platform/linux/` implementing `HypervisorVm` / `HypervisorVCpu`
  over KVM (aarch64 first for Pi 5; x86_64 Linux can follow).
- Add `src/daemon/` serving the RPC schema over **Unix socket only**.
- Add `src/cli/` with a minimal command set (`vm ls/create/start/stop/console`).
- Target: `./tenbox vm create ... && ./tenbox vm start foo && ./tenbox vm console foo`
  works end-to-end on a Pi 5. No network access yet.

Exit criteria: a developer can SSH into a Pi 5 and run real AI-agent VMs with
the CLI.

### Phase 2 — Remote access

- Add HTTPS listener with auto-generated self-signed cert.
- Add token-based auth, with a "first run prints access URL" UX.
- Publish the web UI MVP (VM list, create/edit/delete, console via xterm.js,
  JPEG-based display viewer, settings).
- CLI gains context support (`tenbox context add`, remote hosts).
- Document Tailscale / WireGuard integration patterns (no code — just a
  recipe page in `docs/`).

Exit criteria: from a laptop on another network (via Tailscale), a user can
open `https://pi5:8443/?token=...`, create a VM, see its display, and control
it.

### Phase 3 — Desktop managers as thin clients

- Extract `src/client/tenbox_client`.
- Win32 and SwiftUI managers switch to the client library; "Local" uses
  embedded daemon, "Remote" connects over HTTPS+WS.
- Add Hosts picker UI.

Exit criteria: a Windows or macOS user can add their Pi 5 as a remote host in
the desktop manager and get a native experience for remote VMs.

### Phase 4 — Quality & polish (optional, ongoing)

- WebRTC display transport with Pi 5 hardware H.264 encoding.
- Optional embedded `tsnet` (Tailscale's Go library via cgo or a sidecar) so
  that `tenboxd` can join a tailnet without the user installing `tailscaled`.
- Audit / session log, basic RBAC if product pushes that direction.
- Packaging: `.deb` for Debian-based distros (Pi OS, Ubuntu), systemd unit
  file, `tenbox-web` service.

---

## 10. Open Questions

These are things to decide before/during Phase 1:

1. **HTTP/WS library**: `cpp-httplib` + custom WS, `Boost.Beast`,
   `uWebSockets`, or extending libuv (already a dependency) with a thin HTTP
   layer? Leaning toward `cpp-httplib` + `uWebSockets` for simplicity, but
   library surface on aarch64/glibc/musl needs to be checked.
2. **TLS stack**: OpenSSL (biggest ABI, ships everywhere) vs mbedTLS (smaller,
   already common in embedded) vs BoringSSL. Default guess: OpenSSL for Linux,
   SChannel on Windows, SecureTransport/Network.framework on macOS — abstract
   behind a thin `TlsContext`.
3. **Schema format**: hand-written Markdown, OpenAPI 3.1, or Protobuf (even if
   transport stays JSON-over-HTTP)? OpenAPI gives us codegen for TS clients
   "for free".
4. **Config file format**: reuse the existing `AppSettings` JSON layout, or
   introduce a `/etc/tenbox/config.yaml` for daemon-specific knobs (listen
   addr, cert path, data dir)? Probably keep them separate — daemon-level
   config shouldn't be edited by the app.
5. **Data directory location on Linux**: `/var/lib/tenbox` for system-wide
   installs vs `$XDG_DATA_HOME/tenbox` for per-user installs. We probably need
   both, selected by how the daemon was launched (systemd unit vs user
   session).
6. **Backward compat**: do we keep "no-daemon" embedded mode on
   Windows/macOS, or is `tenboxd` always running as a child process of the
   manager app on those platforms? Child-process approach keeps one code
   path; direct in-process usage is simpler for debugging.

---

## 11. Risks

- **Display transport is the dominant performance concern.** JPEG works but
  can be CPU-heavy on a Pi 5 for full-frame updates; we must use dirty rects
  and adaptive quality from day one, not bolt them on later.
- **Security surface grows sharply once we listen on TCP.** Token rotation,
  TLS hygiene, rate limiting on auth failures, and CSRF protection for the
  browser UI are all must-haves before we advertise remote access as
  "supported".
- **Windows desktop UDS support** requires Windows 10 1803+. Fine for our
  stated Windows 10/11 baseline, but the named-pipe fallback must keep working.
- **Scope creep into "home server / fleet manager" territory.** It is very
  tempting to add multi-user, quotas, scheduling, etc. once there is a
  daemon. We must resist until the single-admin case is genuinely polished.

---

## 12. Out of Scope for this Plan

- Full multi-tenant / multi-user support.
- A hosted control plane ("TenBox Cloud"). Users bring their own networking.
- Guest OS image marketplace beyond the existing `image_manager.py` sources.
- Cluster / multi-host VM scheduling.
