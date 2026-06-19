# Post Service

**Responsabilité** : Création de posts, feed basé sur les abonnements, likes, commentaires avec réponses, recherche par tag et signalement.

- **Stack** : Node.js, Express 5, Mongoose 9, MongoDB 6, axios, morgan
- **Port** : 3003
- **Dépôt** : `breezy-post-service`
- **Tests** : Aucun test automatisé

## Structure du projet

```
breezy-post-service/
├── index.js                          ← Point d'entrée, lance le serveur
├── src/
│   ├── app.js                        ← Configuration Express, morgan, routes montées sur /api
│   ├── config/
│   │   └── database.js               ← Connexion MongoDB via Mongoose
│   ├── controllers/
│   │   ├── post.controller.js        ← CRUD posts, feed, recherche, signalement
│   │   ├── like.controller.js        ← Like/unlike avec notification
│   │   └── comment.controller.js     ← Commentaires et réponses
│   ├── models/
│   │   ├── post.model.js             ← Schéma Mongoose Post
│   │   ├── like.model.js             ← Schéma Mongoose Like
│   │   └── comment.model.js          ← Schéma Mongoose Comment
│   └── routes/
│       └── post.routes.js            ← Toutes les routes (posts, likes, commentaires)
```

!!! note "Montage des routes"
    Les routes sont montées sur `/api` dans `app.js`, donc les routes définies dans `post.routes.js` sont accessibles via `/api/posts/...`.

## Routes API

### Posts

| Méthode | Route | Description |
|---------|-------|-------------|
| `POST` | `/api/posts` | Créer un post |
| `GET` | `/api/posts/:id` | Récupérer un post par ID |
| `DELETE` | `/api/posts/:id` | Supprimer un post |
| `GET` | `/api/posts/feed` | Feed des abonnements |
| `GET` | `/api/posts/user/:userId` | Posts d'un utilisateur |
| `GET` | `/api/posts/search` | Recherche par tag |
| `POST` | `/api/posts/:id/report` | Signaler un post |

### Likes

| Méthode | Route | Description |
|---------|-------|-------------|
| `POST` | `/api/posts/:id/like` | Liker un post |
| `DELETE` | `/api/posts/:id/like` | Retirer un like |

### Commentaires

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/api/posts/:id/comments` | Commentaires d'un post |
| `POST` | `/api/posts/:id/comments` | Ajouter un commentaire |
| `POST` | `/api/posts/:id/comments/:commentId/replies` | Répondre à un commentaire |

## Détail des endpoints

### POST /api/posts

Crée un nouveau post. L'identité de l'auteur est lue depuis les headers `x-user-id` et `x-user-username`.

**Body :**

```json
{
  "content": "string (1-280 caractères, requis)",
  "tags": ["string"] ,
  "media_urls": ["string"]
}
```

**Validation :**

- `content` : requis, max 280 caractères
- `tags` : max 5 éléments

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `201` | `Post` (objet complet) | Succès |
| `400` | `{error: {code: 'INVALID_CONTENT', message}}` | Contenu vide ou > 280 chars |
| `400` | `{error: {code: 'TOO_MANY_TAGS', message}}` | Plus de 5 tags |

(`post.controller.js` lignes 7-21)

---

### GET /api/posts/feed

Récupère le feed de l'utilisateur basé sur ses abonnements. Appelle le user-service pour obtenir la liste des IDs suivis, puis requête les posts MongoDB correspondants.

**Query params :**

| Param | Default | Description |
|-------|---------|-------------|
| `page` | 1 | Page courante |
| `limit` | 20 | Posts par page |

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: Post[], pagination: {page, limit, total, hasNext}}` |

!!! warning "Dépendance au user-service"
    Le feed dépend du user-service pour récupérer les IDs suivis. Si le user-service est indisponible, un feed vide est retourné (pas d'erreur 500).

(`post.controller.js` lignes 49-84)

---

### DELETE /api/posts/:id

Supprime un post et tous ses likes et commentaires associés. L'auteur du post **OU** un modérateur/admin peuvent supprimer.

**Réponses :**

| Code | Condition |
|------|-----------|
| `204` | Succès |
| `403` | `{error: {code: 'FORBIDDEN'}}` — ni auteur ni modérateur |
| `404` | `{error: {code: 'POST_NOT_FOUND'}}` |

(`post.controller.js` lignes 31-47)

---

### POST /api/posts/:id/like

Like un post. Crée un document Like et incrémente le compteur `likes_count` du post via `$inc` (atomique). Envoie une notification au profil-service.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{likes_count: number}` | Succès |
| `404` | `{error: {code: 'POST_NOT_FOUND'}}` | Post inexistant |
| `409` | `{error: {code: 'ALREADY_LIKED', message}}` | Déjà liké (index unique) |

**Effet de bord** : notification `type: 'like'` envoyée au profil-service (timeout 1s, non bloquant).

(`like.controller.js` lignes 6-45)

---

### DELETE /api/posts/:id/like

Retire un like et décrémente le compteur.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{likes_count: number}` | Succès |
| `404` | `{error: {code: 'LIKE_NOT_FOUND'}}` | Pas de like à retirer |

(`like.controller.js` lignes 48-63)

---

### GET /api/posts/:id/comments

Récupère les commentaires d'un post avec leurs réponses imbriquées. Seuls les commentaires racines (sans `parent_comment_id`) sont paginés ; les réponses sont chargées intégralement pour chaque commentaire.

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: [{...comment, replies: Comment[]}], pagination}` |

(`comment.controller.js` lignes 5-28)

---

### POST /api/posts/:id/comments/:commentId/replies

Crée une réponse à un commentaire. La profondeur est limitée à **1 niveau** : on ne peut pas répondre à une réponse.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `201` | `Comment` | Succès |
| `400` | `{error: {code: 'MAX_DEPTH', message}}` | Réponse à une réponse |
| `404` | `{error: {code: 'COMMENT_NOT_FOUND'}}` | Commentaire parent inexistant |

(`comment.controller.js` lignes 53-75)

---

### GET /api/posts/search

Recherche de posts par tag.

**Query params :**

| Param | Description |
|-------|-------------|
| `tag` | Tag à rechercher (converti en minuscules) |
| `page` | Page (default: 1) |
| `limit` | Résultats par page (default: 20) |

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: Post[], pagination}` |
| `400` | `{error: {code: 'MISSING_TAG'}}` |

(`post.controller.js` lignes 103-118)

---

### POST /api/posts/:id/report

Signale un post en mettant `is_reported: true`.

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{message: 'Post signalé.'}` |

(`post.controller.js` lignes 121-124)

## Configuration

| Variable d'env | Requis | Default | Description |
|----------------|--------|---------|-------------|
| `MONGO_URI` | **Oui** | — | URL MongoDB |
| `PORT` | Non | 3003 | Port d'écoute |
| `USER_SERVICE_URL` | Non | — | URL du user-service (pour le feed) |
| `PROFIL_SERVICE_URL` | Non | — | URL du profil-service (pour les notifications) |
| `INTERNAL_SECRET` | Non | — | Secret inter-services |
