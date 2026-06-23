# Questions par membre

---

## Arthur -- Auth Service + User Service

### Q1 : Comment fonctionne la rotation des refresh tokens et la detection de vol ?

La fonction `refresh` dans `auth.controller.js` met en oeuvre un pattern de rotation avec detection de rejeu (token reuse detection).

**Flux normal :**
1. Le refresh token est recu du cookie httpOnly ou du body
2. Il est hache avec SHA-256 et recherche en base
3. Si trouve et non revoque, l'ancien token est marque `is_revoked = true`
4. Un nouveau token est genere et stocke (hash)
5. Un nouveau JWT est renvoye

**Detection de vol :**
Si un refresh token deja revoque est presente (`stored.is_revoked === true`), c'est le signe qu'un attaquant a peut-etre vole le token et l'a utilise en premier. Dans ce cas, TOUS les refresh tokens de l'utilisateur sont revoques massivement :
```javascript
await RefreshToken.update({ is_revoked: true }, { where: { user_id: stored.user_id } });
```

Ceci force l'utilisateur a se reconnecter -- l'attaquant et la victime sont tous deux deconnectes.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 115-166
- Detection de vol : lignes 133-138
- Hash SHA-256 : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\utils\jwt.utils.js`, ligne 12

---

### Q2 : Pourquoi avoir separe auth-service et user-service au lieu d'un seul service utilisateur ?

La separation repose sur le principe de responsabilite unique et des besoins de persistence differents :

**Auth-service** (PostgreSQL `breezy_auth`) :
- Gerer les credentials (email, password_hash)
- Emettre les JWT et refresh tokens
- Verifier les bans au login
- Table `users` avec donnees sensibles

**User-service** (PostgreSQL `breezy_users`) :
- Gerer les profils publics (username, role, stats)
- Gerer les relations de follow (table `follows`)
- Gerer les compteurs (followers_count, following_count)
- Table `user_profiles` sans donnees sensibles

Cette separation permet :
- De faire evoluer les schemas independamment
- D'appliquer des politiques de securite differentes (auth plus restreint)
- De scaler independamment (le user-service a plus de trafic que l'auth-service)

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\models\user.model.js` (password_hash, email, is_banned)
- `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\models\userProfile.model.js` (followers_count, following_count, pas de password)
- `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\.env.example` (DATABASE_URL differente)
- `C:\Users\barto\Desktop\breezy projet\breezy-user-service\.env.example` (DATABASE_URL differente)

---

### Q3 : Comment garantis-tu l'atomicite des compteurs followers/following ?

J'utilise `sequelize.transaction()` pour encapsuler les operations de follow et unfollow. Les deux operations (creation/suppression du lien + increments/decrements des compteurs) sont dans la meme transaction. Si une etape echoue, les deux sont rollback.

**Follow :**
```javascript
await sequelize.transaction(async (t) => {
  const [follow, created] = await Follow.findOrCreate(
    { where: { follower_id, followed_id }, transaction: t }
  );
  if (!created) throw new FollowError('ALREADY_FOLLOWING');
  await UserProfile.increment('following_count', { by: 1, where: { id: follower_id }, transaction: t });
  await UserProfile.increment('followers_count', { by: 1, where: { id: followed_id }, transaction: t });
});
```

L'index unique composite `[follower_id, followed_id]` sur la table `follows` empeche les doublons au niveau base de donnees.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 89-102 (follow transaction)
- Lignes 136-148 (unfollow transaction)
- `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\models\follow.model.js`, ligne 20 (index unique)

---

### Q4 : Explique le flux d'inscription complet, de la creation du compte a la sync profil

