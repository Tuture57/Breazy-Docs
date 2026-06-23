# User Service

Microservice de gestion des profils utilisateur et des relations (follow) pour Breezy.

---

## Stack

| Technologie | Version |
|---|---|
| Node.js | 20 (Alpine) |
| Express | 5.2.1 |
| Sequelize | 6.37.8 |
| PostgreSQL | 15 |
| axios | 1.18.0 |
| pg | 8.21.0 |

---

## Modeles

### UserProfile (`user_profiles` table)

| Champ | Type | Contraintes |
|---|---|---|
| `id` | UUID | PK (impose par auth-service, PAS auto-genere) |
| `username` | STRING(50) | NOT NULL |
| `role` | ENUM('user','moderator','admin') | DEFAULT 'user' |
| `is_active` | BOOLEAN | DEFAULT true |
| `is_banned` | BOOLEAN | DEFAULT false |
| `followers_count` | INTEGER | DEFAULT 0 (mises a jour atomiques via transactions) |
| `following_count` | INTEGER | DEFAULT 0 (mises a jour atomiques via transactions) |

### Follow (`follows` table)

| Champ | Type | Contraintes |
|---|---|---|
| `follower_id` | UUID | NOT NULL |
| `followed_id` | UUID | NOT NULL |

**Index :** Index unique sur `(follower_id, followed_id)`.

**Particularite :** Pas de colonne `updatedAt`. La table est creee avec `timestamps: { updatedAt: false }` dans la definition Sequelize.

---

## Routes

### POST /users/sync

Cree ou met a jour un profil utilisateur (appele par auth-service apres inscription).

**Middleware :** aucun (securise par `INTERNAL_SECRET`)

**Headers requis :** `x-internal-secret`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `id` | string (UUID) | **Oui** |
| `username` | string | **Oui** |
| `email` | string | Non (utilise pour creation uniquement) |

**Reponses :**

```
201 Created
{
  "message": "User profile created",
  "profile": {
    "id": "uuid",
    "username": "johndoe",
    "role": "user",
    "is_active": true,
    "is_banned": false,
    "followers_count": 0,
    "following_count": 0
  }
}

200 OK
{
  "message": "User profile synced",
  "profile": { ... }
}
```

```
403 Forbidden
{
  "error": "FORBIDDEN"
}

500 Internal Server Error (si email est absent a la creation)
```

**Logique metier :**
1. Verifier le header `x-internal-secret`.
2. Avec `findOrCreate` sur `UserProfile`, cle `id` : si trouve -> mettre a jour `username` ; si cree -> utiliser le flag `email` (present uniquement a la creation).
3. Retourner le profil.

---

### GET /users/search

Recherche d'utilisateurs par username.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Parametres de requete (query string) :**

| Champ | Type | Requis |
|---|---|---|
| `q` | string | **Oui** (terme de recherche) |
| `page` | integer | Non (defaut 1) |
| `limit` | integer | Non (defaut 20) |

**Reponses :**

```
200 OK
{
  "users": [
    {
      "id": "uuid",
      "username": "johndoe",
      "display_name": "John Doe",
      "avatar_url": "https://...",
      "bio": "Bio text...",
      "followers_count": 42
    }
  ],
  "total": 5,
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
1. Utiliser `Op.iLike` sur `username` pour une recherche partielle et insensible a la casse.
2. Exclure les utilisateurs `is_banned = true` ou `is_active = false`.
3. Trier par `followers_count DESC`.
4. Paginer avec `offset` et `limit`.

---

### GET /users/by-username/:username

Recuperer un profil public par son username.

**Middleware :** aucun (ROUTE PUBLIQUE)

**Reponses :**

```
200 OK
{
  "id": "uuid",
  "username": "johndoe",
  "display_name": "John Doe",
  "avatar_url": "https://...",
  "bio": "...",
  "followers_count": 42,
  "following_count": 10
}
```

```
404 Not Found
{
  "error": "USER_NOT_FOUND"
}
```

**Logique metier :**
1. Chercher par `username` avec `UserProfile.findOne`.
2. Utilisee par le post-service pour la resolution des @mentions (ex: `@johndoe` -> resoudre l'UUID).
3. Aucune authentification requise.

---

### GET /users/:id

Recuperer le profil complet d'un utilisateur.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Reponses :**

```
200 OK
{
  "id": "uuid",
  "username": "johndoe",
  "display_name": "John Doe",
  "avatar_url": "https://...",
  "banner_url": "https://...",
  "bio": "...",
  "location": "Paris",
  "followers_count": 42,
  "following_count": 10,
  "role": "user",
  "is_active": true,
  "is_banned": false,
  "is_following": true
}
```

```
401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}

