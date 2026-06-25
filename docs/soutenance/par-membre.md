# Questions par membre

5 questions ciblées par membre, sur sa partie, avec une réponse fondée sur le code.

---

## Arthur — Auth Service & User Service

### Q1. Rotation des refresh tokens et détection de vol ?

À chaque `POST /auth/refresh`, le token est haché en SHA-256 et recherché en base. S'il est
valide, l'ancien est révoqué et un nouveau émis (rotation). S'il est **déjà révoqué** (rejeu), je
révoque **tous** les refresh tokens de l'utilisateur :
`RefreshToken.update({ is_revoked: true }, { where: { user_id } })`. Attaquant et victime sont
alors déconnectés.

### Q2. Pourquoi séparer auth-service et user-service ?

L'auth-service (base `auth_db`) gère les données sensibles : email, `password_hash`, émission des
tokens, vérification du ban au login. Le user-service (base `users_db`) gère le public : profils,
relations de follow, compteurs. Cette séparation permet des politiques de sécurité différentes et
un scaling indépendant. Le même UUID relie les deux bases, synchronisé via `POST /users/sync`.

### Q3. Atomicité des compteurs followers/following ?

J'utilise `sequelize.transaction()` : la création du `Follow` (`findOrCreate`, qui lève
`ALREADY_FOLLOWING` si doublon) et les deux `increment` de compteurs sont dans la **même**
transaction. En cas d'échec, tout est rollback. L'index unique composite
`(follower_id, followed_id)` garantit l'unicité au niveau base.

### Q4. Flux d'inscription complet ?

Validation (`express-validator`) → vérification unicité email/username → hash bcrypt → création
dans `users` → `POST /users/sync` non bloquant vers le user-service → génération JWT (15 min) +
refresh token (7 j, haché) → cookie httpOnly → réponse `201 { user, token }`. Si le user-service
est down, le sync échoue silencieusement mais l'inscription reste valide.

### Q5. Propagation du ban entre user et auth ?

Le ban part du user-service (`PUT /users/:id/ban`, rôle modérateur/admin requis). Je mets
`is_banned = true` localement, puis j'appelle `POST /auth/internal/ban` (avec `x-internal-secret`,
timeout 3 s, non bloquant). L'auth-service vérifie le secret et met `is_banned = true` dans sa
table. Le ban est nécessaire des deux côtés : l'auth le vérifie au login/refresh, le user à la
recherche.

---

## Maxime — Post Service & Profil Service

### Q1. Algorithme du feed ?

`getFeed` appelle `GET /users/:userId/following` (timeout 3 s, fallback liste vide), fusionne avec
l'ID courant (donc inclut mes posts), puis `Post.find({ user_id: { $in } })` trié par
`created_at:-1` avec pagination offset. Enfin, deux requêtes parallèles sur `Like` et `Repost`
ajoutent `likedByMe`/`repostedByMe` à chaque post. Tri chronologique, pas de ranking.

### Q2. Cohérence des compteurs (likes_count, comments_count) ?

`$inc` atomique pour éviter les race conditions, et index unique `{post_id, user_id}` sur Like et
Repost (erreur 11000 → 409 `ALREADY_LIKED`). À l'unlike, je borne l'affichage avec
`Math.max(0, ...)`. Je connais deux limites : `likes_count` peut rester négatif en base, et
`comments_count` ne décrémente que de 1 même quand des réponses sont supprimées en cascade.

### Q3. Système de notifications ?

Le profil-service expose `POST /api/notifications/internal` (protégé par `x-internal-secret`). Le
post-service y envoie les `like`/`mention`, le user-service les `follow`. Deux filtres : la
self-notification (`recipient === sender` → 204) et le rôle (les modérateurs/admins ne reçoivent
pas like/follow, vérifié via `GET /auth/internal/users/:id/role`). Les types `comment`/`reply`
existent dans le schéma mais ne sont pas générés.

### Q4. Le bot IA `@breezy_ai` ?

À la création d'un post contenant `@breezy_ai`, j'appelle OpenRouter (`gpt-oss-20b:free`,
timeout 15 s) et je publie la réponse comme commentaire du compte bot
(`user_id` fixe, username `breezy_ai`), tronquée à 280 caractères, avec `$inc comments_count +1`.
C'est non bloquant. ⚠️ La clé API est malheureusement commitée en clair, à révoquer.

### Q5. Pourquoi 1 seul niveau de réponse aux commentaires ?

