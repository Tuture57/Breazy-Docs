# Questions de soutenance — générales

Réponses courtes (3–5 phrases) basées sur le code réel, défendables devant le jury. Organisées
par thème.

---

## Architecture & choix techniques

### Pourquoi une architecture microservices ?

Chaque domaine métier (authentification, utilisateurs, posts, profils/notifications) est un
service indépendant avec sa propre base, son cycle de vie et son scaling. Cela permet de
développer, tester et déployer chaque partie séparément, et d'isoler les pannes grâce à des
appels inter-services non bloquants. Le découpage suit le principe de responsabilité unique :
l'auth gère les credentials sensibles, le user gère le social, etc.

### Pourquoi PostgreSQL pour auth/user et MongoDB pour post/profil ?

Le type de base suit la nature des données. Auth et User ont des schémas stricts et des besoins
transactionnels (relations users/refresh_tokens, compteurs de follow atomiques) → PostgreSQL +
Sequelize. Posts et profils/notifications ont des structures flexibles (tags et médias en
tableaux, documents de types variés) et profitent du `$inc` atomique sans transaction →
MongoDB + Mongoose.

### Pourquoi une gateway qui vérifie le JWT et injecte des headers ?

La gateway est le seul point d'entrée : elle vérifie le JWT une seule fois puis injecte
`x-user-id`, `x-user-role`, `x-user-username` dans les requêtes proxifiées. Les services backend
n'ont donc pas à décoder le JWT — ils lisent l'identité dans les headers. Avantage : sécurité
centralisée, un seul endroit à changer si la clé évolue. Limite assumée : les headers ne sont
pas signés, donc l'isolation réseau (aucun service exposé) est indispensable.

### Pourquoi HTTP REST et pas un message broker pour l'inter-services ?

Pour la simplicité : pas d'infrastructure supplémentaire (RabbitMQ/Kafka) à maintenir, et les
communications internes sont peu nombreuses (sync, notifications, propagation de ban). Tous les
appels sont « fire-and-forget » avec timeout court (1–3 s) et catch silencieux, donc une panne
d'un service ne bloque pas le flux principal. Un bus d'événements est envisagé en évolution
moyen terme pour garantir la livraison.

### Pourquoi Next.js App Router ?

