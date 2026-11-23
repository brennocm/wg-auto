<div align="center">
  <img src="src/logo-wgauto.png" alt="wg-auto" width="200">
  <h1>wg-auto</h1>
</div>

Two scripts that set up a WireGuard VPN between a Debian or Ubuntu server and one client: they install WireGuard, generate the keys, write `/etc/wireguard/wg0.conf` on both sides and start `wg-quick@wg0`. All of the client's traffic then goes through the server.

## Requirements

- Debian or Ubuntu on both machines, run as root (`sudo`).
- UDP port 51820 open on the server (in the cloud provider's firewall too).
- Both scripts run `apt upgrade -y` first.

## Usage

The server needs the client's public key and the client needs the server's, so run them side by side:

1. **Client:** start the script. It prints the client's public key and waits.
   ```bash
   git clone https://github.com/brennocm/wg-auto.git && cd wg-auto
   sudo bash WGAuto-client.sh
   ```
2. **Server:** run the server script and paste the client's public key when asked.
   ```bash
   git clone https://github.com/brennocm/wg-auto.git && cd wg-auto
   sudo bash WGAuto-server.sh
   ```
   At the end it runs `wg show wg0`; copy the server's public key from there.
3. **Client:** answer `yes`, then give the server's public IP, port (default 51820), public key, and the client's address inside the VPN: `10.10.10.2/24`.

Check from the client: `sudo wg show` lists a recent handshake, and `curl https://api.ipify.org` shows the server's IP. To turn the VPN off and on: `sudo wg-quick down wg0` / `sudo wg-quick up wg0`.

A walkthrough video is on [YouTube](https://youtu.be/Nr_En-eo2c0).

## What it changes

| Machine | Changes |
| --- | --- |
| Server | Installs `wireguard`, enables IP forwarding in `/etc/sysctl.conf`, creates `wg0` at `10.10.10.1/24` with NAT (iptables `MASQUERADE`) to the main interface, adds the client as a peer at `10.10.10.2/32`. |
| Client | Installs `wireguard` and `resolvconf`, **disables `systemd-resolved`**, routes all IPv4 traffic (`0.0.0.0/0`) through the tunnel. |

**DNS.** The client uses Quad9 (`9.9.9.9`, `149.112.112.112`) inside the VPN. To use other servers:

```bash
sudo WG_DNS="1.1.1.1 1.0.0.1" bash WGAuto-client.sh
```

## Limits

- One client per run. For more clients, add a `[Peer]` with the new public key and a new address (`10.10.10.3/32`, …) to the server's `wg0.conf` and restart `wg-quick@wg0`.
- IPv4 only; IPv6 traffic does not go through the tunnel.

## License

[MIT](LICENSE)