1. **Validation** : les donnees (username 3-50 chars, email valide, password 8+ avec majuscule et chiffre) sont validees par `express-validator`
2. **Unicite** : verification que l'email et le username sont uniques (409 sinon)
3. **Hash** : le mot de passe est hache avec `bcrypt` (10 rounds dans l'env de dev)
4. **Creation** : un utilisateur est cree dans la table `users` de l'auth-service (PostgreSQL)
5. **Sync non-bloquant** : appel `POST /users/sync` vers le user-service avec `{ id, username, role }` et le header `x-internal-secret`
6. **Tokens** : generation du JWT (15 min) et du refresh token (7 jours, hache SHA-256)
7. **Cookie** : le refresh token est place en cookie httpOnly
8. **Reponse** : 201 avec `{ user, token }`

Si le user-service est down, l'etape 5 echoue silencieusement (warning log), mais l'inscription est toujours valide.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 19-70
- Sync non-bloquant : lignes 37-48
- Validation : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\routes\auth.routes.js`, lignes 8-26

---

### Q5 : Comment le ban est-il propage entre user-service et auth-service ?

Le ban est initie depuis le user-service (`PUT /users/:id/ban`). La propagation suit ce chemin :

1. **Verification du role** : seuls `moderator` ou `admin` peuvent bannir (ligne 215)
2. **Ban local** : `user.update({ is_banned: true })` dans `user_profiles` (ligne 224)
3. **Propagation non-bloquante** : `POST /auth/internal/ban` avec `{ userId }` (lignes 227-236)
4. **Cote auth** : l'endpoint interne verifie `x-internal-secret`, trouve l'utilisateur par PK, met `is_banned: true`

Le ban est propage aux deux services car chacun verifie ce flag a des moments differents :
- **Auth** : au login (ligne 83-85) et au refresh (lignes 146-151)
- **User** : lors des requetes GET et follow

Le flux est non-bloquant : si l'auth-service est down, le ban local est applique immediatement.

**Sources :**
- banUser : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\controllers\user.controller.js`, lignes 213-243
- internalBan : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 225-247
- Verification ban login : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, lignes 83-85

---

## Maxime -- Post Service + Profil Service

### Q1 : Comment fonctionne l'algorithme du feed ?

L'algorithme dans `getFeed` suit 4 etapes :

**Etape 1 - Recuperation des abonnements :**
Le post-service appelle `GET /users/:userId/following` sur le user-service avec un timeout de 3 secondes. Si le user-service est indisponible, la liste est vide (fallback).

```javascript
const response = await axios.get(
    `${process.env.USER_SERVICE_URL}/users/${userId}/following`,
    { headers: { 'x-user-id': userId }, timeout: 3000 }
);
followingIds = response.data.ids || response.data.data || [];
```

**Etape 2 - Fusion :** on combine l'ID de l'utilisateur courant avec les IDs des abonnements.

**Etape 3 - Requete MongoDB :** posts tries par `created_at: -1` avec pagination offset-based.

**Etape 4 - Enrichissement :** deux requetes paralleles (`Promise.all`) sur Like et Repost pour determiner `likedByMe` et `repostedByMe` pour chaque post.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 111-161
- Fallback user-service : ligne 128
- Enrichissement likedByMe : lignes 140-151

---

### Q2 : Pourquoi MongoDB plutot que PostgreSQL pour les posts ?

Le choix de MongoDB pour le post-service est justifie par plusieurs facteurs :

1. **Schema flexible** : un post peut avoir des tags (array), des medias (array), et des champs optionnels. Avec MongoDB, on ajoute un champ sans migration
2. **Operations atomiques** : `$inc` pour les compteurs (likes_count, comments_count, reposts_count) sans transaction
3. **Index compose** : index sur `{ user_id, created_at }` optimise les requetes de feed et de profil
4. **Horizontal scaling** : le sharding natif de MongoDB permet de distribuer les posts sur plusieurs serveurs
5. **Document-oriented** : les posts sont des documents autonomes, pas besoin de jointures complexes

**Sources :**
- Post model : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\post.model.js` (tags en array ligne 7, media_urls ligne 8)
- Index compose feed : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\post.model.js`, ligne 17
- $inc likes : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, ligne 18

---

### Q3 : Comment geres-tu la coherence des compteurs (likes_count, comments_count) ?

Les compteurs sont geres avec `$inc` atomique de MongoDB, ce qui garantit qu'il n'y a pas de race condition entre increments simultanes.

**Like :**
```javascript
// Creation du like
await Like.create({ post_id: postId, user_id: userId });
// Incrementation atomique
const updated = await Post.findByIdAndUpdate(postId, { $inc: { likes_count: 1 } }, { new: true });
```

**Protection contre les doublons :**
Les collections Like et Repost ont un index unique compose `{ post_id: 1, user_id: 1 }`. Si un utilisateur tente de liker deux fois le meme post, MongoDB renvoie une erreur 11000 qui est interceptee et transformee en 409 ALREADY_LIKED.

**Protection contre les negatifs :**
Lors d'un unlike, on utilise `Math.max(0, updated.likes_count)` pour empecher un compteur negatif en cas de race condition.

**Sources :**
- $inc likes : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 15-20
- Detection doublon : ligne 37 (`err.code === 11000`)
- Math.max securite : ligne 60
- Index unique Like : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\like.model.js`, ligne 11
- Index unique Repost : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\repost.model.js`, ligne 11

---

### Q4 : Explique le systeme de notifications : comment sont-elles creees et consommrees ?

Les notifications sont gerees par le profil-service.

**Creation (endpoint interne) :**
```javascript
POST /api/notifications/internal
Body: { recipient_user_id, type, from_user_id, from_username, post_id }
Header: x-internal-secret
```

Les notifications sont creees depuis :
- **Like** : quand un utilisateur like un post
- **Follow** : quand un utilisateur en suit un autre
- **Mention** : quand un post contient `@username`
- **Comment/Reply** : types definis dans le schema mais pas generes actuellement

**Protection :**
- Auto-notification ignoree : `recipient_user_id === from_user_id` => 204 No Content
- Secret interne : `x-internal-secret` requis
- Timeout court : 1 seconde (non-bloquant)

**Consommation (frontend) :**
```javascript
GET /api/notifications?page=1&unread_only=true
PUT /api/notifications/read-all  (tout marquer comme lu)
PUT /api/notifications/:id/read (marquer une comme lue)
```

**Sources :**
- Notification model : `C:\Users\barto\Desktop\breezy projet\breezy-profil-service\src\models\notification.model.js`, lignes 1-19
- createNotification : `C:\Users\barto\Desktop\breezy projet\breezy-profil-service\src\controllers\notification.controller.js`, lignes 60-75
- Auto-notification ignoree : lignes 68-70
- Appel depuis like : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 22-33
- Types supportes : `['like', 'follow', 'mention', 'comment', 'reply']`

---

### Q5 : Pourquoi limiter la profondeur des commentaires a 1 niveau ?

La limite a 1 niveau de profondeur (commentaire principal + reponses directes, pas de reponse-a-reponse) est un choix de conception :

1. **UX simplifiee** : un fil de commentaires plat est plus lisible qu'un arbre complexe de 3+ niveaux
2. **Performance** : evite les requetes recursives, les aggregations MongoDB complexes et les rendus cote client couteux
3. **Implementation simple** : chaque commentaire peut avoir un tableau `replies` charge en une seule requete supplementaire
4. **Cas d'usage** : pour un micro-blogging, les conversations profondes sont rares

La limite est enforcee dans le controller :
```javascript
if (parentComment.parent_comment_id) {
    return res.status(400).json({
        error: { code: 'MAX_DEPTH', message: 'Reponse a une reponse non autorisee.' }
    });
}
```

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\comment.controller.js`, lignes 120-122
- getComments avec replies : lignes 10-21

---

## Jessica -- Frontend

### Q1 : Comment le JWT est-il gere cote client ?

Le JWT est stocke dans `localStorage` sous une cle configurable via `NEXT_PUBLIC_TOKEN_KEY` (par defaut `'breezy_token'`).

**AuthContext :**
- Lecture synchrone dans `useState` pour eviter les deconnexions flash :
  ```javascript
  const [token, setToken] = useState(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem(TOKEN_KEY) || null
    }
    return null
  })
  ```
- `saveToken(t)` ecrit a la fois dans le state React et dans `localStorage`
- Au montage, si un token existe, `getMe()` est appele pour recuperer les infos utilisateur
- `logout()` appelle l'API de deconnexion, vide le state et `localStorage`
- Le context expose aussi le compteur de notifications non lues et de messages non lus

**Request interceptor Axios :**
Chaque requete est interceptee pour ajouter le header `Authorization: Bearer <token>` depuis `localStorage`.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\context\AuthContext.js`, lignes 1-97
- Token dans localStorage : lignes 12-17 (lecture synchrone)
- saveToken : lignes 74-77
- logout : lignes 79-84
- Intercepteur requete : `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\services\api.js`, lignes 11-17

