# Routes completes

> Toutes les routes HTTP de tous les microservices Breezy, classees par service.

---

## Gateway (api-gateway)

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/api/health` | Public | - | Health check du gateway |

**Proxies configures :**

| Prefix | Target | Auth |
|--------|--------|------|
| `/api/auth/login` | auth-service `POST /auth/login` | Public |
| `/api/auth/register` | auth-service `POST /auth/register` | Public |
| `/api/auth/refresh` | auth-service `POST /auth/refresh` | Public |
| `/api/auth/logout` | auth-service `POST /auth/logout` | Public |
| `/api/auth/me` | auth-service `GET /auth/me` | JWT |
| `/api/auth/change-password` | auth-service `POST /auth/change-password` | JWT |
| `/api/users/*` | user-service `/users/*` | JWT |
| `/api/posts/*` | post-service `/api/posts/*` | JWT |
| `/api/upload` | post-service `POST /api/upload` | JWT |
| `/api/uploads/*` | post-service `GET /api/uploads/*` | Public (fichiers statiques) |
| `/api/profils/*` | profil-service `/api/profils/*` | JWT |
| `/api/notifications/*` | profil-service `/api/notifications/*` | JWT |

---

## Auth-Service (port 3001)

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| POST | `/auth/register` | Public | - | Creer un compte (email + username + password) |
| POST | `/auth/login` | Public | - | Authentification (email + password) |
| POST | `/auth/refresh` | Public (cookie) | - | Rafraichir le JWT via refresh token |
| POST | `/auth/logout` | Public (cookie) | - | Revoquer le refresh token |
| GET | `/auth/me` | JWT | - | Recuperer les infos de l'utilisateur connecte |
| POST | `/auth/change-password` | JWT | - | Changer le mot de passe (currentPassword + newPassword) |
| POST | `/auth/internal/ban` | Internal | - | Bannir un utilisateur (interne, x-internal-secret) |
| GET | `/health` | Public | - | Health check du service |

**Details Auth :**

| Champ | Signification |
|-------|---------------|
| **Public** | Aucune authentification requise. |
| **JWT** | Header `Authorization: Bearer <token>` requis. Gateway verifie le JWT et injecte `x-user-id`, `x-user-role`, `x-user-username`. |
| **Internal** | Header `x-internal-secret` requis (secret partage entre services). Jamais expose au client. |
| **Public (cookie)** | Accepte le refresh token depuis le cookie `refreshToken` (httpOnly) ou depuis le body JSON. |

---

## User-Service (port 3002)

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| POST | `/users/sync` | Internal | - | Synchroniser un profil depuis l'auth-service (x-internal-secret) |
| GET | `/users/search` | JWT | - | Rechercher des utilisateurs par username (`?q=...&page=1&limit=10`) |
| GET | `/users/by-username/:username` | Public | - | Resoudre un username en UUID (utilise par @mentions) |
| GET | `/users/:id` | JWT | - | Profil public d'un utilisateur avec statut follow |
| GET | `/users/:id/followers` | JWT | - | Liste des abonnes d'un utilisateur (pagine) |
| GET | `/users/:id/following` | JWT | - | Liste des abonnements d'un utilisateur (pagine) |
| POST | `/users/:id/follow` | JWT | - | Suivre un utilisateur (transaction + notification) |
| DELETE | `/users/:id/follow` | JWT | - | Ne plus suivre un utilisateur (transaction) |
| PUT | `/users/:id/ban` | JWT | moderator, admin | Bannir un utilisateur (seulement moderateur/admin, propagation auth) |
| GET | `/health` | Public | - | Health check du service |

**Particularites User-Service :**

| Note | Details |
|------|---------|
| **x-user-username absent** | La gateway n'injecte PAS `x-user-username` pour les routes `/users/*`. Le controller `follow` utilise `req.username` pour la notification, qui sera `undefined`. |
| **/by-username/:username est public** | Pas de middleware identity, accessible sans JWT. Necessaire pour la resolution des @mentions depuis le post-service. |
| **/search** | Utilise `Op.iLike`, exclut `is_banned=true` et `is_active=false`, trie par `followers_count DESC`. |
| **/ban** | Verifie `req.userRole` dans le controller : `moderator` ou `admin`. Propagation vers auth-service non bloquante. |

---

## Post-Service (port 3003)

### Posts

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| POST | `/api/upload` | JWT | - | Uploader un fichier media (multer, 5MB, images) |
| GET | `/api/posts/feed` | JWT | - | Feed principal (posts des suivis + propres) |
| GET | `/api/posts/search` | JWT | - | Rechercher des posts (`?q=...` ou `?tag=...`) |
| GET | `/api/posts/user/:userId` | JWT | - | Posts d'un utilisateur |
| GET | `/api/posts/user/:userId/media` | JWT | - | Posts avec media d'un utilisateur |
| GET | `/api/posts/user/:userId/likes` | JWT | - | Posts likes par un utilisateur |
| GET | `/api/posts/user/:userId/replies` | JWT | - | Commentaires d'un utilisateur |
| GET | `/api/posts/user/:userId/reposts` | JWT | - | Posts repostes par un utilisateur |
| POST | `/api/posts` | JWT | - | Creer un post (content + tags + media_urls) |
| PUT | `/api/posts/:id` | JWT | owner | Modifier son propre post |
| GET | `/api/posts/:id` | JWT | - | Recuperer un post par ID |
| DELETE | `/api/posts/:id` | JWT | owner, moderator, admin | Supprimer un post (proprietaire ou moderateur/admin) |
| POST | `/api/posts/:id/report` | JWT | - | Signaler un post (passe `is_reported: true`) |
| POST | `/api/posts/:id/repost` | JWT | - | (De)reposter un post (toggle) |

