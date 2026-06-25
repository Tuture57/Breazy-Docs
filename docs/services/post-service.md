# Post Service

Cœur social de Breezy : posts, likes, commentaires et réponses, reposts, signalement, upload
d'images, mentions `@username`, et un **bot IA** (`@breezy_ai`). Stocke ses données dans
MongoDB.

- **Dépôt** : `breezy-post-service`
- **Port** : `3003`
- **Base de données** : MongoDB `posts_db` (conteneur `mongo-posts`)
- **ODM** : Mongoose 9

!!! info "Aucune authentification interne"
    Toutes les routes (sauf l'upload qui a multer) sont sans middleware : l'identité vient des
    headers `x-user-id` / `x-user-role` / `x-user-username` injectés par la gateway, lus
    directement dans les contrôleurs.

---

## Stack & dépendances

| Paquet | Version |
|---|---|
| express | `^5.2.1` |
| mongoose | `^9.7.0` |
| multer | `^1.4.5-lts.1` |
| axios | `^1.18.0` |
| morgan | `^1.11.0` |
| cors | `^2.8.6` |
| express-validator | `^7.3.2` ⚠️ **déclaré mais jamais utilisé** |

---

## Modèles de données

Tous les timestamps sont renommés `created_at` / `updated_at`.

### `posts`

| Champ | Type | Contraintes |
|---|---|---|
| `user_id` | String | `required`, `index` |
| `username` | String | `required` (dénormalisé) |
| `content` | String | `required`, max 280 |
| `tags` | [String] | chaque tag max 30 |
| `media_urls` | [String] | — |
| `likes_count` / `comments_count` / `reposts_count` | Number | défaut 0, min 0 |
| `is_reported` | Boolean | défaut `false` |

Index : `{user_id:1}`, `{user_id:1, created_at:-1}`, `{tags:1}`, `{created_at:-1}`.

### `comments`

| Champ | Type | Contraintes |
|---|---|---|
| `post_id` | ObjectId (ref `Post`) | `required` |
| `user_id` / `username` | String | `required` |
| `content` | String | `required`, max 280 |
| `parent_comment_id` | ObjectId (ref `Comment`) | défaut `null` (=`racine`) |

Index : `{post_id:1, created_at:1}`, `{parent_comment_id:1}`. Pas d'index unique.

### `likes` et `reposts`

Structure identique : `post_id` (ref `Post`, required), `user_id` (required), `created_at`
(`updatedAt: false`). **Index unique `{post_id:1, user_id:1}`** → un seul like / repost par
utilisateur et par post.

---

## Routes (préfixe `/api`)

| Méthode | Path | Contrôleur |
|---|---|---|
| POST | `/api/upload` | `uploadMedia` (multer `single('file')`) |
| GET | `/api/posts/feed` | `getFeed` |
| GET | `/api/posts/search` | `searchByTag` |
| GET | `/api/posts/user/:userId` | `getByUser` |
| GET | `/api/posts/user/:userId/media` | `getUserMedia` |
| GET | `/api/posts/user/:userId/likes` | `getUserLikes` |
| GET | `/api/posts/user/:userId/replies` | `getUserReplies` |
| GET | `/api/posts/user/:userId/reposts` | `getUserReposts` |
| POST | `/api/posts` | `create` |
| GET | `/api/posts/:id` | `getById` |
| PUT | `/api/posts/:id` | `update` |
| DELETE | `/api/posts/:id` | `delete` |
| POST | `/api/posts/:id/report` | `report` |
| POST | `/api/posts/:id/repost` | `toggleRepost` |
| POST | `/api/posts/:id/like` | `like` |
| DELETE | `/api/posts/:id/like` | `unlike` |
| GET | `/api/posts/:id/comments` | `getComments` |
| POST | `/api/posts/:id/comments` | `createComment` |
| PUT | `/api/posts/:id/comments/:commentId` | `updateComment` |
| DELETE | `/api/posts/:id/comments/:commentId` | `deleteComment` |
| POST | `/api/posts/:id/comments/:commentId/replies` | `createReply` |

---

## Endpoints détaillés

Format d'erreur : `{ error: { code, message? } }`.

### POST /api/posts — créer un post

| Champ body | Type | Requis | Description |
|---|---|---|---|
| `content` | string | ✅ | max 280 |
| `tags` | string[] | non | max 5 tags |
| `media_urls` | string[] | non | URLs renvoyées par `/api/upload` |

- **Succès `201`** : le document Post complet.
- Effets de bord (non bloquants) : notifications de mention, réponse du bot IA.

| Code | Erreur |
|---|---|
| 400 | `INVALID_CONTENT` (vide ou > 280) |
| 400 | `TOO_MANY_TAGS` (> 5) |

### GET /api/posts/feed

Query `page` (1), `limit` (20). **Algorithme** :

1. Appel `GET {USER_SERVICE_URL}/users/{userId}/following` (timeout 3 s) → `ids`. En cas
   d'échec, `followingIds = []` (le feed n'affiche que les posts de l'utilisateur).
2. `feedUserIds = Set([userId, ...followingIds])` → **inclut les propres posts**.
3. `Post.find({ user_id: { $in } }).sort({ created_at: -1 }).skip().limit()` — tri purement
   chronologique, **pas de ranking**.
4. Enrichissement parallèle (`Like.find` + `Repost.find`) → `likedByMe` / `repostedByMe`.

- **Succès `200`** : `{ data: [posts enrichis], pagination: { page, limit, total, hasNext } }`.

### GET /api/posts/:id · PUT /api/posts/:id · DELETE /api/posts/:id

- **GET** : `200` post, `404 POST_NOT_FOUND`.
- **PUT** (édition) : body `{ content, tags, media_urls? }`. **Auteur uniquement** (sinon
  `403 FORBIDDEN`, pas d'exception modérateur). `media_urls` mis à jour seulement si fourni.
- **DELETE** : auteur **ou** rôle `moderator`/`admin`. **Cascade** : supprime les `likes` et
  `comments` du post. ⚠️ **les `reposts` ne sont pas supprimés** (orphelins possibles).
  **Succès `204`**.

### POST /api/posts/:id/report

Met `is_reported = true`. **Succès `200`** : `{ message: 'Post signalé.' }`. ⚠️ Ne vérifie pas
l'existence du post (pas de `404`). Aucune route ne liste ni ne lève les signalements.

### POST /api/posts/:id/repost — toggle

`404 POST_NOT_FOUND` si absent. Si déjà reposté → suppression + `$inc reposts_count -1` →
`{ reposts_count, reposted: false }`. Sinon création + `$inc +1` → `{ reposts_count, reposted: true }`.

### POST /api/posts/:id/like · DELETE /api/posts/:id/like

- **like** : crée un `Like` + `$inc likes_count +1`. Double-like → erreur Mongo `11000`
  interceptée → **`409 ALREADY_LIKED`**. `404 POST_NOT_FOUND` si absent. **Succès `200`** :
  `{ likes_count }`. Notification de like envoyée (voir inter-services).
- **unlike** : `findOneAndDelete` ; si rien → `404 LIKE_NOT_FOUND`. Sinon `$inc -1` →
  `{ likes_count: max(0, ...) }`.

!!! warning "Compteur de like potentiellement négatif en base"
    `max(0, ...)` borne seulement l'**affichage**. Une valeur négative stockée n'est pas
    corrigée.

### Commentaires & réponses

- **GET /comments** : renvoie les commentaires racines (`parent_comment_id: null`) paginés, tri
  `created_at:1`, chacun avec son tableau `replies`. `total` = nombre de **racines** seulement.
- **POST /comments** : body `{ content }` (max 280). Crée une racine + `$inc comments_count +1`.
  **`201`**.
- **PUT /comments/:commentId** : auteur uniquement (`403 FORBIDDEN`).
- **DELETE /comments/:commentId** : auteur **ou** modérateur/admin. Supprime le commentaire +
  ses réponses (`deleteMany({ parent_comment_id })`) + `$inc comments_count -1`. **`204`**.
- **POST /comments/:commentId/replies** : **profondeur max 1** — si le parent est déjà une
  réponse (`parent_comment_id` non nul) → `400 MAX_DEPTH`. Crée la réponse + `$inc comments_count +1`.

!!! warning "Incohérence de `comments_count` à la suppression"
    Supprimer un commentaire ayant des réponses décrémente le compteur de **1 seulement**, alors
    que plusieurs documents (le commentaire + ses réponses) sont supprimés → `comments_count`
    peut diverger.

### POST /api/upload

`multipart/form-data`, champ `file`. multer `diskStorage` vers `<racine>/uploads`, nom
`Date.now()-<random>.<ext>`, **images uniquement** (filtre `mimetype` `image/*`), **5 Mo max**.
Servi en statique sur `/api/uploads/<filename>`. **Succès `201`** : `{ url: "/api/uploads/<filename>" }`.

| Code | Erreur |
|---|---|
| 400 | `NO_FILE` |
| 413 | `FILE_TOO_LARGE` (> 5 Mo) |
| 400 | `INVALID_FILE` (non-image) |

!!! warning "Uploads non persistants par défaut au build"
    Les fichiers vivent dans `/app/uploads`. La persistance est assurée par le volume
    `uploads_data` monté en docker-compose, **pas** par le Dockerfile (aucun volume déclaré).

---

## Recherche par tags & contenu

`GET /api/posts/search?q=...` ou `?tag=...` (sinon `400 MISSING_QUERY`). Filtre `$or` :
`content` (regex insensible à la casse), `tags` (égalité exacte sur `q.toLowerCase()`),
`username` (regex insensible). **Pas d'index full-text MongoDB.** Les tags ne sont pas
normalisés en minuscules à la création, alors que la recherche compare au `toLowerCase()` de la
requête → matching de tag imparfait.

---

## Bot IA `@breezy_ai`

!!! tip "Fonctionnalité absente de l'ancienne documentation"
    À la création d'un post, si `content` contient `@breezy_ai` (insensible à la casse), le
    service appelle **OpenRouter** (`https://openrouter.ai/api/v1/chat/completions`, modèle
    `openai/gpt-oss-20b:free`, timeout 15 s, `Authorization: Bearer ${OPENROUTER_API_KEY}`).
    La réponse est créée comme un **commentaire racine** du compte bot
    (`user_id = a7af3029-cd8b-4cda-b827-aab8095cf800`, username `breezy_ai`), tronquée à 280
    caractères, avec `$inc comments_count +1`. L'appel est non bloquant (pas de `await` dans
    `create`).

!!! danger "Clé API exposée"
    `OPENROUTER_API_KEY` est **vide dans `.env.example`** mais une **clé réelle est commitée en
    clair dans le `.env`** du dépôt. Voir [Secrets & configuration](../securite/secrets-configuration.md).

---

## Appels inter-services

| Quand | Méthode + URL | Headers | Timeout | Échec |
|---|---|---|---|---|
| Feed | `GET {USER_SERVICE_URL}/users/{userId}/following` | `x-user-id` | 3000 ms | following = [] |
| Mentions (`@user`) | `GET {USER_SERVICE_URL}/users/by-username/{name}` | `x-user-id` | défaut | catch silencieux |
| Mentions | `POST {PROFIL_SERVICE_URL}/api/notifications/internal` (`type:'mention'`) | `x-internal-secret` | 1000 ms | catch silencieux |
| Like | `GET {USER_SERVICE_URL}/users/{post.user_id}` (récupère le `role`) | `x-user-id` | 1000 ms | role = null |
| Like | `POST {PROFIL_SERVICE_URL}/api/notifications/internal` (`type:'like'`, + `recipient_role`) | `x-internal-secret` | 1000 ms | catch silencieux |
| Bot IA | `POST https://openrouter.ai/api/v1/chat/completions` | `Authorization: Bearer` | 15000 ms | warn, ignoré |

!!! note "Notifications comment/reply non générées"
    Les types `comment` et `reply` existent dans le schéma du profil-service, mais le
    post-service **ne déclenche que** les notifications `like` et `mention`. Aucune notification
    n'est créée à la publication d'un commentaire ou d'une réponse.

---

## Variables d'environnement

| Variable | Défaut | Usage |
|---|---|---|
| `PORT` | `3003` | Port d'écoute |
| `MONGO_URI` | `mongodb://localhost:27017/breezy-post` | Connexion MongoDB |
| `USER_SERVICE_URL` | — | Feed, mentions, rôle du destinataire |
| `PROFIL_SERVICE_URL` | — | Notifications |
| `INTERNAL_SECRET` | — | Secret inter-services |
| `OPENROUTER_API_KEY` | (vide dans `.env.example`) | Bot IA |
| `CORS_ORIGIN` | `http://localhost:3000` | CORS (absent de `.env.example`) |

---

## Dockerfile

`node:20-alpine`, `npm install`, `CMD ["npm","start"]`. Pas d'`EXPOSE`, pas de volume `uploads`
dans le Dockerfile (la persistance est gérée par docker-compose).
