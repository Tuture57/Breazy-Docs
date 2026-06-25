# Auth Service

Service d'authentification : inscription, connexion, gestion des tokens (JWT + refresh tokens
avec rotation et détection de vol), changement de mot de passe, changement de username,
création de comptes par un admin, et bannissement interne.

- **Dépôt** : `breezy-auth-service`
- **Port** : `3001`
- **Base de données** : PostgreSQL `auth_db` (conteneur `pg-auth`)
- **ORM** : Sequelize 6 — **`sync({ alter: true })` au démarrage** (migration automatique)

!!! info "L'auth-service ne vérifie pas le JWT lui-même"
    Sur ses routes utilisateur (`/me`, `/change-password`…), il fait confiance au header
    `x-user-id` injecté par la gateway. `verifyToken` existe dans le code mais **n'est jamais
    utilisé** ici — la vérification de signature est déléguée à la gateway.

---

## Stack & dépendances (versions exactes)

| Paquet | Version | Rôle |
|---|---|---|
| express | `^5.2.1` | Serveur HTTP |
| sequelize | `^6.37.8` | ORM PostgreSQL |
| pg / pg-hstore | `^8.21.0` / `^2.3.4` | Driver PostgreSQL |
| bcryptjs | `^3.0.3` | Hachage des mots de passe |
| jsonwebtoken | `^9.0.3` | JWT |
| express-validator | `^7.3.2` | Validation des entrées |
| helmet | `^8.2.0` | En-têtes de sécurité HTTP |
| cookie-parser | `^1.4.7` | Lecture du cookie `refreshToken` |
| cors | `^2.8.6` | CORS |
| axios | `^1.18.0` | Appel inter-service (sync user) |

Au démarrage, si `JWT_SECRET` est absent → log d'erreur + `process.exit(1)`.

---

## Modèles de données

### Table `users`

| Colonne | Type | Contraintes / défaut |
|---|---|---|
| `id` | UUID | PK, `defaultValue: UUIDV4` |
| `email` | STRING(255) | `NOT NULL`, `UNIQUE` |
| `username` | STRING(50) | `NOT NULL`, `UNIQUE` |
| `password_hash` | STRING(255) | `NOT NULL` |
| `role` | ENUM(`user`,`moderator`,`admin`) | défaut `user` |
| `is_active` | BOOLEAN | défaut `true` |
| `is_banned` | BOOLEAN | défaut `false` |
| `created_at` / `updated_at` | TIMESTAMP | auto (Sequelize, `underscored`) |

### Table `refresh_tokens`

| Colonne | Type | Contraintes / défaut |
|---|---|---|
| `id` | UUID | PK, `defaultValue: UUIDV4` |
| `user_id` | UUID | `NOT NULL` |
| `token_hash` | STRING(512) | `NOT NULL`, `UNIQUE` (hash SHA-256 du token) |
| `expires_at` | DATE | `NOT NULL` |
| `is_revoked` | BOOLEAN | défaut `false` |
| `created_at` / `updated_at` | TIMESTAMP | auto |

**Relation** : `User.hasMany(RefreshToken, { foreignKey: 'user_id', onDelete: 'CASCADE' })`.
La suppression d'un utilisateur supprime ses refresh tokens en cascade. Aucun index explicite
au-delà des contraintes `UNIQUE` et des clés.

---

## Routes

| Méthode | Path | Middlewares | Auth |
|---|---|---|---|
| GET | `/health` | — | Public |
| POST | `/auth/register` | `registerRules`, `validate` | Public |
| POST | `/auth/login` | `loginRules`, `validate` | Public |
| POST | `/auth/refresh` | — | Cookie/body |
| POST | `/auth/logout` | — | Cookie/body |
| GET | `/auth/me` | `identity` | JWT (via gateway) |
| POST | `/auth/change-password` | `identity`, `changePasswordRules`, `validate` | JWT |
| PATCH | `/auth/username` | `identity`, `updateUsernameRules`, `validate` | JWT |
| POST | `/auth/admin/create-user` | `identity`, `adminCreateUserRules`, `validate` | JWT + rôle `admin` |
| POST | `/auth/internal/ban` | — (`x-internal-secret`) | Interne |
| GET | `/auth/internal/users/:id/role` | — (`x-internal-secret`) | Interne |

