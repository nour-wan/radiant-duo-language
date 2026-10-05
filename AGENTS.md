<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting published git history.
<!-- LOVABLE:END -->

- Keep all catalog content behind `src/services/catalog.ts` so a future Django REST API can replace local mock data without page changes.
- Keep locale and theme state in the shared site context so every route uses consistent RTL/LTR and persisted appearance.
