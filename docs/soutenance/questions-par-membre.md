# Questions par membre/service

## Membre responsable de l'auth-service

### Q1 : Comment fonctionne la rotation des refresh tokens ?

**Points clés à mentionner :**

- À chaque appel `POST /auth/refresh`, l'ancien token est marqué `is_revoked: true`
- Un nouveau token aléatoire (64 bytes hex) est généré et hashé en SHA-256 avant stockage
- Si un token déjà révoqué est présenté → **tous les tokens du compte** sont révoqués (détection de vol de session)
- Le token est envoyé via cookie `httpOnly` + `sameSite: Strict` + `secure` en production

**Fichier :** `breezy-auth-service/src/controllers/auth.controller.js` (lignes 113-166)

### Q2 : Pourquoi bcryptjs et pas bcrypt natif ?

- `bcryptjs` est une implémentation **pure JavaScript** de bcrypt, pas de dépendance C++ à compiler
- Plus simple à installer, surtout en environnement Docker
- Performance légèrement inférieure mais acceptable pour un projet de cette taille (12 rounds ≈ 250ms)

### Q3 : Comment la synchronisation auth → user-service fonctionne-t-elle ?

- Après `User.create()`, un appel `axios.post` vers `{USER_SERVICE_URL}/users/sync` envoie `{id, username, role}`
- C'est dans un `try/catch` séparé : si le user-service est down, l'inscription réussit quand même
- Timeout de 3 secondes pour ne pas bloquer l'utilisateur
- Le user-service fait un `upsert` (insert ou update si existe déjà)

### Q4 : Comment avez-vous structuré vos tests ?

- 15 tests d'intégration avec **Supertest** (requêtes HTTP réelles sur l'app Express)
- **Mocks** : `axios` est mocké pour ne pas dépendre du user-service pendant les tests
- **Isolation** : base de données de test séparée, `beforeEach` nettoie les tables
- **Couverture** : register (5 cas), login (3 cas), refresh (2 cas), logout (1 cas), internal/ban (2 cas)

---

## Membre responsable du user-service

### Q1 : Comment les transactions atomiques fonctionnent pour le follow/unfollow ?

**Points clés à mentionner :**

```javascript
await sequelize.transaction(async (t) => {
    const [, created] = await Follow.findOrCreate({
        where: { follower_id, followed_id },
        transaction: t,
    });
    await UserProfile.increment('following_count', { where: { id: followerId }, transaction: t });
    await UserProfile.increment('followers_count', { where: { id: followedId }, transaction: t });
});
```

- Les 3 opérations (create follow + increment follower + increment following) sont dans une **transaction**
- Si une échoue, tout est annulé → les compteurs restent cohérents
- `findOrCreate` empêche de suivre deux fois (retourne `created: false` si déjà suivi)

**Fichier :** `breezy-user-service/src/controllers/user.controller.js` (lignes 83-96)

### Q2 : Comment fonctionne la recherche d'utilisateurs ?

- Utilise l'opérateur `iLike` de PostgreSQL (insensible à la casse)
- Filtre les comptes bannis (`is_banned: false`) et inactifs (`is_active: true`)
- Trié par `followers_count` décroissant (les comptes les plus populaires en premier)
- Minimum 2 caractères requis pour la requête
- Paginé avec `limit` et `offset`

### Q3 : Comment le bannissement se propage entre les services ?

1. Le modérateur appelle `PUT /users/:id/ban` sur le user-service
2. Le user-service met `is_banned: true` dans `user_profiles`
3. En parallèle (non bloquant), il appelle `POST /auth/internal/ban` sur l'auth-service
4. L'auth-service met `is_banned: true` dans `users`
5. Au prochain login, l'auth-service vérifie `is_banned` et refuse l'accès (403)

### Q4 : Pourquoi la table `follows` n'a pas de foreign key Sequelize ?

- Les `follow` référencent des `user_profiles` mais il n'y a pas de `belongsTo`/`hasMany` défini dans le modèle
- La cohérence est assurée au **niveau applicatif** (le controller vérifie que la cible existe avant de créer le follow)
- L'index unique `(follower_id, followed_id)` empêche les doublons en base

---

## Membre responsable du post-service

### Q1 : Comment le feed est-il construit ?

**Points clés :**