---

### Q2 : Comment fonctionne l'intercepteur Axios pour le refresh automatique ?

L'intercepteur de reponse dans `api.js` gere le refresh automatique avec une file d'attente :

1. Quand une requete recoit un 401, l'intercepteur est declenche
2. Si la requete est sur `/auth/login`, on laisse l'erreur passer (mauvais credentials)
3. Si la requete est sur `/auth/refresh` et echoue, on redirige vers `/signin`
4. Si un refresh est deja en cours (`isRefreshing === true`), la requete est mise en file d'attente (`failedQueue`)
5. Sinon, on appelle `POST /auth/refresh` :
   - **Succes** : le nouveau token est sauvegarde, la file d'attente est resolue avec le nouveau token, toutes les requetes sont rejoue
   - **Echec** : le token est supprime de `localStorage`, redirection vers `/signin`

Ce systeme permet d'eviter que plusieurs requetes ne declenchent des refresh concurrents et garantit que toutes les requetes pendantes sont replayees apres le refresh.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\services\api.js`, lignes 19-79
- File d'attente : lignes 19-28 (processQueue)
- Gestion refresh concurrent : lignes 47-53 (isRefreshing)
- Refresh effectif : lignes 56-74

---

### Q3 : Explique le systeme de mocks et son utilite