!!! tip "Routes ajoutées par rapport à l'ancienne doc"
    `PATCH /auth/username`, `POST /auth/admin/create-user` et `GET /auth/internal/users/:id/role`
    existent dans le code mais n'étaient pas documentées (ni dans le README du service). La
    dernière est appelée par le **profil-service** pour filtrer les notifications par rôle.

### Règles de validation (express-validator)

| Règle | Contraintes |
|---|---|
| `username` | trim, 3–50 caractères, regex `^[a-zA-Z0-9_]+$` |
| `email` | `isEmail` + `normalizeEmail` |
| `password` | min 8, au moins 1 majuscule, au moins 1 chiffre |

---

## Endpoints détaillés

Format d'erreur générique : `{ error: { code, message } }`. Validation échouée →
`400 VALIDATION_ERROR` avec `details: [{ field, message }]`.

### POST /auth/register

Crée un compte, synchronise le profil vers le user-service (non bloquant) et ouvre une session.

| Champ body | Type | Requis | Description |
|---|---|---|---|
| `username` | string | ✅ | 3–50, alphanumérique + `_` |
| `email` | string | ✅ | email valide |
| `password` | string | ✅ | ≥8, 1 majuscule, 1 chiffre |

- **Succès `201`** : `{ user: { id, username, email, role }, token }` + cookie `refreshToken` (httpOnly).

| Code | Erreur | Cause |
|---|---|---|
| 409 | `EMAIL_TAKEN` | Email déjà utilisé |
| 409 | `USERNAME_TAKEN` | Username déjà pris |
| 400 | `VALIDATION_ERROR` | Données invalides |
| 500 | `INTERNAL_ERROR` | Exception serveur |

### POST /auth/login

| Champ body | Type | Requis |
|---|---|---|
| `email` | string | ✅ |
| `password` | string | ✅ |

- **Succès `200`** : `{ user: { id, username, email, role }, token }` + cookie `refreshToken`.

| Code | Erreur | Cause |
|---|---|---|
| 401 | `INVALID_CREDENTIALS` | Email inexistant **ou** mauvais mot de passe (message identique → anti-énumération) |
| 403 | `ACCOUNT_BANNED` | `is_banned = true` |
| 403 | `ACCOUNT_INACTIVE` | `is_active = false` |
| 400 | `VALIDATION_ERROR` | — |

### POST /auth/refresh

Token lu dans `req.cookies.refreshToken`, sinon `req.body.refreshToken`. Implémente la
**rotation + détection de vol** (voir [Authentification](../securite/authentification.md)).

- **Succès `200`** : `{ token }` (nouvel access token) + nouveau cookie `refreshToken`.

| Code | Erreur | Cause |
|---|---|---|
| 400 | `MISSING_TOKEN` | Aucun refresh token fourni |
| 401 | `INVALID_REFRESH_TOKEN` | Token introuvable / révoqué / expiré / user invalide (+ `clearCookie`) |

### POST /auth/logout

Révoque le refresh token présenté (`is_revoked = true`) et efface le cookie. **Succès `204`**.

### GET /auth/me

Middleware `identity`. `findByPk(req.userId)`. **Succès `200`** : `{ user }` avec
`id, username, email, role, is_active, is_banned`. `404 USER_NOT_FOUND` sinon.

### POST /auth/change-password

| Champ body | Type | Requis |
|---|---|---|
| `currentPassword` | string | ✅ |
| `newPassword` | string | ✅ (≥8, majuscule, chiffre) |

Vérifie l'ancien mot de passe, re-hache le nouveau, puis **révoque tous les refresh tokens** de
l'utilisateur. **Succès `200`** : `{ message: 'Mot de passe modifié avec succès.' }`.

| Code | Erreur | Cause |
|---|---|---|
| 401 | `INVALID_PASSWORD` | `currentPassword` incorrect |
| 404 | `USER_NOT_FOUND` | — |

### PATCH /auth/username

Body `{ newUsername }`. Vérifie la disponibilité, met à jour, re-synchronise le user-service,
et **émet un nouveau JWT** (le username est dans le payload).

