# paperless-ngx on AlmaLinux with Podman Quadlet

Rootless [paperless-ngx](https://docs.paperless-ngx.com/) managed by systemd via
Podman Quadlet — no docker-compose, no root daemon. Postgres + Valkey + the
paperless webserver, three units, started on boot.

Everything lives in `/home/ivan/containers/paperless` on the server.

## Layout

```
/home/ivan/containers/paperless/
├── quadlet/                        # copy these into ~/.config/containers/systemd/
│   ├── paperless.network
│   ├── paperless-{data,media,pgdata,redisdata}.volume
│   ├── paperless-db.container      # postgres 18
│   ├── paperless-broker.container  # valkey 9
│   └── paperless-webserver.container
├── paperless.env                   # non-secret settings (in git)
├── secrets.env                     # passwords (gitignored, you create it)
├── consume/                        # drop documents here
└── export/                         # paperless writes exports here
```

Documents and the database live in named podman volumes
(`paperless-{data,media,pgdata,redisdata}`), `consume/` and `export/` are bind
mounts so you can reach them from the host.

## Install

### 1. Host prep (once)

```bash
sudo dnf install -y podman
sudo loginctl enable-linger ivan          # keep user units running after logout
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload
```

### 2. Get the repo

```bash
mkdir -p ~/containers
git clone https://github.com/toftul/paperless-podman.git ~/containers/paperless
cd ~/containers/paperless
```

### 3. Fill in the secrets

```bash
cp secrets.env.example secrets.env
sed -i "s/CHANGEME_DB/$(openssl rand -hex 16)/g; s/CHANGEME_SECRET/$(openssl rand -hex 32)/" secrets.env
vim secrets.env          # set PAPERLESS_ADMIN_PASSWORD
chmod 600 secrets.env
```

Also check `paperless.env` — at minimum `PAPERLESS_URL`, `PAPERLESS_TIME_ZONE`
and `PAPERLESS_OCR_LANGUAGE`.

### 4. Copy the units in and start

```bash
mkdir -p consume export ~/.config/containers/systemd
cp quadlet/* ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start paperless-webserver
```

The webserver unit pulls in the database and broker, so starting it starts
everything. First start downloads ~1 GB of images and runs the database
migrations — give it a few minutes.

Then open <http://server:8000> and log in with the admin credentials from
`secrets.env`.

## Day-to-day

```bash
systemctl --user status  paperless-webserver
systemctl --user restart paperless-webserver
systemctl --user stop    paperless-webserver paperless-db paperless-broker
journalctl --user -u paperless-webserver -f
podman ps
```

There is no `enable` step: quadlet units are generated with
`WantedBy=default.target`, so they come up on boot by themselves (that is what
`enable-linger` above is for).

**Changing config:** edit `paperless.env`, then
`systemctl --user restart paperless-webserver`. No copying needed — the units
read it at runtime.

**Changing a unit:** edit it here in `quadlet/`, then copy it over again:

```bash
cp quadlet/paperless-webserver.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart paperless-webserver
```

The copies in `~/.config/containers/systemd/` are what systemd actually reads;
this repo is the master copy. Same after a `git pull`.

**Consuming documents:** copy or `scp` files into `consume/`. Paperless picks
them up via inotify; subdirectories become tags.

## Updating

All units carry `AutoUpdate=registry`, so:

```bash
podman auto-update                             # update now
systemctl --user enable --now podman-auto-update.timer   # or update weekly
```

Pin `paperless-ngx:latest` to a specific tag in
`quadlet/paperless-webserver.container` if you prefer manual upgrades — and read
the release notes before crossing a major version.

## Backup

The important things are the postgres volume plus the media volume:

```bash
# Paperless' own exporter (documents + metadata, restorable anywhere)
podman exec -it paperless-webserver document_exporter ../export

# or raw volume dumps
podman volume export paperless-pgdata -o pgdata.tar
podman volume export paperless-media  -o media.tar
```

`export/` and `secrets.env` are what you want off-box.

## Notes / gotchas

- **User mapping.** The webserver runs with
  `UserNS=keep-id:uid=1000,gid=1000` plus `User=0`, so the `paperless` user
  inside the container is uid 1000 = `ivan` on the host. That is what keeps
  `consume/` and `export/` readable and writable from both sides. The `User=0`
  is not optional: `keep-id` alone would start the container as uid 1000 and the
  paperless entrypoint needs namespace-root to set itself up. If your uid is not
  1000, adjust the `keep-id` line (`id -u`).
- **SELinux.** The two bind mounts use `:z`; AlmaLinux relabels them
  automatically on first start. Nothing else to do — do not disable SELinux.
- **Paths are absolute** (`/home/ivan/containers/paperless/...`) in the
  `.container` files. They have to be: the units run from
  `~/.config/containers/systemd/`, so a relative path would be resolved against
  that directory, not this one. If you clone elsewhere, `sed -i` them.
- **Ports.** Rootless podman can bind 8000 fine. For anything below 1024 put a
  reverse proxy in front instead of granting capabilities.
- **`podman ps` shows nothing?** Check `journalctl --user -u paperless-db -n 50`;
  a wrong or missing `secrets.env` is the usual cause.