Le systeme de mocks permet de developper et tester le frontend independamment du backend.

**Activation :** `NEXT_PUBLIC_USE_MOCKS=true` dans `.env.local`

**Detection :**
```javascript
export const isMockEnabled = () =>
  typeof window !== 'undefined' &&
  process.env.NEXT_PUBLIC_USE_MOCKS === 'true'
```

**Aiguillage :** chaque service (authService, postService, etc.) exporte des fonctions qui appellent soit l'implementation reelle (Axios), soit l'implementation mockee :
```javascript
export const login = (...a) => isMockEnabled() ? mock.login(...a) : real.login(...a)
```

**Donnees de test :** 5 utilisateurs fictifs, 8 posts realistes, 3 jeux de commentaires, 6 notifications, 5 conversations avec un token JWT factice.

**Persistence :** les posts et commentaires crees en mode mock sont stockes dans `sessionStorage` sous les cles `breezy_mock_posts` et `breezy_mock_comments`, ce qui permet de conserver les donnees entre les navigations mais pas entre les sessions.

**Utilite :**
- Permet le developpement frontend sans backend
- Tests de l'UI sans dependance externe
- Scenarios de test rapides sans nettoyage de base de donnees
- Demo de l'application sans infrastructure

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\utils.js`, lignes 1-8
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\data.js`, lignes 1-260
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\authService.mock.js`
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\mocks\postService.mock.js`

---

### Q4 : Comment sont gerees les mises a jour optimistes (likes, follows) ?

Les hooks `useLike` et `useFollow` implementent un pattern de mise a jour optimiste.

**useLike :**
```javascript
async function handleLike() {
  if (loading) return
  const was = liked; const prev = count
  setLiked(!was); setCount(was ? prev-1 : prev+1)  // UI update immediate
  setLoad(true)
  try {
    const d = was ? await unlikePost(post._id) : await likePost(post._id)
    setLiked(!was); setCount(d.likes_count)
    onUpdate?.({ ...post, likedByMe: !was, likes_count: d.likes_count })
  } catch { setLiked(was); setCount(prev) }  // Rollback sur erreur
  finally { setLoad(false) }
}
```

**useFollow :**
```javascript
async function toggle() {
  if (loading) return
  const was = following; setF(!was); setL(true)  // UI update immediate
  try { was ? await unfollowUser(userId) : await followUser(userId) }
  catch { setF(was) }  // Rollback sur erreur
  finally { setL(false) }
}
```

**Points communs :**
1. L'interface utilisateur est mise a jour immediatement (UX reactive)
2. L'etat precedent est sauvegarde avant la mutation
3. Si l'appel API echoue, l'etat est restaure (rollback)
4. Un flag `loading` empeche les clics multiples
5. Le parent peut etre notifie via un callback `onUpdate`

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\hooks\useLike.js`, lignes 1-25
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\hooks\useFollow.js`, lignes 1-18

