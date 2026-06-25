# Couverture fonctionnelle

Statut **réel** de chaque fonctionnalité, vérifié dans le code (backend + frontend + intégration).

| Légende | Signification |
|---|---|
| ✅ Complet | backend + frontend + intégration fonctionnels |
| ⚠️ Partiel | une partie manque (précisée) |
| ❌ Absent | non implémenté |
| 🔄 Backend only | backend prêt, frontend manquant |

---

## Tableau Fx1 → Fx23

| Fx | Description | Backend | Frontend | Intégration | Statut |
|----|-------------|---------|----------|-------------|--------|
| Fx1 | Inscription | `POST /auth/register` | `/register` + validation | ✅ | ✅ |
| Fx2 | Connexion | `POST /auth/login` (ban/inactif gérés) | `/signin` | ✅ | ✅ |
| Fx3 | JWT + Refresh | rotation + détection de vol | intercepteur Axios + file d'attente | ✅ | ✅ |
| Fx4 | Profil utilisateur | user-service + profil-service | `/profile`, `/profile/:id`, fusion | ✅ | ✅ |
| Fx5 | Édition profil | `PUT /profils/:userId` | `/profile/edit` | ✅ | ✅ |
| Fx6 | Follow/Unfollow | transactions + notification | `useFollow` (optimiste) | ✅ | ✅ |
| Fx7 | Feed | following `$in` + soi-même | infinite scroll | ✅ | ✅ |
| Fx8 | Création post | ≤280, ≤5 tags, médias | `/compose` + autocomplete @ | ✅ | ✅ |
| Fx9 | Like/Unlike | `$inc` + index unique + notif | `useLike` (optimiste, rollback) | ✅ | ✅ |
| Fx10 | Commentaires | + réponses 1 niveau (`MAX_DEPTH`) | `CommentThread` | ✅ | ✅ |
| Fx11 | Recherche utilisateurs | `ILIKE`, exclut bannis, tri followers | `/search` | ✅ | ✅ |
| Fx12 | Recherche posts | regex content/tags/username | `/search` | ✅ | ✅ |
| Fx13 | Notifications | like, follow, mention | `/notifications` + badge | ⚠️ | ✅* |
| Fx14 | @mentions | extraction + résolution + notif | `useMentions` dropdown | ✅ | ✅ |
| Fx15 | Upload média | multer 5 Mo, images | `PostForm` + preview | ✅ | ✅ |
| Fx16 | Repost | toggle `$inc` + index unique | `PostActions` (optimiste) | ✅ | ✅ |
| Fx17 | Édition post | `PUT /posts/:id` (owner) | édition inline `PostCard` | ✅ | ✅ |
| Fx18 | Suppression post | cascade likes + comments | menu + confirmation | ✅ | ✅ |
| Fx19 | Signalement | `POST /posts/:id/report` | **❌ pas d'UI** | — | ⚠️ |
| Fx20 | Changement mot de passe | `POST /auth/change-password` | `/settings` | ✅ | ✅ |
| Fx21 | Bannissement | user + propagation auth | **❌ pas d'UI modération** | — | ⚠️ |
| Fx22 | Messagerie | **❌ aucun backend** | placeholder + composants morts | — | ❌ |
| Fx23 | Mot de passe oublié | **❌ aucun backend** | bouton inactif | — | ❌ |

\* **Fx13 partiel** : les notifications `like`, `follow` et `mention` fonctionnent ; les types
`comment` et `reply` existent dans le schéma mais **ne sont jamais générés** par le post-service.

---

## Fonctionnalité hors périmètre initial

| Fonctionnalité | Backend | Frontend | Statut |
|---|---|---|---|
| **Bot IA `@breezy_ai`** | post-service → OpenRouter (`gpt-oss-20b:free`) | détection `@breezy_ai` dans `/home` (re-fetch +5 s) | ➕ Implémenté |

Mentionner `@breezy_ai` dans un post déclenche une réponse automatique publiée comme commentaire
du compte bot. Voir [Post Service](../services/post-service.md#bot-ia-breezy_ai). ⚠️ La clé API
est commitée en clair (voir [Secrets](../securite/secrets-configuration.md)).

---

## Détail des fonctionnalités partielles ou absentes

### Fx19 — Signalement (⚠️ partiel)

Backend : `POST /api/posts/:id/report` met `is_reported = true` (sans vérifier l'existence du
post). **Aucune UI** de signalement (le menu `PostActions` n'a que Modifier/Supprimer), et
aucune route pour lister/lever les signalements → fonctionnalité inutilisable en pratique.

### Fx21 — Bannissement (⚠️ partiel)

Backend complet : `PUT /api/users/:id/ban` (rôle modérateur/admin) + propagation non bloquante
vers l'auth-service. **Aucun panneau de modération** côté frontend : pas de liste d'utilisateurs,
pas de bouton « Bannir », pas de vue des signalements. Utilisable uniquement via appels API
directs.

### Fx22 — Messagerie (❌ absente)

Aucun backend (collection, route, contrôleur). Le frontend contient des composants
(`ConversationList`, `MessageThread`, `MessageInput`) **non connectés** et une page placeholder.
`messageService.getUnreadMessagesCount()` renvoie toujours `0` en dur.

### Fx23 — Mot de passe oublié (❌ absente)

Aucune route `/forgot-password` ni `/reset-password`, pas d'envoi d'email. Le bouton « Oublié ? »
affiche un message d'indisponibilité.

---

## Divergences & incohérences relevées dans le code

| # | Constat |
|---|---|
| 1 | **Validation mot de passe** : `isValidPassword` (frontend) accepte ≥6 ; le formulaire et le backend exigent ≥8 + majuscule + chiffre |
| 2 | **Validation username** : frontend ≥2, backend 3–50 alphanumérique → un username de 2 caractères est rejeté côté backend |
| 3 | **`x-user-username` absent** pour le user-service → `from_username: undefined` dans la notif de follow |
| 4 | **`comments_count`** peut diverger (décrément de 1 même quand des réponses sont supprimées en cascade) |
| 5 | **`likes_count`** peut devenir négatif en base (seul l'affichage est borné) |
| 6 | **Pas de route** de filtrage des posts signalés (`is_reported`) |
| 7 | **Notifications `comment`/`reply`** : types prévus mais jamais générés |
| 8 | **Reposts** non supprimés à la suppression d'un post (orphelins) |

!!! note "Rate limiting désormais actif"
    Contrairement à une ancienne version de la doc, le rate limiting de la gateway est **actif**
    (`NODE_ENV=production` dans docker-compose). Le rate limiting Nginx, lui, reste déclaré mais
    non appliqué.
