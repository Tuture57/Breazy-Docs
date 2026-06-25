# Diagramme de composants UML

Cette page présente l'architecture de **Breezy** sous forme de diagramme de
composants UML, généré à partir du **code réel** des services. Chaque relation
représentée est prouvée par une référence `fichier:ligne`
(voir le rapport `diagrams/ANALYSE_DEPENDANCES.md` à la racine du dépôt).

Les noms des composants correspondent exactement aux noms des **containers**
définis dans `breezy-infra/docker-compose.yml`.

## Vue complète

Le diagramme ci-dessous montre l'ensemble des composants (frontend,
infrastructure, microservices, bases de données), leurs interfaces principales
et toutes les dépendances réelles entre eux.

```mermaid
graph TD
    client([" Client<br/>navigateur"])
    openrouter["OpenRouter<br/>IA externe"]

    subgraph FE["Frontend"]
        frontend["breezy-frontend<br/>Next.js :3000"]
    end

    subgraph INFRA["Infrastructure"]
        nginx["breezy-nginx<br/>reverse proxy :80"]
        gateway["breezy-gateway<br/>API Gateway :3000<br/>JWT + routage"]
    end

    subgraph BACK["Backend Services"]
        auth["breezy-auth<br/>auth-service :3001"]
        user["breezy-user<br/>user-service :3002"]
        post["breezy-post<br/>post-service :3003"]
        profil["breezy-profil<br/>profil-service :3004"]
    end

    subgraph DB["Bases de données"]
        pgauth[("breezy-db-pg-auth<br/>PostgreSQL · auth_db")]
        pgusers[("breezy-db-pg-users<br/>PostgreSQL · users_db")]
        mongoposts[("breezy-db-mongo-posts<br/>MongoDB · posts_db")]
        mongoprofils[("breezy-db-mongo-profils<br/>MongoDB · profils_db")]
    end

    seed["breezy-seed<br/>seeding (one-shot)"]

    client -->|"HTTP :80"| nginx
    nginx -->|"/ → frontend:3000"| frontend
    nginx -->|"/api/ → gateway:3000"| gateway
    frontend -. "API /api/* · Bearer JWT" .-> gateway

    gateway -->|"/api/auth/*"| auth
    gateway -->|"/api/users · x-user-id"| user
    gateway -->|"/api/posts · /api/upload"| post
    gateway -->|"/api/profils · /api/notifications"| profil

    auth -->|"POST /users/sync"| user
    user -->|"POST /auth/internal/ban"| auth
    user -->|"POST /api/notifications/internal<br/>(follow)"| profil
    post -->|"GET /users/:id/following (feed)<br/>GET /users/:id · /users/by-username/:u"| user
    post -->|"POST /api/notifications/internal<br/>(like / mention)"| profil
    profil -->|"GET /auth/internal/users/:id/role"| auth
    post -->|"POST /chat/completions<br/>(@breezy_ai)"| openrouter

    auth -->|"Sequelize"| pgauth
    user -->|"Sequelize"| pgusers
    post -->|"Mongoose"| mongoposts
    profil -->|"Mongoose"| mongoprofils

    seed -. "HTTP peuplement" .-> gateway
    seed -. "psql rôles" .-> pgauth

    classDef infraCls fill:#F3E5F5,stroke:#9C27B0,stroke-width:2px,color:#000;
    classDef backCls fill:#E8F4FD,stroke:#2196F3,stroke-width:2px,color:#000;
    classDef dbCls fill:#FFF3E0,stroke:#FF9800,stroke-width:2px,color:#000;
    classDef feCls fill:#E8F5E9,stroke:#4CAF50,stroke-width:2px,color:#000;
    classDef extCls fill:#ECEFF1,stroke:#607D8B,stroke-width:2px,color:#000,stroke-dasharray: 4 3;

    class nginx,gateway infraCls;
    class auth,user,post,profil backCls;
    class pgauth,pgusers,mongoposts,mongoprofils dbCls;
    class frontend,client feCls;
    class openrouter,seed extCls;
```

