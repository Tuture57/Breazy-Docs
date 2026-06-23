# Schema PostgreSQL

## Vue d'ensemble

Deux bases de donnees PostgreSQL distinctes, chacune dediee a un microservice :

| Base | Service | Conteneur Docker |
|------|---------|-----------------|
| `breezy_auth` | auth-service | `breezy-db-pg-auth` (PostgreSQL 15 Alpine) |
| `breezy_users` | user-service | `breezy-db-pg-users` (PostgreSQL 15 Alpine) |

Les deux bases sont synchronisees via `sequelize.sync({ alter: true })` au demarrage de chaque service. Ce mode auto-cree et auto-modifie les tables en fonction des modeles Sequelize. Il est **destructeur en production** (peut supprimer des colonnes).

---

## Database : `breezy_auth`

### Table : `users`

Creee par le modele `User` (`auth-service/src/models/user.model.js`).

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin')),
    is_active BOOLEAN DEFAULT true,
    is_banned BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Index :**
- `users_pkey` PRIMARY KEY (id)
- `users_email_key` UNIQUE (email) -- cree par `unique: true` dans le modele
- `users_username_key` UNIQUE (username) -- cree par `unique: true` dans le modele

**Particularites :**
- Le role est un ENUM cree par Sequelize (`ENUM('user', 'moderator', 'admin')`). En SQL, cela se traduit par un CHECK.
- `password_hash` stocke le hash bcrypt (jamais le mot de passe en clair).
- Les timestamps sont geres automatiquement par Sequelize (`underscored: true` -> `created_at`, `updated_at`).

---

### Table : `refresh_tokens`

Creee par le modele `RefreshToken` (`auth-service/src/models/refreshToken.model.js`).

```sql
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(512) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_revoked BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Index :**
- `refresh_tokens_pkey` PRIMARY KEY (id)
- `refresh_tokens_token_hash_key` UNIQUE (token_hash)
- Index sur `user_id` (cree par la FK `REFERENCES users(id)`)

**Particularites :**
- `token_hash` stocke le hash SHA-256 du token brut (jamais le token en clair).
- `user_id` est lie a `users.id` avec `ON DELETE CASCADE` : si un utilisateur est supprime, tous ses refresh tokens le sont aussi.
- Plusieurs refresh tokens peuvent exister pour un meme utilisateur (support multi-appareils).
- Un token expire ou revoque peut etre conserve en base avec les flags correspondants.

---

## Database : `breezy_users`

### Table : `user_profiles`

Creee par le modele `UserProfile` (`user-service/src/models/userProfile.model.js`).

```sql
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    role VARCHAR(20) DEFAULT 'user' CHECK (role IN ('user', 'moderator', 'admin')),
    is_active BOOLEAN DEFAULT true,
    is_banned BOOLEAN DEFAULT false,
    followers_count INTEGER DEFAULT 0,
    following_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

**Index :**
- `user_profiles_pkey` PRIMARY KEY (id)

**Particularites :**
- `id` est un UUID **impose** par l'auth-service (pas de `DEFAULT gen_random_uuid()`). Le user-service recoit l'ID depuis l'auth-service via la route interne `POST /users/sync`.
- `followers_count` et `following_count` sont mis a jour atomiquement via `UserProfile.increment()` / `UserProfile.decrement()` a l'interieur de **transactions Sequelize**.
- Pas de contrainte UNIQUE sur `username` ici (la source de verite est l'auth-service).

---

### Table : `follows`

Creee par le modele `Follow` (`user-service/src/models/follow.model.js`).

```sql
CREATE TABLE follows (
    id SERIAL PRIMARY KEY,
    follower_id UUID NOT NULL,
    followed_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(follower_id, followed_id)
);
```

**Index :**
- `follows_pkey` PRIMARY KEY (id)
- `follows_follower_id_followed_id_key` UNIQUE (follower_id, followed_id)

**Particularites :**
- **Pas de colonne `updated_at`** : le modele definit `updatedAt: false`.
- **Pas de contrainte FK** : les relations sont gerees au niveau applicatif, pas en base. Cela evite les problemes de synchronisation entre les deux bases de donnees.
- `follower_id` et `followed_id` ref`erencent des UUIDs de la table `users` (auth-service), mais sans contrainte formelle.
- L'index unique empeche un utilisateur de suivre deux fois la meme personne (verification cote application + base).

---

## Synchronisation des donnees

### Flux de creation de compte

```
1. auth-service : POST /auth/register
   → Cree un enregistrement dans users (breezy_auth)
   → POST /users/sync → user-service

2. user-service : POST /users/sync (interne, x-internal-secret)
   → UserProfile.upsert({ id, username, role })
   → Cree/met a jour l'enregistrement dans user_profiles (breezy_users)
```

Le meme ID UUID est utilise dans les deux bases. La synchronisation est **non bloquante** : si le user-service est indisponible, l'inscription reste valide.

### Gestion des compteurs de follow

Les compteurs `followers_count` et `following_count` ne sont pas calcules a la volee mais stockes et mis a jour atomiquement :

```javascript
// Dans une transaction Sequelize
await UserProfile.increment('following_count', { where: { id: followerId } });
await UserProfile.increment('followers_count', { where: { id: followedId } });
```

Cette approche evite les `COUNT(*)` a chaque requete, au prix d'une synchronisation a maintenir.

---

## Notes techniques

- **`sequelize.sync({ alter: true })** : utilise en developpement dans les deux services. `alter: true` modifie les tables existantes pour correspondre aux modeles. Peut etre destructeur (suppression de colonnes) si un modele est modifie. Deconseille en production.
- **Driver PostgreSQL** : `pg` v8.21.0, avec `Sequelize` v6.37.8.
- **Connexion** : les deux services lisent `DATABASE_URL` depuis les variables d'environnement.
- **Reseau Docker** : les bases sont sur un reseau interne `breezy-network`, exposees uniquement aux services backend, pas a l'exterieur.