Pour la lisibilité (fil plat) et la simplicité : `getComments` charge les racines
(`parent_comment_id: null`) avec leurs `replies`, sans récursion. Dans `createReply`, si le parent
est déjà une réponse, je renvoie `400 MAX_DEPTH`. L'upsert des profils (`findOneAndUpdate` avec
`upsert`) évite par ailleurs tout 404 sur un profil inexistant.

---

## Jessica — Frontend

### Q1. Gestion du JWT côté client ?

Le JWT est dans `localStorage` (clé `breezy_token`), lu **synchroniquement** à l'init du
`AuthContext` pour éviter le flash de déconnexion. Un intercepteur de requête Axios ajoute
`Authorization: Bearer <token>`. Au montage, `getMe()` hydrate l'utilisateur. Le refresh token,
lui, n'est jamais manipulé côté front : il vit dans un cookie httpOnly.

### Q2. Intercepteur Axios et refresh automatique ?

Sur un `401`, l'intercepteur de réponse appelle `POST /auth/refresh` (sans corps, il s'appuie sur
le cookie). Si un refresh est déjà en cours (`isRefreshing`), les requêtes sont mises en file
(`failedQueue`) puis rejouées après succès. Cas particuliers : `/auth/login` laisse l'erreur
passer, `/auth/refresh` en échec → suppression du token et redirection `/signin`.

### Q3. Mises à jour optimistes (like, follow) ?

`useLike` et `useFollow` mettent à jour l'UI immédiatement, sauvegardent l'état précédent, puis
appellent l'API. En cas d'échec, rollback vers l'état sauvegardé. Un flag `loading` empêche les
clics multiples, et un callback `onUpdate` notifie le parent. Cela donne une UX réactive sans
attendre le serveur.

### Q4. Protection des routes et limites ?

`(app)/layout.js` (client) redirige vers `/connect` si aucun token. Un cookie `breezy_auth=1`
est posé « pour un middleware serveur », mais **aucun `middleware.js` n'existe** → la protection
est 100 % côté client. La messagerie est un placeholder (composants non connectés,
`getUnreadMessagesCount` renvoie `0` en dur).

### Q5. Composants réutilisables ?

Une bibliothèque UI : `Button` (7 variants + état `loading`), `Avatar` (5 tailles), `Input`
(label/error/icônes), `Spinner`, et `AppShell` (sidebar desktop + colonne centrale 600 px +
bottom nav mobile). Cela garantit la cohérence visuelle et réduit la duplication. Le formatage des
dates est fait maison (pas de `date-fns` malgré le README).

---

## Estéban — Infrastructure & Gateway

### Q1. Vérification du JWT et injection des headers ?

Le middleware `auth.js` extrait le token de `Authorization: Bearer`, appelle `verifyToken`
(`jwt.verify`), et renvoie `401` si absent/invalide. Sinon `req.user = decoded`. Chaque proxy
protégé injecte ensuite `x-user-id` (`req.user.sub`), `x-user-role`, `x-user-username`. Le
user-service ne reçoit délibérément pas le username.

### Q2. Pourquoi l'ordre des routes `/api/auth` est-il critique ?

Les sous-routes protégées (`/me`, `/change-password`, `/username`, `/admin`) sont enregistrées
**avant** le catch-all public `/api/auth`. Si on inversait, le catch-all intercepterait ces
routes sensibles sans authentification. Le code le commente explicitement.

### Q3. Rate limiting : où est-il réellement appliqué ?

Uniquement côté gateway : 500 req/15min global, 20 req/15min sur login/register, actifs car
`NODE_ENV=production`. Côté Nginx, les zones `global`/`auth` sont **déclarées mais jamais
activées** (pas de `limit_req`), donc sans effet. C'est un point à corriger.

### Q4. Comment les services communiquent-ils dans Docker ?

Via le réseau bridge `breezy-network` et le DNS interne : `http://auth-service:3001`, etc. Seul
Nginx publie un port (`80:80`) ; tout le reste est en `expose`. La gateway ne reçoit pas
`INTERNAL_SECRET` (seuls les 4 microservices l'ont), car elle ne fait pas d'appel interne — elle
ne propage que l'identité utilisateur via les headers.

### Q5. Que se passe-t-il si la gateway tombe ? Et un service backend ?

La gateway est un point de défaillance unique : si elle tombe, Nginx renvoie 502 et plus aucun
appel API n'aboutit. Pour un service backend, le système se dégrade partiellement grâce aux
fallbacks (feed limité, notifications perdues, etc.), et la gateway renvoie un 502 ciblé par
service. En production, il faudrait load-balancer plusieurs instances de gateway.