---

### Q5 : Quels sont les choix de composants reutilisables et pourquoi ?

Nous avons concu une bibliotheque de composants UI reutilisables pour garantir la coherence visuelle et reduire la duplication.

**Button** (7 variantes) :
- `primary` : fond sombre, texte blanc (action principale)
- `secondary` : fond blanc, bordure (action secondaire)
- `ghost` : texte seul (action tertiaire)
- `follow` / `unfollow` : etats specifiques pour le bouton de follow
- `primary_pill` / `secondary_pill` : variantes arrondies pleine largeur

```javascript
const VARIANTS = {
  primary:   'bg-breezy-dark text-white hover:bg-black',
  secondary: 'bg-white text-breezy-dark border border-breezy-border hover:bg-gray-50',
  ghost:     'text-breezy-dark hover:bg-breezy-hover',
  follow:    'bg-breezy-dark text-white ... rounded-full hover:bg-black',
  unfollow:  'bg-white text-breezy-dark ... rounded-full border ... hover:text-red-600',
  primary_pill: 'bg-breezy-dark text-white ... rounded-full w-full',
  secondary_pill: 'bg-white ... rounded-full border w-full',
}
```

**Avatar** (5 tailles) : `xs` (28px), `sm` (36px), `md` (44px), `lg` (64px), `xl` (96px). Affiche l'image ou la premiere lettre du username.

**Input** : supporte `label`, `error`, `icon` (gauche), `rightIcon`, etat focus/error.

**Spinner** : 3 tailles (16px, 24px, 32px) avec animation CSS `animate-spin`.

**AppShell** : layout principal avec sidebar desktop, contenu central (max-w-[600px]), et bottom nav mobile.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\components\ui\Button.js`, lignes 1-24
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\components\ui\Avatar.js`, lignes 1-14
- `C:\Users\barto\Desktop\breezy projet\breezy-frontend\src\components\layout\AppShell.js`

---

## Esteban -- Infra & Gateway

### Q1 : Comment la Gateway verifie-t-elle les JWT et injecte-t-elle les headers ?

**Verification JWT (middleware `auth.js`) :**
```javascript
function authenticate(req, res, next) {
    const authHeader = req.headers['authorization'];
    if (!authHeader) return res.status(401).json({ message: "No token provided" });
    const token = authHeader.split(' ')[1];
    const decoded = verifyToken(token);
    if (!decoded) return res.status(401).json({ message: "Invalid or expired token" });
    req.user = decoded;
    next();
}
```

**Injection des headers :**
Apres verification, chaque proxy route injecte les headers `x-user-*` dans la requete transferee au service backend :
```javascript
proxyReq.setHeader('x-user-id', req.user.sub);
proxyReq.setHeader('x-user-role', req.user.role);
proxyReq.setHeader('x-user-username', req.user.username);
```

Le JWT est decode avec `jwt.verify(token, JWT_SECRET)` qui retourne le payload `{ sub, username, role, iat, exp }`. Le `sub` (subject) correspond a l'UUID de l'utilisateur.

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\middleware\auth.js`, lignes 1-21
- `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\utils\jwt.utils.js`, lignes 1-13
- Injection headers user-service : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 111-113
- Injection headers post-service : lignes 163-165

---

### Q2 : Pourquoi un double niveau de rate limiting (Nginx + Gateway) ?

La double couche offre une defense en profondeur :

**Nginx (infrastructure, couche 1) :**
- Agit au niveau TCP avant meme que la requete n'atteigne Node.js
- Consomme extremement peu de ressources
- Protege contre les attaques DDoS de base
- Zones memoire partagee : `global:10m` (30 req/min), `auth:10m` (5 req/min)

**Gateway (application, couche 2) :**
- Rate limiting plus fin, avec des messages d'erreur personnalises en francais
- Limiteur global : 500 req/15min/IP
- Limiteur auth : 20 req/15min/IP (login/register)
- Headers standardises (`RateLimit-*`) pour que le client sache quand il est limite
- Possibilite de desactiver en mode test (`NODE_ENV=test`)

En production, les deux couches seraient actives. En environnement Docker actuel, seuls les limiteurs Express sont effectifs.

**Sources :**
- Nginx rate limit zones : `C:\Users\barto\Desktop\breezy projet\breezy-infra\nginx\nginx.conf`, lignes 16-17
- Gateway global limiter : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 19-25
- Gateway auth limiter : lignes 28-34
- Application selectif : lignes 37-43

---

### Q3 : Comment les services communiquent-ils entre eux dans Docker ?

Les services communiquent via le reseau bridge `breezy-network` defini dans `docker-compose.yml`. Chaque service peut acceder aux autres par leur nom de conteneur (hostname DNS interne).

**Configuration reseau :**
```yaml
networks:
  breezy-network:
    driver: bridge