404 Not Found
{
  "error": "USER_NOT_FOUND"
}
```

**Logique metier :**
1. Recuperer l'utilisateur par son `id`.
2. Verifier si l'utilisateur authentifie (`x-user-id`) suit cet utilisateur : requete sur la table `Follows`.
3. Ajouter le champ `is_following` (boolean).

---

### GET /users/:id/followers

Liste des abonnes (followers) d'un utilisateur.

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
  "followers": [...],
  "total": 42,
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
1. Requete `Follow.findAll({ where: { followed_id: id } })` avec `include: UserProfile` (alias follower).
2. Pagination.

---

### GET /users/:id/following

Liste des abonnements (following) d'un utilisateur.

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
  "data": [
    {
      "id": "uuid",
      "username": "janedoe",
      "display_name": "Jane Doe",
      "avatar_url": "...",
      "bio": "..."
    }
  ],
  "ids": ["uuid1", "uuid2", "uuid3"],
  "total": 10,
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
1. Requete `Follow.findAll({ where: { follower_id: id } })` avec `include: UserProfile` (alias followed).
2. Retourne DEUX formats dans la meme reponse :
   - `data` : tableau des profils complets.
   - `ids` : tableau plat des UUIDs uniquement.
3. Le format `ids` est utilise par le post-service pour construire le feed.

---

### POST /users/:id/follow

Suivre un utilisateur.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Reponses :**

```
200 OK
{
  "message": "Followed successfully",
  "followers_count": 43
}
```

```
400 Bad Request
{
  "error": "CANNOT_FOLLOW_SELF"
}

409 Conflict
{
  "error": "ALREADY_FOLLOWING"
}

404 Not Found
{
  "error": "USER_NOT_FOUND"
}

401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}
```

**Logique metier :**
1. Verifier que `x-user-id` != `id` (ne pas se follow soi-meme).
2. Verifier que la cible existe.
3. Utiliser une **transaction Sequelize** :
   - Creer l'entree dans `Follows`.
   - Incrementer `followers_count` de la cible (`UserProfile.increment`).
   - Incrementer `following_count` de l'utilisateur courant.
4. Envoyer une notification au profil-service.

---

### DELETE /users/:id/follow

Ne plus suivre un utilisateur.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Reponses :**

```
200 OK
{
  "message": "Unfollowed successfully",
  "followers_count": 42
}
```

```
400 Bad Request
{
  "error": "CANNOT_UNFOLLOW_SELF"
}

400 Bad Request
{
  "error": "NOT_FOLLOWING"
}

401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}

404 Not Found
{
  "error": "USER_NOT_FOUND"
}
```

**Logique metier :**
1. Verifier que `x-user-id` != `id`.
2. Verifier que la cible existe.
3. Verifier que la relation de follow existe.
4. Utiliser une **transaction Sequelize** :
   - Supprimer l'entree de `Follows`.
   - Decrementer `followers_count` de la cible.
   - Decrementer `following_count` de l'utilisateur courant.

---

### PUT /users/:id/ban

Bannir un utilisateur.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `ban` | boolean | **Oui** |

**Reponses :**

```
200 OK
{
  "message": "User banned successfully",
  "is_banned": true
}

200 OK
{
  "message": "User unbanned successfully",
  "is_banned": false
}
```

```
401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}

403 Forbidden
{
  "error": "INSUFFICIENT_PERMISSIONS"
}

404 Not Found
{
  "error": "USER_NOT_FOUND"
}
```

**Logique metier :**
1. Verifier que l'utilisateur authentifie a le role `moderator` ou `admin`.
2. Si le role est insuffisant -> `INSUFFICIENT_PERMISSIONS`.
3. Mettre a jour `is_banned` sur le profil local.
4. Propager le ban au auth-service via `POST /auth/internal/ban` avec le header `x-internal-secret`.

---

### GET /health

Healthcheck du service.

**Middleware :** aucun

**Reponses :**

```
200 OK
{
  "status": "ok",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

---

## Middlewares

### identity.middleware.js

Identique a celui de auth-service : extrait `x-user-id`, `x-user-role`, `x-username` des headers injectes par le gateway.

---

## Variables d'environnement

| Variable | Defaut | Requis | Description |
|---|---|---|---|
| `PORT` | `3002` | Non | Port d'ecoute |
| `DATABASE_URL` | -- | **Oui** | URL de connexion PostgreSQL |
| `INTERNAL_SECRET` | -- | Non | Secret pour les communications inter-services |
| `AUTH_SERVICE_URL` | -- | Non | URL du auth-service (pour propagation ban) |
| `PROFIL_SERVICE_URL` | -- | Non | URL du profil-service (pour notifications follow) |
| `CORS_ORIGIN` | -- | Non | Origine autorisee pour CORS |

---

## Notes d'implementation

- Les routes `/users/:id/followers` et `/users/:id/following` exposent les donnees sans verifier le statut de la cible (publique).
- La route `/users/by-username/:username` est la seule route publique (sans middleware `identity`). Elle est utilisee par le post-service pour resoudre les @mentions.
- Les compteurs `followers_count` et `following_count` sont mis a jour atomiquement via `UserProfile.increment()` a l'interieur de transactions Sequelize, garantissant la coherence meme en cas de requetes concurrentes.
- Le ban est propage au auth-service via HTTP ; si le auth-service est inaccessible, le user-service ne peut pas completer l'operation de ban.
