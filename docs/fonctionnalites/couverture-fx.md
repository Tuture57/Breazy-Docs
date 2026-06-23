# Couverture Fonctionnelle

## Tableau des fonctionnalites

| Fx | Description | Backend | Frontend | Statut |
|----|-------------|---------|----------|--------|
| Fx1 | Inscription | ✅ auth-service (`POST /auth/register`) | ✅ `/register`, validation email/username/password | ✅ Complet |
| Fx2 | Connexion | ✅ auth-service (`POST /auth/login`) | ✅ `/signin`, gestion erreurs bannissement | ✅ Complet |
| Fx3 | JWT + Refresh Token | ✅ Rotation + detection vol + revocation | ✅ Interceptor Axios + file attente requetes | ✅ Complet |
| Fx4 | Profil utilisateur | ✅ user-service + profil-service | ✅ `/profile`, `/profile/:id`, `getFullProfile` fusion | ✅ Complet |
| Fx5 | Edition profil | ✅ profil-service (`PUT /profils/:userId`) | ✅ `/profile/edit` | ✅ Complet |
| Fx6 | Follow/Unfollow | ✅ Transactions atomiques + notifications | ✅ `useFollow` hook (optimistic) | ✅ Complet |
| Fx7 | Feed | ✅ Base sur following list (`$in`) | ✅ Infinite scroll pagination | ✅ Complet |
| Fx8 | Creation post | ✅ 280 chars + tags (max 5) + media | ✅ `/compose` + `PostForm` avec autocomplete @mentions | ✅ Complet |
| Fx9 | Like/Unlike | ✅ `$inc` atomique + notif + index unique | ✅ `useLike` (optimistic, rollback) | ✅ Complet |
| Fx10 | Commentaires | ✅ + reponses 1 niveau (MAX_DEPTH) + cascade | ✅ `CommentThread` avec reponses imbriquees | ✅ Complet |
| Fx11 | Recherche utilisateurs | ✅ `Op.iLike`, exclut bannis, tri followers_count | ✅ `/search`, `SearchBar` | ✅ Complet |
| Fx12 | Recherche posts | ✅ regex content/tags/username | ✅ `/search`, meme page que recherche users | ✅ Complet |
| Fx13 | Notifications | ✅ like, follow, mention, comment, reply | ✅ `/notifications` + badge compteur non lues | ✅ Complet |
| Fx14 | @mentions | ✅ Extraction regex + resolution + notification | ✅ `useMentions` dropdown autocomplete | ✅ Complet |
| Fx15 | Upload media | ✅ multer 5MB, images seulement | ✅ `PostForm` + `ComposeFab` avec preview | ✅ Complet |
| Fx16 | Repost | ✅ toggle avec `$inc` + index unique | ✅ `PostActions` toggle (optimistic) | ✅ Complet |
| Fx17 | Edition post | ✅ `PUT /posts/:id` (owner only) | ✅ `PostCard` inline edit | ✅ Complet |
| Fx18 | Suppression post | ✅ Cascade likes+comments+reposts | ✅ `PostActions` menu avec confirmation | ✅ Complet |
| Fx19 | Signalement | ✅ `is_reported=true` via `POST /posts/:id/report` | ❌ Pas d'UI signalement | ⚠️ Partiel |
| Fx20 | Changement mot de passe | ✅ `POST /auth/change-password` | ✅ `/settings` | ✅ Complet |
| Fx21 | Bannissement | ✅ user-service + auth-service sync | ❌ Pas d'UI moderation | ⚠️ Partiel |
| Fx22 | Messagerie | ❌ Aucun backend | ⚠️ Page placeholder, composants `ConversationList` + `MessageThread` | ❌ Absent |
| Fx23 | Mot de passe oublie | ❌ Aucun backend | ⚠️ Bouton "Oublie?" inactif, message indisponibilite | ❌ Absent |

---

## Details des fonctionnalites partielles ou absentes

### Fx19 - Signalement (PARTIEL)

**Backend** : La route `POST /api/posts/:id/report` existe et fonctionne. Elle passe `is_reported: true` sur le post.

**Frontend** : Aucun bouton "Signaler" n'est implemente dans le menu d'options des posts (`PostActions.js`). Les seules options disponibles sont "Modifier" et "Supprimer" (pour le proprietaire uniquement).

**Impact** : La fonctionnalite backend est inutilisable sans interface frontend. Les moderators ne peuvent pas voir la liste des posts signales (pas de route de filtrage par `is_reported`).

---

### Fx21 - Bannissement (PARTIEL)

**Backend** : La route `PUT /api/users/:id/ban` existe dans le user-service. Elle verifie le role (`moderator` ou `admin`), met a jour `is_banned` localement et propage vers l'auth-service via `POST /auth/internal/ban`. La propagation est **non bloquante** (timeout 3s, ignore les erreurs).

**Frontend** : Aucun panneau d'administration ou de moderation n'est implemente. Il n'y a pas :
- De page de liste des utilisateurs pour les moderators
- De bouton "Bannir" sur les profils
- De visualisation des posts signales
- De notification de bannissement a l'utilisateur concerne

**Impact** : Le bannissement n'est utilisable que via des appels API directs (curl, Postman).

