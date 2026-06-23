# Auth Service

Microservice d'authentification et de gestion des utilisateurs pour Breezy.

---

## Stack

| Technologie | Version |
|---|---|
| Node.js | 20 (Alpine) |
| Express | 5.2.1 |
| Sequelize | 6.37.8 |
| PostgreSQL | 15 |
| bcryptjs | 3.0.3 |
| jsonwebtoken | 9.0.3 |
| cookie-parser | 1.4.7 |
| express-validator | 7.3.2 |
| axios | 1.18.0 |
| pg | 8.21.0 |

---

## Modèles

### User (`users` table)

| Champ | Type | Contraintes |
|---|---|---|
| `id` | UUID | PK, auto-généré (`UUIDV4`) |
| `email` | STRING(255) | NOT NULL, UNIQUE |
| `username` | STRING(50) | NOT NULL, UNIQUE |
| `password_hash` | STRING(255) | NOT NULL |
| `role` | ENUM('user','moderator','admin') | DEFAULT 'user' |
| `is_active` | BOOLEAN | DEFAULT true |
| `is_banned` | BOOLEAN | DEFAULT false |

### RefreshToken (`refresh_tokens` table)

| Champ | Type | Contraintes |
|---|---|---|
| `id` | UUID | PK, auto-généré (`UUIDV4`) |
| `user_id` | UUID | NOT NULL, FK -> User.id (CASCADE on delete) |
| `token_hash` | STRING(512) | NOT NULL, UNIQUE (SHA-256 du refresh token) |
| `expires_at` | DATE | NOT NULL |
| `is_revoked` | BOOLEAN | DEFAULT false |

---

## Routes

### POST /auth/register

Création d'un nouveau compte utilisateur.

**Middleware :** `registerRules`, `validate`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis | Validation |
|---|---|---|---|
| `email` | string | **Oui** | Email valide |
| `username` | string | **Oui** | 3-50 caracteres, alphanumerique + underscores |
| `password` | string | **Oui** | Min 8 caracteres, 1 majuscule, 1 chiffre |

**Reponses :**

```
201 Created
{
  "message": "User registered successfully",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "username": "johndoe",
    "role": "user",
    "is_active": true,
    "is_banned": false,
    "createdAt": "2024-01-01T00:00:00.000Z",
    "updatedAt": "2024-01-01T00:00:00.000Z"
  }
}
```

```
400 Bad Request
{
  "error": "VALIDATION_ERROR",
  "details": [
    { "field": "email", "message": "Must be a valid email address" },
    { "field": "password", "message": "Password must be at least 8 characters, include 1 uppercase letter and 1 digit" }
  ]
}

409 Conflict
{
  "error": "EMAIL_ALREADY_EXISTS"
}

409 Conflict
{
  "error": "USERNAME_ALREADY_EXISTS"
}
```

**Logique metier :**
1. Valider les champs avec express-validator.
2. Verifier qu'aucun utilisateur n'existe deja avec cet email ou ce username (requetes Sequelize separees).
3. Hasher le mot de passe avec `bcryptjs` (salt rounds depuis `BCRYPT_ROUNDS`, valeur par defaut 12, mais .env utilise 10).
4. Creer l'utilisateur avec `User.create()`.
5. Retourner l'utilisateur cree (sans le mot de passe).

---

### POST /auth/login

Authentification par email/mot de passe.

**Middleware :** `loginRules`, `validate`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `email` | string | **Oui** |
| `password` | string | **Oui** |

**Reponses :**

```
200 OK
{
  "message": "Login successful",
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "abc123def456...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "username": "johndoe",
    "role": "user",
    "is_active": true,
    "is_banned": false
  }
}
```

```
400 Bad Request
{
  "error": "VALIDATION_ERROR",
  "details": [...]
}

401 Unauthorized
{
  "error": "INVALID_CREDENTIALS"
}

401 Unauthorized
{
  "error": "ACCOUNT_BANNED"
}

401 Unauthorized
{
  "error": "ACCOUNT_INACTIVE"
}
```