> Une version PlantUML équivalente (`diagrams/composants.puml`) et une version
> simplifiée pour la soutenance (`diagrams/composants-simplifie.mmd`) sont
> disponibles à la racine du dépôt.

## Légende

| Couleur / Style | Zone |
|-----------------|------|
| 🟪 Violet | Infrastructure (`breezy-nginx`, `breezy-gateway`) |
| 🟦 Bleu | Microservices backend (`auth`, `user`, `post`, `profil`) |
| 🟧 Orange (cylindre) | Bases de données (PostgreSQL / MongoDB) |
| 🟩 Vert | Frontend & Client |
| ⬜ Gris pointillé | Composants externes / one-shot (OpenRouter, seed) |
| Flèche pleine `→` | Appel HTTP synchrone / persistance |
| Flèche pointillée `-.->` | Flux indirect (via proxy) ou tâche ponctuelle |

## Relations inter-services

Toutes ces relations sont des appels HTTP **non bloquants**
(`try/catch` + timeout) : une cible indisponible n'échoue jamais la requête
utilisateur principale.

| Source | Destination | Type | Description | Réf. code |
|--------|-------------|------|-------------|-----------|
| auth-service | user-service | Synchrone HTTP | `POST /users/sync` — réplique le profil après register / changement de username / création admin | auth.controller.js:38, 247, 299 |
| user-service | auth-service | Synchrone HTTP | `POST /auth/internal/ban` — propagation du bannissement vers la source de vérité | user.controller.js:229 |
| user-service | profil-service | Synchrone HTTP | `POST /api/notifications/internal` — notification de *follow* | user.controller.js:106 |
| post-service | user-service | Synchrone HTTP | `GET /users/:id/following` (feed), `GET /users/:id` (rôle au like), `GET /users/by-username/:u` (mention) | post.controller.js:163, 77 · like.controller.js:27 |
| post-service | profil-service | Synchrone HTTP | `POST /api/notifications/internal` — notifications de *like* et de *mention* | like.controller.js:34 · post.controller.js:84 |
| profil-service | auth-service | Synchrone HTTP | `GET /auth/internal/users/:id/role` — vérifie le rôle du destinataire avant de créer la notif | notification.controller.js:75 |
| post-service | OpenRouter | Synchrone HTTP (externe) | `POST /api/v1/chat/completions` — réponse IA `@breezy_ai` | post.controller.js:12 |

## Interfaces internes vs externes

### Interfaces publiques (accessibles via le gateway, JWT requis)

Le frontend ne parle **qu'au gateway** (`/api/*`, `src/services/api.js:6`). Le
gateway valide le JWT une seule fois (`gateway/src/middleware/auth.js`) puis
injecte `x-user-id` / `x-user-role` / `x-user-username` vers les services.

- **auth** : `/api/auth/register`, `/login`, `/refresh`, `/logout`, `/me`,
  `/change-password`, `/username`, `/admin/create-user`
- **user** : `/api/users/:id`, `/search`, `/:id/follow`, `/:id/followers`,
  `/:id/following`, `/:id/ban`, `/by-username/:username`
- **post** : `/api/posts` (CRUD), `/feed`, `/search`, `/:id/like`, `/:id/repost`,
  `/:id/comments`, `/user/:userId/*`, `/api/upload`
- **profil** : `/api/profils/:userId`, `/api/notifications`,
  `/api/notifications/read-all`, `/api/notifications/:id/read`

### Interfaces internes (protégées par `INTERNAL_SECRET`, hors gateway)

Appelées **uniquement de service à service** via l'en-tête `x-internal-secret` ;
elles ne sont pas exposées par le gateway.

| Interface | Service | Appelée par |
|-----------|---------|-------------|
| `POST /users/sync` | user-service | auth-service |
| `POST /auth/internal/ban` | auth-service | user-service |
| `GET /auth/internal/users/:id/role` | auth-service | profil-service |
| `POST /api/notifications/internal` | profil-service | user-service, post-service |

---

*Diagramme généré par analyse du code source (6 services analysés en parallèle).
Voir `diagrams/ANALYSE_DEPENDANCES.md` pour la matrice de dépendances, l'analyse
de couplage, les SPOF et les recommandations.*
