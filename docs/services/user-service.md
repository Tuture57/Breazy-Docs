# User Service

**Responsabilité** : Profils publics, système de follow/unfollow, recherche d'utilisateurs et modération (bannissement).

- **Stack** : Node.js, Express 5, Sequelize 6, PostgreSQL 15, axios
- **Port** : 3002
- **Dépôt** : `breezy-user-service`
- **Tests** : Jest + Supertest (`tests/user.test.js`)

## Structure du projet

```
breezy-user-service/
├── index.js                          ← Point d'entrée, lance le serveur
├── src/
│   ├── app.js                        ← Configuration Express, CORS, routes
│   ├── config/
│   │   └── database.js               ← Connexion PostgreSQL via Sequelize
│   ├── controllers/
│   │   └── user.controller.js        ← Logique métier
│   ├── middleware/
│   │   └── identity.middleware.js     ← Extrait x-user-id/x-user-role depuis les headers
│   ├── models/
│   │   ├── userProfile.model.js      ← Modèle Sequelize UserProfile
│   │   └── follow.model.js           ← Modèle Sequelize Follow
│   └── routes/
│       └── user.routes.js            ← Déclaration des routes
└── tests/
    └── user.test.js                  ← Tests d'intégration
```

## Routes API

| Méthode | Route | Auth | Description |
|---------|-------|------|-------------|
| `POST` | `/users/sync` | `INTERNAL_SECRET` | Synchronise un nouvel utilisateur (appel interne) |
| `GET` | `/users/search` | Identity | Recherche d'utilisateurs |
| `GET` | `/users/:id` | Identity | Profil public d'un utilisateur |
| `GET` | `/users/:id/followers` | Identity | Liste des followers (paginée) |
| `GET` | `/users/:id/following` | Identity | Liste des IDs suivis |
| `POST` | `/users/:id/follow` | Identity | Suivre un utilisateur |
| `DELETE` | `/users/:id/follow` | Identity | Ne plus suivre un utilisateur |
| `PUT` | `/users/:id/ban` | Identity (mod/admin) | Bannir un utilisateur |
| `GET` | `/health` | Non | Health check |

## Détail des endpoints

### POST /users/sync

Route interne appelée par l'auth-service lors de l'inscription d'un nouvel utilisateur. Crée ou met à jour le profil dans la table `user_profiles`.

**Sécurité** : vérifie `x-internal-secret`.

**Body :**
```json
{
  "id": "UUID (même que dans auth-service)",
  "username": "string",
  "role": "user|moderator|admin"
}
```

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `201` | `{ok: true}` | Succès (upsert) |
| `401` | `{error: {code: 'UNAUTHORIZED'}}` | Secret invalide |

(`user.controller.js` lignes 8-22)

---

### GET /users/search

Recherche insensible à la casse via `iLike`. Exclut les comptes bannis et inactifs. Triée par nombre de followers décroissant.

**Query params :**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `q` | string | — | Terme de recherche (min 2 caractères) |
| `page` | number | 1 | Page courante |
| `limit` | number | 10 | Résultats par page |

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: UserProfile[], pagination: {page, limit, total, hasNext}}` |
| `400` | `{error: {code: 'QUERY_TOO_SHORT', message}}` |

(`user.controller.js` lignes 38-66)

---

### GET /users/:id

Retourne le profil public d'un utilisateur.

**Réponses :**

| Code | Body |
|------|------|
| `200` | `UserProfile` (tous les champs) |
| `404` | `{error: {code: 'USER_NOT_FOUND', message}}` |

(`user.controller.js` lignes 25-36)

---

### POST /users/:id/follow

Crée la relation de suivi et met à jour les compteurs dans une **transaction atomique** Sequelize.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{message: "Vous suivez maintenant {username}."}` | Succès |
| `400` | `{error: {code: 'CANNOT_SELF_FOLLOW', message}}` | Se suivre soi-même |
| `404` | `{error: {code: 'USER_NOT_FOUND', message}}` | Cible inexistante |
| `409` | `{error: {code: 'ALREADY_FOLLOWING', message}}` | Déjà suivi |

!!! info "Transaction atomique"
    La relation Follow, l'incrémentation de `following_count` chez le follower et de `followers_count` chez le suivi sont effectuées dans une seule transaction. Si une étape échoue, tout est annulé.

(`user.controller.js` lignes 69-106)

---

### DELETE /users/:id/follow

Supprime la relation et décrémente les compteurs dans une transaction atomique.

**Réponses :**

| Code | Condition |
|------|-----------|
| `204` | Succès |
| `404` | `{error: {code: 'NOT_FOLLOWING', message}}` |

(`user.controller.js` lignes 109-137)

---

### GET /users/:id/followers

Retourne la liste paginée des followers avec leurs profils complets.

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: UserProfile[], pagination: {page, limit, total, hasNext}}` |

(`user.controller.js` lignes 140-162)

---

### GET /users/:id/following

Retourne uniquement les **IDs** des utilisateurs suivis (pas les profils complets).

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: ["uuid1", "uuid2", ...]}` |

(`user.controller.js` lignes 165-177)

---

### PUT /users/:id/ban

Bannit un utilisateur. Réservé aux modérateurs et admins. Propage le bannissement vers l'auth-service.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `{message: "Utilisateur {username} banni."}` | Succès |
| `403` | `{error: {code: 'FORBIDDEN', message}}` | Rôle insuffisant |
| `404` | `{error: {code: 'USER_NOT_FOUND', message}}` | Cible inexistante |

**Effet de bord** : appel non bloquant `POST {AUTH_SERVICE_URL}/auth/internal/ban` (timeout 3s).

(`user.controller.js` lignes 180-210)

## Configuration

| Variable d'env | Requis | Default | Description |
|----------------|--------|---------|-------------|
| `DATABASE_URL` | **Oui** | — | URL PostgreSQL |
| `PORT` | Non | 3002 | Port d'écoute |
| `CORS_ORIGIN` | Non | `http://localhost:3000` | Origine CORS |
| `INTERNAL_SECRET` | Non | — | Secret inter-services |
| `AUTH_SERVICE_URL` | Non | — | URL de l'auth-service pour propager les bans |

## Tests

14 tests d'intégration :

- `POST /users/sync` : sans/avec INTERNAL_SECRET
- `GET /users/:id` : sans headers, inexistant, existant
- `POST /users/:id/follow` : succès, self-follow, déjà suivi
- `DELETE /users/:id/follow` : succès
- `GET /users/:id/followers` : liste paginée
- `GET /users/:id/following` : liste d'IDs
- `PUT /users/:id/ban` : sans rôle, avec rôle moderator

```bash
cd breezy-user-service
npm test
```
