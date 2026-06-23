# Flux de données

Cette page détaille les principaux flux de données dans Breezy, du navigateur jusqu'aux bases de données.

---

## 1. Inscription complète

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Nginx as Nginx (:80)
    participant Gateway as API Gateway (:3000)
    participant Auth as Auth Service (:3001)
    participant UserSvc as User Service (:3002)
    participant PGauth as PostgreSQL (auth)
    participant PGuser as PostgreSQL (users)

    Client->>Nginx: POST /api/auth/register
    Nginx->>Gateway: POST /api/auth/register

    Note over Gateway: Rate limiter (20 req/15min)

    Gateway->>Auth: POST /auth/register {username, email, password}

    Auth->>Auth: Validation express-validator (username 3-50, email, password 8+ avec maj+chiffre)
    Auth->>PGauth: SELECT users WHERE email = ?
    Auth->>PGauth: SELECT users WHERE username = ?
    Auth->>Auth: bcrypt.hash(password, 12 rounds)
    Auth->>PGauth: INSERT users (id, username, email, password_hash, role='user')

    Note over Auth: Génération des tokens
    Auth->>Auth: jwt.sign({sub: id, username, role}, JWT_SECRET, {expiresIn: '15m'})
    Auth->>Auth: crypto.randomBytes(64).toString('hex') → refreshToken
    Auth->>Auth: hashToken(refreshToken) → SHA-256
    Auth->>PGauth: INSERT refresh_tokens (token_hash, user_id, expires_at)

    Note over Auth: Sync vers User Service (non bloquant, timeout 3s)
    Auth->>UserSvc: POST /users/sync {id, username, role} [x-internal-secret]
    UserSvc->>Auth: Vérifie x-internal-secret
    UserSvc->>PGuser: UPSERT user_profiles (id, username, role)
    UserSvc-->>Auth: 201 {ok: true}

    Auth-->>Gateway: 201 {user: {id, username, email, role}, token}
    Gateway-->>Nginx: Réponse + Set-Cookie: refreshToken (httpOnly)
    Nginx-->>Client: 201 + JWT + refreshToken cookie
```

**Points clés :**
- Validation stricte : username 3-50 caractères (lettres, chiffres, underscores), email valide, password 8+ avec majuscule et chiffre
- UUID v4 généré automatiquement par Sequelize pour l'ID utilisateur
- Le refresh token est émis en cookie `httpOnly` (pas accessible en JavaScript)
- L'appel au User Service est non bloquant : si le service est down, l'inscription réussit quand même

---

## 2. Connexion

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Nginx as Nginx (:80)
    participant Gateway as API Gateway (:3000)
    participant Auth as Auth Service (:3001)
    participant PGauth as PostgreSQL (auth)

    Client->>Nginx: POST /api/auth/login
    Nginx->>Gateway: POST /api/auth/login
    Gateway->>Auth: POST /auth/login {email, password}

    Auth->>PGauth: SELECT * FROM users WHERE email = ?
    Auth->>Auth: bcrypt.compare(password, user.password_hash)

    alt Identifiants invalides
        Auth-->>Gateway: 401 {code: 'INVALID_CREDENTIALS'}
        Gateway-->>Client: 401
    else Compte banni
        Auth-->>Gateway: 403 {code: 'ACCOUNT_BANNED'}
        Gateway-->>Client: 403
    else Compte inactif
        Auth-->>Gateway: 403 {code: 'ACCOUNT_INACTIVE'}
        Gateway-->>Client: 403
    else Succès
        Auth->>Auth: generateAccessToken(user) → JWT 15min
        Auth->>Auth: generateRefreshToken() → crypto 64 bytes hex
        Auth->>PGauth: INSERT refresh_tokens (token_hash, user_id, expires_at)
        Auth-->>Gateway: 200 {user, token} + Set-Cookie: refreshToken
        Gateway-->>Client: 200 + JWT + refreshToken cookie
    end
```

---

## 3. Requête authentifiée typique

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Nginx as Nginx (:80)
    participant Gateway as API Gateway (:3000)
    participant Svc as Service Backend
    participant DB as Base de données

    Client->>Nginx: GET /api/posts/feed
    Note over Client: Header: Authorization: Bearer <JWT>

    Nginx->>Gateway: GET /api/posts/feed (avec Bearer token)

    Gateway->>Gateway: jwt.verify(token, JWT_SECRET)
    Gateway->>Gateway: Extrait payload: {sub, username, role}

    alt Token invalide ou expiré
        Gateway-->>Client: 401 "Invalid or expired token"
    else Token valide
        Gateway->>Gateway: Injecte x-user-id, x-user-role, x-user-username
        Gateway->>Svc: Requête proxyfiée avec headers d'identité

        Svc->>Svc: Lit x-user-id depuis les headers
        Svc->>DB: Requête (find, insert, update, delete)
        DB-->>Svc: Résultat
        Svc-->>Gateway: Réponse JSON
        Gateway-->>Client: Réponse JSON
    end
