# Auth Service

**Responsabilité** : Inscription, connexion, gestion des tokens JWT, refresh tokens et bannissement de comptes.

- **Stack** : Node.js, Express 5, Sequelize 6, PostgreSQL 15, bcryptjs, jsonwebtoken
- **Port** : 3001
- **Dépôt** : `breezy-auth-service`
- **Tests** : Jest + Supertest (`tests/auth.test.js`)

## Structure du projet

```
breezy-auth-service/
├── index.js                          ← Point d'entrée, lance le serveur
├── src/
│   ├── app.js                        ← Configuration Express, CORS, routes
│   ├── config/
│   │   └── database.js               ← Connexion PostgreSQL via Sequelize
│   ├── controllers/
│   │   └── auth.controller.js        ← Logique métier (register, login, refresh, logout, me, internalBan)
│   ├── middleware/
│   │   ├── identity.middleware.js     ← Extrait x-user-id/x-user-role depuis les headers
│   │   └── validate.middleware.js     ← Centralise les erreurs express-validator
│   ├── models/
│   │   ├── user.model.js             ← Modèle Sequelize User
│   │   └── refreshToken.model.js     ← Modèle Sequelize RefreshToken
│   ├── routes/
│   │   └── auth.routes.js            ← Déclaration des routes + règles de validation
│   └── utils/
│       └── jwt.utils.js              ← Génération/vérification JWT, hash SHA-256
└── tests/
    └── auth.test.js                  ← Tests d'intégration
```

## Routes API

| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| `POST` | `/auth/register` | Non | Inscription d'un nouvel utilisateur |
| `POST` | `/auth/login` | Non | Connexion avec email/password |
| `POST` | `/auth/refresh` | Non | Rotation du refresh token |
| `POST` | `/auth/logout` | Non | Révocation du refresh token |
| `GET` | `/auth/me` | Oui (identity) | Informations de l'utilisateur connecté |
| `POST` | `/auth/internal/ban` | `INTERNAL_SECRET` | Bannir un utilisateur (appel inter-service) |
| `GET` | `/health` | Non | Health check |

## Détail des endpoints

### POST /auth/register

Crée un compte utilisateur, génère les tokens, et synchronise le profil vers le user-service.

**Body :**

```json
{
  "username": "string (3-50 chars, alphanum + _)",
  "email": "string (email valide)",
  "password": "string (min 8 chars, 1 majuscule, 1 chiffre)"
}
```

**Validation** (express-validator, `auth.routes.js` lignes 8-26) :

- `username` : 3-50 caractères, uniquement `[a-zA-Z0-9_]`
- `email` : format email valide, normalisé
- `password` : min 8 caractères, au moins 1 majuscule, au moins 1 chiffre

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `201` | `{user: {id, username, email, role}, token}` + cookie `refreshToken` | Succès |
| `400` | `{error: {code: 'VALIDATION_ERROR', message, details[]}}` | Données invalides |
| `409` | `{error: {code: 'EMAIL_TAKEN', message}}` | Email déjà utilisé |
| `409` | `{error: {code: 'USERNAME_TAKEN', message}}` | Username déjà pris |
| `500` | `{error: {code: 'INTERNAL_ERROR', message}}` | Erreur serveur |

**Effet de bord** : appel non bloquant `POST {USER_SERVICE_URL}/users/sync` avec `{id, username, role}` (timeout 3s).

(`auth.controller.js` lignes 19-69)

---

### POST /auth/login

Vérifie les credentials et retourne les tokens.

**Body :**