- **Succès `200`** : `{ user, token }` (ou `{ user }` sans token si le username est inchangé).
- **`409 USERNAME_TAKEN`** si déjà pris.

### POST /auth/admin/create-user

Réservé aux administrateurs (`req.userRole === 'admin'`, sinon `403 FORBIDDEN`). Crée un compte
avec un rôle choisi. **Ne génère ni token ni cookie.** **Succès `201`** : `{ user }`.

| Champ body | Type | Requis |
|---|---|---|
| `username`, `email`, `password` | string | ✅ |
| `role` | `user`\|`moderator`\|`admin` | ✅ |

### POST /auth/internal/ban *(interne)*

Header `x-internal-secret` requis. Body `{ userId }`. Met `is_banned = true`. Appelé par le
**user-service**. **Succès `200`** : `{ ok: true }`. `401 UNAUTHORIZED` si secret invalide,
`404 USER_NOT_FOUND` sinon.

### GET /auth/internal/users/:id/role *(interne)*

Header `x-internal-secret` requis. Renvoie `{ role }` pour l'utilisateur. Appelé par le
**profil-service** pour exclure modérateurs/admins des notifications like/follow.

---

## Mécanisme JWT, refresh token, hachage

```javascript
// auth-service/src/utils/jwt.utils.js
const generateAccessToken = (user) =>
  jwt.sign({ sub: user.id, username: user.username, role: user.role },
           process.env.JWT_SECRET,
           { expiresIn: process.env.JWT_EXPIRES_IN || '15m' });
const generateRefreshToken = () => crypto.randomBytes(64).toString('hex');
const hashToken = (t) => crypto.createHash('sha256').update(t).digest('hex');
```

| Élément | Valeur |
|---|---|
| **Payload JWT** | `{ sub, username, role }` (+ `iat`, `exp`). **Pas d'email.** |
| **Algorithme JWT** | HS256 |
| **Durée access token** | `JWT_EXPIRES_IN`, défaut `15m` (docker : `15m`) |
| **Refresh token** | 64 octets aléatoires → 128 caractères hex, opaque |
| **Stockage refresh** | hash SHA-256 uniquement (jamais en clair) |
| **Durée refresh** | `REFRESH_TOKEN_DAYS`, défaut `7` (docker : `7`) |
| **Cookie** | `httpOnly`, `secure` si `NODE_ENV=production`, `sameSite: 'Strict'` |
| **Hachage mot de passe** | bcrypt, `BCRYPT_ROUNDS` (code défaut `12`, **docker `10`**, tests `4`) |

---

## Appels inter-services

| Vers | Endpoint | Body | Headers | Timeout | Déclenché par |
|---|---|---|---|---|---|
| user-service | `POST /users/sync` | `{ id, username, role }` | `x-internal-secret` | 3000 ms | `register`, `updateUsername`, `adminCreateUser` |

Tous non bloquants (try/catch + `console.warn`) : l'opération principale réussit même si le
user-service est indisponible.

---

## Variables d'environnement

| Variable | Obligatoire | Défaut code | Usage |
|---|---|---|---|
| `PORT` | non | `3001` | Port d'écoute |
| `DATABASE_URL` | ✅ | — | Connexion PostgreSQL |
| `JWT_SECRET` | ✅ | — (sinon `exit(1)`) | Signature JWT |
| `JWT_EXPIRES_IN` | non | `15m` | Durée access token |
| `REFRESH_TOKEN_DAYS` | non | `7` | TTL refresh token |
| `BCRYPT_ROUNDS` | non | `12` | Rounds bcrypt |
| `INTERNAL_SECRET` | ✅ | — | Secret inter-services |
| `USER_SERVICE_URL` | ✅ | — | URL du user-service (sync) |
| `CORS_ORIGIN` | non | `http://localhost:3000` | Origine CORS |
| `NODE_ENV` | non | — | `production` → cookie `secure` |

---

## Dockerfile

`node:20-alpine`, `npm install`, `CMD ["npm","start"]`. Pas d'`EXPOSE`, pas de build
multi-stage, pas d'utilisateur non-root. `.dockerignore` exclut `node_modules`, `.env`, `.git`.
