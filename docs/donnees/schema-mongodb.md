# Schema MongoDB

## Vue d'ensemble

Deux bases de donnees MongoDB distinctes, chacune dediee a un microservice :

| Base | Service | Conteneur Docker |
|------|---------|-----------------|
| `breezy_posts` | post-service | `breezy-db-mongo-posts` (MongoDB 6) |
| `breezy_profils` | profil-service | `breezy-db-mongo-profils` (MongoDB 6) |

Les schemas sont definis via **Mongoose** et indexes explicitement dans les modeles. Les connexions sont configurees via `MONGO_URI` dans les variables d'environnement.

---

## Database : `breezy_posts` (post-service)

### Collection : `posts`

Modele : `Post` (`post-service/src/models/post.model.js`)

```javascript
{
  _id: ObjectId,
  user_id: String,          // UUID de l'utilisateur (source: auth-service)
  username: String,          // Denormalise pour eviter les JOINs
  content: String,           // Texte du post, max 280 caracteres
  tags: [String],            // Tags, chaque tag max 30 caracteres
  media_urls: [String],      // URLs des medias uploades (images)
  likes_count: Number,       // Compteur atomique, default 0, min 0
  comments_count: Number,    // Compteur atomique, default 0, min 0
  reposts_count: Number,     // Compteur atomique, default 0, min 0
  is_reported: Boolean,      // Flag de signalement, default false
  created_at: Date,          // Cree automatiquement par timestamps: true
  updated_at: Date           // Cree automatiquement par timestamps: true
}
```

