# Features

What's actually implemented, not what's planned — see [ROADMAP.md](ROADMAP.md) for the feature plan and tracking issues. Update this file whenever a feature is added or its status changes.

| Feature | Status | Details |
| --- | --- | --- |
| Self-hosted server configuration | Data layer only, no UI yet | A public server URL and an optional private (LAN) URL, with automatic switching to the private one on trusted Wi-Fi networks. See [networking-auth.md](networking-auth.md). |
| Account authentication | Data layer only, no UI yet | Login, TOTP MFA, logout, and expiry-aware session persistence, against Trek's single-JWT session model. See [networking-auth.md](networking-auth.md). |
