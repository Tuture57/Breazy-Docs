# API Gateway

## Stack technique

| Technologie | Version |
|---|---|
| Node.js | 20 (Alpine) |
| Express | 4.19.2 |
| http-proxy-middleware | 3.x |
| jsonwebtoken | 9.x |
| express-rate-limit | 7.2.0 |
| dotenv | 16.4.5 |
| cors | 2.8.5 |
| nodemon (dev) | 3.1.0 |

- **Port interne** : 3000
- **Dossier** : `breezy-infra/gateway/`

---

## Rôle

L'API Gateway est le point d'entrée unique pour toutes les requêtes API. Elle assure :

1. **Vérification des tokens JWT** (middleware `auth.js`)
2. **Injection des headers d'identité** dans les requêtes proxyfiées
3. **Rate limiting** global et spécifique à l'auth
4. **Proxy** vers les 4 services backend
5. **Health check** pour la supervision

---

## Routes proxy

| Chemin client | JWT requis | Cible | Headers injectés |
|---|---|---|---|
| `/api/auth/me` | Oui | `AUTH_SERVICE_URL` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/auth/change-password` | Oui | `AUTH_SERVICE_URL` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/auth/*` (login, register, refresh, logout) | Non | `AUTH_SERVICE_URL` | Aucun |
| `/api/users/*` | Oui | `USER_SERVICE_URL` | `x-user-id`, `x-user-role` |
| `/api/posts/*` | Oui | `POST_SERVICE_URL` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/upload` | Oui | `POST_SERVICE_URL` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/uploads/*` (fichiers statiques) | Non | `POST_SERVICE_URL` | Aucun |
| `/api/profils/*` | Oui | `PROFIL_SERVICE_URL` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/notifications/*` | Oui | `PROFIL_SERVICE_URL` | `x-user-id`, `x-user-role`, `x-user-username` |
| `/api/health` | Non | Local (Gateway) | Aucun |

### Détail des headers injectés

La Gateway injecte les headers suivants après vérification du JWT :

```javascript
proxyReq.setHeader('x-user-id', req.user.sub);
proxyReq.setHeader('x-user-role', req.user.role);
proxyReq.setHeader('x-user-username', req.user.username);  // Sauf pour /api/users
```

**IMPORTANT** : Les routes `/api/users/*` ne reçoivent **pas** le header `x-user-username`. Elles reçoivent uniquement `x-user-id` et `x-user-role`.

Les routes auth publiques (login, register, refresh, logout) ne reçoivent **aucun** header d'identité.

---

## Middleware JWT

Fichier : `gateway/src/middleware/auth.js`

```javascript
const { verifyToken } = require("../utils/jwt.utils.js");

function authenticate(req, res, next) {
    const authHeader = req.headers['authorization'];

    if (!authHeader) {
        return res.status(401).json({ message: "No token provided" });
    }

    const token = authHeader.split(' ')[1];
    const decoded = verifyToken(token);

    if (!decoded) {
        return res.status(401).json({ message: "Invalid or expired token" });
    }

    req.user = decoded;
    next();
}
```

- Extrait le token du header `Authorization: Bearer <token>`
- Appelle `jwt.verify(token, JWT_SECRET)` 
- Retourne `401` si le token est manquant ou invalide
- Stocke le payload décodé dans `req.user` (contient `sub`, `username`, `role`)

---

## Rate Limiting

```javascript
const isTest = process.env.NODE_ENV === 'test';

// Global : 500 requêtes / 15 minutes par IP
const globalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: isTest ? 999999 : 500,
    message: { error: 'Trop de requêtes, réessaie dans 15 minutes' },
});

// Auth : 20 tentatives / 15 minutes sur login et register
const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: isTest ? 999999 : 20,
    message: { error: 'Trop de tentatives de connexion, réessaie dans 15 minutes' },
});

if (!isTest) app.use(globalLimiter);
if (!isTest) {
    app.use('/api/auth/login', authLimiter);
    app.use('/api/auth/register', authLimiter);
}
```

| Limiteur | Fenêtre | Maximum | Route |
|---|---|---|---|
| Global | 15 min | 500 req | Toutes les routes |
| Auth | 15 min | 20 req | `/api/auth/login`, `/api/auth/register` |

Les deux limiteurs sont **désactivés** lorsque `NODE_ENV=test` (valeur par défaut dans docker-compose).

---

## Configuration

Variables d'environnement utilisées par la Gateway :

| Variable | Défaut | Description |
|---|---|---|
| `PORT` | 3000 | Port d'écoute |
| `JWT_SECRET` | `defaultSecret` | Clé de signature JWT |
| `AUTH_SERVICE_URL` | - | URL du Auth Service |
| `USER_SERVICE_URL` | - | URL du User Service |
| `POST_SERVICE_URL` | - | URL du Post Service |
| `PROFIL_SERVICE_URL` | - | URL du Profil Service |
| `NODE_ENV` | - | `test` désactive le rate limiting |

---

## Health Check

```javascript
app.get('/api/health', (req, res) => {
    res.status(200).json({ status: 'UP', service: 'api-gateway' });
});
```

## Gestion des erreurs

```javascript
app.use(errorHandler);

// errorHandler.js
module.exports = (err, req, res, next) => {
  console.error(`[Gateway Error] ${err.message}`);
  res.status(err.status || 500).json({
    error: err.message || 'Erreur interne du serveur'
  });
};
```

Chaque proxy route gère également les erreurs de connexion au service cible :

```javascript
on: {
    error: (err, req, res) => {
        res.status(502).json({ error: 'Auth service indisponible' });
    }
}
```

- **502 Bad Gateway** : retourné si le service backend est inaccessible
- **500** : erreur interne non gérée
- Codes d'erreur des services backend : proxyfiés tels quels

---

## Rewriting de chemins

Les chemins d'URL sont réécrits avant d'être envoyés aux services backend :

| Chemin entrant | Chemin sortant | Cible |
|---|---|---|
| `/api/auth/me` | `/auth/me` | Auth Service |
| `/api/auth/*` | `/auth/*` | Auth Service |
| `/api/users/*` | `/users/*` | User Service |
| `/api/posts/*` | `/api/posts/*` | Post Service |
| `/api/upload` | `/api/upload` | Post Service |
| `/api/uploads/*` | `/api/uploads/*` | Post Service |
| `/api/profils/*` | `/api/profils/*` | Profil Service |
| `/api/notifications/*` | `/api/notifications/*` | Profil Service |
