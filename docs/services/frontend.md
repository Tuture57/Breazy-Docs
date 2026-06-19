# Frontend (Next.js)

**Responsabilité** : Interface utilisateur du réseau social Breezy.

- **Stack** : Next.js 14 (App Router), React 18, Tailwind CSS 3, Axios, date-fns
- **Port** : 3000
- **Dépôt** : `breezy-frontend`

## Structure du projet

```
breezy-frontend/
├── src/
│   ├── app/
│   │   ├── layout.js                 ← Layout racine (AuthProvider, Google Fonts Inter)
│   │   ├── page.js                   ← Page d'accueil publique
│   │   ├── (auth)/                   ← Route group — pages d'authentification
│   │   │   ├── layout.js
│   │   │   ├── connect/page.js       ← Landing page (choix inscription/connexion)
│   │   │   ├── signin/page.js        ← Formulaire de connexion
│   │   │   └── register/page.js      ← Formulaire d'inscription
│   │   ├── (app)/                    ← Route group — pages protégées
│   │   │   ├── layout.js             ← Garde d'authentification (redirect /connect si pas de token)
│   │   │   ├── home/page.js          ← Feed principal
│   │   │   ├── compose/page.js       ← Création de post (page dédiée)
│   │   │   ├── reply/page.js         ← Répondre à un post
│   │   │   ├── profile/
│   │   │   │   ├── page.js           ← Mon profil
│   │   │   │   ├── [userId]/page.js  ← Profil d'un autre utilisateur
│   │   │   │   └── edit/page.js      ← Édition du profil
│   │   │   ├── search/page.js        ← Recherche utilisateurs/posts
│   │   │   ├── notifications/page.js ← Liste des notifications
│   │   │   ├── messages/
│   │   │   │   ├── page.js           ← Liste des conversations
│   │   │   │   └── [convId]/page.js  ← Conversation spécifique
│   │   │   └── settings/page.js      ← Paramètres
│   │   └── legal/                    ← Pages légales (terms, privacy, cookies, accessibility, ads)
│   ├── components/
│   │   ├── layout/                   ← AppShell, TopBar, BottomNav, DesktopSidebar, RightSidebar
│   │   ├── feed/                     ← PostCard, PostList, PostForm, PostActions, ComposeFab
│   │   ├── comment/                  ← CommentThread
│   │   ├── profile/                  ← ProfileHeader, FollowersModal
│   │   ├── notifications/            ← NotificationItem, NotificationList
│   │   ├── messages/                 ← ConversationList, MessageThread, MessageInput
│   │   ├── search/                   ← SearchBar
│   │   └── ui/                       ← Avatar, Button, Input, Spinner
│   ├── context/
│   │   └── AuthContext.js            ← Provider React pour l'authentification
│   ├── hooks/
│   │   ├── useAuth.js                ← Ré-export de useAuth depuis AuthContext
│   │   ├── useComments.js
│   │   ├── useFollow.js
│   │   ├── useLike.js
│   │   └── usePosts.js
│   ├── services/
│   │   ├── api.js                    ← Instance Axios configurée
│   │   ├── authService.js            ← API auth (login, register, logout, getMe)
│   │   ├── postService.js            ← API posts (feed, create, like, search)
│   │   ├── userService.js            ← API users (profil, follow, search)
│   │   ├── commentService.js         ← API commentaires
│   │   ├── notificationService.js    ← API notifications
│   │   └── messageService.js         ← API messages
│   ├── mocks/                        ← Données et services mock pour le développement
│   │   ├── utils.js                  ← isMockEnabled(), delay()
│   │   ├── data.js                   ← Données mockées
│   │   ├── authService.mock.js
│   │   ├── postService.mock.js
│   │   ├── userService.mock.js
│   │   ├── commentService.mock.js
│   │   └── notificationService.mock.js
│   └── utils/
│       ├── formatDate.js             ← Formatage des dates
│       └── validators.js             ← Validation des formulaires
```

## Gestion de l'authentification

### AuthContext (`src/context/AuthContext.js`)

Le `AuthProvider` est le composant racine qui gère l'état d'authentification :

- **Token** : stocké dans `localStorage` sous la clé `breezy_token` (configurable via `NEXT_PUBLIC_TOKEN_KEY`)
- **Utilisateur** : chargé au montage via `getMe()` si un token existe
- **Notifications** : compteur de notifications non lues rafraîchi quand l'utilisateur change
- **Messages** : compteur de messages non lus (via `getUnreadMessagesCount()`)

**Valeurs exposées :**

```javascript
{ user, setUser, token, saveToken, logout, loading,
  unreadCount, setUnreadCount, unreadMsgCount, setUnreadMsgCount,
  refreshUnreadCount }
```

### Protection des routes

Le layout `(app)/layout.js` vérifie la présence d'un token au chargement :

- Si pas de token → redirection vers `/connect`
- Pendant le chargement → affichage d'un `Spinner`

### Instance Axios (`src/services/api.js`)

```javascript
const api = axios.create({
  baseURL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:4000/api',
  timeout: 10000,
})
```

**Intercepteur request** : injecte `Authorization: Bearer {token}` depuis `localStorage`.

**Intercepteur response** : sur une erreur 401, supprime le token et redirige vers `/signin`.

!!! warning "URL de base"
    L'URL par défaut est `http://localhost:4000/api`, mais en production via Docker, l'API est accessible via Nginx sur le port 80 (`http://localhost/api`). La variable `NEXT_PUBLIC_API_URL` doit être configurée selon l'environnement.

## Système de mocks

Chaque service possède une version mock activable via `NEXT_PUBLIC_USE_MOCKS=true`. Ce mécanisme permet de développer le frontend sans aucun backend.