### Likes

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| POST | `/api/posts/:id/like` | JWT | - | Liker un post (index unique, `$inc`) |
| DELETE | `/api/posts/:id/like` | JWT | - | Enlever son like (`$inc`) |

### Commentaires

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/api/posts/:id/comments` | JWT | - | Commentaires d'un post (avec reponses imbriquees) |
| POST | `/api/posts/:id/comments` | JWT | - | Creer un commentaire racine |
| PUT | `/api/posts/:id/comments/:commentId` | JWT | owner | Modifier son commentaire |
| DELETE | `/api/posts/:id/comments/:commentId` | JWT | owner, moderator, admin | Supprimer un commentaire (proprietaire ou moderateur/admin, cascade) |
| POST | `/api/posts/:id/comments/:commentId/replies` | JWT | - | Repondre a un commentaire (max 1 niveau) |

### Health

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/api/health` | Public | - | Health check du service |

**Particularites Post-Service :**

| Note | Details |
|------|---------|
| **Feed** | Recupere la liste des following IDs depuis le user-service (`/users/:userId/following`), puis `$in` sur `user_id`. Inclut les posts de l'utilisateur courant. Enrichi avec `likedByMe` et `repostedByMe`. |
| **Upload** | Multer configure pour accepter uniquement les images, max 5MB. Stocke dans `/app/uploads/`. |
| **@mentions** | Extrait les `@username` du contenu, resoud via `/users/by-username/:username` (user-service), envoie notification. Erreurs ignorees. |
| **Delete** | Cascade manuelle : supprime les likes, commentaires (et leurs reponses) associes. |
| **Report** | Simple flag booleen `is_reported: true`. Pas de route pour lister/lever les signalements. |
| **Comment depth** | Bloque les reponses aux reponses (`MAX_DEPTH`). |
| **x-user-username** | Bien injecte par la gateway pour les routes posts. |

---

## Profil-Service (port 3004)

### Profils

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/api/profils/:userId` | JWT | - | Recuperer le profil (upsert auto si inexistant) |
| PUT | `/api/profils/:userId` | JWT | owner | Modifier le profil (display_name, bio, avatar_url, banner_url, location) |

### Notifications

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/api/notifications` | JWT | - | Liste des notifications (`?page=1&limit=20&unread_only=true`) |
| PUT | `/api/notifications/read-all` | JWT | - | Marquer toutes les notifications comme lues |
| PUT | `/api/notifications/:id/read` | JWT | - | Marquer une notification comme lue |
| POST | `/api/notifications/internal` | Internal | - | Creer une notification (interne, x-internal-secret) |

**Particularites Profil-Service :**

| Note | Details |
|------|---------|
| **GET /profils/:userId** | Utilise `findOneAndUpdate` avec `upsert: true` et `$setOnInsert`. Si le profil n'existe pas, il est cree automatiquement. |
| **PUT /profils/:userId** | Verifie que `x-user-id` === `:userId`. Champs autorises seulement : display_name, bio, avatar_url, banner_url, location. Bio max 160 caracteres. |
| **Internal notifications** | Verifie `x-internal-secret`. Ignore les auto-notifications (recipient === from_user_id -> 204). |
| **Notifications types** | `like`, `follow`, `mention`, `comment`, `reply` (enum Mongoose valide). |

---

## Resume par nombre de routes

| Service | Routes | Publiques | JWT | Internal | Dont health |
|---------|--------|-----------|-----|----------|-------------|
| Gateway | 1 (+ 12 proxies) | 3 proxies | 8 proxies | - | 1 |
| Auth-Service | 8 | 4 | 2 | 1 | 1 |
| User-Service | 10 | 2 | 6 | 1 | 1 |
| Post-Service | 22 | 1 | 20 | - | 1 |
| Profil-Service | 6 | 0 | 4 | 1 | - |
| **Total** | **47** | **8** | **32** | **3** | **3** |

---

## Notes sur la securite des routes

### Verification d'appartenance (owner)

Plusieurs routes verifient que `x-user-id` === l'ID du proprietaire de la ressource :

- `PUT /api/posts/:id` -- seul le createur du post peut modifier
- `DELETE /api/posts/:id` -- createur OU moderateur/admin
- `PUT /api/profils/:userId` -- seul l'utilisateur concerne
- `PUT /api/posts/:id/comments/:commentId` -- seul l'auteur du commentaire
- `DELETE /api/posts/:id/comments/:commentId` -- auteur OU moderateur/admin

### Routes sans middleware identity

Ces routes ne passent pas par le middleware identity et sont accessibles sans en-tete d'identite :

| Route | Raison |
|-------|--------|
| `POST /users/sync` | Appelee par auth-service (x-internal-secret) |
| `GET /users/by-username/:username` | Utilisee par post-service pour @mentions |
| `POST /auth/internal/ban` | Appelee par user-service (x-internal-secret) |
| `POST /api/notifications/internal` | Appelee par user-service et post-service (x-internal-secret) |

### Routes Public (sans aucune authenticatication)

| Route | Expose |
|-------|--------|
| `GET /health` (tous services) | Statut du service, aucune donnee sensible |
| `POST /auth/register` | Creation de compte |
| `POST /auth/login` | Authentification |
| `POST /auth/refresh` | Renouvellement de JWT (via cookie httpOnly) |
| `POST /auth/logout` | Revocation de session |
| `GET /users/by-username/:username` | Resolution username -> UUID (donnee publique) |
| `GET /api/health` (gateway) | Statut du gateway |
| `GET /api/uploads/*` | Fichiers statiques (media uploades) |