**Index :**
- `{ user_id: 1, created_at: -1 }` -- Optimise les requetes de timeline utilisateur (afficher les posts d'un utilisateur tries par date)
- `{ tags: 1 }` -- Optimise la recherche de posts par tag
- `{ created_at: -1 }` -- Optimise le tri par date dans le feed global

**Particularites :**
- `username` est denormalise dans le document post pour eviter une requete au user-service a chaque affichage.
- Les compteurs (`likes_count`, `comments_count`, `reposts_count`) sont incrementes/decrementes atomiquement via `$inc`.
- `is_reported` est un flag booleen, pas de systeme de moderation complet.
- La validation Mongoose impose `maxlength: 280` sur `content` et `maxlength: 30` sur chaque tag.

---

### Collection : `likes`

Modele : `Like` (`post-service/src/models/like.model.js`)

```javascript
{
  _id: ObjectId,
  post_id: ObjectId,      // Reference au Post (ref: 'Post')
  user_id: String,         // UUID de l'utilisateur
  created_at: Date         // Cree automatiquement, pas de updated_at
}
```

**Index :**
- `{ post_id: 1, user_id: 1 }` -- **UNIQUE** (contrainte : un like par utilisateur par post)

**Particularites :**
- Pas de champ `updated_at` (`updatedAt: false` dans le schema).
- L'index unique empeche les doublons. En cas de violation, l'erreur MongoDB 11000 est capturee et transformee en `409 ALREADY_LIKED`.
- La suppression d'un post entraine la suppression des likes associes (pas de cascade automatique, faite manuellement dans le controller).

---

### Collection : `comments`

Modele : `Comment` (`post-service/src/models/comment.model.js`)

```javascript
{
  _id: ObjectId,
  post_id: ObjectId,            // Reference au Post (ref: 'Post')
  user_id: String,               // UUID de l'utilisateur
  username: String,              // Denormalise
  content: String,               // Texte du commentaire, max 280 caracteres
  parent_comment_id: ObjectId,   // Reference au Comment parent, null pour les commentaires racines
  created_at: Date,              // Cree automatiquement
  updated_at: Date               // Cree automatiquement
}
```

**Index :**
- `{ post_id: 1, created_at: 1 }` -- Optimise le chargement des commentaires d'un post tries par date
- `{ parent_comment_id: 1 }` -- Optimise la recherche des reponses a un commentaire

**Regles de profondeur :**
- **Maximum 1 niveau** : on ne peut pas repondre a une reponse.
- Si `parent_comment_id` est non-null (c'est deja une reponse), la tentative de creer une reponse renvoie l'erreur `MAX_DEPTH`.
- Les commentaires racines : `parent_comment_id: null`.
- Les reponses : `parent_comment_id: <ObjectId du commentaire parent>`.

**Cascade :**
- A la suppression d'un commentaire, ses reponses sont egalement supprimees (`Comment.deleteMany({ parent_comment_id: commentId })`).
- Le compteur `comments_count` du post est decremente via `$inc`.

---

### Collection : `reposts`

Modele : `Repost` (`post-service/src/models/repost.model.js`)

```javascript
{
  _id: ObjectId,
  post_id: ObjectId,      // Reference au Post (ref: 'Post')
  user_id: String,         // UUID de l'utilisateur
  created_at: Date         // Cree automatiquement, pas de updated_at
}
```

**Index :**
- `{ post_id: 1, user_id: 1 }` -- **UNIQUE** (contrainte : un repost par utilisateur par post)

**Particularites :**
- Pas de champ `updated_at`.
- Le repost est un **toggle** : une seule action (POST /posts/:id/repost) qui cree ou supprime selon l'etat existant.
- Utilise `$inc` pour mettre a jour `reposts_count` sur le post.
- Pas de contenu propre : un repost est juste une reference au post original.

---

## Database : `breezy_profils` (profil-service)

### Collection : `profiles`

Modele : `Profile` (`profil-service/src/models/profile.model.js`)

```javascript
{
  _id: ObjectId,
  user_id: String,         // UUID, unique, indexe
  display_name: String,    // Nom affiche, max 100 caracteres, default ''
  bio: String,             // Biographie, max 160 caracteres, default ''
  avatar_url: String,      // URL de l'avatar, default ''
  banner_url: String,      // URL de la banniere, default ''
  location: String,        // Localisation, max 100 caracteres, default ''
  created_at: Date,        // Cree automatiquement
  updated_at: Date         // Cree automatiquement
}
```

**Index :**
- `{ user_id: 1 }` -- **UNIQUE** (un seul profil par utilisateur)

**Particularites :**
- Le profil est cree automatiquement au premier appel `GET /api/profils/:userId` via `upsert: true` et `$setOnInsert: { user_id }`. Pas besoin de pre-creation via un flux de synchronisation.
- `display_name` est distinct de `username`. Le `username` vient du user-service, le `display_name` est propre au profil.
- La mise a jour est restreinte aux champs autorises : `display_name`, `bio`, `avatar_url`, `banner_url`, `location`.
- Validation : `bio` max 160 caracteres verifiee a la fois par Mongoose et par le controller.

---

### Collection : `notifications`

Modele : `Notification` (`profil-service/src/models/notification.model.js`)

```javascript
{
  _id: ObjectId,
  recipient_user_id: String,  // UUID du destinataire
  type: String,               // Enum: 'like', 'follow', 'mention', 'comment', 'reply'
  from_user_id: String,       // UUID de l'emetteur
  from_username: String,      // Username de l'emetteur (denormalise)
  post_id: String,            // Optionnel, UUID du post concerne, default null
  is_read: Boolean,           // Flag de lecture, default false
  created_at: Date            // Cree automatiquement, pas de updated_at
}
```

**Index :**
- `{ recipient_user_id: 1, is_read: 1, created_at: -1 }` -- Optimise l'affichage des notifications non lues d'un utilisateur, triees par date

**Types de notifications :**
| Type | Declencheur | post_id |
|------|------------|---------|
| `like` | Un utilisateur like un post | Oui |
| `follow` | Un utilisateur suit un autre | Non |
| `mention` | Un utilisateur est mentionne dans un post | Oui |
| `comment` | Un utilisateur commente un post | Oui |
| `reply` | Un utilisateur repond a un commentaire | Oui |

**Particularites :**
- Pas de champ `updated_at`.
- Auto-notification bloquee : si `recipient_user_id === from_user_id`, la notification est ignoree (status 204).
- La creation de notification est **non bloquante** : les appels inter-services avec timeout court (1000ms) ne doivent pas ralentir l'operation principale.
- Le champ `post_id` est de type `String` (pas un ObjectId), car il peut contenir soit un ObjectId (pour les posts du post-service) soit etre null.

---

## Notes transverses

### Denormalisation du username
Le `username` est denormalise dans les collections `posts` et `comments`. Cela evite un appel inter-service a chaque affichage, au prix d'une eventual inconsistency si le username change. Actuellement, le username n'est pas modifiable dans l'application.

### Gestion des compteurs avec $inc
Les compteurs (`likes_count`, `comments_count`, `reposts_count`) sont mis a jour avec `$inc` plutot que recalcules a chaque requete. Cela offre :
- Avantage : performances elevees, pas de `COUNT()` couteux
- Risque : si un like est supprime deux fois, le compteur peut devenir negatif (protection : `Math.max(0, ...)`)

### Pas de contraintes inter-bases
Les services ne partagent pas de base de donnees. Les references entre collections (ex: `post_id` dans `likes` -> `_id` dans `posts`) sont au niveau applicatif uniquement. MongoDB n'impose pas d'integrite referentielle.
