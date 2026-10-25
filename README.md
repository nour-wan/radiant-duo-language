# آلاس لتجارة المواد الغذائية / Alas for Foodstuff Trading

Arabic/English food-ingredients catalog with saved day/night appearance.

## Ubuntu VPS deployment (Node, no Docker)

The current deployment uses:

- Project: `/opt/radiant-duo-language`
- Existing systemd service: `radiant-duo.service`
- Existing command: `/usr/bin/node /opt/radiant-duo-language/.output/server/index.mjs`
- Existing port: `3001`, behind Nginx as a reverse proxy

`vite.config.ts` explicitly selects Nitro's `node-server` preset, with server
output in `.output/server` and static assets in `.output/public`. TanStack Start
continues to use `src/server.ts`, including its error-handling behavior. Deploy
the **entire `.output` directory**, not just `index.mjs` or the static assets.

### Prerequisites

Use Node.js **22.12 or newer** (Node 22 LTS is suitable). Verify the actual Node
binary used by systemd, not only a shell-local Node installed through nvm:

```sh
/usr/bin/node --version
```

If this version is older, upgrade the system Node installation first; do not
change the service's executable path. Install Bun for dependency installation
and building (the repository's committed lockfile is `bun.lock`):

```sh
sudo apt-get update
sudo apt-get install -y curl unzip
curl -fsSL https://bun.sh/install | bash
export PATH="$HOME/.bun/bin:$PATH"
bun --version
```

### Update and build

Upload/extract the latest repository source into `/opt/radiant-duo-language`
using your existing update method. Preserve any existing secrets and environment
files; do not overwrite them with files from another machine. Run as the project
owner (not root) and keep the current service running until the build succeeds:

```sh
cd /opt/radiant-duo-language
bun install --frozen-lockfile
bun run test
bun run build
test -s .output/server/index.mjs
test -d .output/public
```

The build command is `vite build`; there is no Cloudflare or Docker deployment
step on the VPS. Do not set Lovable sandbox/build environment variables on the
VPS: Lovable's managed build environment overrides the target for its own preview
hosting, so its managed output is not the VPS deployment artifact. Build from
source on Ubuntu to obtain the Node output above.

For rollback, save the previous complete `.output` directory outside the project
before building. For safer production updates, build in a separate release
directory, verify the output there, then replace the project's complete `.output`
before restarting; retain all previous output files together for rollback.

### Restart and check the existing service

Only restart after installation, tests, building, and output checks all succeed:

```sh
sudo systemctl restart radiant-duo.service
sudo systemctl status radiant-duo.service --no-pager
sudo journalctl -u radiant-duo.service -n 80 --no-pager
curl --fail --silent --output /dev/null http://127.0.0.1:3001/
curl --fail --silent --output /dev/null http://127.0.0.1:3001/products/
```

Then open the site's existing IP/domain through Nginx and check the home page,
product images, product details, Arabic/English switching, and day/night themes.
The Node server serves `.output/public`; no Nginx static-root changes are needed.
Keep the existing service environment that sets port `3001` (`PORT` or
`NITRO_PORT`). Do not edit Nginx, systemd unit files, or secrets for this update,
and no `daemon-reload` is needed for an unchanged unit.

To smoke-test a built release manually without colliding with the running service,
use a separate temporary port, stop it with Ctrl+C after checking it, and do not
use this command as a replacement for systemd:

```sh
NITRO_HOST=127.0.0.1 NITRO_PORT=3002 /usr/bin/node .output/server/index.mjs
# In another terminal:
curl --fail http://127.0.0.1:3002/
```

## Local development

```sh
bun install --frozen-lockfile
bun run dev
```

This repository remains editable in [Lovable](https://lovable.dev/projects/f52e1b6e-b8d7-4281-ac07-d29b7af2fd75).
