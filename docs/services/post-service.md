# Post Service

Microservice de gestion des posts, likes, commentaires, reposts, uploads et flux (feed) pour Breezy.

---

## Stack

| Technologie | Version |
|---|---|
| Node.js | 20 (Alpine) |
| Express | 5.2.1 |
| Mongoose | 9.7.0 |
| MongoDB | 6 |
| axios | 1.18.0 |
| multer | 1.4.5 |
| morgan | 1.11.0 |
| express-validator | 7.3.2 |

---

## Modeles Mongoose

### Post

| Champ | Type | Contraintes |
|---|---|---|
| `user_id` | String | Requis, indexe |
| `username` | String | Requis |
| `content` | String | Requis, `maxlength` 280 |
| `tags` | [String] | Chaque tag `maxlength` 30 |
| `media_urls` | [String] | -- |
| `likes_count` | Number | Defaut 0, `min` 0 |
| `comments_count` | Number | Defaut 0, `min` 0 |
| `reposts_count` | Number | Defaut 0, `min` 0 |
| `is_reported` | Boolean | Defaut false |
| `created_at` | Date | Timestamp Mongoose |
| `updated_at` | Date | Timestamp Mongoose |

**Index :**
- `{ user_id: 1, created_at: -1 }`
- `{ tags: 1 }`
- `{ created_at: -1 }`

### Like

| Champ | Type | Contraintes |
|---|---|---|
| `post_id` | ObjectId (ref `Post`) | Requis |
| `user_id` | String | Requis |
| `created_at` | Date | Timestamp (creation only) |

**Index :** Index unique compose `{ post_id: 1, user_id: 1 }`

### Comment

| Champ | Type | Contraintes |
|---|---|---|
| `post_id` | ObjectId (ref `Post`) | Requis |
| `user_id` | String | Requis |
| `username` | String | Requis |
| `content` | String | Requis, `maxlength` 280 |
| `parent_comment_id` | ObjectId (ref `Comment`) | Defaut null |
| `created_at` | Date | Timestamp Mongoose |
| `updated_at` | Date | Timestamp Mongoose |

**Index :**
- `{ post_id: 1, created_at: 1 }`
- `{ parent_comment_id: 1 }`

### Repost

| Champ | Type | Contraintes |
|---|---|---|
| `post_id` | ObjectId (ref `Post`) | Requis |
| `user_id` | String | Requis |
| `created_at` | Date | Timestamp (creation only) |

**Index :** Index unique compose `{ post_id: 1, user_id: 1 }`

---

## Routes

Toutes les routes sont montees sous `/api` dans `app.js`.

### POST /api/posts

Creer un nouveau post.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `content` | string | **Oui** (max 280 caracteres) |
| `tags` | string[] | Non |
| `media_urls` | string[] | Non |

**Reponses :**

```
201 Created
{
  "message": "Post created",
  "post": {
    "_id": "objectid",
    "user_id": "uuid",
    "username": "johndoe",
    "content": "Mon premier post !",
    "tags": ["breezy", "hello"],
    "media_urls": [],
    "likes_count": 0,
    "comments_count": 0,
    "reposts_count": 0,
    "is_reported": false,
    "created_at": "2024-01-01T00:00:00.000Z",
    "updated_at": "2024-01-01T00:00:00.000Z"
  }
}
```

```
400 Bad Request
{
  "error": "Content is required"
}

401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}
```

**Logique metier :**
1. Extraire l'identite depuis les headers.
2. Valider le contenu.
3. Analyser les @mentions avec la regex `@([a-zA-Z0-9_]+)`.
4. Pour chaque mention, resoudre l'UUID via `GET USER_SERVICE_URL/users/by-username/:username`.
5. Creer le post avec `Post.create()`.
6. Envoyer une notification pour chaque mention resolue via `PROFIL_SERVICE_URL/notifications/internal`.

---

### GET /api/posts/feed

Feed principal de l'utilisateur authentifie.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Parametres de requete (query string) :**

| Champ | Type | Requis |
|---|---|---|
| `page` | integer | Non (defaut 1) |
| `limit` | integer | Non (defaut 20) |

**Reponses :**

