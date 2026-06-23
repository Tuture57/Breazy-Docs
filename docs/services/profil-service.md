# Profil Service

Microservice de gestion des profils utilisateur (biographie, avatar, banniere) et des notifications pour Breezy.

---

## Stack

| Technologie | Version |
|---|---|
| Node.js | 20 (Alpine) |
| Express | 5.2.1 |
| Mongoose | 9.7.0 |
| MongoDB | 6 |
| axios | 1.18.0 |
| morgan | 1.11.0 |

---

## Modeles Mongoose

### Profile

| Champ | Type | Contraintes |
|---|---|---|
| `user_id` | String | Requis, UNIQUE |
| `display_name` | String | `maxlength` 100, defaut `''` |
| `bio` | String | `maxlength` 160, defaut `''` |
| `avatar_url` | String | Defaut `''` |
| `banner_url` | String | Defaut `''` |
| `location` | String | `maxlength` 100, defaut `''` |
| `created_at` | Date | Timestamp Mongoose |
| `updated_at` | Date | Timestamp Mongoose |

### Notification

| Champ | Type | Contraintes |
|---|---|---|
| `recipient_user_id` | String | Requis |
| `type` | String | Enum : `'like'`, `'follow'`, `'mention'`, `'comment'`, `'reply'` |
| `from_user_id` | String | Requis |
| `from_username` | String | Requis |
| `post_id` | String | Defaut null |
| `is_read` | Boolean | Defaut false |
| `created_at` | Date | Timestamp (creation only) |

**Index :** `{ recipient_user_id: 1, is_read: 1, created_at: -1 }`

---

## Routes

### GET /profils/:userId

Recuperer le profil d'un utilisateur (creation automatique si inexistant).

**Middleware :** aucun

**Reponses :**

```
200 OK
{
  "user_id": "uuid",
  "display_name": "John Doe",
  "bio": "Developpeur fullstack",
  "avatar_url": "https://cdn.breezy.app/avatars/uuid.jpg",
  "banner_url": "https://cdn.breezy.app/banners/uuid.jpg",
  "location": "Paris",
  "created_at": "2024-01-01T00:00:00.000Z",
  "updated_at": "2024-01-01T00:00:00.000Z"
}
```

**Logique metier :**
1. Utiliser `findOneAndUpdate` avec `upsert: true` et `$setOnInsert: { user_id }`.
2. Si le profil n'existe pas, il est cree automatiquement avec les valeurs par defaut (lazy creation / auto-provisioning).
3. Retourner le profil existant ou nouvellement cree.

---

### PUT /profils/:userId

Mettre a jour un profil (proprietaire uniquement).

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Corps de la requete (body JSON) :**

Champs autorises (whitelist) :

| Champ | Type | Requis | Contraintes |
|---|---|---|---|
| `display_name` | string | Non | `maxlength` 100 |
| `bio` | string | Non | `maxlength` 160 |
| `avatar_url` | string | Non | -- |
| `banner_url` | string | Non | -- |
| `location` | string | Non | `maxlength` 100 |

**Reponses :**

```
200 OK
{
  "message": "Profile updated",
  "profile": { ... }
}
```

```
401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}

403 Forbidden
{
  "error": "FORBIDDEN",
  "message": "You can only edit your own profile"
}
```

**Logique metier :**
1. Verifier que `x-user-id` === `userId` (proprietaire).
2. Filtrer les champs recus pour n'accepter que ceux de la whitelist (display_name, bio, avatar_url, banner_url, location). Les champs non autorises sont ignores silencieusement.
3. Mettre a jour le document avec `findOneAndUpdate`.

---

### GET /notifications

Recuperer les notifications de l'utilisateur authentifie.

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
  "notifications": [
    {
      "_id": "objectid",
      "recipient_user_id": "uuid",
      "type": "like",
      "from_user_id": "uuid2",
      "from_username": "janedoe",
      "post_id": "objectid",
      "is_read": false,
      "created_at": "2024-01-01T00:00:00.000Z"
    }
  ],
  "unread_count": 3,
  "total": 15,
  "page": 1,
  "limit": 20
}
```

```
401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}
```

**Logique metier :**
1. `Notification.find({ recipient_user_id: x-user-id })`, trie par `created_at: -1`.
2. Compter le nombre de notifications avec `is_read: false` pour `unread_count`.
3. Pagination.

---

### PUT /notifications/read-all

Marquer toutes les notifications comme lues.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Reponses :**

```
200 OK
{
  "message": "All notifications marked as read"
}
```

**Logique metier :**
1. `Notification.updateMany({ recipient_user_id: x-user-id, is_read: false }, { is_read: true })`.

---

### PUT /notifications/:id/read

Marquer une notification specifique comme lue.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Reponses :**

```
200 OK
{
  "message": "Notification marked as read"
}
```

```
404 Not Found
{
  "error": "NOTIFICATION_NOT_FOUND"
}
```

**Logique metier :**
1. Trouver la notification par `_id`.
2. Verifier que `recipient_user_id` === `x-user-id` (scope a l'utilisateur).
3. Marquer `is_read: true`.

---

### POST /notifications/internal

Creer une notification (appele par les autres services internes).

**Middleware :** aucun (securise par header `x-internal-secret`)

**Headers requis :** `x-internal-secret`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis | Description |
|---|---|---|---|
| `recipient_user_id` | string | **Oui** | UUID du destinataire |
| `type` | string | **Oui** | Enum : `like`, `follow`, `mention`, `comment`, `reply` |
| `from_user_id` | string | **Oui** | UUID de l'emetteur |
| `from_username` | string | **Oui** | Username de l'emetteur |
| `post_id` | string | Non | Optionnel, lie a un post specifique |

**Reponses :**

```
201 Created
{
  "message": "Notification created",
  "notification": { ... }
}

204 No Content
{}
```

```
403 Forbidden
{
  "error": "FORBIDDEN"
}
```

**Logique metier :**
1. Verifier le header `x-internal-secret` correspond a `INTERNAL_SECRET`.
2. **Self-notification guard** : si `recipient_user_id === from_user_id` -> retour `204 No Content` (un utilisateur ne recoit pas de notification pour ses propres actions).
3. Creer la notification avec `Notification.create()`.

---

## Middlewares

### identity.middleware.js

Identique aux autres services. Extrait `x-user-id`, `x-user-role`, `x-username` des headers injectes par le gateway.

---

## Variables d'environnement

| Variable | Defaut | Requis | Description |
|---|---|---|---|
| `PORT` | `3004` | Non | Port d'ecoute |
| `MONGO_URI` | -- | **Oui** | URI de connexion MongoDB |
| `INTERNAL_SECRET` | -- | Non | Secret pour les communications inter-services |

---

## Notes d'implementation

- Le profil est cree de maniere lazy (paresseuse) : il n'existe pas en base tant que la premiere requete `GET /profils/:userId` n'est pas faite. L'upsert avec `$setOnInsert` garantit qu'aucun doublon n'est cree.
- La self-notification guard empeche un utilisateur de recevoir des notifications pour ses propres actions (ex: se follow soi-meme declencherait une notification `follow` sans ce guard).
- Le service utilise `mongoose` avec `timestamps` (created_at, updated_at) pour Profile, mais `timestamps: { createdAt: 'created_at', updatedAt: false }` pour Notification (pas de `updated_at`).
