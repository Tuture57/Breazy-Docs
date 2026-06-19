# Profil Service

**Responsabilité** : Gestion du profil étendu (bio, avatar, bannière) et système de notifications.

- **Stack** : Node.js, Express 5, Mongoose 9, MongoDB 6, morgan
- **Port** : 3004
- **Dépôt** : `breezy-profil-service`
- **Tests** : Aucun test automatisé

## Structure du projet

```
breezy-profil-service/
├── index.js                          ← Point d'entrée, lance le serveur
├── src/
│   ├── app.js                        ← Configuration Express, morgan, routes montées sur /api
│   ├── config/
│   │   └── database.js               ← Connexion MongoDB via Mongoose
│   ├── controllers/
│   │   ├── profile.controller.js     ← Get/update profil
│   │   └── notification.controller.js ← CRUD notifications + route interne
│   ├── models/
│   │   ├── profile.model.js          ← Schéma Mongoose Profile
│   │   └── notification.model.js     ← Schéma Mongoose Notification
│   └── routes/
│       └── profil.routes.js          ← Routes profils + notifications
```

!!! note "Montage des routes"
    Comme le post-service, les routes sont montées sur `/api` dans `app.js`.

## Routes API

### Profils

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/api/profiles/:userId` | Récupérer un profil (auto-création si inexistant) |
| `PUT` | `/api/profiles/:userId` | Modifier son propre profil |

### Notifications

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/api/notifications` | Liste des notifications |
| `PUT` | `/api/notifications/:id/read` | Marquer une notification comme lue |
| `PUT` | `/api/notifications/read-all` | Marquer toutes comme lues |
| `POST` | `/api/notifications/internal` | Créer une notification (appel inter-service) |

## Détail des endpoints

### GET /api/profiles/:userId

Récupère le profil d'un utilisateur. Si le profil n'existe pas encore, il est **créé automatiquement** (upsert avec `$setOnInsert`).

**Réponses :**

| Code | Body |
|------|------|
| `200` | `Profile` (objet complet, toujours retourné) |

(`profile.controller.js` lignes 4-11)

---

### PUT /api/profiles/:userId

Modifie le profil. Seul le propriétaire peut modifier son propre profil (vérification `x-user-id === :userId`).

**Champs modifiables :**

| Champ | Type | Contrainte |
|-------|------|------------|
| `display_name` | string | Max 100 caractères |
| `bio` | string | Max 160 caractères |
| `avatar_url` | string | URL de l'avatar |
| `banner_url` | string | URL de la bannière |

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `Profile` (mis à jour) | Succès |
| `400` | `{error: {code: 'BIO_TOO_LONG', message}}` | Bio > 160 caractères |
| `403` | `{error: {code: 'FORBIDDEN'}}` | Pas le propriétaire |

(`profile.controller.js` lignes 14-35)

---

### GET /api/notifications

Liste les notifications de l'utilisateur connecté (identifié via `x-user-id`).

**Query params :**

| Param | Default | Description |
|-------|---------|-------------|
| `page` | 1 | Page courante |
| `limit` | 20 | Notifications par page |
| `unread_only` | `false` | `'true'` pour ne voir que les non lues |

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{data: Notification[], unread_count: number, pagination}` |

!!! info "unread_count"
    Le champ `unread_count` est toujours retourné, même si `unread_only` est `false`. Il représente le nombre total de notifications non lues pour l'utilisateur.

(`notification.controller.js` lignes 4-23)

---

### PUT /api/notifications/:id/read

Marque une notification spécifique comme lue. Vérifie que la notification appartient bien à l'utilisateur.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `200` | `Notification` (mise à jour) | Succès |
| `404` | `{error: {code: 'NOT_FOUND'}}` | Notification inexistante ou pas la sienne |

(`notification.controller.js` lignes 26-35)

---

### PUT /api/notifications/read-all

Marque toutes les notifications non lues comme lues.

**Réponses :**

| Code | Body |
|------|------|
| `200` | `{updated_count: number}` |

(`notification.controller.js` lignes 38-42)

---

### POST /api/notifications/internal

Route interne pour créer une notification depuis un autre service (ex: post-service lors d'un like).

**Sécurité** : vérifie `x-internal-secret`.

**Body :**

```json
{
  "recipient_user_id": "string (UUID)",
  "type": "like|follow|mention|comment|reply",
  "from_user_id": "string (UUID)",
  "from_username": "string",
  "post_id": "string (optionnel)"
}
```

!!! note "Auto-notification"
    Si `recipient_user_id === from_user_id`, aucune notification n'est créée (204 No Content). On ne se notifie pas soi-même.

**Réponses :**

| Code | Body | Condition |
|------|------|-----------|
| `201` | `Notification` | Succès |
| `204` | — | Auto-notification ignorée |
| `401` | `{error: {code: 'UNAUTHORIZED'}}` | Secret invalide |

(`notification.controller.js` lignes 44-55)

## Configuration

| Variable d'env | Requis | Default | Description |
|----------------|--------|---------|-------------|
| `MONGO_URI` | **Oui** | — | URL MongoDB |
| `PORT` | Non | 3004 | Port d'écoute |
| `INTERNAL_SECRET` | Non | — | Secret inter-services |
