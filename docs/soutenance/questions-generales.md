# Questions generales de soutenance

> Chaque reponse cite des fichiers et lignes precis du code source reel du projet Breezy.

---

## 1. Pourquoi une architecture microservices ?

**Reponse :** Nous avons choisi 4 services independants (`breezy-auth-service`, `breezy-user-service`, `breezy-post-service`, `breezy-profil-service`) car chaque service gere un domaine metier distinct avec ses propres besoins de persistence et peut etre developpe, teste et deploye independamment.

- **Auth** : PostgreSQL (donnees relationnelles, credentials, tokens)
- **User** : PostgreSQL (profils publics, relations de follow, compteurs)
- **Post** : MongoDB (contenu flexible, tags, media)
- **Profil** : MongoDB (notifications, profils)

Chaque service a sa propre base de donnees, son propre cycle de vie et peut etre mis a l'echelle horizontalement sans impacter les autres.

**Sources :**
- docker-compose.yml : 12 conteneurs dont 4 services applicatifs, chacun avec sa propre DB (`C:\Users\barto\Desktop\breezy projet\breezy-infra\docker-compose.yml`, lignes 53-167)
- auth-service package.json : port 3001 (`C:\Users\barto\Desktop\breezy projet\breezy-auth-service\package.json`)
- user-service package.json : port 3002 (`C:\Users\barto\Desktop\breezy projet\breezy-user-service\package.json`)
- post-service package.json : port 3003 (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\package.json`)
- profil-service package.json : port 3004 (`C:\Users\barto\Desktop\breezy projet\breezy-profil-service\package.json`)

---

## 2. Pourquoi PostgreSQL pour auth/user et MongoDB pour posts/profils ?

**Reponse :** Le choix du type de base de donnees est dicte par la nature des donnees.

**PostgreSQL (Auth + User)** :
- Auth : relations strictes entre users, refresh_tokens (clefs etrangeres, contraintes d'integrite)
- User : relations de follow avec contraintes (pas de doublon, compteurs atomiques en transaction)
- Les schemas sont stables et previsibles

**MongoDB (Post + Profil)** :
- Post : schema flexible (tags en array, media_urls optionnels, champs qui peuvent evoluer)
- Les compteurs (likes_count, comments_count) beneficient de `$inc` atomique sans transaction
- Horizontal scaling nativement plus simple pour un volume de posts important
- Profil : upsert automatique a la lecture, structure simple (pas de jointures)
- Notifications : documents avec types variables (like, follow, mention, comment, reply)

**Sources :**
- Post model MongoDB : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\post.model.js` -- schema flexible avec tags en array (ligne 7) et tableaux de media_urls (ligne 8)
- User model PostgreSQL : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\models\userProfile.model.js` -- colonnes strictement definies (lignes 6-28)
- Auth model PostgreSQL : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\models\user.model.js` -- schema relationnel avec enum role (ligne 27)

---

## 3. JWT + Refresh Token : expliquez le flux complet avec detection de vol

**Reponse :** Le flux d'authentification repose sur un JWT court (15 minutes) et un refresh token long (7 jours) stocke en base sous forme de hash SHA-256.

**Flux normal :**
1. Connexion (`POST /auth/login`) : verification des credentials, generation JWT + refresh token. Le refresh token est stocke en base (hash SHA-256) et envoye en cookie httpOnly.
2. Appels API : le JWT est envoye dans le header `Authorization: Bearer <token>`. La Gateway le verifie a chaque requete.
3. Expiration JWT : le frontend recoit un 401, l'intercepteur Axios appelle `POST /auth/refresh` automatiquement.
4. Refresh : l'ancien refresh token est revoque (rotation), un nouveau est emis.

**Detection de vol :**
Si un refresh token deja revoque est presente (`stored.is_revoked === true`), le systeme reactive TOUS les refresh tokens de l'utilisateur :
```javascript
await RefreshToken.update({ is_revoked: true }, { where: { user_id: stored.user_id } });
```
Ceci est une mesure de securite : si un attaquant a vole un token et l'a utilise en premier, le refresh legitime de la victime declenchera cette detection. Les deux sessions sont alors invalidees et l'utilisateur doit se reconnecter.

**Sources :**
- Auth controller refresh function : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 115-166
- Detection de vol : ligne 133-138 (reutilisation d'un token deja revoque => revocation massive)
- Hash SHA-256 : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\utils\jwt.utils.js`, ligne 12 (`crypto.createHash('sha256').update(token).digest('hex')`)
- RefreshToken model : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\models\refreshToken.model.js`, ligne 18 (token_hash unique), ligne 27 (is_revoked)
- Frontend interceptor : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\services\api.js`, lignes 30-79 (file d'attente des requetes pendant le refresh)

---

## 4. Gateway pattern : pourquoi une verification JWT centralisee et injection de headers ?

**Reponse :** La Gateway est le seul point d'entree des requetes externes. Elle verifie le JWT une seule fois et injecte les headers `x-user-id`, `x-user-role`, `x-user-username` dans les requetes proxyfiees vers les services internes. Ceci offre plusieurs avantages :

1. **Securite centralisee** : un seul point de verification JWT, pas de duplication de la logique dans chaque service
2. **Changement de cle** : si la cle JWT change, seule la Gateway est impactee
3. **Headers inter-servic**es : les services backend n'ont pas besoin de decoder le JWT, ils lisent simplement les headers
4. **Reseau interne** : les services communiquent entre eux via le reseau interne Docker, les headers ne sont pas accessibles depuis l'exterieur

**Sources :**
- Gateway auth middleware : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\middleware\auth.js`, lignes 1-21
- Injection headers proxy : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 111-113 (user-service) et 163-165 (post-service)
- JWT utils gateway : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\utils\jwt.utils.js`, lignes 1-13

---

## 5. Communication inter-services : pourquoi HTTP REST et pas un message broker ?

**Reponse :** Nous avons utilise des appels HTTP REST synchrones avec timeout court pour la communication inter-services pour plusieurs raisons :

1. **Simplicite** : pas d'infrastructure supplementaire (RabbitMQ, Kafka)
2. **Appels critiques uniquement** : les communications sont limitees a quelques cas (sync user, notifications, ban propagation)
3. **Fail-safe pattern** : tous les appels inter-services sont non-bloquants avec catch silencieux. Si le service distant est down, l'operation principale continue
4. **Timeouts courts** : 1 seconde pour les notifications, 3 secondes pour les appels critiques. Si le timeout expire, l'erreur est loggee et ignoree
5. **Vision future** : un message broker est prevu en evolution moyen terme pour les evenements comme les notifications et la propagation de bans, ce qui decouplera les services

**Sources :**
- Sync user non-bloquant : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 37-48 (timeout 3s, catch silencieux)
- Notification like non-bloquante : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 22-33 (timeout 1s)
- Notification mention : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 44-64 (timeout 1s)
- Ban propagation non-bloquante : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 227-236 (timeout 3s)
- Follow notification non-bloquante : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 105-118 (timeout 1s)

---

## 6. Non-blocking pattern : pourquoi les appels inter-services sont fire-and-forget ?

**Reponse :** Tous les appels inter-services sont concus comme "fire-and-forget" (non-bloquants) pour garantir la resilience du systeme :

- Si le user-service est down lors de l'inscription, le compte est cree et le sync sera reessaye plus tard (ou fait manuellement)
- Si le profil-service est down lors d'un like, le like est enregistre, la notification est perdue
- Si l'auth-service est down lors d'un ban, le ban local est applique, la propagation se fera plus tard

Ce pattern evite les pannes en cascade : un service qui tombe ne bloque pas les autres services.

**Sources :**
- Sync registration : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 37-48
- Follow notification : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 105-118
- Ban propagation : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 227-236
- Like notification : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 22-33

---

## 7. Pourquoi Sequelize pour PostgreSQL et Mongoose pour MongoDB ?

**Reponse :** Chaque ORM/ODM est choisi pour ses forces naturelles avec sa base de donnees :

**Sequelize (PostgreSQL)** :
- Mapping objet-relationnel puissant pour les schemas strictes
- Support natif des transactions (`sequelize.transaction`) pour les operations atomiques (follow/unfollow avec compteurs)
- Migration automatique avec `{ alter: true }`
- Gere les relations (User.hasMany, RefreshToken.belongsTo)

**Mongoose (MongoDB)** :
- Schema flexible avec validation integree
- `$inc` atomique pour les compteurs sans transaction
- `findOneAndUpdate` avec `upsert` pour la creation automatique de profil
- Indexes composees uniques simples a declarer
- Population de references (ObjectId)

**Sources :**
- Sequelize transaction follow : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 89-102
- Mongoose $inc likes : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 15-20
- Sequelize relation RefreshToken : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\models\refreshToken.model.js`, lignes 36-37
- Mongoose upsert profil : `C:\Users\barto\Desktop\breezy projet\breezy-profil-service\src\controllers\profile.controller.js`, lignes 6-10

---

## 8. Comment fonctionne l'algorithme du feed ?

**Reponse :** L'algorithme du feed suit 4 etapes :

1. **Recuperation des abonnements** : le post-service appelle `GET /users/:userId/following` sur le user-service pour obtenir la liste des utilisateurs suivis (timeout 3s, fallback liste vide si erreur)
2. **Fusion des IDs** : l'utilisateur courant + ses abonnements sont combines dans un Set
3. **Requete MongoDB** : `Post.find({ user_id: { $in: feedUserIds } })` trie par `created_at: -1` avec pagination offset-based
4. **Enrichissement** : pour chaque post, on verifie si l'utilisateur courant l'a like (`likedByMe`) et reposte (`repostedByMe`) via deux requetes paralleles `Promise.all`

Si le user-service est indisponible, le feed affiche uniquement les posts de l'utilisateur courant (fallback silencieux).

**Sources :**
- getFeed controller : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 111-161
- Fallback liste vide : ligne 128 (catch silencieux)
- Enrichissement likedByMe/repostedByMe : lignes 140-151

---

## 9. Comment les compteurs sont-ils maintenus coherents ?

**Reponse :** Deux strategies differentes selon la base de donnees :

**MongoDB (posts)** : utilisation de `$inc` atomique pour les likes, commentaires et reposts. L'unicite est garantie par des indexes composees uniques (`{ post_id, user_id }`) sur les collections Like et Repost. Les duplicatas sont interceptes par le code erreur 11000.

```javascript
// like controller
await Post.findByIdAndUpdate(postId, { $inc: { likes_count: 1 } }, { new: true });
```

**PostgreSQL (user)** : utilisation de `sequelize.transaction()` pour les operations de follow/unfollow. La creation/suppression du lien de follow ET l'incrementation/decrementation des compteurs sont dans la meme transaction.

**Sources :**
- $inc likes : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 15-20
- Index unique Like : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\like.model.js`, ligne 11
- Index unique Repost : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\repost.model.js`, ligne 11
- Transaction Sequelize follow : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 89-102
- Math.max(0) securite un-like : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, ligne 60

---

## 10. Limitation de profondeur des commentaires : pourquoi seulement 1 niveau ?

**Reponse :** Les commentaires sont limites a 1 niveau de profondeur (commentaire principal + reponses, pas de reponse-a-reponse) pour plusieurs raisons :

1. **UX simplifiee** : un fil de commentaires plat avec reponses est plus facile a lire qu'un arbre complexe
2. **Performance** : evite les requetes recursives ou les aggregations complexes
3. **Implementation** : la logique de rendu est simple (une boucle sur les commentaires, chaque commentaire a un tableau `replies`)
4. **Cas d'usage** : pour un reseau social comme Breezy, 1 niveau est suffisant pour les conversations

La limite est enforcee dans `createReply` :
```javascript
if (parentComment.parent_comment_id) {
    return res.status(400).json({ error: { code: 'MAX_DEPTH', message: 'Reponse a une reponse non autorisee.' } });
}
```

**Sources :**
- Controller createReply : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\comment.controller.js`, lignes 107-139
- Verification MAX_DEPTH : lignes 120-122
- getComments avec replies : lignes 10-21

---

## 11. Strategie de rate limiting : double couche (Nginx + Gateway)

**Reponse :** Nous avons implemente deux couches de rate limiting :

**Nginx (infrastructure)** :
- Zone `global:10m` definie a `30 req/min`
- Zone `auth:10m` definie a `5 req/min`

**Gateway (application)** :
- Limiteur global `express-rate-limit` : 500 requetes / 15 minutes par IP
- Limiteur strict auth : 20 tentatives de connexion / 15 minutes par IP

La double couche permet une defense en profondeur : Nginx bloque au niveau reseau avant meme que la requete n'atteigne la Gateway. Cependant, en environnement Docker, les directives `limit_req` ne sont pas activees dans les `location` blocks -- seul le rate limiting Express est effectif.

**Note** : `NODE_ENV=test` dans le docker-compose desactive le rate limiting de la Gateway (999999 requetes).

**Sources :**
- Nginx config : `C:\Users\barto\Desktop\breezy projet\breezy-infra\nginx\nginx.conf`, lignes 16-17
- Gateway rate limiting : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 16-43
- NODE_ENV=test : `C:\Users\barto\Desktop\breezy projet\breezy-infra\docker-compose.yml`, ligne 37

---

## 12. Comment gere-t-on un service indisponible ?

**Reponse :** Chaque service a un mecanisme de fallback specifique :

1. **User-service down pendant le feed** : le post-service recupere une liste vide d'abonnements, le feed affiche uniquement les posts de l'utilisateur courant
2. **User-service down pendant l'inscription** : le compte est cree, un warning est logge, le sync se fera plus tard
3. **Profil-service down pendant un like** : le like est enregistre, la notification est silencieusement ignoree
4. **Auth-service down pendant un ban** : le ban local est applique dans user-service, la propagation est differee

De plus, chaque proxy de la Gateway a un handler `error` qui retourne un 502 avec le message "Service indisponible".

**Sources :**
- Feed fallback : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, ligne 128 (`console.warn`)
- Registration fallback : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 46-48
- Ban fallback : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 235-236
- Gateway 502 error handler : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 59-61, 77-79, etc.

---

## 13. Pourquoi Next.js App Router plutot que Pages Router ?

**Reponse :** Nous avons choisi Next.js 14 avec App Router pour plusieurs raisons :

1. **Server Components** : rendu cote serveur par defaut pour les pages, ce qui ameliore le SEO et les performances de chargement initial
2. **Route Groups** : organisation claire des routes (`(app)/` pour les pages authentifiees, `(auth)/` pour les pages non authentifiees, `legal/` pour les pages juridiques)
3. **Layouts imbriques** : `layout.js` racine avec AuthProvider, `(app)/layout.js` pour la garde d'authentification
4. **Client/Server separation** : le prefixe `'use client'` est explicite pour les composants interactifs
5. **Routing automatique** : la structure des dossiers definit les URLs sans configuration manuelle

**Sources :**
- `package.json` : `"next": "14.2.0"` (`C:\Users\barto\Desktop\breezy projet\breezy-frontend\package.json`)
- Route groups (auth) vs (app) : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\app\(auth)\layout.js` et `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\app\(app)\layout.js`
- Root layout avec AuthProvider : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\app\layout.js`

---

## 14. Comment fonctionne le systeme de mocks dans le frontend ?

**Reponse :** Le systeme de mocks permet de developper le frontend sans backend. Il fonctionne ainsi :

1. **Activation** : variable d'environnement `NEXT_PUBLIC_USE_MOCKS=true` dans `.env.local`
2. **Detection** : `isMockEnabled()` verifie la variable cote client (`sessionStorage` n'est pas accessible en SSR)
3. **Aiguillage** : chaque service exporte les deux implementations (reelle et mock) et choisit au moment de l'appel
4. **Donnees** : 5 utilisateurs fictifs, 8 posts, 3 jeux de commentaires, 6 notifications, 5 conversations
5. **Persistence** : les posts et commentaires crees en mode mock sont stockes dans `sessionStorage` (survivent au re-render mais pas au rechargement)

```javascript
// Pattern d'aiguillage
export const login = (...a) => isMockEnabled() ? mock.login(...a) : real.login(...a)
```

**Sources :**
- Utils mock : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\utils.js`, lignes 1-8
- Donnees mock : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\data.js`, lignes 1-260
- Mock auth service : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\authService.mock.js`
- Mock post service : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\postService.mock.js`
- Persistence sessionStorage : postService.mock.js (stocke sous `breezy_mock_posts`)

---

## 15. Qu'est-ce qui manque pour la production ?

**Reponse :** Plusieurs elements sont necessaires pour une mise en production :

1. **HTTPS** : pas de certificat SSL/TLS configure (le nginx ecoute en HTTP sur le port 80)
2. **CI/CD** : les workflows GitHub Actions existent mais ne sont pas completement operationalises
3. **Monitoring** : pas de Prometheus/Grafana, pas d'alerting, pas de logging centralise (uniquement `console.log`)
4. **Logging** : les logs sont en console uniquement, pas de stockage persistant (ELK, Loki)
5. **Mot de passe oublie** : pas de flux de reinitialisation de mot de passe (Fx23 non implementee)
6. **2FA** : pas d'authentification a deux facteurs
7. **`sequelize.sync({ alter: true })`** : dangereux en production car peut modifier le schema sans supervision
8. **`NODE_ENV=test`** : desactive le rate limiting dans Docker (risque de brute-force)
9. **Headers non signes** : les headers `x-user-*` ne sont pas signes -- un service compromis pourrait usurper l'identite
10. **Single point of failure** : la Gateway n'est pas load-balancee

**Sources :**
- sequelize.sync({ alter: true }) : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\config\database.js`, ligne 12
- NODE_ENV=test : `C:\Users\barto\Desktop\breezy projet\breezy-infra\docker-compose.yml`, ligne 37
- HTTP only (no HTTPS) : `C:\Users\barto\Desktop\breezy projet\breezy-infra\nginx\nginx.conf`, ligne 26

---

## 16. Expliquez la propagation du ban : user-service vers auth-service

**Reponse :** Le ban d'un utilisateur est initie depuis le user-service (route `PUT /users/:id/ban`). Le flux est le suivant :

1. **Verification du role** : seul un moderateur ou un admin peut bannir (403 sinon)
2. **Ban local** : `user.update({ is_banned: true })` dans la table `user_profiles`
3. **Propagation non-bloquante** : appel `POST /auth/internal/ban` avec `{ userId }` et le header `x-internal-secret`
4. **Auth-service** : verifie le secret interne, met a jour `is_banned: true` dans sa table `users`

Le ban doit etre propage aux deux services car :
- **Auth-service** : verifie `is_banned` au login (refuse la connexion) et au refresh
- **User-service** : verifie `is_banned` a la recherche, pour empecher les follow, etc.

Si l'auth-service est indisponible, le ban local est tout de meme applique immediatement.

**Sources :**
- banUser controller : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 213-243
- Role check moderateur/admin : ligne 215
- Propagation auth-service : lignes 227-236
- internalBan auth-service : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 225-247
- Verification ban au login : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 83-85
- Verification ban au refresh : lignes 146-151
