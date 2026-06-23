# Frontend

Application web Next.js pour Breezy.

---

## Stack

| Technologie | Version |
|---|---|
| Next.js | 14.2.0 |
| React | 18.2.0 |
| Tailwind CSS | 3.4.1 |
| Axios | 1.6.0 |
| date-fns | 3.3.1 |
| lucide-react | 1.21.0 |

---

## Pages

### Pages publiques

| Route | Composant | Description |
|---|---|---|
| `/` | Landing | Page d'accueil publique |
| `/connect` | Connect | Page de connexion |
| `/signin` | SignIn | Page de connexion (alias) |
| `/register` | Register | Page d'inscription |
| `/legal/terms` | Terms | Conditions d'utilisation |
| `/legal/privacy` | Privacy | Politique de confidentialite |
| `/legal/cookies` | Cookies | Politique des cookies |
| `/legal/accessibility` | Accessibility | Declaration d'accessibilite |
| `/legal/ads` | Ads | Politique publicitaire |

### Pages protegees (groupe `app`)

| Route | Composant | Description |
|---|---|---|
| `/home` | HomePage | Fil d'actualite principal |
| `/compose` | ComposePage | Creation d'un nouveau post |
| `/reply` | ReplyPage | Reponse a un post (`?postId=` en query) |
| `/search` | SearchPage | Recherche de posts et d'utilisateurs |
| `/notifications` | NotificationsPage | Liste des notifications |
| `/profile` | MyProfilePage | Profil de l'utilisateur connecte |
| `/profile/[userId]` | UserProfilePage | Profil d'un autre utilisateur |
| `/profile/edit` | EditProfilePage | Edition du profil |
| `/messages` | MessagesPage | Messagerie (placeholder) |
| `/messages/[convId]` | ConversationPage | Conversation (placeholder) |
| `/settings` | SettingsPage | Parametres du compte |

---

## Gestion des tokens JWT

### Stockage

- Le token JWT est stocke dans `localStorage` sous la cle `breezy_token`.
- La cle est configurable via la variable d'environnement `NEXT_PUBLIC_TOKEN_KEY`.

### Injection automatique

- Un intercepteur Axios (`request`) ajoute le header `Authorization: Bearer <token>` sur chaque requete sortante lorsque le token est present dans localStorage.

### Rafraichissement automatique

- Un intercepteur Axios (`response`) intercepte les erreurs `401`.
- Sur un `401`, le frontend tente un rafraichissement en appelant `POST /auth/refresh` avec le `refresh_token` stocke.
- Pendant le rafraichissement, les requetes suivantes sont mises en file d'attente (queue).
- Une fois le rafraichissement reussi :
  - Le nouveau token est stocke.
  - Les requetes mises en file sont rejouees.
- Si le rafraichissement echoue (refresh token expire ou invalide) :
  - Les tokens sont effaces du localStorage.
  - L'utilisateur est redirige vers `/signin`.

### Contexte d'authentification

- `AuthProvider` (React Context) enveloppe toute l'application.
- Au montage, le provider lit le token depuis localStorage et appelle `GET /auth/me` pour charger l'utilisateur.
- Expose via le hook `useAuth()` : `{ user, loading, login, register, logout, updateUser, changePassword }`.

---

## API Endpoints appeles par le frontend

### Auth

| Fonction | Methode | Route backend |
|---|---|---|
| `login` | POST | `/auth/login` |
| `register` | POST | `/auth/register` |
| `logout` | POST | `/auth/logout` |
| `getMe` | GET | `/auth/me` |
| `changePassword` | POST | `/auth/change-password` |
| `refresh` | POST | `/auth/refresh` |

### Posts

| Fonction | Methode | Route backend |
|---|---|---|
| `getFeed` | GET | `/api/posts/feed` |
| `getUserPosts` | GET | `/api/posts/user/:userId` |
| `getUserReplies` | GET | `/api/posts/user/:userId/replies` |
| `getUserMedia` | GET | `/api/posts/user/:userId/media` |
| `getUserLikes` | GET | `/api/posts/user/:userId/likes` |
| `getUserReposts` | GET | `/api/posts/user/:userId/reposts` |
| `createPost` | POST | `/api/posts` |
| `updatePost` | PUT | `/api/posts/:id` |
| `deletePost` | DELETE | `/api/posts/:id` |
| `likePost` | POST | `/api/posts/:id/like` |
| `unlikePost` | DELETE | `/api/posts/:id/like` |
| `toggleRepost` | POST | `/api/posts/:id/repost` |
| `searchPosts` | GET | `/api/posts/search` |

### Comments

| Fonction | Methode | Route backend |
|---|---|---|
| `getComments` | GET | `/api/posts/:id/comments` |
| `createComment` | POST | `/api/posts/:id/comments` |
| `updateComment` | PUT | `/api/posts/:id/comments/:commentId` |
| `deleteComment` | DELETE | `/api/posts/:id/comments/:commentId` |
| `replyToComment` | POST | `/api/posts/:id/comments/:commentId/replies` |

### Users

