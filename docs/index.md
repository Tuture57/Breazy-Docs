# Breezy — Documentation technique

Bienvenue sur la documentation technique de **Breezy**, un réseau social de micro-blogging
(type Twitter/X) développé en architecture **microservices**. Les utilisateurs publient des
posts courts (280 caractères max), se suivent, likent, commentent, repostent et reçoivent des
notifications. L'ensemble est conteneurisé avec Docker et orchestré via `docker-compose`.

!!! info "Cette documentation reflète le code réel"
    Chaque affirmation a été vérifiée dans le code source des dépôts `breezy-*`. Lorsqu'un
    comportement est partiel, incohérent ou risqué, il est signalé explicitement plutôt que
    masqué. Les écarts corrigés par rapport à l'ancienne documentation sont listés dans le
    [Journal des modifications](CHANGELOG.md).

---

## En une phrase par composant

| Composant | Rôle en une phrase |
|---|---|
| **Frontend** | Application Next.js (App Router) mobile-first qui consomme l'API via la gateway. |
| **API Gateway** | Point d'entrée unique : vérifie le JWT, injecte l'identité et proxifie vers les services. |
| **Auth Service** | Inscription, connexion, JWT + refresh tokens, changement de mot de passe, bannissement. |
| **User Service** | Profils publics, relations de follow/unfollow, compteurs, recherche, bannissement. |
| **Post Service** | Posts, likes, commentaires/réponses, reposts, upload d'images, mentions, bot IA. |
| **Profil Service** | Profils détaillés (bio, avatar, bannière) et notifications. |
| **Nginx** | Reverse proxy : `/api/*` → gateway, `/*` → frontend. |

---

## Équipe

| Membre | Responsabilité | Services |
|---|---|---|
| **Arthur** | Authentification & utilisateurs (PostgreSQL) | `breezy-auth-service`, `breezy-user-service` |
| **Maxime** | Contenu social & notifications (MongoDB) | `breezy-post-service`, `breezy-profil-service` |
| **Jessica** | Interface utilisateur | `breezy-frontend` |
| **Estéban** | Infrastructure & passerelle | `breezy-infra` (Docker, Nginx, **gateway**) |

---

## Stack technique

| Technologie | Version (exacte) | Usage |
|---|---|---|
| Next.js | `14.2.0` | Frontend (App Router) |
| React | `18.2.0` | UI |
| Axios | `1.6.0` (front) / `1.18.0` (services) | Client HTTP |
| Tailwind CSS | `3.4.1` | Styles frontend |
| Express | `4.19` (gateway) / `5.2.1` (services) | Serveur HTTP |
| http-proxy-middleware | `3.x` | Reverse proxy applicatif (gateway) |
| jsonwebtoken | `9.x` | Signature/vérification JWT |
| express-rate-limit | `7.2` | Rate limiting (gateway) |
| Sequelize | `6.37.8` | ORM PostgreSQL (auth, user) |
| pg | `8.21.0` | Driver PostgreSQL |
| bcryptjs | `3.0.3` | Hachage des mots de passe |
| Mongoose | `9.7.0` | ODM MongoDB (post, profil) |
| Multer | `1.4.5-lts.1` | Upload de fichiers (post) |
| PostgreSQL | `15-alpine` | BDD auth & user |
| MongoDB | `6` | BDD post & profil |
| Nginx | `alpine` | Reverse proxy |
| Docker / docker-compose | — | Conteneurisation & orchestration |

---

## Cartographie des conteneurs

L'infrastructure compte **12 conteneurs** sur un unique réseau bridge `breezy-network`.

