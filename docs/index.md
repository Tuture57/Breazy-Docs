# Breezy — Réseau Social

**L'essentiel, tout simplement.**

Breezy est un réseau social de type microblogging construit en architecture **microservices**. Chaque service est indépendant, avec sa propre base de données et son propre dépôt Git.

## Stack technique

| Couche | Technologie |
|--------|-------------|
| **Frontend** | Next.js 14 (App Router), React 18, Tailwind CSS 3 |
| **API Gateway** | Express 4 + http-proxy-middleware |
| **Backend** | Node.js, Express 5 (auth/user) / Express 5 (post/profil) |
| **BDD relationnelle** | PostgreSQL 15 (auth-service, user-service) via Sequelize 6 |
| **BDD document** | MongoDB 6 (post-service, profil-service) via Mongoose 9 |
| **Reverse proxy** | Nginx |
| **Conteneurisation** | Docker & Docker Compose |
| **Authentification** | JWT (access token) + Refresh Token (cookie httpOnly) |
| **Tests** | Jest + Supertest (auth-service, user-service) |

## Les 6 dépôts

| Dépôt | Rôle | Port par défaut |
|-------|------|-----------------|
| `breezy-auth-service` | Inscription, connexion, JWT, refresh tokens, bannissement | 3001 |
| `breezy-user-service` | Profils publics, follow/unfollow, recherche utilisateurs, modération | 3002 |
| `breezy-post-service` | Posts, feed, likes, commentaires, signalement | 3003 |
| `breezy-profil-service` | Bio, avatar, bannière, notifications | 3004 |
| `breezy-frontend` | Interface React/Next.js, gestion JWT côté client | 3000 |
| `breezy-infra` | Docker Compose, Nginx, API Gateway | 80 (Nginx) |

## Organisation GitHub

Tous les dépôts sont hébergés sous l'organisation **[El-Pouleto-ultimate](https://github.com/El-Pouleto-ultimate)**.

## Démarrage rapide

```bash
# Depuis le dossier breezy-infra/
docker-compose up --build
```

Le site sera accessible sur `http://localhost` (port 80 via Nginx).
