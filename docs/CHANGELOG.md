# Journal des modifications

Réécriture complète de la documentation après lecture intégrale du code source des 6 dépôts
(`breezy-auth-service`, `breezy-user-service`, `breezy-post-service`, `breezy-profil-service`,
`breezy-frontend`, `breezy-infra`). Chaque affirmation a été vérifiée dans le code.

---

## Réorganisation de la structure

La nomenclature des fichiers a été alignée sur une arborescence plus lisible :

| Ancien fichier | Nouveau fichier |
|---|---|
| `architecture/communication-services.md` | `architecture/communication.md` |
| `architecture/docker-deploiement.md` | `architecture/deploiement.md` |
| `donnees/schema-postgresql.md` | `donnees/postgresql.md` |
| `donnees/schema-mongodb.md` | `donnees/mongodb.md` |
| `api/routes-completes.md` | `api/routes.md` |
| `fonctionnalites/couverture-fx.md` | `fonctionnalites/couverture.md` |
| `soutenance/questions-generales.md` | `soutenance/questions.md` |
| `soutenance/questions-par-membre.md` | `soutenance/par-membre.md` |
| `soutenance/limites-evolutions.md` | `soutenance/limites.md` |
| `CHANGELOG_DOC.md` | `CHANGELOG.md` |

**Fichiers conservés** : `index.md`, `architecture/vue-ensemble.md`, `architecture/flux-donnees.md`
(8 diagrammes de séquence), les 6 fiches `services/*.md`, `securite/authentification.md`.

**Fichiers ajoutés** :

- `securite/secrets-configuration.md` — page transversale recensant les secrets commités et les
  configurations à risque (initiative : ces constats récurrents méritaient une page dédiée).

**Fichiers retirés** :

- `architecture/diagramme-composants.md` + `.svg` (×2) — superseded par le diagramme Mermaid de
  `vue-ensemble.md` (un schéma versionné en texte est plus maintenable que des SVG figés).

---

## Corrections majeures (écarts doc ↔ code)

| Élément | Ancienne doc | Code réel |
|---|---|---|
| `NODE_ENV` de la gateway | `test` (rate limiting **désactivé**) | **`production`** (rate limiting **actif**) |
| Noms des bases PostgreSQL | `breezy_auth`, `breezy_users` | **`auth_db`, `users_db`** |
| Noms des bases MongoDB | `breezy_posts`, `breezy_profils` | **`posts_db`, `profils_db`** |
| Rate limiting Nginx | présenté comme effectif | zones déclarées mais **jamais appliquées** (`limit_req` absent) |
| Routes auth | 8 routes | + `PATCH /auth/username`, `POST /auth/admin/create-user`, `GET /auth/internal/users/:id/role` |
| Notifications like/follow | non filtrées | **filtrées par rôle** (modérateurs/admins exclus) |
| Notif de follow | `from_username` correct | `from_username: undefined` (header non injecté) |
| `BCRYPT_ROUNDS` | 12 | **10 en Docker** (12 défaut code, 4 tests) |

---

## Ajouts par rapport à l'ancienne doc (fonctionnalités non documentées)

- **Bot IA `@breezy_ai`** : réponses automatiques via OpenRouter (`gpt-oss-20b:free`) à la
  création d'un post mentionnant `@breezy_ai`. Documenté dans `services/post-service.md` et
  `fonctionnalites/couverture.md`.
- **Filtrage des notifications par rôle** : le profil-service appelle
  `GET /auth/internal/users/:id/role` pour exclure modérateurs/admins des notifs `like`/`follow`.
- **`PATCH /auth/username`** (émet un nouveau JWT) et **`POST /auth/admin/create-user`** (réservé
  admin) : routes auth absentes de l'ancienne doc.
- **Protection des routes 100 % côté client** : le cookie `breezy_auth` est posé mais aucun
  `middleware.js` n'existe.

---

## Constats de sécurité ajoutés

Documentés dans `securite/secrets-configuration.md` et `soutenance/limites.md` :

- **Clé OpenRouter réelle commitée en clair** dans le `.env` du post-service.
- `JWT_SECRET` et `INTERNAL_SECRET` (placeholders) commités.
- Fallback `JWT_SECRET || "defaultSecret"` dans la gateway.
- Headers `x-user-*` non signés (usurpation possible si un service est joignable directement).
- `sequelize.sync({ alter: true })` au démarrage, configuration hybride dev/prod (bind-mounts +
  `NODE_ENV=production`).

---

## Incohérences de code documentées honnêtement

- `likes_count` potentiellement négatif en base ; `comments_count` divergent à la suppression en
  cascade ; reposts non supprimés à la suppression d'un post.
- Types de notifications `comment`/`reply` prévus mais **jamais générés**.
- `express-validator` déclaré mais inutilisé dans user-service et post-service.
- Tests divergents du code (`getFollowing` du user-service) ; pas de tests pour post/profil.
- `runValidators` non activé sur les profils (limites `maxlength` non garanties).

---

## Mise à jour de la navigation

`mkdocs.yml` a été réécrit pour refléter la nouvelle arborescence (sections Architecture,
Services, Données, API, Sécurité, Fonctionnalités, Soutenance) et inclure la page
`securite/secrets-configuration.md`.
