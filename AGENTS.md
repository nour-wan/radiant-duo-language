<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting published git history.
<!-- LOVABLE:END -->

- Keep all catalog content behind `src/services/catalog.ts` so a future Django REST API can replace local mock data without page changes.
- Keep locale and theme state in the shared site context so every route uses consistent RTL/LTR and persisted appearance.
- Catalog seeds may override localized descriptions and applications so ingredient-specific content remains in the data layer rather than pages.
- Self-hosted production builds must explicitly use Nitro's node-server preset with the complete .output/server and .output/public tree while preserving src/server.ts, because the existing Ubuntu systemd service launches .output/server/index.mjs behind Nginx.
