# Changelog de la documentation

> Ce fichier retrace toutes les mises a jour, corrections et ajouts effectues dans la documentation du projet Breezy, suite a l'analyse du code source reel.

---

## Ce qui a ete mis a jour

### index.md
- Stack technique mise a jour avec les versions exactes des dependances (Express 5, Next.js 14.2, Mongoose 9, Sequelize 6, etc.)
- Ajout du conteneur `seed` dans la liste des services
- Statut reel du projet (fonctionnalites implementees vs documentees)

### architecture/vue-ensemble.md
- Diagramme Mermaid complet avec les 12 conteneurs (4 services applicatifs + 4 bases de donnees + nginx + frontend + gateway + seed)
- Correction des limites de rate : la doc indiquait 100 req/10min pour le limiteur global, le code reel utilise 500 req/15min
- Correction du header injecte : la doc disait que `x-user-username` n'etait pas propage par la Gateway, le code l'injecte pour la plupart des routes
- Correction du middleware : la doc disait 403 pour token invalide, le code retourne 401

### architecture/communication-services.md
- Correction : `x-user-username` est bien propage par la Gateway pour les routes protegees (sauf user-service)
- Ajout du flux @mention (resolve username > userId > notification)
- Timeouts exacts documentes : 1s pour notifications, 3s pour sync/feed

### architecture/docker-deploiement.md
- Passage de 10 a 12 conteneurs (ajout seed + volume uploads_data)
- Variables d'environnement manquantes documentees : `MONGO_USER`, `MONGO_PASSWORD`, `SEED_ROLE_MODE`
- Detail des healthchecks (seulement sur les bases de donnees, pas sur les services applicatifs)