| Fonction | Methode | Route backend |
|---|---|---|
| `getUserById` | GET | `/users/:id` |
| `searchUsers` | GET | `/users/search` |
| `followUser` | POST | `/users/:id/follow` |
| `unfollowUser` | DELETE | `/users/:id/follow` |
| `getFollowing` | GET | `/users/:id/following` |
| `getFollowers` | GET | `/users/:id/followers` |

### Profiles

| Fonction | Methode | Route backend |
|---|---|---|
| `getProfile` | GET | `/profils/:userId` |
| `updateProfile` | PUT | `/profils/:userId` |

### Notifications

| Fonction | Methode | Route backend |
|---|---|---|
| `getNotifications` | GET | `/notifications` |
| `markAllAsRead` | PUT | `/notifications/read-all` |

### Upload

| Fonction | Methode | Route backend |
|---|---|---|
| `uploadMedia` | POST | `/api/upload` |

---

## Composants

### Layout

| Composant | Description |
|---|---|
| `AppShell` | Structure principale de l'application (sidebar + topbar + contenu) |
| `TopBar` | Barre de navigation superieure (titre de page, bouton retour) |
| `BottomNav` | Navigation inferieure mobile (accueil, recherche, notifications, messages, profil) |
| `DesktopSidebar` | Barre laterale desktop (logo, navigation, bouton poster) |
| `RightSidebar` | Barre laterale droite (commente / desactivee) |

### Feed

| Composant | Description |
|---|---|
| `PostList` | Liste paginee de posts (infinite scroll) |
| `PostCard` | Carte individuelle d'un post (avatar, nom, contenu, actions) |
| `PostActions` | Barre d'actions sur un post (like, comment, repost, share) |
| `PostForm` | Formulaire de creation de post (textarea, bouton poster) |
| `ComposeFab` | Bouton flottant "composer" (FAB) pour mobile |

### UI

| Composant | Description |
|---|---|
| `Button` | Bouton avec 7 variantes : `primary`, `secondary`, `danger`, `ghost`, `outline`, `link`, `icon` |
| `Input` | Champ de texte stylise |
| `Avatar` | Avatar utilisateur avec 5 tailles : `xs`, `sm`, `md`, `lg`, `xl` |
| `Spinner` | Indicateur de chargement |

### Comments

| Composant | Description |
|---|---|
| `CommentThread` | Fil de commentaires (affiche les commentaires et les reponses imbriquees sur 1 niveau) |

### Profile

| Composant | Description |
|---|---|
| `ProfileHeader` | En-tete de profil (banniere, avatar, display name, bio, compteurs) |
| `FollowersModal` | Modale listant les abonnes/abonnements |

### Notifications

| Composant | Description |
|---|---|
| `NotificationList` | Liste paginee des notifications |
| `NotificationItem` | Element individuel de notification (icone selon le type, message) |

### Search

| Composant | Description |
|---|---|
| `SearchBar` | Barre de recherche avec debounce (recherche posts + utilisateurs) |

### Messages

| Composant | Description |
|---|---|
| `ConversationList` | Liste des conversations (placeholder) |
| `MessageThread` | Fil de messages d'une conversation (placeholder) |
| `MessageInput` | Champ de saisie de message (placeholder) |

---

## Hooks

| Hook | Description |
|---|---|
| `useAuth` | Authentification (connexion, deconnexion, utilisateur courant, changement de mot de passe) |
| `usePosts` | Gestion des posts (CRUD, feed, pagination) |
| `useLike` | Like/unlike d'un post (avec etat local optimiste) |
| `useFollow` | Follow/unfollow d'un utilisateur (avec mise a jour du compteur local) |
| `useComments` | Gestion des commentaires (CRUD, pagination, replies) |
| `useMentions` | Detection et resolution des @mentions dans le texte |

---

## Système de mocks

Le frontend integre un systeme de mocks active via la variable d'environnement :

```
NEXT_PUBLIC_USE_MOCKS=true
```

| Service mock | Stockage |
|---|---|
| auth mock | sessionStorage |
| posts mock | sessionStorage |
| users mock | sessionStorage |
| profiles mock | sessionStorage |
| notifications mock | sessionStorage |

En mode mock, toutes les donnees sont stockees en local dans `sessionStorage` et aucune requete reelle n'est envoyee aux services backend.

---

## Problèmes connus

### Validation de mot de passe asymetrique

| Cote | Regle |
|---|---|
| Frontend | Minimum 6 caracteres |
| Backend (auth-service) | Minimum 8 caracteres, 1 majuscule, 1 chiffre |

Un mot de passe valide selon le frontend (6-7 caracteres, sans majuscule/chiffre) sera rejete par le backend avec une erreur `VALIDATION_ERROR`.

### Changement de mot de passe

La fonctionnalite `POST /auth/change-password` est implementee **cote frontend ET cote backend** (contrairement a une version anterieure de la documentation qui indiquait le contraire). L'appel API est correct et les deux cotes fonctionnent.

### Endpoint de mise a jour de profil

Le frontend appelle correctement `PUT /profils/:userId` (profil-service) pour la mise a jour du profil, et non `PUT /users/:id` (user-service). Ce comportement est correct.

### Page Messages

La page `/messages` et `/messages/[convId]` sont des placeholders. Le message suivant est affiché :

> "La messagerie sera disponible dans une prochaine version"
