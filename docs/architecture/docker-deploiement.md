# Docker et déploiement

## Architecture des conteneurs

L'infrastructure Breezy est orchestrée via **docker-compose** avec **12 services** interconnectés sur un réseau bridge `breezy-network`.

### Fichier de composition

Le fichier principal se trouve à la racine du dépôt `breezy-infra` :

```
breezy-infra/
├── docker-compose.yml
├── .env
├── .env.example
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf
├── gateway/
│   ├── Dockerfile
│   ├── package.json
│   └── src/
│       ├── index.js
│       └── middleware/
└── seed/
    ├── Dockerfile
    ├── package.json
    └── seed.js
```

### Les 12 services

```yaml
services:
  nginx:          # Reverse proxy → port 80
  frontend:       # Next.js → port 3000
  gateway:        # API Gateway → port 3000 (interne)
  auth-service:   # Auth Service → port 3001
  user-service:   # User Service → port 3002
  post-service:   # Post Service → port 3003
  profil-service: # Profil Service → port 3004
  seed:           # Script de seeding (one-shot)
  pg-auth:        # PostgreSQL Auth → port 5432
  pg-users:       # PostgreSQL Users → port 5432
  mongo-posts:    # MongoDB Posts → port 27017
  mongo-profils:  # MongoDB Profils → port 27017
```

---

## Volumes persistants

5 volumes Docker sont définis pour la persistance des données :

| Volume | Monté sur | Stocke |
|---|---|---|
| `pg_auth_data` | `pg-auth:/var/lib/postgresql/data` | Données utilisateur (auth) |
| `pg_users_data` | `pg-users:/var/lib/postgresql/data` | Profils et relations |
| `mongo_posts_data` | `mongo-posts:/data/db` | Posts, likes, commentaires |
| `mongo_profils_data` | `mongo-profils:/data/db` | Profils détaillés, notifications |
| `uploads_data` | `post-service:/app/uploads` | Images uploadées |

Les volumes sont déclarés en bas du fichier docker-compose :

```yaml
volumes:
  pg_auth_data:
  pg_users_data:
  mongo_posts_data:
  mongo_profils_data:
  uploads_data:
```

---

## Variables d'environnement

### Fichier `.env` principal (breezy-infra/.env)

```
# Sécurité Globale
JWT_SECRET=CACACACACACACACA
INTERNAL_SECRET=PIPIPIIPIPI

# Configuration Gateway & Front
GATEWAY_PORT=3000
FRONTEND_PORT=3000

# URLs d'aiguillage pour la Gateway
AUTH_SERVICE_URL=http://auth-service:3001
USER_SERVICE_URL=http://user-service:3002
POST_SERVICE_URL=http://post-service:3003
PROFIL_SERVICE_URL=http://profil-service:3004

# Configuration Auth Service & sa DB
AUTH_PORT=3001
AUTH_DB_USER=user
AUTH_DB_PASSWORD=auth-password
AUTH_DB_NAME=auth_db
AUTH_DB_URL=postgres://user:auth-password@pg-auth:5432/auth_db

# Configuration User Service & sa DB
USER_PORT=3002
USER_DB_USER=user
USER_DB_PASSWORD=user-password
USER_DB_NAME=users_db
USER_DB_URL=postgres://user:user-password@pg-users:5432/users_db

# MongoDB (commun aux deux)
MONGO_USER=admin
MONGO_PASSWORD=breezy-mongo-2024

# Configuration Post Service & sa DB
POST_PORT=3003
POST_DB_URL=mongodb://admin:breezy-mongo-2024@mongo-posts:27017/posts_db?authSource=admin

# Configuration Profil Service & sa DB
PROFIL_PORT=3004
PROFIL_DB_URL=mongodb://admin:breezy-mongo-2024@mongo-profils:27017/profils_db?authSource=admin
```

> **Note importante** : Le fichier `.env.example` ne contient pas les credentials MongoDB (`MONGO_USER` et `MONGO_PASSWORD`). Ces variables sont présentes uniquement dans le `.env` réel. En production, il faut les ajouter manuellement au fichier `.env`.

### Gateway en mode test

La Gateway est configurée avec `NODE_ENV=test` dans docker-compose :

```yaml
gateway:
  environment:
    - NODE_ENV=test
```

Ceci désactive le rate limiting (global 500 req/15min et auth 20 req/15min) pour que les tests et le seed puissent fonctionner sans restriction.

---

## Healthchecks

Chaque base de données dispose d'un healthcheck pour garantir que les services backend ne démarrent qu'après que la base soit prête.

