# Breezy — Documentation technique

Bienvenue sur la documentation technique de **Breezy**, un réseau social moderne développé par une équipe de 4 membres. Cette documentation couvre l'architecture, les services, les données, la sécurité et les fonctionnalités de la plateforme.

---

## Vue d'ensemble

Breezy est une application web full-stack découpée en **microservices**, déployée avec **Docker** et orchestrée via **docker-compose**. L'infrastructure repose sur **12 conteneurs** interconnectés sur un réseau bridge dédié.

### Stack technique

| Composant | Technologie |
|---|---|
| **Frontend** | Next.js 14.2.0, React 18.2.0, Tailwind CSS 3.4.1 |
| **API Gateway** | Express 4.19.2, http-proxy-middleware 3.x |
| **Auth Service** | Express 5.2.1, PostgreSQL 15 (via Sequelize 6) |
| **User Service** | Express 5.2.1, PostgreSQL 15 (via Sequelize 6) |
| **Post Service** | Express 5.2.1, MongoDB 6 (via Mongoose 9.7.0) |
| **Profil Service** | Express 5.2.1, MongoDB 6 (via Mongoose 9.7.0) |
| **Reverse Proxy** | Nginx (Alpine) |
| **Conteneurisation** | Docker, docker-compose |

### Dépôts GitHub

Tous les dépôts sont hébergés sous l'organisation GitHub `El-Pouleto-ultimate` :

| Service | Dépôt | Port interne |
|---|---|---|
| API Gateway | `breezy-infra` (dossier `gateway/`) | `:3000` |
| Auth Service | `breezy-auth-service` | `:3001` |
| User Service | `breezy-user-service` | `:3002` |
| Post Service | `breezy-post-service` | `:3003` |
| Profil Service | `breezy-profil-service` | `:3004` |
| Frontend | `breezy-frontend` | `:3000` |

### Équipe

| Membre | Responsabilité |
|---|---|
| **Arthur** | Auth Service, User Service, bases PostgreSQL |
| **Maxime** | Post Service, Profil Service, bases MongoDB |
| **Jessica** | Frontend Next.js (React, Tailwind) |
| **Esteban** | Infrastructure Docker, API Gateway, Nginx |

### Statut du projet

Les fonctionnalités **principales** sont opérationnelles :
- Inscription et connexion (JWT + refresh tokens)
- Publication de posts (texte, tags, images)
- Likes, commentaires et réponses
- Abonnements (follow / unfollow)
- Fil d'actualité personnalisé
- Profils utilisateur (bio, avatar, bannière)
- Notifications (likes, mentions, follow, commentaires)
- Recherche de posts par tags et contenu
- Signalement de posts
- Modération (bannissement, modérateurs / admins)

En attente / à implémenter :
- Messagerie privée
- Signalement et gestion de la modération avancée

---

## Démarrage rapide

```bash
# Cloner le projet
git clone https://github.com/El-Pouleto-ultimate/breezy-infra.git

# Lancer l'infrastructure complète
cd breezy-infra
docker-compose up --build
```

L'application est accessible sur `http://localhost:80`.

---

## Structure de la documentation

### Architecture
- **[Vue d'ensemble](architecture/vue-ensemble.md)** : Diagramme des conteneurs, flux réseau, stack complète
- **[Communication inter-services](architecture/communication-services.md)** : Authentification JWT, appels internes, synchronisation
- **[Flux de données](architecture/flux-donnees.md)** : Diagrammes de séquence pour les parcours utilisateur clés
- **[Docker et déploiement](architecture/docker-deploiement.md)** : docker-compose, volumes, healthchecks

### Services
- **[API Gateway](services/gateway.md)** : Proxy, JWT, rate limiting, table de routage
- **[Auth Service](services/auth-service.md)** : Inscription, connexion, JWT, refresh tokens
- **[User Service](services/user-service.md)** : Profils, abonnements, recherche, bannissement
- **[Post Service](services/post-service.md)** : CRUD posts, likes, commentaires, upload, mentions
- **[Profil Service](services/profil-service.md)** : Profils détaillés, notifications
- **[Frontend](services/frontend.md)** : Application Next.js, composants, contexte d'authentification

### Données
- **[Schéma PostgreSQL](donnees/schema-postgresql.md)** : Tables auth + user (users, refresh_tokens, user_profiles, follows)
- **[Schéma MongoDB](donnees/schema-mongodb.md)** : Collections post + profil (posts, likes, comments, reposts, profiles, notifications)

### Sécurité
- **[Authentification](securite/authentification.md)** : JWT, refresh tokens, rotation, headers internes

### Fonctionnalités
- **[Couverture fonctionnelle](fonctionnalites/couverture-fx.md)** : Tableau des fonctionnalités avec statut

### API
- **[Routes complètes](api/routes-completes.md)** : Liste exhaustive de toutes les routes exposées

---

## Liens utiles

- [GitHub Organization](https://github.com/El-Pouleto-ultimate)
- [Docker Hub](https://hub.docker.com/)
