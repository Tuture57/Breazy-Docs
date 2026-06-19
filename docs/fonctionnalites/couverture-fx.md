# Couverture fonctionnelle Fx1-Fx23

Ce tableau recense les fonctionnalités attendues du sujet et leur statut d'implémentation réel dans le code.

## Légende

| Statut | Description |
|--------|-------------|
| ✅ Implémenté | Fonctionnalité complète et fonctionnelle |
| ⚠️ Partiel | Fonctionnalité partiellement implémentée |
| ❌ Non implémenté | Fonctionnalité absente du code |

## Tableau de couverture

| Fx | Fonctionnalité | Statut | Service(s) | Détail |
|----|----------------|--------|------------|--------|
| Fx1 | Inscription | ✅ Implémenté | auth-service, frontend | `POST /auth/register` — validation username/email/password, hash bcrypt, génération JWT + refresh token, sync vers user-service |
| Fx2 | Connexion | ✅ Implémenté | auth-service, frontend | `POST /auth/login` — vérification credentials, vérification ban/inactif, émission JWT |
| Fx3 | Déconnexion | ✅ Implémenté | auth-service, frontend | `POST /auth/logout` — révocation du refresh token, suppression cookie |
| Fx4 | Profil utilisateur | ✅ Implémenté | profil-service, user-service, frontend | Profil étendu (bio, avatar, bannière) dans profil-service + profil public (username, compteurs) dans user-service |
| Fx5 | Modification du profil | ✅ Implémenté | profil-service, frontend | `PUT /profiles/:userId` — display_name, bio (160 chars max), avatar_url, banner_url |
| Fx6 | Publier un post | ✅ Implémenté | post-service, frontend | `POST /posts` — contenu 280 chars max, tags (max 5), media_urls |
| Fx7 | Supprimer un post | ✅ Implémenté | post-service, frontend | `DELETE /posts/:id` — par l'auteur ou modérateur/admin, suppression en cascade (likes + commentaires) |
| Fx8 | Feed / Fil d'actualité | ✅ Implémenté | post-service, user-service, frontend | `GET /posts/feed` — basé sur les abonnements, appel inter-service au user-service, pagination |
| Fx9 | Liker un post | ✅ Implémenté | post-service, frontend | `POST /posts/:id/like` — compteur atomique ($inc), index unique empêche le double like, notification envoyée |
| Fx10 | Retirer un like | ✅ Implémenté | post-service, frontend | `DELETE /posts/:id/like` — décrémentation du compteur |
| Fx11 | Commenter un post | ✅ Implémenté | post-service, frontend | `POST /posts/:id/comments` — 280 chars max, incrémente comments_count |
| Fx12 | Répondre à un commentaire | ✅ Implémenté | post-service, frontend | `POST /posts/:id/comments/:commentId/replies` — profondeur limitée à 1 niveau |
| Fx13 | Suivre un utilisateur (Follow) | ✅ Implémenté | user-service, frontend | `POST /users/:id/follow` — transaction atomique, compteurs mis à jour, protection self-follow |
| Fx14 | Ne plus suivre (Unfollow) | ✅ Implémenté | user-service, frontend | `DELETE /users/:id/follow` — transaction atomique, décrémentation des compteurs |
| Fx15 | Voir les followers | ✅ Implémenté | user-service, frontend | `GET /users/:id/followers` — paginé avec profils complets |
| Fx16 | Voir les following | ✅ Implémenté | user-service, frontend | `GET /users/:id/following` — retourne les IDs uniquement |
| Fx17 | Recherche utilisateurs | ✅ Implémenté | user-service, frontend | `GET /users/search?q=` — iLike, exclut bannis/inactifs, trié par followers_count |
| Fx18 | Recherche par tag | ✅ Implémenté | post-service, frontend | `GET /posts/search?tag=` — recherche en minuscules |
| Fx19 | Notifications | ✅ Implémenté | profil-service, post-service, frontend | Types: like, follow, mention, comment, reply — marquer lu/tout lu |
| Fx20 | Signalement de post | ⚠️ Partiel | post-service | `POST /posts/:id/report` — met `is_reported: true` mais pas de workflow de modération pour traiter les signalements |
| Fx21 | Bannissement | ✅ Implémenté | user-service, auth-service | `PUT /users/:id/ban` — réservé aux modérateurs/admins, propagation inter-service, vérification au login |
| Fx22 | Messagerie privée | ❌ Non implémenté | — | Le frontend a les pages et composants (`messages/`, `ConversationList`, `MessageThread`, `MessageInput`) mais aucun backend n'existe. Fonctionne uniquement en mode mock. |
| Fx23 | Changement de mot de passe | ❌ Non implémenté | — | Le frontend appelle `POST /auth/change-password` mais cette route n'existe pas dans l'auth-service |

## Fonctionnalités transverses

| Fonctionnalité | Statut | Détail |
|----------------|--------|--------|
| API Gateway | ✅ | Routage, vérification JWT, injection headers, rate limiting |
| Rate limiting | ✅ | Double couche : Nginx (30/min global, 5/min auth) + Gateway (100/15min, 10/15min auth) |
| Refresh token avec rotation | ✅ | Cookie httpOnly, hashé SHA-256, détection de vol |
| Docker Compose | ✅ | 11 conteneurs (4 services + gateway + frontend + nginx + 4 BDD) |
| Tests unitaires/intégration | ⚠️ | Présents pour auth-service (15 tests) et user-service (14 tests), absents pour post-service et profil-service |
| Mode mock (frontend) | ✅ | Développement sans backend via `NEXT_PUBLIC_USE_MOCKS=true` |
| Pages légales | ✅ | CGU, confidentialité, cookies, accessibilité, publicité |
| Health checks | ✅ | `/health` sur auth-service et user-service, `/api/health` sur gateway |
| Repost / Partage | ❌ | Le frontend a `toggleRepost()` mais aucune route backend n'existe |
| Modification de post | ❌ | Le frontend a `updatePost()` mais aucune route `PUT /posts/:id` n'existe dans le backend |
| Réinitialisation de mot de passe | ❌ | Le bouton "Oublié ?" dans le frontend affiche un faux message de succès |

## Divergences frontend/backend

| Appel frontend | Route backend attendue | Existe ? |
|----------------|----------------------|----------|
| `POST /auth/change-password` | `POST /auth/change-password` | ❌ |
| `GET /posts/user/:uid/replies` | — | ❌ |
| `GET /posts/user/:uid/media` | — | ❌ |
| `GET /posts/user/:uid/likes` | — | ❌ |
| `GET /posts/user/:uid/reposts` | — | ❌ |
| `PUT /posts/:id` | — | ❌ |
| `POST /posts/:id/repost` | — | ❌ |
| `GET /posts/search?q=` | `GET /posts/search?tag=` | ⚠️ Param différent |
| `PUT /users/:id` (updateProfile) | `PUT /profiles/:userId` (profil-service) | ⚠️ Mauvais service |
| `GET /messages/unread-count` | — | ❌ |