```

**Variables d'environnement pour les URLs internes (fichier `.env` de breezy-infra) :**
```
AUTH_SERVICE_URL=http://auth-service:3001
USER_SERVICE_URL=http://user-service:3002
POST_SERVICE_URL=http://post-service:3003
PROFIL_SERVICE_URL=http://profil-service:3004
```

Seul Nginx expose un port public (80:80). Tous les services backend utilisent `expose` (accessible uniquement depuis le reseau interne).

**Sources :**
- `C:\Users\barto\Desktop\breezy projet\breezy-infra\docker-compose.yml`, lignes 244-247 (reseau)
- Variables d'environnement : lignes 40-43 (gateway), 63-65 (auth), etc.
- Nginx unique point d'entree : ligne 9 (`"80:80"`)

---

### Q4 : Comment sont geres les fichiers uploades dans l'infrastructure ?

**Upload :**
1. Le frontend envoie le fichier vers `POST /api/upload` (proxy Gateway)
2. La Gateway verifie le JWT, injecte `x-user-*` headers
3. Le post-service recoit la requete, multer traite le fichier
4. Validation : image uniquement, maximum 5MB
5. Stockage : disque local dans `uploads/` avec nom unique (`timestamp-randomNumber.ext`)

**Stockage :** un volume Docker nomme `uploads_data` est monte sur le conteneur du post-service :
```yaml
volumes:
  - uploads_data:/app/uploads
```

**Servi statiquement :**
```javascript
app.use('/api/uploads', express.static(path.join(__dirname, '..', 'uploads')));
```
Les fichiers sont accessibles publiquement via `GET /api/uploads/<filename>` (proxy Gateway sans authentification).

**Sources :**
- Multer config : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\middleware\upload.middleware.js`, lignes 1-35
- uploadMedia controller : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 334-350
- Static serving : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\app.js`, ligne 16
- Volume uploads_data : `C:\Users\barto\Desktop\breezy projet\breezy-infra\docker-compose.yml`, ligne 115
- Gateway proxy public uploads : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 141-153

---

### Q5 : Que se passe-t-il si le gateway est down ? Et si un service backend est down ?

**Gateway down = tout down :**
La Gateway est un single point of failure. Toutes les requetes API passent par elle. Si elle est indisponible :
- Nginx renvoie une erreur 502 Bad Gateway
- Le frontend ne peut plus faire aucun appel API
- Les utilisateurs voient une page vide ou une erreur reseau

C'est la principale limitation de l'infrastructure actuelle. En production, il faudrait load-balancer plusieurs instances de Gateway.

**Service backend down :**
Grace au pattern fail-safe, le systeme continue de fonctionner partiellement :
- **User-service down** : le feed affiche seulement les posts de l'utilisateur courant, les likes/notifications ne sont pas envoyees
- **Post-service down** : le feed ne se charge pas, la creation de post echoue
- **Profil-service down** : les notifications ne sont pas sauvegardees
- **Auth-service down** : les connexions et refresh echouent, les utilisateurs deja connectes continuent jusqu'a expiration du JWT

La Gateway renvoie un 502 avec un message explicite pour chaque proxy quand le backend est indisponible.

**Sources :**
- Gateway 502 handlers : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 59-61, 77-79, 95-97, 115-117, 134-136, 149-151, 168-170, 187-189, 206-208
- Feed fallback : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, ligne 128