```
200 OK
{
  "posts": [...],
  "total": 100,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. Recuperer la liste des `followingIds` depuis `GET USER_SERVICE_URL/users/:id/following` (utilise le champ `ids`).
2. Construire la liste des auteurs : `[userId, ...followingIds]`.
3. Requete `Post.find({ user_id: { $in: auteurs } })`, trie par `created_at: -1`, pagine.
4. Enrichir chaque post :
   - `likedByMe` : verifier existence dans la collection `Like` (`Like.findOne({ post_id, user_id })`).
   - `repostedByMe` : verifier existence dans la collection `Repost`.
5. Retourner les posts enrichis.

---

### GET /api/posts/search

Rechercher des posts.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Parametres de requete (query string) :**

| Champ | Type | Requis |
|---|---|---|
| `q` | string | **Oui** |
| `page` | integer | Non (defaut 1) |
| `limit` | integer | Non (defaut 20) |

**Reponses :**

```
200 OK
{
  "posts": [...],
  "total": 5,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. Utiliser `$or` sur trois champs :
   - `content` : `{ $regex: q, $options: 'i' }` (recherche insensible a la casse).
   - `tags` : correspondance exacte.
   - `username` : `{ $regex: q, $options: 'i' }`.
2. Pagination.

---

### GET /api/posts/user/:userId

Posts d'un utilisateur specifique.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Parametres :**
- `userId` (parametre URL) : UUID de l'utilisateur.

**Parametres optionnels (query) :** `page`, `limit`

**Reponses :**

```
200 OK
{
  "posts": [...],
  "total": 15,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. `Post.find({ user_id: userId })`, trie par `created_at: -1`.
2. Enrichir avec `likedByMe` et `repostedByMe`.

---

### GET /api/posts/user/:userId/media

Posts media d'un utilisateur (ceux avec `media_urls` non vides).

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Parametres :** `userId`, optionnels `page`, `limit`

**Reponses :**

```
200 OK
{
  "posts": [...],
  "total": 3,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. `Post.find({ user_id: userId, media_urls: { $exists: true, $not: { $size: 0 } } })`.

---

### GET /api/posts/user/:userId/likes

Posts qu'un utilisateur a likés.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Parametres :** `userId`, optionnels `page`, `limit`

**Reponses :**

```
200 OK
{
  "posts": [...],
  "total": 7,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. Trouver tous les `Like` de l'utilisateur.
2. Resoudre les `post_id` correspondants.
3. Retourner les posts enrichis.

---

### GET /api/posts/user/:userId/replies

Commentaires (replies) d'un utilisateur.

**Middleware :** `identity`

**Parametres :** `userId`, optionnels `page`, `limit`

**Reponses :**

```
200 OK
{
  "comments": [...],
  "total": 5,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. `Comment.find({ user_id: userId })`, trie par `created_at: -1`.

---

### GET /api/posts/user/:userId/reposts

Reposts d'un utilisateur.

**Middleware :** `identity`

**Parametres :** `userId`, optionnels `page`, `limit`

**Reponses :**

```
200 OK
{
  "posts": [...],
  "total": 2,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. Trouver tous les `Repost` de l'utilisateur.
2. Resoudre les `post_id` correspondants.

---

### GET /api/posts/:id

Recuperer un post par son ID.

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "post": { ... }
}
```

```
404 Not Found
{
  "error": "Post not found"
}
```

---

### PUT /api/posts/:id

Modifier un post (proprietaire uniquement).

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `content` | string | **Oui** |

**Reponses :**

```
200 OK
{
  "message": "Post updated",
  "post": { ... }
}
```

```
403 Forbidden
{
  "error": "FORBIDDEN"
}

404 Not Found
{
  "error": "Post not found"
}
```

**Logique metier :**
1. Trouver le post.
2. Verifier que `user_id === x-user-id`.
3. Mettre a jour le contenu.

---

### DELETE /api/posts/:id

Supprimer un post (proprietaire uniquement).

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "message": "Post deleted"
}
```

**Logique metier :**
1. Verifier le proprietaire.
2. Supprimer le post avec `Post.findByIdAndDelete`.
3. **Cascade** : supprimer tous les `Like` et `Comment` associes.

---

### POST /api/posts/:id/report

Signaler un post.

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "message": "Post reported"
}
```

**Logique metier :**
1. Marquer `is_reported = true` sur le post.

---

### POST /api/posts/:id/repost

Reposter (ou annuler un repost) un post.

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "message": "Post reposted",
  "reposted": true,
  "reposts_count": 3
}

200 OK
{
  "message": "Repost removed",
  "reposted": false,
  "reposts_count": 2
}
```

**Logique metier :**
1. **Upsert pattern** : tenter de trouver un `Repost` existant avec `findOne({ post_id, user_id })`.
2. Si existe -> supprimer le repost et `$inc: { reposts_count: -1 }`.
3. Si n'existe pas -> creer le repost et `$inc: { reposts_count: 1 }`.

---

### POST /api/posts/:id/like

Liker un post.

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "message": "Post liked",
  "likes_count": 5
}
```

```
409 Conflict
{
  "error": "ALREADY_LIKED"
}
```

**Logique metier :**
1. Tentative de creation d'un `Like` avec `create({ post_id, user_id })`.
2. Si l'index unique `{ post_id, user_id }` est viole -> MongoDB renvoie une erreur 11000 -> capture et retour `409 ALREADY_LIKED`.
3. `Post.findOneAndUpdate({ $inc: { likes_count: 1 } })`.
4. Envoyer une notification `like` au profil-service.

---

### DELETE /api/posts/:id/like

Retirer un like.

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "message": "Like removed",
  "likes_count": 4
}
```

```
400 Bad Request
{
  "error": "NOT_LIKED"
}
```

**Logique metier :**
1. Trouver et supprimer le `Like`.
2. Si introuvable -> `NOT_LIKED`.
3. `Post.findOneAndUpdate({ $inc: { likes_count: -1 } })`.

---

### GET /api/posts/:id/comments

Recuperer les commentaires d'un post.

**Middleware :** `identity`

**Parametres optionnels (query) :** `page`, `limit`

**Reponses :**

```
200 OK
{
  "comments": [...],
  "total": 10,
  "page": 1,
  "limit": 20
}
```

**Logique metier :**
1. `Comment.find({ post_id }).sort({ created_at: 1 })`.
2. Pagination.

---

### POST /api/posts/:id/comments

Ajouter un commentaire a un post.

**Middleware :** `identity`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `content` | string | **Oui** (max 280) |

**Reponses :**

```
201 Created
{
  "message": "Comment added",
  "comment": {
    "_id": "objectid",
    "post_id": "objectid",
    "user_id": "uuid",
    "username": "johndoe",
    "content": "Super post !",
    "parent_comment_id": null,
    "created_at": "...",
    "updated_at": "..."
  },
  "comments_count": 6
}
```

**Logique metier :**
1. Creer le commentaire.
2. Incrementer `comments_count` du post.
3. Envoyer notification `comment` au profil-service.

---

### PUT /api/posts/:id/comments/:commentId

Modifier un commentaire (proprietaire uniquement).

**Middleware :** `identity`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `content` | string | **Oui** |

---

### DELETE /api/posts/:id/comments/:commentId

Supprimer un commentaire (proprietaire uniquement).

**Middleware :** `identity`

**Reponses :**

```
200 OK
{
  "message": "Comment deleted",
  "comments_count": 5
}
```

**Logique metier :**
1. Verifier le proprietaire.
2. Supprimer le commentaire.
3. Decrementer `comments_count` du post.

---

### POST /api/posts/:id/comments/:commentId/replies

Repondre a un commentaire.

**Middleware :** `identity`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `content` | string | **Oui** (max 280) |

**Reponses :**

```
201 Created
{
  "message": "Reply added",
  "comment": { ... },
  "comments_count": 6
}
```

```
400 Bad Request
{
  "error": "MAX_DEPTH",
  "message": "Cannot reply to a reply"
}
```

**Logique metier :**
1. Verifier que `parent_comment_id` du commentaire cible est `null` (max 1 niveau de profondeur).
2. Si le commentaire cible est deja une reponse (`parent_comment_id !== null`) -> erreur `MAX_DEPTH`.
3. Creer le commentaire avec `parent_comment_id` defini.
4. Incrementer `comments_count`.
5. Envoyer notification `reply` au profil-service.

---

### POST /api/upload

Upload de fichiers media.

**Middleware :** `identity` + `multer`

**Headers requis :** `Content-Type: multipart/form-data`

**Taille max :** 5 Mo

**Types acceptes :** images uniquement

**Reponses :**

```
201 Created
{
  "message": "File uploaded",
  "urls": ["https://cdn.breezy.app/uploads/filename.jpg"]
}
```

```
400 Bad Request
{
  "error": "File too large",
  "maxSize": "5MB"
}