```json
{
  "email": "string",
  "password": "string"
}
```

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{user: {id, username, email, role}, token}` + cookie `refreshToken` | Succès |
| `400` | `{error: {code: 'VALIDATION_ERROR', ...}}` | Données manquantes |
| `401` | `{error: {code: 'INVALID_CREDENTIALS', message}}` | Email/password incorrect |
| `403` | `{error: {code: 'ACCOUNT_BANNED', message}}` | Compte banni |
| `403` | `{error: {code: 'ACCOUNT_INACTIVE', message}}` | Compte inactif |

!!! note "Sécurité"
    Le message d'erreur est identique pour email inexistant et mauvais mot de passe (`INVALID_CREDENTIALS`), ce qui empêche l'énumération des comptes.

(`auth.controller.js` lignes 72-111)

---

### POST /auth/refresh

Rotation du refresh token : l'ancien est révoqué, un nouveau est émis.

**Source du token** : cookie `refreshToken` OU body `{refreshToken: "..."}`.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{token}` + nouveau cookie `refreshToken` | Succès |
| `400` | `{error: {code: 'MISSING_TOKEN', message}}` | Token absent |
| `401` | `{error: {code: 'INVALID_REFRESH_TOKEN', message}}` | Token invalide, révoqué ou expiré |

!!! warning "Détection de vol de session"
    Si un token **déjà révoqué** est présenté, **tous les tokens de l'utilisateur** sont révoqués immédiatement. Cela détecte une possible interception de token.

(`auth.controller.js` lignes 113-166)

---

### POST /auth/logout

Révoque le refresh token sans exiger d'authentification JWT.

**Réponses :**

| Code | Condition |
|------|-----------|
| `204` | Succès (pas de body) |

(`auth.controller.js` lignes 168-181)

---

### GET /auth/me

Retourne les informations de l'utilisateur connecté. Nécessite le middleware `identity` (header `x-user-id`).

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{user: {id, username, email, role, is_active, is_banned}}` | Succès |
| `401` | `{error: {code: 'MISSING_IDENTITY', message}}` | Header x-user-id absent |
| `404` | `{error: {code: 'USER_NOT_FOUND', message}}` | Utilisateur non trouvé en BDD |

(`auth.controller.js` lignes 183-196)

---

### POST /auth/internal/ban

Route interne pour bannir un utilisateur. Appelée par le user-service lors d'un bannissement.

**Sécurité** : vérifie `x-internal-secret` (pas JWT).

**Body :**

```json
{
  "userId": "UUID"
}
```

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{ok: true}` | Succès |
| `400` | `{error: {code: 'MISSING_USER_ID'}}` | userId absent |
| `401` | `{error: {code: 'UNAUTHORIZED'}}` | Secret invalide |
| `404` | `{error: {code: 'USER_NOT_FOUND'}}` | Utilisateur non trouvé |

(`auth.controller.js` lignes 199-221)

## Configuration

| Variable d'env | Requis | Default | Description |
|----------------|--------|---------|-------------|
| `JWT_SECRET` | **Oui** | — | Clé de signature JWT (arrêt si absent) |
| `DATABASE_URL` | **Oui** | — | URL PostgreSQL |
| `PORT` | Non | 3001 | Port d'écoute |
| `JWT_EXPIRES_IN` | Non | `15m` | Durée de vie de l'access token |
| `BCRYPT_ROUNDS` | Non | 12 | Nombre de rounds bcrypt |
| `REFRESH_TOKEN_DAYS` | Non | 7 | Durée de vie du refresh token (jours) |
| `CORS_ORIGIN` | Non | `http://localhost:3000` | Origine autorisée CORS |
| `USER_SERVICE_URL` | Non | — | URL du user-service pour la sync |
| `INTERNAL_SECRET` | Non | — | Secret pour les appels inter-services |

## Tests

15 tests d'intégration couvrent les cas principaux :

- `POST /auth/register` : succès, email pris, username pris, password trop court, email invalide
- `POST /auth/login` : succès, mauvais mot de passe, email inexistant
- `POST /auth/refresh` : token valide, token révoqué
- `POST /auth/logout` : révocation réussie
- `POST /auth/internal/ban` : sans/avec INTERNAL_SECRET

```bash
cd breezy-auth-service
npm test
```