1. Le post-service appelle le user-service : `GET /users/{userId}/following` → liste d'IDs
2. Si le user-service est indisponible, retourne un **feed vide** (pas d'erreur 500)
3. Requête MongoDB : `Post.find({ user_id: { $in: followingIds } })` trié par `created_at DESC`
4. Pagination avec `skip` et `limit`

**Fichier :** `breezy-post-service/src/controllers/post.controller.js` (lignes 50-84)

### Q2 : Comment fonctionne le système de likes avec MongoDB ?

- Un document `Like` est créé avec un **index unique** sur `(post_id, user_id)` → impossible de liker deux fois
- Le compteur `likes_count` du post est incrémenté avec `$inc` (opération **atomique** MongoDB)
- Si le `Like.create` échoue avec erreur 11000 (duplicate key), on renvoie 409 `ALREADY_LIKED`
- Une notification est envoyée au profil-service (non bloquant, timeout 1s)

### Q3 : Pourquoi limiter la profondeur des commentaires à 1 niveau ?

- Évite l'**imbrication infinie** ("poupée russe") qui complique l'affichage
- Simplifie la requête : on charge les commentaires racines (`parent_comment_id: null`) puis les réponses pour chacun
- Choix de design similaire à Twitter/X : on peut répondre à un commentaire mais pas à une réponse

### Q4 : Pourquoi `morgan` pour les logs ?

- Middleware de logging HTTP pour Express
- Affiche le méthode, URL, status code et temps de réponse dans la console
- Mode `dev` pour un format lisible pendant le développement
- Les auth-service et user-service n'utilisent pas morgan (ils ont des `console.error` manuels)

---

## Membre responsable du profil-service

### Q1 : Pourquoi séparer le profil-service du user-service ?

- Le **user-service** gère les données "sociales" (follow/unfollow, compteurs, recherche) → PostgreSQL
- Le **profil-service** gère les données "personnelles" (bio, avatar, bannière) → MongoDB
- Les notifications sont dans le profil-service car elles sont liées à l'activité de l'utilisateur
- Chaque service peut évoluer indépendamment (ex: ajouter un système de badges au profil)

### Q2 : Comment fonctionne l'upsert automatique du profil ?

```javascript
const profile = await Profile.findOneAndUpdate(
    { user_id: req.params.userId },
    { $setOnInsert: { user_id: req.params.userId } },
    { upsert: true, new: true }
);
```

- `findOneAndUpdate` avec `upsert: true` : crée le document s'il n'existe pas
- `$setOnInsert` : ne définit le champ que lors de la création (pas de l'update)
- `new: true` : retourne le document après modification
- Le profil est créé "à la demande" au premier accès, pas à l'inscription

### Q3 : Comment les notifications sont-elles créées par les autres services ?

- Route interne `POST /notifications/internal` protégée par `INTERNAL_SECRET`
- Le post-service l'appelle quand quelqu'un like un post (avec `type: 'like'`)
- L'appel est non bloquant (timeout 1s)
- Auto-notification ignorée : si `recipient === from_user`, 204 No Content
- Types supportés : `like`, `follow`, `mention`, `comment`, `reply`

### Q4 : Pourquoi les notifications n'ont pas de `updatedAt` ?

- Une notification ne se "modifie" pas vraiment : elle est créée, puis marquée comme lue (`is_read: true`)
- `updatedAt: false` dans le schéma Mongoose évite une colonne inutile
- Seul le champ `is_read` change, via `findOneAndUpdate` dans les endpoints `/read` et `/read-all`

---

## Membre responsable du frontend

### Q1 : Comment fonctionne le système de mocks ?

- Chaque service (auth, post, user, etc.) a un fichier `.mock.js` avec les mêmes fonctions
- La variable `NEXT_PUBLIC_USE_MOCKS=true` active le mode mock
- Chaque export vérifie `isMockEnabled()` et route vers le mock ou l'API réelle
- Permet de développer et tester le frontend **sans aucun backend**

### Q2 : Comment la protection des routes est-elle gérée ?

- Le layout `(app)/layout.js` vérifie la présence du token au montage
- Si pas de token → `router.replace('/connect')`
- Pendant le chargement → affichage d'un `Spinner`
- L'intercepteur Axios sur les 401 supprime le token et redirige vers `/signin`
- Le `AuthContext` lit le token synchroniquement depuis `localStorage` pour éviter les flash de déconnexion

### Q3 : Pourquoi Next.js App Router plutôt que Pages Router ?

- App Router est la **direction officielle** de Next.js 14
- Les **route groups** `(auth)` et `(app)` permettent de séparer les layouts sans affecter l'URL
- Les **Server Components** améliorent les performances (même si ici tout est `'use client'`)
- Meilleure organisation du code avec le système de layouts imbriqués

---

## Membre responsable de l'infra

### Q1 : Pourquoi Nginx en plus de la Gateway ?

- **Nginx** : reverse proxy "classique", sert le frontend et route `/api/*` vers la gateway, rate limiting au niveau IP
- **Gateway** : logique applicative (vérification JWT, injection de headers, rate limiting applicatif)
- Séparation des préoccupations : Nginx gère le réseau, la Gateway gère la logique métier
- En production, Nginx pourrait servir les assets statiques et gérer le SSL/TLS

### Q2 : Comment les variables d'environnement sont-elles gérées ?

- Un fichier `.env` à la racine de `breezy-infra/` (non versionné)
- Docker Compose injecte les variables dans chaque conteneur via la section `environment`
- Chaque service charge son `.env` local avec `dotenv` pour le développement sans Docker
- Variables critiques : `JWT_SECRET`, `INTERNAL_SECRET`, URLs des bases de données

### Q3 : Comment fonctionne le réseau Docker ?

- Tous les conteneurs sont sur le réseau bridge `breezy-network`
- Les conteneurs se référencent par leur **nom de service** (DNS Docker interne)
- Seul Nginx expose le port **80** vers la machine hôte
- Les ports internes (`3001`, `3002`, etc.) ne sont pas accessibles depuis l'extérieur
