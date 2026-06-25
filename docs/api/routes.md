# Routes API complètes

Toutes les routes telles qu'**accessibles depuis le frontend** (préfixe `/api`, via Nginx puis
la gateway). La gateway réécrit le préfixe avant de transmettre au service (voir
[Gateway](../services/gateway.md)).

- **Auth** : JWT requis (`Authorization: Bearer <token>`), vérifié par la gateway.
- **Public** : aucune authentification.
- **Interne** : `x-internal-secret`, jamais exposé au client (non listé ici comme appelable).

---

## Authentification

| Méthode | Path | Auth | Rôle | Description |
|---|---|---|---|---|
| POST | `/api/auth/register` | Public | — | Créer un compte |
| POST | `/api/auth/login` | Public | — | Connexion |
| POST | `/api/auth/refresh` | Public (cookie) | — | Renouveler le JWT |
| POST | `/api/auth/logout` | Public (cookie) | — | Révoquer la session |
| GET | `/api/auth/me` | JWT | — | Infos de l'utilisateur connecté |
| POST | `/api/auth/change-password` | JWT | — | Changer le mot de passe |
| PATCH | `/api/auth/username` | JWT | — | Changer le username (nouveau JWT émis) |
| POST | `/api/auth/admin/create-user` | JWT | **admin** | Créer un compte avec un rôle |

## Utilisateurs

| Méthode | Path | Auth | Rôle | Description |
|---|---|---|---|---|
| GET | `/api/users/search?q=` | JWT | — | Recherche (exclut bannis/inactifs, tri `followers_count`) |
| GET | `/api/users/by-username/:username` | Public | — | Résolution username → profil (mentions) |
| GET | `/api/users/:id` | JWT | — | Profil public + `followedByMe` |
| GET | `/api/users/:id/followers` | JWT | — | Abonnés (paginé) |
| GET | `/api/users/:id/following` | JWT | — | Abonnements (paginé, renvoie aussi `ids`) |
| POST | `/api/users/:id/follow` | JWT | — | Suivre (transaction + notification) |
| DELETE | `/api/users/:id/follow` | JWT | — | Ne plus suivre |
| PUT | `/api/users/:id/ban` | JWT | **modérateur/admin** | Bannir (propagé à l'auth) |

## Posts

| Méthode | Path | Auth | Rôle | Description |
|---|---|---|---|---|
| GET | `/api/posts/feed` | JWT | — | Feed (suivis + soi-même), chronologique |
| GET | `/api/posts/search?q=` \| `?tag=` | JWT | — | Recherche regex content/tags/username |
| GET | `/api/posts/user/:userId` | JWT | — | Posts d'un utilisateur |
| GET | `/api/posts/user/:userId/media` | JWT | — | Posts avec média |
| GET | `/api/posts/user/:userId/likes` | JWT | — | Posts likés |
| GET | `/api/posts/user/:userId/replies` | JWT | — | Commentaires de l'utilisateur |
| GET | `/api/posts/user/:userId/reposts` | JWT | — | Posts repostés |
| POST | `/api/posts` | JWT | — | Créer un post (≤280, ≤5 tags, médias) |
| GET | `/api/posts/:id` | JWT | — | Récupérer un post |
| PUT | `/api/posts/:id` | JWT | **owner** | Modifier son post |
| DELETE | `/api/posts/:id` | JWT | **owner / modo / admin** | Supprimer (cascade likes+comments) |
| POST | `/api/posts/:id/report` | JWT | — | Signaler (`is_reported = true`) |
| POST | `/api/posts/:id/repost` | JWT | — | (Dé)reposter (toggle) |

## Likes

| Méthode | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/posts/:id/like` | JWT | Liker (index unique → 409 si doublon) |
| DELETE | `/api/posts/:id/like` | JWT | Retirer son like |

## Commentaires

| Méthode | Path | Auth | Rôle | Description |
|---|---|---|---|---|
| GET | `/api/posts/:id/comments` | JWT | — | Commentaires racines + réponses |
| POST | `/api/posts/:id/comments` | JWT | — | Créer un commentaire racine |
| PUT | `/api/posts/:id/comments/:commentId` | JWT | **owner** | Modifier son commentaire |
| DELETE | `/api/posts/:id/comments/:commentId` | JWT | **owner / modo / admin** | Supprimer (cascade réponses) |
| POST | `/api/posts/:id/comments/:commentId/replies` | JWT | — | Répondre (1 niveau max) |

## Upload

| Méthode | Path | Auth | Description |
|---|---|---|---|
| POST | `/api/upload` | JWT | Uploader une image (multer, 5 Mo, `image/*`) |
| GET | `/api/uploads/:filename` | **Public** | Servir un fichier uploadé (statique) |

## Profils

| Méthode | Path | Auth | Rôle | Description |
|---|---|---|---|---|
| GET | `/api/profils/:userId` | JWT | — | Profil détaillé (upsert auto) |
| PUT | `/api/profils/:userId` | JWT | **owner** | Éditer (display_name, bio≤160, avatar, bannière, location) |

## Notifications

| Méthode | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/notifications?unread_only=` | JWT | Liste paginée + `unread_count` |
| PUT | `/api/notifications/read-all` | JWT | Tout marquer comme lu |
| PUT | `/api/notifications/:id/read` | JWT | Marquer une notification comme lue |

## Santé

| Méthode | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/health` | Public | Health check de la gateway |

---

## Routes internes (non exposées au client)

Protégées par `x-internal-secret`, **non transmises par la gateway** (appels service-à-service
sur le réseau Docker uniquement).

| Méthode | Path interne | Appelé par | But |
|---|---|---|---|
| POST | `/users/sync` (user-service) | auth-service | Créer/mettre à jour le profil miroir |
| POST | `/auth/internal/ban` (auth-service) | user-service | Propager un bannissement |
| GET | `/auth/internal/users/:id/role` (auth-service) | profil-service | Filtrer les notifs par rôle |
| POST | `/api/notifications/internal` (profil-service) | post-service, user-service | Créer une notification |

---

## Conventions transverses

### Vérification d'appartenance (`owner`)

Comparaison `x-user-id` == ID propriétaire de la ressource :

- `PUT /api/posts/:id`, `PUT /api/posts/:id/comments/:commentId`, `PUT /api/profils/:userId`
- `DELETE /api/posts/:id` et `DELETE …/comments/:commentId` autorisent en plus `moderator`/`admin`.

### Format d'erreur

Tous les services renvoient `{ error: { code, message? } }`. La validation
(`express-validator`, auth-service) ajoute `details: [{ field, message }]`.

### Pagination

Offset-based (`page` / `limit`) partout, réponse `{ data, pagination: { page, limit, total, hasNext } }`.

!!! note "Décompte exhaustif"
    Le projet expose ~30 routes client + 4 routes internes + les health checks de chaque
    service (`GET /health`, accessibles uniquement en interne). Les chiffres exacts par service
    figurent dans chaque fiche service.
