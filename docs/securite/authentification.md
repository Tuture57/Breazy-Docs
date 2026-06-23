# Authentification et Securite

## Architecture globale

L'authentification repose sur un **double token system** (JWT + Refresh Token) avec une **gateway centralisee** qui verifie les JWT et injecte les headers d'identite dans les services backend.

```
Client  →  NGINX  →  Gateway  →  auth-service (login, register, refresh)
               ↓
          (verifie JWT)
               ↓
          injecte headers x-user-id, x-user-role, x-user-username
               ↓
     ┌──────┬──────┬────────┬──────────┐
     ↓      ↓      ↓        ↓          ↓
   auth   user   post   profil   upload
```

Les services backend **ne verifient jamais le JWT eux-memes** : ils font confiance aux headers injectes par la gateway.

---

## JWT (Access Token)

### Structure du payload

```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "username": "johndoe",
  "role": "user",
  "iat": 1718000000,
  "exp": 1718000900
}
```

| Champ | Valeur | Description |
|-------|--------|-------------|
| `sub` | UUID | Identifiant unique de l'utilisateur |
| `username` | string | Nom d'utilisateur |
| `role` | `user` / `moderator` / `admin` | Role pour les permissions |
| `iat` | timestamp Unix | Date d'emission |
| `exp` | timestamp Unix | Date d'expiration |

### Generation

```javascript
// auth-service/src/utils/jwt.utils.js
const generateAccessToken = (user) =>
  jwt.sign(
    { sub: user.id, username: user.username, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '15m' }
  );
```