400 Bad Request
{
  "error": "Only image files are allowed"
}
```

---

## Middlewares

### identity.middleware.js

Identique aux autres services. Extrait `x-user-id`, `x-user-role`, `x-username` des headers injectes par le gateway.

### validate.middleware.js

Gestionnaire centralise des erreurs express-validator.

---

## Variables d'environnement

| Variable | Defaut | Requis | Description |
|---|---|---|---|
| `PORT` | `3003` | Non | Port d'ecoute |
| `MONGO_URI` | -- | **Oui** | URI de connexion MongoDB |
| `USER_SERVICE_URL` | -- | Non | URL du user-service (feed, mentions) |
| `PROFIL_SERVICE_URL` | -- | Non | URL du profil-service (notifications) |
| `INTERNAL_SECRET` | -- | Non | Secret pour les communications inter-services |

---

## Notes d'implementation

- Le feed est construit en interrogeant le user-service pour obtenir la liste des abonnements de l'utilisateur. Si le user-service est inaccessible, le feed echoue.
- L'enrichissement (`likedByMe`, `repostedByMe`) est fait post-requete : pour chaque post du resultat, une requete supplementaire est faite sur les collections `Like` et `Repost`. Ce n'est pas optimal pour de grandes pages.
- La detection des @mentions utilise la regex `@([a-zA-Z0-9_]+)` sur le contenu du post avant creation.
- Les notifications sont envoyees de maniere synchrone au profil-service. Un echec d'envoi de notification n'empeche pas la creation du post, mais peut entrainer des notifications manquantes.