**Logique metier :**
1. Trouver l'utilisateur par email avec `User.findOne({ where: { email } })`.
2. Si introuvable -> `INVALID_CREDENTIALS`.
3. Si `is_banned` est true -> `ACCOUNT_BANNED`.
4. Si `is_active` est false -> `ACCOUNT_INACTIVE`.
5. Comparer le mot de passe avec `bcrypt.compare(password, user.password_hash)`.
6. Si echec -> `INVALID_CREDENTIALS`.
7. Generer un access token JWT (payload : `{ id, email, username, role }`, expire selon `JWT_EXPIRES_IN`, defaut `15m`).
8. Generer un refresh token aleatoire avec `crypto.randomBytes(40).toString('hex')`.
9. Hasher le refresh token (SHA-256) et le stocker dans la table `refresh_tokens` avec `expires_at` = maintenant + `REFRESH_TOKEN_DAYS` (defaut 7 jours).
10. Retourner les tokens et l'utilisateur.

---

### POST /auth/refresh

Rafraichir un access token expire.

**Middleware :** aucun

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `refresh_token` | string | **Oui** |

**Reponses :**

```
200 OK
{
  "message": "Token refreshed successfully",
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "newRefreshtoken456..."
}
```

```
401 Unauthorized
{
  "error": "INVALID_REFRESH_TOKEN"
}

401 Unauthorized
{
  "error": "REFRESH_TOKEN_EXPIRED"
}

401 Unauthorized
{
  "error": "REFRESH_TOKEN_REVOKED"
}
```

**Logique metier :**
1. Hasher le refresh_token recu (SHA-256).
2. Chercher le token dans la table `refresh_tokens` par `token_hash`.
3. Si introuvable -> `INVALID_REFRESH_TOKEN`.
4. Si `is_revoked` est true -> `REFRESH_TOKEN_REVOKED`.
5. Si `expires_at` est depasse -> `REFRESH_TOKEN_EXPIRED`, et revoquer le token (soft delete).
6. Revoquer l'ancien token (`is_revoked = true`).
7. Recuperer l'utilisateur associe (`User.findByPk`). Si introuvable -> `INVALID_REFRESH_TOKEN`.
8. Generer un nouveau jeu de tokens (access + refresh).
9. Stocker le nouveau refresh token.
10. Retourner les nouveaux tokens.

---

### POST /auth/logout

Revoquer le refresh token actuel.

**Middleware :** aucun

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `refresh_token` | string | **Oui** |

**Reponses :**

```
200 OK
{
  "message": "Logged out successfully"
}
```

**Logique metier :**
1. Hasher le refresh_token recu.
2. Trouver le token par `token_hash`.
3. Si trouve, marquer `is_revoked = true`.
4. Retourner succes (meme si le token n'existait pas).

---

### GET /auth/me

Recuperer les informations de l'utilisateur authentifie.

**Middleware :** `identity`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username` (injectes par le gateway)

**Reponses :**

```
200 OK
{
  "id": "uuid",
  "email": "user@example.com",
  "username": "johndoe",
  "role": "user",
  "is_active": true,
  "is_banned": false,
  "createdAt": "2024-01-01T00:00:00.000Z",
  "updatedAt": "2024-01-01T00:00:00.000Z"
}
```

```
401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}
```

**Logique metier :**
1. Extraire `x-user-id` des headers.
2. Requete `User.findByPk(id)`.
3. Retourner l'utilisateur complet (sans password_hash).

---

### POST /auth/change-password

Changer le mot de passe de l'utilisateur authentifie.

**Middleware :** `identity`, `changePasswordRules`, `validate`

**Headers requis :** `x-user-id`, `x-user-role`, `x-username`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis | Validation |
|---|---|---|---|
| `current_password` | string | **Oui** | -- |
| `new_password` | string | **Oui** | Min 8 car, 1 majuscule, 1 chiffre |

**Reponses :**

```
200 OK
{
  "message": "Password changed successfully"
}
```

```
400 Bad Request
{
  "error": "VALIDATION_ERROR",
  "details": [...]
}