**Fonctionnement** (`src/mocks/utils.js`) :

```javascript
export const isMockEnabled = () =>
  typeof window !== 'undefined' &&
  process.env.NEXT_PUBLIC_USE_MOCKS === 'true'
```

Chaque export de service vérifie `isMockEnabled()` et route vers le mock ou le vrai service :

```javascript
export const login = (...a) => isMockEnabled() ? mock.login(...a) : real.login(...a)
```

## Appels API côté frontend

### Auth Service

| Fonction | Appel API | Description |
|----------|-----------|-------------|
| `login(data)` | `POST /auth/login` | Connexion |
| `register(data)` | `POST /auth/register` | Inscription |
| `logout()` | `POST /auth/logout` | Déconnexion |
| `getMe()` | `GET /auth/me` | Infos utilisateur |
| `changePassword(data)` | `POST /auth/change-password` | Changement de mot de passe |

!!! warning "Route non implémentée"
    `changePassword` appelle `POST /auth/change-password` mais cette route **n'existe pas** dans l'auth-service backend. L'appel échouera en 404.

### Post Service

| Fonction | Appel API |
|----------|-----------|
| `getFeed(page)` | `GET /posts/feed?page=&limit=10` |
| `getUserPosts(uid, page)` | `GET /posts/user/:uid?page=&limit=10` |
| `getUserReplies(uid, page)` | `GET /posts/user/:uid/replies?page=&limit=10` |
| `getUserMedia(uid, page)` | `GET /posts/user/:uid/media?page=&limit=10` |
| `getUserLikes(uid, page)` | `GET /posts/user/:uid/likes?page=&limit=10` |
| `getUserReposts(uid, page)` | `GET /posts/user/:uid/reposts?page=&limit=10` |
| `createPost(data)` | `POST /posts` |
| `updatePost(id, data)` | `PUT /posts/:id` |
| `deletePost(id)` | `DELETE /posts/:id` |
| `toggleLike(id)` | `POST /posts/:id/like` |
| `toggleRepost(id)` | `POST /posts/:id/repost` |
| `searchPosts(q, page)` | `GET /posts/search?q=` |

!!! warning "Routes non implémentées"
    Les fonctions suivantes appellent des routes qui **n'existent pas** dans le post-service :
    
    - `getUserReplies` → `GET /posts/user/:uid/replies`
    - `getUserMedia` → `GET /posts/user/:uid/media`
    - `getUserLikes` → `GET /posts/user/:uid/likes`
    - `getUserReposts` → `GET /posts/user/:uid/reposts`
    - `updatePost` → `PUT /posts/:id`
    - `toggleRepost` → `POST /posts/:id/repost`
    - `searchPosts` → recherche par `q` au lieu de `tag`

### User Service

| Fonction | Appel API |
|----------|-----------|
| `getUserById(id)` | `GET /users/:id` |
| `updateProfile(id, data)` | `PUT /users/:id` |
| `followUser(id)` | `POST /users/:id/follow` |
| `unfollowUser(id)` | `DELETE /users/:id/follow` |
| `getFollowing(id)` | `GET /users/:id/following` |
| `getFollowers(id)` | `GET /users/:id/followers` |
| `searchUsers(q)` | `GET /users/search?q=` |

!!! warning "Route divergente"
    `updateProfile` appelle `PUT /users/:id` mais le user-service n'a pas cette route. La modification du profil (bio, avatar, etc.) se fait via le profil-service (`PUT /profiles/:userId`).

### Notification Service

| Fonction | Appel API |
|----------|-----------|
| `getNotifications()` | `GET /notifications` |
| `markAllAsRead()` | `PUT /notifications/read-all` |

### Message Service

| Fonction | Appel API |
|----------|-----------|
| `getUnreadMessagesCount()` | `GET /messages/unread-count` |

!!! warning "Service non implémenté"
    Le endpoint `GET /messages/unread-count` n'existe dans **aucun** service backend. La messagerie est prévue dans l'interface mais non implémentée côté backend.

## Validation des formulaires

(`src/utils/validators.js`)

| Fonction | Règle |
|----------|-------|
| `isValidEmail(e)` | Regex basique `^[^\s@]+@[^\s@]+\.[^\s@]+$` |
| `isValidPassword(p)` | Longueur >= 6 caractères |
| `isValidUsername(u)` | Longueur >= 2 caractères (après trim) |

!!! note "Divergence frontend/backend"
    Le frontend valide le mot de passe à **6 caractères minimum**, alors que le backend exige **8 caractères + 1 majuscule + 1 chiffre**. Un formulaire peut passer la validation côté client mais être rejeté par le serveur.

## Pages du frontend

| Route | Page | Description |
|-------|------|-------------|
| `/` | Landing | Page d'accueil publique |
| `/connect` | Connect | Choix inscription/connexion |
| `/signin` | Sign In | Connexion (email + password) |
| `/register` | Register | Inscription (username + email + password + confirmation) |
| `/home` | Feed | Feed des abonnements |
| `/compose` | Compose | Création de post |
| `/reply` | Reply | Réponse à un post |
| `/profile` | Mon profil | Profil de l'utilisateur connecté |
| `/profile/:userId` | Profil | Profil d'un autre utilisateur |
| `/profile/edit` | Édition | Édition du profil |
| `/search` | Recherche | Recherche utilisateurs/posts |
| `/notifications` | Notifications | Liste des notifications |
| `/messages` | Messages | Liste des conversations |
| `/messages/:convId` | Conversation | Conversation spécifique |
| `/settings` | Paramètres | Paramètres du compte |
| `/legal/*` | Légal | CGU, confidentialité, cookies, accessibilité, publicité |
