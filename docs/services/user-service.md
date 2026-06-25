# User Service

Service des **profils publics** et des **relations sociales** : follow/unfollow avec compteurs
atomiques, recherche d'utilisateurs, résolution username → ID (pour les mentions), et
bannissement (propagé à l'auth-service).

- **Dépôt** : `breezy-user-service`
- **Port** : `3002`
- **Base de données** : PostgreSQL `users_db` (conteneur `pg-users`)
- **ORM** : Sequelize 6 — `sync({ alter: true })` au démarrage (`force: true` en test)

!!! info "Identité par header"
    Comme tous les services backend, le user-service ne vérifie pas le JWT : il lit
    `x-user-id` / `x-user-role` injectés par la gateway. **`x-user-username` n'est pas injecté
    pour ce service** (voir l'encart sur `follow`).

---

## Stack & dépendances

| Paquet | Version |
|---|---|
| express | `^5.2.1` |
| sequelize | `^6.37.8` |
| pg / pg-hstore | `^8.21.0` / `^2.3.4` |
| axios | `^1.18.0` |
| cors | `^2.8.6` |
| express-validator | `^7.3.2` ⚠️ **déclaré mais jamais utilisé** (validation manuelle) |

---

## Modèles de données

### Table `user_profiles`

| Colonne | Type | Contraintes / défaut |
|---|---|---|
| `id` | UUID | PK — **imposé par l'auth-service** (pas de génération auto) |
| `username` | STRING(50) | `NOT NULL` — **pas d'index unique** dans le modèle |
| `role` | ENUM(`user`,`moderator`,`admin`) | défaut `user` (répliqué depuis l'auth) |
| `is_active` | BOOLEAN | défaut `true` |
| `is_banned` | BOOLEAN | défaut `false` |
| `followers_count` | INTEGER | défaut `0` |
| `following_count` | INTEGER | défaut `0` |
| `created_at` / `updated_at` | TIMESTAMP | auto |

### Table `follows`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | INTEGER | PK auto-incrémentée |
| `follower_id` | UUID | `NOT NULL` |
| `followed_id` | UUID | `NOT NULL` |
| `created_at` | TIMESTAMP | auto (`updatedAt: false`) |

- **Index unique composite** `(follower_id, followed_id)` → empêche de suivre deux fois.
- **Aucune association Sequelize ni FK** vers `user_profiles` : la jointure est faite côté
  application (récupérer les `Follow`, puis `UserProfile.findAll` par IDs).

!!! warning "Pas de cascade entre `follows` et `user_profiles`"
    Supprimer un profil ne nettoie pas les `follows` associés → risque de relations orphelines
    et de compteurs incohérents. Les compteurs n'ont pas de garde-fou contre les valeurs
    négatives en base.

---

## Routes

| Méthode | Path | Middleware | Auth |
|---|---|---|---|
| GET | `/health` | — | Public |
| POST | `/users/sync` | — (`x-internal-secret`) | Interne |
| GET | `/users/search` | `identity` | JWT |
| GET | `/users/by-username/:username` | — | **Public** |
| GET | `/users/:id` | `identity` | JWT |
| GET | `/users/:id/followers` | `identity` | JWT |
| GET | `/users/:id/following` | `identity` | JWT |
| POST | `/users/:id/follow` | `identity` | JWT |
| DELETE | `/users/:id/follow` | `identity` | JWT |
| PUT | `/users/:id/ban` | `identity` | JWT + rôle modérateur/admin |

`/users/search` et `/users/by-username/:username` sont déclarées **avant** `/users/:id` pour
éviter la capture par le paramètre `:id`.

---

## Endpoints détaillés

### POST /users/sync *(interne)*

Appelé par l'auth-service. Header `x-internal-secret`. Body `{ id, username, role }`.
`UserProfile.upsert(...)` (création ou mise à jour). **Succès `201`** : `{ ok: true }`.
`401 UNAUTHORIZED` si secret invalide. Aucune validation des champs.

### GET /users/search

Query `q` (requis, ≥2 caractères), `page` (1), `limit` (10). Filtre `username ILIKE %q%`
**ET** `is_active = true` **ET** `is_banned = false`, trié par `followers_count DESC`.

- **Succès `200`** : `{ data: [UserProfile], pagination: { page, limit, total, hasNext } }`.
- **`400 QUERY_TOO_SHORT`** si `q` absent ou < 2 caractères.

### GET /users/by-username/:username *(public)*

`findOne({ where: { username } })`. **Ne filtre pas** les bannis/inactifs. Utilisé par le
post-service pour résoudre les `@mentions`. **`404 USER_NOT_FOUND`** sinon.

### GET /users/:id

`findByPk(id)`. Si `req.userId` ≠ `:id`, calcule `followedByMe` (l'appelant suit-il la cible ?).
**Succès `200`** : `{ ...UserProfile, followedByMe }`. Ne filtre pas les bannis.

### GET /users/:id/followers · GET /users/:id/following

Pagination `page` (1) / `limit` (20). `followers` renvoie `{ data, pagination }`.

`following` renvoie **`{ data, ids, pagination }`** — `data` contient les objets `UserProfile`
et `ids` les UUID suivis. C'est le champ `ids` (ou `data`) que le post-service exploite pour le
feed.

### POST /users/:id/follow

`followerId = req.userId`, `followedId = :id`. **Transaction atomique** :

```javascript
await sequelize.transaction(async (t) => {
  const [follow, created] = await Follow.findOrCreate({
    where: { follower_id, followed_id }, transaction: t });
  if (!created) throw new FollowError('ALREADY_FOLLOWING');
  await UserProfile.increment('following_count', { where: { id: follower_id }, transaction: t });
  await UserProfile.increment('followers_count', { where: { id: followed_id }, transaction: t });
});
```

Puis (hors transaction) envoie une notification de follow au profil-service.
**Succès `200`** : `{ message: "Vous suivez maintenant <username>." }`.

| Code | Erreur |
|---|---|
| 400 | `CANNOT_SELF_FOLLOW` |
| 404 | `USER_NOT_FOUND` |
| 409 | `ALREADY_FOLLOWING` |

### DELETE /users/:id/follow

Transaction symétrique : `Follow.destroy` puis `decrement` des deux compteurs. Si 0 ligne
supprimée → `404 NOT_FOLLOWING`. **Succès `204`** (corps vide). Ne vérifie pas l'existence de la
cible, ne bloque pas l'auto-unfollow.

### PUT /users/:id/ban

`req.userRole` doit être `moderator` ou `admin`, sinon `403 FORBIDDEN`. Met `is_banned = true`
localement, puis propage vers l'auth-service (non bloquant). **Succès `200`** :
`{ message: "Utilisateur <username> banni." }`. Pas d'unban. `is_active` et les compteurs sont
inchangés.

!!! warning "Le bannissement ne masque pas partout"
    Les bannis sont exclus de `/users/search`, mais **restent visibles** via `/users/:id` et
    `/users/by-username/:username` (ces routes ne filtrent pas `is_banned`).

---

## Logique des compteurs followers/following

Les compteurs sont **dénormalisés** et maintenus uniquement par `follow` / `unfollow`, dans une
transaction Sequelize qui englobe la création/suppression du lien **et** les deux incréments.
Cette atomicité garantit la cohérence en cas d'échec partiel. Aucun `COUNT(*)` n'est fait à la
lecture (performance), au prix d'une synchronisation à maintenir.

---

## Appels inter-services

| Vers | Endpoint | Body | Headers | Timeout | Quand |
|---|---|---|---|---|---|
| profil-service | `POST /api/notifications/internal` | `{ recipient_user_id, type:'follow', from_user_id, from_username, recipient_role }` | `x-internal-secret` | 1000 ms | après un follow réussi |
| auth-service | `POST /auth/internal/ban` | `{ userId }` | `x-internal-secret` | 3000 ms | après un ban local |

Les deux appels sont non bloquants (`console.warn` en cas d'échec). `from_username` provient de
`x-user-username` — **non injecté** pour le user-service, donc souvent `undefined` dans la
notification de follow.

---

## Variables d'environnement

| Variable | Défaut | Usage |
|---|---|---|
| `PORT` | `3002` | Port d'écoute |
| `DATABASE_URL` | — | Connexion PostgreSQL |
| `INTERNAL_SECRET` | — | Secret inter-services |
| `AUTH_SERVICE_URL` | — | Propagation du ban |
| `PROFIL_SERVICE_URL` | — | Notification de follow |
| `CORS_ORIGIN` | `http://localhost:3000` | CORS |

---

## Dockerfile

`node:20-alpine`, `npm install`, `CMD ["npm","start"]`. Pas d'`EXPOSE`. Le port 3002 est mappé
via docker-compose / `docker run -p 3002:3002`.