```

**Détail des headers injectés par route :**

| Route | Headers injectés |
|---|---|
| `/api/auth/me` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/auth/change-password` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/users/*` | `x-user-id`, `x-user-role` (pas de username) |
| `/api/posts/*` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/upload` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/profils/*` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/notifications/*` | `x-user-id`, `x-user-role`, `x-user-username` |

---

## 4. Création de post avec mention @

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Gateway as API Gateway
    participant Post as Post Service (:3003)
    participant UserSvc as User Service (:3002)
    participant Profil as Profil Service (:3004)
    participant MongoP as MongoDB (posts)
    participant MongoPr as MongoDB (profils)

    Client->>Gateway: POST /api/posts {content: "Salut @arthur !"}
    Note over Client: Authorization: Bearer <JWT>

    Gateway->>Gateway: Vérifie JWT, injecte headers
    Gateway->>Post: POST /api/posts/ [x-user-id, x-user-username]

    Post->>Post: Validation (content max 280, tags max 5)
    Post->>MongoP: INSERT post (user_id, username, content, tags, media_urls)
    Post->>Post: Détecte "@arthur" dans le contenu

    Note over Post: Logique mentions (non bloquante)
    Post->>UserSvc: GET /users/by-username/arthur [x-user-id]
    UserSvc->>Post: 200 {id: "uuid-d-arthur"}

    Post->>Profil: POST /api/notifications/internal [x-internal-secret]
    Note over Profil: Vérifie x-internal-secret
    Profil->>MongoPr: INSERT notification (type: 'mention', recipient: arthur, from: sender)
    Profil-->>Post: 201

    Post-->>Gateway: 201 {post object}
    Gateway-->>Client: 201
```

**Caractéristiques :**
- La détection des mentions se fait par regex `@([a-zA-Z0-9_]+)` sur le contenu
- Chaque mention résout le username via User Service
- Le timeout de l'appel mention est de 1 seconde
- Les échecs sont silencieusement ignorés (le post est publié même si les notifications échouent)
- Les auto-mentions sont ignorées (on ne se notifie pas soi-même)

---

## 5. Like avec notification

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Gateway as API Gateway
    participant Post as Post Service (:3003)
    participant Profil as Profil Service (:3004)
    participant MongoP as MongoDB (posts)

    Client->>Gateway: POST /api/posts/:id/like
    Note over Client: Authorization: Bearer <JWT>

    Gateway->>Gateway: Vérifie JWT, injecte headers
    Gateway->>Post: POST /api/posts/:id/like [x-user-id, x-user-username]

    Post->>MongoP: LIKE.find({post_id, user_id}) → vérification unique
    Post->>MongoP: INSERT like (post_id, user_id)
    Post->>MongoP: UPDATE posts SET likes_count++ WHERE _id = ?

    Note over Post: Notification (non bloquante, timeout 1s)
    Post->>Profil: POST /api/notifications/internal [x-internal-secret]
    Note over Profil: Vérifie x-internal-secret
    Profil->>MongoP: INSERT notification (type: 'like', recipient: post.user_id, from: liker)
    Profil-->>Post: 201

    Post-->>Gateway: 200 {likes_count: N}
    Gateway-->>Client: 200
```

**En cas de doublon :**
- MongoDB renvoie une erreur `11000` (index unique `{post_id, user_id}`)
- Le service retourne `409 ALREADY_LIKED`

---

## 6. Follow avec notification

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Gateway as API Gateway
    participant UserSvc as User Service (:3002)
    participant Profil as Profil Service (:3004)
    participant PGuser as PostgreSQL (users)
    participant MongoPr as MongoDB (profils)

    Client->>Gateway: POST /api/users/:id/follow
    Note over Client: Authorization: Bearer <JWT>

    Gateway->>Gateway: Vérifie JWT, injecte x-user-id, x-user-role
    Gateway->>UserSvc: POST /users/:id/follow [x-user-id]

    UserSvc->>UserSvc: Vérifie que :id != x-user-id (pas d'auto-follow)
    UserSvc->>PGuser: BEGIN TRANSACTION
    UserSvc->>PGuser: Follow.findOrCreate({follower_id, followed_id})
    UserSvc->>PGuser: UPDATE user_profiles SET following_count++ WHERE id = follower_id
    UserSvc->>PGuser: UPDATE user_profiles SET followers_count++ WHERE id = followed_id
    UserSvc->>PGuser: COMMIT

    Note over UserSvc: Notification (non bloquante, timeout 1s)
    UserSvc->>Profil: POST /api/notifications/internal [x-internal-secret]
    Note over Profil: Vérifie x-internal-secret
    Profil->>MongoPr: INSERT notification (type: 'follow', recipient: followed, from: follower)
    Profil-->>UserSvc: 201

    UserSvc-->>Gateway: 200 {message: "Vous suivez maintenant @username."}
    Gateway-->>Client: 200
```

**Cas particuliers :**
- Auto-follow : `400 CANNOT_SELF_FOLLOW`
- Double follow : `409 ALREADY_FOLLOWING` (vérifié par la transaction + findOrCreate)
- Cible inexistante : `404 USER_NOT_FOUND`
- Unfollow : `DELETE /users/:id/follow` → `204` (succès) ou `404 NOT_FOLLOWING`

---

## 7. Rafraîchissement de token (refresh)

```mermaid
sequenceDiagram
    participant Client as Navigateur
    participant Gateway as API Gateway
    participant Auth as Auth Service
    participant PGauth as PostgreSQL (auth)

    Note over Client: L'access token a expiré (401)
    Client->>Gateway: POST /api/auth/refresh (Cookie: refreshToken=xxx)

    Gateway->>Auth: POST /auth/refresh

    Auth->>Auth: hashToken(refreshToken) → SHA-256
    Auth->>PGauth: SELECT * FROM refresh_tokens WHERE token_hash = ?

    alt Token introuvable
        Auth-->>Client: 401 INVALID_REFRESH_TOKEN + Clear-Cookie
    else Token déjà révoqué (vol)
        Auth->>PGauth: UPDATE refresh_tokens SET is_revoked=true WHERE user_id = ?
        Auth-->>Client: 401 INVALID_REFRESH_TOKEN + Clear-Cookie
    else Token expiré
        Auth->>PGauth: UPDATE refresh_tokens SET is_revoked=true WHERE id = ?
        Auth-->>Client: 401 INVALID_REFRESH_TOKEN + Clear-Cookie
    else Utilisateur banni/inactif
        Auth->>PGauth: UPDATE refresh_tokens SET is_revoked=true WHERE id = ?
        Auth-->>Client: 401 INVALID_REFRESH_TOKEN + Clear-Cookie
    else Succès
        Note over Auth: Rotation: ancien token révoqué
        Auth->>PGauth: UPDATE refresh_tokens SET is_revoked=true WHERE id = ?
        Note over Auth: Nouveau refresh token généré
        Auth->>Auth: crypto.randomBytes(64).toString('hex')
        Auth->>PGauth: INSERT refresh_tokens (token_hash, user_id, expires_at)
        Note over Auth: Nouvel access token généré
        Auth->>Auth: jwt.sign({sub, username, role}, JWT_SECRET, {expiresIn: '15m'})
        Auth-->>Client: 200 {token: nouveau_JWT} + Set-Cookie: nouveau_refreshToken
    end
```

---

## 8. Refresh token côté frontend

```mermaid
sequenceDiagram
    participant Client as Application React
    participant API as Axios Instance

    Client->>API: Requête avec JWT
    API->>API: Intercepte 401

    Note over Client,API: Vérifie si la requête était /auth/login ou /auth/refresh
    alt Login 401
        API-->>Client: Rejette (le composant gère)
    else Refresh 401
        API->>API: Clear token + redirige /signin
    else Autre 401
        Note over API: Marque _retry=true
        API->>API: POST /auth/refresh (avec cookie)
        alt Refresh réussi
            API->>API: Stocke nouveau JWT
            API->>API: Rejoue la requête originale avec nouveau JWT
            API-->>Client: Résultat de la requête originale
        else Refresh échoué
            API->>API: Clear token + redirige /signin
        end
    end
```

Le mécanisme implémente un `failedQueue` : si plusieurs requêtes échouent simultanément avec 401, une seule tentative de refresh est effectuée, et les autres requêtes sont mises en attente puis rejouées avec le nouveau token.