---

### Fx22 - Messagerie (ABSENT)

**Backend** : Aucun service de messagerie n'existe. Aucune collection, route ou controller dedie.

**Frontend** : Deux composants existent (`ConversationList`, `MessageThread`) mais ne sont pas relies a une API. La page `/messages` affiche un message placeholder :

```
"La messagerie directe sera disponible dans une prochaine version de Breezy."
```

**Probleme detecte** : Le `AuthContext` appelle `getUnreadMessagesCount()` depuis `messageService.js`, mais cette fonction est un stub qui retourne toujours `0` :

```javascript
// frontend/src/services/messageService.js
export const getUnreadMessagesCount = async () => 0
```

Cette fonction est importee et appelee dans `AuthContext.js` ligne 5 et 40, mais la route backend correspondante n'existe pas.

---

### Fx23 - Mot de passe oublie (ABSENT)

**Backend** : Aucune route de reinitialisation de mot de passe n'existe. Pas de token de reset, pas d'envoi d'email, pas de logique de validation.

**Frontend** : Le bouton "Oublie?" sur la page `/signin` affiche un message d'indisponibilite :

```javascript
function handleForgotPassword() {
    setInfoMessage(
        'La reinitialisation de mot de passe n\'est pas encore disponible. ' +
        'Contactez un administrateur.'
    );
}
```

**Impact** : Si un utilisateur oublie son mot de passe, la seule solution est de contacter un administrateur pour une reinitialisation manuelle en base de donnees.

---

## Divergences et problemes identifies

### 1. Divergence de validation des mots de passe

Le fichier `frontend/src/utils/validators.js` contient deux fonctions avec des regles differentes :

```javascript
// Fonction generique -- PLUS PERMISSIVE
export const isValidPassword = (p) => typeof p === 'string' && p.length >= 6;

// Validation du formulaire d'inscription -- COHERENTE avec le backend
else if (form.password.length < 8) { ... }
else if (!/[A-Z]/.test(form.password)) { ... }
else if (!/[0-9]/.test(form.password)) { ... }
```

- `isValidPassword` : >= 6 caracteres, aucune complexite requise
- `validateRegisterForm` : >= 8 caracteres, >= 1 majuscule, >= 1 chiffre (coherent avec le backend)
- Backend (express-validator) : >= 8 caracteres, >= 1 majuscule, >= 1 chiffre

La fonction `isValidPassword` n'est pas utilisee dans le formulaire d'inscription, mais pourrait etre utilisee ailleurs (changement de mot de passe par exemple), creant un risque de validation inconsistante.

### 2. Divergence de validation du username

- **Frontend** (`isValidUsername`) : >= 2 caracteres
- **Backend** (express-validator) : 3-50 caracteres, alphanumerique + underscores

```javascript
// Backend auth-service/src/routes/auth.routes.js
body('username')
  .isLength({ min: 3, max: 50 })
  .matches(/^[a-zA-Z0-9_]+$/)
```

Le backend rejette les noms de 2 caracteres qui pourraient etre acceptes par le frontend.

### 3. Absence du header x-user-username pour le user-service

La gateway n'injecte pas le header `x-user-username` pour les routes `/api/users/*` :

```javascript
// gateway/src/index.js — routes /api/users
proxyReq.setHeader('x-user-id', req.user.sub);
proxyReq.setHeader('x-user-role', req.user.role);
// x-user-username MANQUANT
fixRequestBody(proxyReq, req, res);
```

Les autres services recoivent bien ce header :
```javascript
// gateway/src/index.js — routes /api/posts, /api/profils, etc.
proxyReq.setHeader('x-user-username', req.user.username);
```

**Impact** : Dans le user-service, le controller `follow` utilise `req.username` pour envoyer une notification de follow. Comme `x-user-username` n'est pas injecte, `req.username` est `undefined` et la notification de follow contiendra `from_username: undefined`.

### 4. Route de profil : divergence d'appel

Le frontend a ete verifie : il utilise bien `PUT /profils/:userId` (profil-service) via `userService.updateProfile()` :

```javascript
// frontend/src/services/userService.js
updateProfile: (id, d) => api.put(`/profils/${id}`, d).then(r => r.data),
```

Le controleur de profile utilise bien `PUT /api/profils/:userId`. Les appels sont corrects.

### 5. Rate limiting desactive en Docker

Le docker-compose.yml definit `NODE_ENV=test` pour la gateway :

```yaml
gateway:
  environment:
    - NODE_ENV=test  # Desactive le rate limiting
```

Le code de la gateway desactive effectivement les limiteurs en mode test :

```javascript
const isTest = process.env.NODE_ENV === 'test';
const globalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: isTest ? 999999 : 500,  // 999999 en test
});
```

En production, `NODE_ENV` ne doit pas etre `test`.

### 6. Pas de route de filtrage des posts signales

Bien que la route `POST /api/posts/:id/report` existe et marque `is_reported: true`, il n'y a aucune route pour :
- Lister les posts signales (`GET /api/posts/reported`)
- Lever un signalement (`PUT /api/posts/:id/unreport`)
- Supprimer un post signale apres moderation (la suppression classique existe deja)
