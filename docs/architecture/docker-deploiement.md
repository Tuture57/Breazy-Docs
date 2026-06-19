# Docker & Déploiement

## Architecture Docker

L'infrastructure est définie dans `breezy-infra/docker-compose.yml`. Tous les conteneurs sont connectés via un réseau bridge `breezy-network`.

## Services Docker

```mermaid
graph LR
    subgraph Réseau breezy-network
        NGINX["nginx<br/>:80 → public"]
        FE["frontend<br/>:FRONTEND_PORT"]
        GW["gateway<br/>:GATEWAY_PORT"]
        AUTH["auth-service<br/>:AUTH_PORT"]
        USER["user-service<br/>:USER_PORT"]
        POST["post-service<br/>:POST_PORT"]
        PROFIL["profil-service<br/>:PROFIL_PORT"]
        PGA[("pg-auth<br/>PostgreSQL 15")]
        PGU[("pg-users<br/>PostgreSQL 15")]
        MPO[("mongo-posts<br/>MongoDB 6")]
        MPR[("mongo-profils<br/>MongoDB 6")]
    end

    NGINX --> FE
    NGINX --> GW
    GW --> AUTH
    GW --> USER
    GW --> POST
    GW --> PROFIL
    AUTH --> PGA
    USER --> PGU
    POST --> MPO
    PROFIL --> MPR
```

## Conteneurs

| Conteneur | Image / Build context | Port exposé | Dépendances |
|-----------|----------------------|-------------|-------------|
| `breezy-nginx` | `./nginx/Dockerfile` | **80:80** (seul port public) | frontend, gateway |
| `breezy-frontend` | `../breezy-frontend/Dockerfile` | `FRONTEND_PORT` (interne) | — |
| `breezy-gateway` | `./gateway/Dockerfile` | `GATEWAY_PORT` (interne) | auth, user, post, profil |
| `breezy-auth` | `../breezy-auth-service/Dockerfile` | `AUTH_PORT` (interne) | pg-auth |
| `breezy-user` | `../breezy-user-service/Dockerfile` | `USER_PORT` (interne) | pg-users |
| `breezy-post` | `../breezy-post-service/Dockerfile` | `POST_PORT` (interne) | mongo-posts |
| `breezy-profil` | `../breezy-profil-service/Dockerfile` | `PROFIL_PORT` (interne) | mongo-profils |
| `breezy-db-pg-auth` | `postgres:15-alpine` | Interne uniquement | — |
| `breezy-db-pg-users` | `postgres:15-alpine` | Interne uniquement | — |
| `breezy-db-mongo-posts` | `mongo:6` | Interne uniquement | — |
| `breezy-db-mongo-profils` | `mongo:6` | Interne uniquement | — |

## Volumes persistants

| Volume | Conteneur | Point de montage |
|--------|-----------|-----------------|
| `pg_auth_data` | pg-auth | `/var/lib/postgresql/data` |
| `pg_users_data` | pg-users | `/var/lib/postgresql/data` |
| `mongo_posts_data` | mongo-posts | `/data/db` |
| `mongo_profils_data` | mongo-profils | `/data/db` |

Les volumes des services applicatifs montent le code source en développement :

```yaml
volumes:
  - ../breezy-auth-service:/app
  - /app/node_modules    # Évite d'écraser les node_modules du conteneur
```

## Variables d'environnement

Les variables sont définies dans un fichier `.env` à la racine de `breezy-infra/` (non versionné).

### Variables requises

| Variable | Service(s) | Description |
|----------|-----------|-------------|
| `JWT_SECRET` | gateway, auth-service | Clé secrète pour signer les JWT |
| `INTERNAL_SECRET` | auth, user, post, profil | Secret partagé pour les appels inter-services |
| `AUTH_DB_URL` | auth-service | URL PostgreSQL (ex: `postgresql://user:pass@pg-auth:5432/breezy_auth`) |
| `USER_DB_URL` | user-service | URL PostgreSQL |
| `POST_DB_URL` | post-service | URL MongoDB (ex: `mongodb://mongo-posts:27017/breezy_posts`) |
| `PROFIL_DB_URL` | profil-service | URL MongoDB |
| `AUTH_DB_USER` / `AUTH_DB_PASSWORD` / `AUTH_DB_NAME` | pg-auth | Credentials PostgreSQL |
| `USER_DB_USER` / `USER_DB_PASSWORD` / `USER_DB_NAME` | pg-users | Credentials PostgreSQL |

### Variables de ports

| Variable | Valeur par défaut | Description |
|----------|------------------|-------------|
| `FRONTEND_PORT` | 3000 | Port du frontend Next.js |
| `GATEWAY_PORT` | 3000 | Port de la gateway |
| `AUTH_PORT` | 3001 | Port du auth-service |
| `USER_PORT` | 3002 | Port du user-service |
| `POST_PORT` | 3003 | Port du post-service |
| `PROFIL_PORT` | 3004 | Port du profil-service |

### Variables d'URL inter-services

| Variable | Service consommateur | Valeur type |
|----------|---------------------|-------------|
| `AUTH_SERVICE_URL` | gateway, user-service | `http://auth-service:3001` |
| `USER_SERVICE_URL` | gateway, auth-service, post-service | `http://user-service:3002` |
| `POST_SERVICE_URL` | gateway | `http://post-service:3003` |
| `PROFIL_SERVICE_URL` | gateway, post-service | `http://profil-service:3004` |

## Configuration Nginx

(`breezy-infra/nginx/nginx.conf`)

```nginx
# Rate limiting
limit_req_zone $binary_remote_addr zone=global:10m rate=30r/m;
limit_req_zone $binary_remote_addr zone=auth:10m   rate=5r/m;

server {
    listen 80;

    # API → Gateway
    location /api/ {
        proxy_pass http://gateway:3000;
        proxy_connect_timeout 30s;
        proxy_read_timeout    30s;
    }

    # Frontend → Next.js
    location / {
        proxy_pass http://frontend:3000;
        error_page 404 = /index.html;
    }
}
```

## Commandes de déploiement

```bash
# Lancer tous les services
cd breezy-infra
docker-compose up --build

# Lancer en arrière-plan
docker-compose up --build -d

# Voir les logs d'un service
docker-compose logs -f auth-service

# Reconstruire un seul service
docker-compose up --build auth-service

# Arrêter tout
docker-compose down

# Arrêter et supprimer les volumes (reset BDD)
docker-compose down -v
```

## Développement local (sans Docker)

Chaque service peut être lancé individuellement :

```bash
# Terminal 1 — auth-service
cd breezy-auth-service
npm install
npm run dev    # nodemon, port 3001

# Terminal 2 — user-service
cd breezy-user-service
npm install
npm run dev    # nodemon, port 3002

# Terminal 3 — post-service
cd breezy-post-service
npm install
npm run dev    # nodemon, port 3003

# Terminal 4 — profil-service
cd breezy-profil-service
npm install
npm run dev    # nodemon, port 3004

# Terminal 5 — frontend
cd breezy-frontend
npm install
npm run dev    # next dev, port 3000
```

!!! tip "Mode mock"
    Le frontend peut fonctionner **sans aucun backend** grâce au système de mocks. Il suffit de définir `NEXT_PUBLIC_USE_MOCKS=true` dans `.env.local` du frontend.