- **Algorithme** : HS256 (HMAC avec SHA-256)
- **Duree de vie** : `JWT_EXPIRES_IN` (defaut : `15m` = 15 minutes)
- **Secret** : `JWT_SECRET` (variable d'environnement, verifiee au demarrage)
- **Bibliotheque** : `jsonwebtoken`

### Verification (Gateway)

```javascript
// gateway/src/middleware/auth.js
function authenticate(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded; // { sub, username, role, iat, exp }
    next();
}
```

### Injection des headers

Apres verification du JWT, la gateway injecte les headers suivants dans la requete vers le service backend :

| Header | Source | Services qui le recoivent |
|--------|--------|--------------------------|
| `x-user-id` | `req.user.sub` | auth-service, user-service, post-service, profil-service |
| `x-user-role` | `req.user.role` | auth-service, user-service, post-service, profil-service |
| `x-user-username` | `req.user.username` | auth-service (me, change-password), post-service, profil-service |

**IMPORTANT** : Le header `x-user-username` n'est PAS injecte pour les routes du user-service (`/api/users/*`). Cela signifie que les controllers du user-service qui lisent `req.username` (via le middleware identity) recevront `undefined`. Cela affecte notamment l'envoi de notifications de follow.

---

## Refresh Token

### Generation

```javascript
const generateRefreshToken = () =>
  crypto.randomBytes(64).toString('hex');
```

- **Entropie** : 512 bits (64 octets aleatoires)
- **Format** : chaine hexadecimale (128 caracteres)
- **Stockage** : jamais en clair, hash SHA-256 uniquement

### Stockage en base

```sql
-- Table refresh_tokens
token_hash VARCHAR(512) NOT NULL UNIQUE  -- SHA-256(token)
expires_at TIMESTAMP NOT NULL
is_revoked BOOLEAN DEFAULT false
```

### Livraison au client

Le refresh token est envoye dans un cookie HTTP-only :

```javascript
const cookieOptions = {
  httpOnly: true,                           // Inaccessible depuis JavaScript
  secure: process.env.NODE_ENV === 'production',  // HTTPS seulement en prod
  sameSite: 'Strict',                       // Protege contre les CSRF
  maxAge: REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000,  // Duree de vie
};
res.cookie('refreshToken', refreshToken, cookieOptions);
```

**Duree de vie** : `REFRESH_TOKEN_DAYS` (defaut 7 jours).

### Rotation et detection de vol

Le refresh token implemente un mecanisme de **rotation avec detection de rejeu** :

1. Le client presente un refresh token valide
2. L'ancien token est **reveque** (`is_revoked = true`)
3. Un **nouveau** refresh token est emis
4. Token expire ou deja reveque -> `401 INVALID_REFRESH_TOKEN`

**Detection de vol** : si un token deja reveque est presente (vol de session), **tous les tokens** de l'utilisateur sont reveques :

```javascript
if (stored.is_revoked) {
  await RefreshToken.update(
    { is_revoked: true },
    { where: { user_id: stored.user_id } }
  );
  // L'attaquant ET l'utilisateur legitime sont deconnectes
}
```

---

## Hachage des mots de passe

```javascript
const bcrypt = require('bcryptjs');
const password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
```

- **Bibliotheque** : `bcryptjs`
- **Rounds de salage** : `BCRYPT_ROUNDS` (defaut : 12)
- **Valeur reelle dans `.env`** : 10
- **Verification** : `bcrypt.compare(password, user.password_hash)`

---

## Rate Limiting (double couche)

### Couche 1 : Nginx

Configure dans `infra/nginx/nginx.conf` :

```
limit_req_zone $binary_remote_addr zone=global:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;
```

| Zone | Taux | Application |
|------|------|-------------|
| `global` | 30 req/min | Toutes les requetes passant par NGINX |
| `auth` | 5 req/min | Routes /api/auth/* |

### Couche 2 : Gateway (express-rate-limit)

Configure dans `infra/gateway/src/index.js` :

```javascript
const globalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,  // 15 minutes
    max: 500,                    // 500 requetes
});

const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,  // 15 minutes
    max: 20,                     // 20 tentatives
});
app.use('/api/auth/login', authLimiter);
app.use('/api/auth/register', authLimiter);
```

**ATTENTION** : Docker Compose definit `NODE_ENV=test` pour la gateway, ce qui **desactive** le rate limiting (`max: 999999`). En production, cette valeur doit etre supprimee du docker-compose.yml.

---

## Flux d'authentification complet

### 1. Connexion

```
Client                    Gateway                  auth-service
  │                         │                         │
  │── POST /api/auth/login ─┤                         │
  │    {email, password}     │── POST /auth/login ─────┤
  │                         │    (sans verif JWT)      │── bcrypt.compare()
  │                         │                         │── Verif is_banned
  │                         │                         │── Verif is_active
  │                         │                         │── Gen JWT + RefreshToken
  │                         │                         │── Stocke refresh hash
  │                         │◄── {token, user} ───────┤
  │                         │    + Set-Cookie: refreshToken
  │◄── {token, user} ──────┤                         │
  │    + refreshToken cookie                         │
```

### 2. Requetes authentifiees

```
Client                    Gateway                    Service
  │                         │                         │
  │── GET /api/posts/feed ──┤                         │
  │    Authorization:       │── jwt.verify(token) ────│
  │    Bearer <JWT>         │                         │
  │                         │── x-user-id: <uuid> ────┤
  │                         │── x-user-role: user ────┤
  │                         │── x-user-username: john ┤
  │                         │                         │
  │                         │◄── response ────────────┤
  │◄── response ───────────┤                         │
```

### 3. Refresh automatique (interceptor Axios)

```javascript
// Frontend: api.js interceptor
api.interceptors.response.use(
  (res) => res,
  async (err) => {
    if (err.response?.status === 401 && !originalRequest._retry) {
      const { data } = await api.post('/auth/refresh');
      localStorage.setItem('breezy_token', data.token);
      originalRequest.headers.Authorization = `Bearer ${data.token}`;
      return api(originalRequest);
    }
    if (err.response?.status === 401 && is refresing) {
      // File d'attente : les requetes echouent jusqu'au refresh
    }
  }
);
```

Si le refresh echoue : le token est supprime du localStorage, l'utilisateur est redirige vers `/signin`.

---

## Flux de bannissement

```
Moderateur                 user-service              auth-service
  │                         │                         │
  │── PUT /users/:id/ban ──┤                         │
  │    (JWT, role=moderator)│── Verif role ───────────│
  │                         │── Update is_banned=true │
  │                         │                         │
  │                         │── POST /auth/internal ──┤
  │                         │    /ban (x-internal-    │
  │                         │    secret)              │── Update is_banned=true
  │                         │                         │
  │◄── 200 OK ─────────────┤                         │
```

**Comportement apres bannissement :**
- Nouveaux login : `403 ACCOUNT_BANNED`
- Sessions existantes : le JWT reste valide jusqu'a expiration (max 15 min)
- Tentative de refresh : echoue car l'utilisateur est verifie pendant le refresh
- Tous les refresh tokens sont reveques (change-password revaque aussi)

---

## Securite inter-services

### Header `x-internal-secret`

Les communications entre services backend utilisent un secret partage :

```javascript
// Verification cote recepteur
if (req.headers['x-internal-secret'] !== process.env.INTERNAL_SECRET) {
  return res.status(401).json({ error: { code: 'UNAUTHORIZED' } });
}
```

**Routes concernees :**
- `POST /auth/internal/ban` (auth-service)
- `POST /users/sync` (user-service)
- `POST /api/notifications/internal` (profil-service)

**Jamais expose au client** : la gateway ne transmet pas ce header.

### Headers injectes par la gateway

Les headers `x-user-id`, `x-user-role`, `x-user-username` sont ajoutes par la gateway APRES verification du JWT. Les services backend leur font aveuglement confiance. Si un attaquant parvenait a contourner la gateway (appel direct a un service), il pourrait usurper n'importe quelle identite en envoyant ces headers.

---

## Divergences de validation frontend / backend

### Validation du mot de passe

| Couche | Validation | Fichier |
|--------|-----------|---------|
| **Frontend generique** (`isValidPassword`) | >= 6 caracteres | `frontend/src/utils/validators.js` |
| **Frontend formulaire** (`validateRegisterForm`) | >= 8 caracteres, >= 1 majuscule, >= 1 chiffre | `frontend/src/utils/validators.js` |
| **Backend** (express-validator) | >= 8 caracteres, >= 1 majuscule, >= 1 chiffre | `auth-service/src/routes/auth.routes.js` |

Le formulaire d'inscription frontend et le backend sont coherents, mais la fonction utilitaire `isValidPassword` est plus permissive (>= 6 caracteres sans complexite).

### Validation du username

| Couche | Validation |
|--------|-----------|
| **Frontend** (`isValidUsername`) | >= 2 caracteres |
| **Backend** | 3-50 caracteres, alphanumerique + underscores |

### Injection du header x-user-username

| Service | x-user-username injecte par la gateway |
|---------|--------------------------------------|
| auth-service (me, change-password) | Oui |
| post-service | Oui |
| profil-service | Oui |
| user-service | **NON** |

Le user-service ne recoit pas le header `x-user-username` de la gateway. Les controllers qui utilisent `req.username` (ex: notification de follow) recevront `undefined`.

---

## Protection contre les attaques

| Attaque | Protection |
|---------|-----------|
| **Force brute** | Double rate limiting (NGINX 5 req/min + Gateway 20 req/15min) |
| **Enumeration de comptes** | Message identique `INVALID_CREDENTIALS` que l'email existe ou non |
| **Vol de JWT** | Duree de vie courte (15 min), signature HMAC |
| **Vol de refresh token** | Rotation + detection de rejeu -> revocation de tous les tokens |
| **XSS** | Refresh token dans cookie httpOnly (inaccessible depuis JS) |
| **CSRF** | Cookie `sameSite: Strict` |
| **Auto-notification** | Ignoree si `recipient === sender` (profil-service) |