Pour les Route Groups (`(app)` protégé / `(auth)` public), les layouts imbriqués (AuthProvider
au root, garde d'auth dans `(app)/layout.js`) et le routing par structure de dossiers. La
séparation client/serveur est explicite via `'use client'`. Cela dit, la protection des routes
reste 100 % côté client (pas de `middleware.js`).

---

## Sécurité

### Expliquez le flux JWT + refresh avec détection de vol.

Le JWT (15 min) est envoyé en `Authorization: Bearer`. Le refresh token (7 jours, 64 octets
aléatoires) est stocké **hashé en SHA-256** et livré dans un cookie httpOnly. À chaque refresh,
l'ancien token est révoqué et un nouveau émis (rotation). Si un token déjà révoqué est rejoué
(vol probable), **tous** les tokens de l'utilisateur sont révoqués — attaquant et victime
déconnectés.

### Le rate limiting est-il actif ?

Oui, côté gateway : `express-rate-limit` applique 500 req/15min globalement et 20 req/15min sur
login/register, car docker-compose fixe `NODE_ENV=production` (le code ne désactive les limiteurs
que si `NODE_ENV=test`). En revanche, le rate limiting Nginx est **déclaré mais non appliqué**
(zones définies sans directive `limit_req`).

### Comment les mots de passe sont-ils protégés ?

Hachage `bcryptjs` avec `BCRYPT_ROUNDS` (10 en Docker, 12 par défaut dans le code, 4 en tests).
Le mot de passe en clair n'est jamais stocké ni journalisé. La validation impose ≥8 caractères,
1 majuscule et 1 chiffre. À l'inscription, l'erreur de login est volontairement générique
(`INVALID_CREDENTIALS`) pour éviter l'énumération de comptes.

### Quels secrets sont exposés dans le dépôt ?

`JWT_SECRET` et `INTERNAL_SECRET` sont des placeholders commités. Plus grave : une **vraie clé
OpenRouter** (`OPENROUTER_API_KEY`) est commitée en clair dans le `.env` du post-service. La
gateway a aussi un fallback `JWT_SECRET || "defaultSecret"`. Ces points sont détaillés et
priorisés dans la page [Secrets & configuration](../securite/secrets-configuration.md).

---

## Base de données

### Comment garantissez-vous la cohérence des compteurs ?

Deux stratégies. Côté PostgreSQL (follow/unfollow), une `sequelize.transaction()` englobe la
création/suppression du lien **et** les deux incréments de compteurs : tout est atomique.
Côté MongoDB (likes/comments/reposts), un `$inc` atomique, plus un index unique
`{post_id, user_id}` qui empêche les doublons (erreur 11000 → 409). Limites connues :
`likes_count` peut devenir négatif en base, `comments_count` peut diverger à la suppression en
cascade.

### Pourquoi pas de clés étrangères entre `follows` et `user_profiles` ?

Pour éviter de coupler deux bases potentiellement séparées et garder le service léger : les
jointures sont faites au niveau applicatif (récupérer les `Follow`, puis les `UserProfile` par
IDs). Le revers est qu'il n'y a pas de cascade : supprimer un profil laisserait des `follows`
orphelins.

### Comment fonctionne l'algorithme du feed ?

Le post-service appelle `GET /users/:id/following` (timeout 3 s) pour obtenir les abonnements,
fusionne avec l'ID de l'utilisateur (donc inclut ses propres posts), puis fait
`Post.find({ user_id: { $in } })` trié par date décroissante avec pagination offset. Chaque post
est enrichi de `likedByMe`/`repostedByMe`. Tri purement chronologique, pas de ranking. Si le
user-service est indisponible, le feed se replie sur les posts de l'utilisateur seul.

---

## Déploiement

### Comment les services se découvrent-ils dans Docker ?

Via le DNS interne du réseau bridge `breezy-network` : chaque service est résolvable par son nom
de service docker-compose (`http://auth-service:3001`, etc.). Seul Nginx publie un port
(`80:80`) ; tous les autres utilisent `expose`, donc ne sont joignables que sur le réseau
interne. Les microservices attendent leur base (`condition: service_healthy`) avant de démarrer.

### Comment gère-t-on un service indisponible ?

Chaque appel interne a un fallback : feed → liste de following vide, inscription → compte créé
sans sync immédiat, like → notification perdue, ban → propagation différée. La gateway, elle,
renvoie un **502** explicite par service quand le backend est injoignable. Le seul vrai point de
défaillance unique est la gateway (non load-balancée).

### Qu'est-ce qui manque pour une vraie production ?

HTTPS (Nginx est en HTTP), un monitoring/logging centralisé (actuellement `console.*`), des
migrations Sequelize au lieu de `sync({ alter: true })`, la sortie des secrets du dépôt (clé
OpenRouter notamment), la signature des headers inter-services, et la suppression du fallback
`defaultSecret`. La gateway devrait aussi être redondée.

---

## Difficultés & solutions

### Le bot IA `@breezy_ai`, comment ça marche ?

À la création d'un post, si le contenu contient `@breezy_ai`, le post-service appelle OpenRouter
(modèle `gpt-oss-20b:free`, timeout 15 s) et publie la réponse comme commentaire du compte bot
(tronquée à 280 caractères). L'appel est non bloquant. Le frontend détecte la mention et
re-fetch le post après 5 s pour afficher la réponse. Point de vigilance : la clé API est commitée
en clair.

### Pourquoi limiter la profondeur des commentaires à 1 niveau ?

Pour la lisibilité (fil plat plutôt qu'arbre profond) et la simplicité d'implémentation
(`getComments` charge les racines + un tableau `replies`, sans récursion). La limite est imposée
dans `createReply` : si le parent est déjà une réponse (`parent_comment_id` non nul), on renvoie
`400 MAX_DEPTH`.

### Quelles incohérences connues assumez-vous ?

Le `x-user-username` non injecté pour le user-service (notif follow sans username), les types de
notifications `comment`/`reply` jamais générés, l'absence d'UI pour le signalement et la
modération, et la messagerie réduite à des composants non connectés. Ces écarts sont documentés
explicitement dans [Couverture](../fonctionnalites/couverture.md).