### services/auth-service.md
- Ajout de `POST /auth/change-password` (existe dans le code mais n'etait pas documentee)
- Correction de `BCRYPT_ROUNDS` : la doc disait 12 par defaut, le `.env` de dev utilise 10
- Ajout de la detection de vol de refresh token (reuse detection)

### services/user-service.md
- Ajout de `GET /users/by-username/:username` (route publique sans middleware identity)
- Correction du format de `GET /users/:id/following` : retourne `{ data, ids }` et pas seulement des IDs
- Ajout de la propagation de ban non-bloquante vers auth-service

### services/post-service.md
- Ajout de 12 routes manquantes :
  - `PUT /posts/:id` (update)
  - `POST /posts/:id/repost` (toggle repost)
  - `GET /posts/user/:userId/media`
  - `GET /posts/user/:userId/likes`
  - `GET /posts/user/:userId/replies`
  - `GET /posts/user/:userId/reposts`
  - `PUT /posts/:id/comments/:commentId`
  - `DELETE /posts/:id/comments/:commentId`
  - `POST /posts/:id/comments/:commentId/replies`
  - `POST /upload`
- Ajout des notifications de mention (@username resolve)
- Ajout de la gestion des fichiers uploades (multer)

### services/profil-service.md
- Correction de l'auto-creation de profil : `findOneAndUpdate` avec `upsert: true` (la doc disait juste `findOne`)
- Ajout du champ `location` dans le modele de profil

### services/frontend.md
- Correction de l'URL de base API : la doc utilise `/api`, le code lit `NEXT_PUBLIC_API_URL`
- Ajout des pages manquantes : `/compose`, `/reply`, `/messages/[convId]`, `/profile/edit`
- Correction de l'intercepteur Axios : ajout du systeme de file d'attente (`failedQueue`)
- Statut reel des routes : mise a jour des fonctionnalites implementees vs planifiees

### donnees/schema-postgresql.md
- DDL SQL complet pour les deux bases (auth + user)
- Ajout de la table `reposts` dans la documentation MongoDB (collection cote post-service)
- Index documentes pour toutes les tables

### donnees/schema-mongodb.md
- Tous les indexes documentes pour les 4 collections (posts, comments, likes, reposts)
- Indexe compose unique `{ post_id, user_id }` pour Like et Repost
- Indexe `{ parent_comment_id }` pour les commentaires

### securite/authentification.md
- Correction des limites de rate : 500/20 au lieu de 100/10
- Precision sur le cookie httpOnly (secure uniquement en production)
- Ajout de la section detection de vol de refresh token (replay attack)
- Ajout de la section sur les secrets internes (`INTERNAL_SECRET`)

### fonctionnalites/couverture-fx.md
- Statut reel de chaque Fx (implementee, partiellement, non implementee)
- Correction : `change-password` et `repost` etaient marques comme non implementes mais le code les implemente
- Ajout des routes non documentees

---

## Ce qui a ete ajoute

### services/gateway.md (nouveau fichier)
- Documentation complete de la Gateway :
  - Routes et leur mapping (12 routes proxy)
  - Middleware d'authentification JWT
  - Rate limiting (global 500/15min, auth 20/15min)
  - Injection des headers `x-user-id`, `x-user-role`, `x-user-username`
  - Gestion des erreurs (502 service indisponible)
  - Schema d'architecture complete

### architecture/flux-donnees.md (nouveau fichier)
- 6 diagrammes Mermaid de flux utilisateur :
  - Inscription
  - Connexion
  - Publication d'un post
  - Like + notification
  - Follow + notification
  - Refresh token + detection de vol

### api/routes-completes.md (nouveau fichier)
- Tableau exhaustif de toutes les routes API par service :
  - Auth (7 routes)
  - User (10 routes)
  - Post (19 routes)
  - Profil (6 routes)
- Methodes, chemins, middlewares, controleurs, codes de retour

### CHANGELOG_DOC.md (ce fichier)
- Trace de toutes les modifications apportees a la documentation

### mkdocs.yml
- Configuration MkDocs complete avec navigation, themes, plugins
- Structure des sections : Architecture, Services, Donnees, Securite, Fonctionnalites, Soutenance, API

---

## Ecarts trouves entre l'ancienne documentation et le code reel

| Element | Ancienne doc | Code reel |
|---------|-------------|-----------|
| Rate limiting global | 100 req/10min | 500 req/15min |
| Rate limiting auth | -- | 20 req/15min |
| x-user-username | "Pas propage par la Gateway" | Injecte pour la plupart des routes |
| Auth middleware 403 | 403 pour token invalide | 401 pour token invalide |
| BCRYPT_ROUNDS | Defaut 12 | `.env` reel = 10 |
| Nombre de conteneurs | 10 | 12 (seed + uploads_data) |
| GET /users/:id/following | Retourne juste des IDs | Retourne `{ data, ids }` |
| POST /auth/change-password | "Non implemente" | Existe dans le code |
| sequelize.sync({ alter: true }) | Non mentionne | Actif dans auth et user |
| NODE_ENV dans Docker | Non mentionne | `NODE_ENV=test` (desactive rate limiting) |
| Healthchecks Docker | Non mentionnes | Sur les DBs seulement, pas sur les apps |

---

## Fonctionnalites documentees comme absentes mais en realite implementees

- **POST /auth/change-password** : backend (`C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 198-222) + frontend
- **Repost (toggle)** : `POST /posts/:id/repost` (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 308-331)
- **Edition de post** : `PUT /posts/:id` (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 228-260)
- **Routes /posts/user/:userId/replies, /media, /likes, /reposts** : toutes implementees dans `post.controller.js`
- **Upload de fichiers** : multer configure dans `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\middleware\upload.middleware.js`

---

## Fonctionnalites implementees mais non documentees

- **Collection `reposts`** dans MongoDB (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\repost.model.js`)
- **GET /users/by-username/:username** (endpoint public, `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\routes\user.routes.js`, ligne 10)
- **Auto-creation de profil** (upsert sur GET, `C:\Users\barto\Desktop\breezy projet\breezy-profil-service\src\controllers\profile.controller.js`, lignes 6-10)
- **@mention avec resolution username vers userId** (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 25-64)
- **Detection de vol de refresh token** (revocation massive sur rejeu, `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 133-138)
- **File d'attente de requetes pendant le refresh** (`C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\services\api.js`, lignes 19-28)
- **Notifications de mention** (type `'mention'` dans notification.model.js + generation dans post.controller.js)
- **Bannissement avec double propagation** (user-service > auth-service, non-bloquant)
- **Seed conteneur** (`C:\Users\barto\Desktop\breezy projet\breezy-infra\seed\seed.js`, promotion de role via psql direct)