### PostgreSQL

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${AUTH_DB_USER} -d ${AUTH_DB_NAME}"]
  interval: 5s
  timeout: 5s
  retries: 10
```

### MongoDB

```yaml
healthcheck:
  test: ["CMD", "mongosh", "-u", "${MONGO_USER}", "-p", "${MONGO_PASSWORD}", 
         "--authenticationDatabase", "admin", "--eval", "db.adminCommand('ping')"]
  interval: 5s
  timeout: 5s
  retries: 10
```

Les services backend utilisent `condition: service_healthy` pour leurs dépendances :

```yaml
auth-service:
  depends_on:
    pg-auth:
      condition: service_healthy
```

---

## Dockerfiles

### Services backend (auth, user, post, profil)

Les 4 services backend utilisent le même Dockerfile standard :

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["npm", "start"]
```

### Gateway

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ENV PORT=3000
EXPOSE 3000
CMD ["npm", "start"]
```

### Frontend

Le frontend Next.js inclut une étape de build :

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build          # Étape supplémentaire
ENV HOSTNAME="0.0.0.0"
ENV PORT=3000
EXPOSE 3000
CMD ["npm", "start"]
```

### Nginx

```dockerfile
FROM nginx:alpine
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
```

### Seed

```dockerfile
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache postgresql-client  # Pour promotion des rôles
COPY package.json .
RUN npm install
COPY seed.js .
CMD node seed.js
```

---

## Commandes utiles

### Démarrage

```bash
# Lancer tous les services
cd breezy-infra
docker-compose up --build

# Lancer en arrière-plan
docker-compose up --build -d

# Lancer avec un fichier .env alternatif
docker-compose --env-file .env.prod up --build -d
```

### Arrêt

```bash
# Arrêter les conteneurs
docker-compose down

# Arrêter et supprimer les volumes (remet les BDD à zéro)
docker-compose down -v
```

### Logs

```bash
# Logs de tous les services
docker-compose logs -f

# Logs d'un service spécifique
docker-compose logs -f auth-service
docker-compose logs -f gateway
docker-compose logs -f nginx
```

### Exécution de commandes

```bash
# Accéder à un conteneur en cours d'exécution
docker exec -it breezy-auth sh

# Se connecter à PostgreSQL
docker exec -it breezy-db-pg-auth psql -U user -d auth_db

# Se connecter à MongoDB
docker exec -it breezy-db-mongo-posts mongosh -u admin -p breezy-mongo-2024
```

### Seed

Le conteneur `breezy-seed` s'exécute automatiquement une fois après le démarrage de la stack. Pour le relancer manuellement :

```bash
docker-compose run --rm seed
```

---

## Configuration Nginx

Le reverse proxy Nginx est défini dans `breezy-infra/nginx/nginx.conf` :

```nginx
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=global:10m rate=30r/m;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;

    client_max_body_size 5m;

    server {
        listen 80;

        location /api/ {
            proxy_pass http://gateway:3000;
            proxy_connect_timeout 30s;
            proxy_read_timeout 30s;
        }

        location / {
            proxy_pass http://frontend:3000;
            proxy_intercept_errors on;
            error_page 404 = /index.html;  # SPA fallback
        }
    }
}
```

Caractéristiques :
- **Rate limiting** : 30 req/min global, 5 req/min sur l'auth (protège contre le brute force)
- **Taille max des requêtes** : 5 Mo
- **SPA fallback** : les routes 404 du frontend renvoient `index.html` (nécessaire pour Next.js en SPA)
- **Timeouts** : 30 secondes pour la connexion et la lecture

---

## CI/CD

Chaque service dispose d'un pipeline CI sur GitHub Actions qui :

1. Clone le dépôt
2. Démarre une base de données de test (PostgreSQL pour auth/user, ou utilise le service CI)
3. Installe les dépendances
4. Exécute les tests Jest

Exemple pour auth-service (`.github/workflows/ci.yml`) :

```yaml
name: CI -- Tests breezy-auth-service

on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_USER: auth_user
          POSTGRES_PASSWORD: devpassword
          POSTGRES_DB: breezy_auth_test
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm test
        env:
          DATABASE_URL_TEST: postgresql://auth_user:devpassword@localhost:5432/breezy_auth_test
```

Le dépôt `breezy-infra` inclut également un workflow CI qui teste la stack complète : clone tous les dépôts frères, lance `docker compose up --build -d`, attend 30s, puis vérifie que tous les conteneurs sont en état `running`.