401 Unauthorized
{
  "error": "INVALID_CURRENT_PASSWORD"
}

401 Unauthorized
{
  "error": "MISSING_IDENTITY"
}
```

**Logique metier :**
1. Verifier l'identite via le middleware.
2. Recuperer l'utilisateur avec `User.findByPk`.
3. Verifier le mot de passe actuel avec `bcrypt.compare`.
4. Hasher le nouveau mot de passe.
5. Mettre a jour `password_hash`.
6. Optionnellement, revoquer tous les refresh tokens de l'utilisateur (selon implementation).

---

### POST /auth/internal/ban

Bannir un utilisateur (appele par le user-service uniquement).

**Middleware :** aucun (securise par `INTERNAL_SECRET`)

**Headers requis :** `x-internal-secret`

**Corps de la requete (body JSON) :**

| Champ | Type | Requis |
|---|---|---|
| `user_id` | string | **Oui** |

**Reponses :**

```
200 OK
{
  "message": "User banned successfully"
}
```

```
403 Forbidden
{
  "error": "FORBIDDEN"
}

404 Not Found
{
  "error": "USER_NOT_FOUND"
}
```

**Logique metier :**
1. Verifier le header `x-internal-secret` correspond a `INTERNAL_SECRET`.
2. Trouver l'utilisateur par `user_id`.
3. Marquer `is_banned = true`.
4. Revoquer tous les refresh tokens de l'utilisateur.

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

Extrait les informations d'identite depuis les headers injectes par le gateway.

| Header | Description |
|---|---|
| `x-user-id` | UUID de l'utilisateur |
| `x-user-role` | Role de l'utilisateur |
| `x-username` | Username de l'utilisateur |

**Comportement :**
- Si `x-user-id` est absent ou vide -> retourne `401 { "error": "MISSING_IDENTITY" }`.
- Sinon, attache `req.user = { id, role, username }` et appelle `next()`.

### validate.middleware.js

Gestionnaire centralise des erreurs de validation express-validator.

**Comportement :**
- Execute `validationResult(req)`.
- Si des erreurs sont presentes -> retourne `400 { "error": "VALIDATION_ERROR", "details": [...] }`.
- Sinon, appelle `next()`.

---

## Variables d'environnement

| Variable | Defaut | Requis | Description |
|---|---|---|---|
| `PORT` | `3001` | Non | Port d'ecoute |
| `DATABASE_URL` | -- | **Oui** | URL de connexion PostgreSQL |
| `JWT_SECRET` | -- | **Oui** (hard stop si absent) | Cle de signature JWT |
| `JWT_EXPIRES_IN` | `15m` | Non | Duree de validite de l'access token |
| `REFRESH_TOKEN_DAYS` | `7` | Non | Duree de vie des refresh tokens en jours |
| `BCRYPT_ROUNDS` | `12` | Non | Nombre de rounds de salage bcrypt (`.env` utilise 10) |
| `INTERNAL_SECRET` | -- | Non | Secret pour les communications inter-services |
| `USER_SERVICE_URL` | -- | Non | URL du user-service |
| `CORS_ORIGIN` | `http://localhost:3000` | Non | Origine autorisee pour CORS |
| `NODE_ENV` | -- | Non | Environnement d'execution |

---

## Docker

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3001
CMD ["npm", "start"]
```

---

## Notes d'implementation

- La validation du mot de passe est asymetrique avec le frontend : le backend requiert >= 8 caracteres, 1 majuscule et 1 chiffre, tandis que le frontend ne valide que >= 6 caracteres.
- Le refresh token est stocke sous forme de hash SHA-256. Le token brut n'est jamais stocke, seulement retourne au client.
- `JWT_SECRET` est verifie au demarrage : si absent, le processus s'arrete avec `console.error` et `process.exit(1)`.
- La route `/auth/internal/ban` est protegee par `INTERNAL_SECRET` et non par le middleware `identity`, car elle est appelee par un autre service interne.