| Conteneur (DNS interne) | Rôle | Port interne | Port hôte | Base de données |
|---|---|---|---|---|
| `nginx` | Reverse proxy | 80 | **80:80** | — |
| `frontend` | Next.js | 3000 | — | — |
| `gateway` | API Gateway | 3000 | — | — |
| `auth-service` | Auth | 3001 | — | `pg-auth` |
| `user-service` | User | 3002 | — | `pg-users` |
| `post-service` | Post | 3003 | — | `mongo-posts` |
| `profil-service` | Profil | 3004 | — | `mongo-profils` |
| `seed` | Peuplement (one-shot) | — | — | via gateway + `pg-auth` |
| `pg-auth` | PostgreSQL (`auth_db`) | 5432 | — | — |
| `pg-users` | PostgreSQL (`users_db`) | 5432 | — | — |
| `mongo-posts` | MongoDB (`posts_db`) | 27017 | — | — |
| `mongo-profils` | MongoDB (`profils_db`) | 27017 | — | — |

!!! note "Un seul port public"
    Seul `nginx` publie un port (`80:80`). Tous les autres conteneurs utilisent `expose`
    (réseau interne uniquement) : c'est la frontière de sécurité de l'architecture.

---

## Statut du projet (Fx1 → Fx23)

Vue d'ensemble. Le détail justifié figure dans [Couverture fonctionnelle](fonctionnalites/couverture.md).

| Statut | Fonctionnalités |
|---|---|
| ✅ **Complet** (backend + frontend) | Fx1 Inscription, Fx2 Connexion, Fx3 JWT/Refresh, Fx4 Profil, Fx5 Édition profil, Fx6 Follow, Fx7 Feed, Fx8 Post, Fx9 Like, Fx10 Commentaires, Fx11 Recherche users, Fx12 Recherche posts, Fx13 Notifications, Fx14 @mentions, Fx15 Upload média, Fx16 Repost, Fx17 Édition post, Fx18 Suppression post, Fx20 Changement mot de passe |
| ⚠️ **Partiel** (backend sans UI) | Fx19 Signalement (pas d'UI), Fx21 Bannissement (pas d'UI de modération) |
| ❌ **Absent** | Fx22 Messagerie (UI placeholder, aucun backend), Fx23 Mot de passe oublié |
| ➕ **Hors périmètre initial** | **Bot IA `@breezy_ai`** (réponses automatiques via OpenRouter) — implémenté côté backend |

---

## Démarrer le projet localement

!!! warning "Prérequis"
    Docker et docker-compose installés. Le port **80** doit être libre sur la machine hôte.
    Un fichier `.env` doit exister dans `breezy-infra/` (voir [Déploiement](architecture/deploiement.md)).

```bash
# Depuis le dépôt d'infrastructure
cd breezy-infra
docker-compose up --build
```

- Application : <http://localhost> (port 80, servie par Nginx)
- API : <http://localhost/api> (proxifiée vers la gateway)
- Le conteneur `seed` peuple automatiquement les bases (12 comptes de test, posts, follows, likes, commentaires).

```bash
# Arrêter
docker-compose down
# Arrêter + réinitialiser les bases (supprime les volumes)
docker-compose down -v
# Suivre les logs d'un service
docker-compose logs -f gateway
```

---

## Plan de la documentation

- **Architecture** — [Vue d'ensemble](architecture/vue-ensemble.md) · [Communication](architecture/communication.md) · [Déploiement](architecture/deploiement.md)
- **Services** — [Gateway](services/gateway.md) · [Auth](services/auth-service.md) · [User](services/user-service.md) · [Post](services/post-service.md) · [Profil](services/profil-service.md) · [Frontend](services/frontend.md)
- **Données** — [PostgreSQL](donnees/postgresql.md) · [MongoDB](donnees/mongodb.md)
- **API** — [Routes complètes](api/routes.md)
- **Sécurité** — [Authentification](securite/authentification.md) · [Secrets & configuration](securite/secrets-configuration.md)
- **Fonctionnalités** — [Couverture Fx1→Fx23](fonctionnalites/couverture.md)
- **Soutenance** — [Questions générales](soutenance/questions.md) · [Par membre](soutenance/par-membre.md) · [Limites & évolutions](soutenance/limites.md)
- [Journal des modifications](CHANGELOG.md)
