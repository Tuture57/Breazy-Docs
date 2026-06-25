# Déploiement

L'infrastructure (`breezy-infra`) orchestre les **12 conteneurs** via `docker-compose`, plus
Nginx et un conteneur de seed.

---

## Prérequis

- Docker + docker-compose installés.
- Port **80** libre sur l'hôte (seul port publié).
- Un fichier `.env` présent dans `breezy-infra/` (les valeurs `${...}` du `docker-compose.yml`
  en proviennent).

---

## Commandes

```bash
cd breezy-infra

# Démarrer (build + run)
docker-compose up --build
docker-compose up --build -d        # en arrière-plan

# Arrêter
docker-compose down
docker-compose down -v              # + supprime les volumes (réinitialise les bases)

# Logs
docker-compose logs -f              # tous
docker-compose logs -f gateway      # un service

# Relancer le seed manuellement
docker-compose run --rm seed

# Accès direct
docker exec -it breezy-db-pg-auth psql -U user -d auth_db
docker exec -it breezy-db-mongo-posts mongosh -u admin -p breezy-mongo-2024
```

---

## Schéma du réseau Docker

```mermaid
graph TB
    subgraph host["Hôte"]
        PORT80(["localhost:80"])
    end
    subgraph breezy-network["breezy-network (bridge)"]
        NGINX[nginx]
        FRONT[frontend]
        GW[gateway]
        SVC["auth · user · post · profil"]
        DBS[("pg-auth · pg-users<br/>mongo-posts · mongo-profils")]
    end
    PORT80 --> NGINX
    NGINX --> FRONT
    NGINX --> GW
    GW --> SVC
    SVC --> DBS
```

Un seul réseau bridge : toutes les bases sont sur le **même réseau** que le reste (pas de réseau
DB isolé). L'isolation repose sur l'absence de port publié.

---

## Variables d'environnement par service

Valeurs résolues telles qu'injectées par `docker-compose.yml` depuis `.env`.

### Gateway

| Variable | Valeur |
|---|---|
| `NODE_ENV` | `production` |
| `PORT` | `3000` |
| `JWT_SECRET` | `CACACACACACACACA` |
| `AUTH/USER/POST/PROFIL_SERVICE_URL` | `http://<service>:<port>` |

!!! note "La gateway ne reçoit PAS `INTERNAL_SECRET`"
    Seuls les 4 microservices le reçoivent.

### auth-service

| Variable | Valeur |
|---|---|
| `PORT` | `3001` |
| `NODE_ENV` | `production` |
| `JWT_SECRET` | `CACACACACACACACA` |
| `JWT_EXPIRES_IN` | `15m` |
| `REFRESH_TOKEN_DAYS` | `7` |
| `BCRYPT_ROUNDS` | `10` |
| `DATABASE_URL` | `postgres://user:auth-password@pg-auth:5432/auth_db` |
| `USER_SERVICE_URL` | `http://user-service:3002` |
| `INTERNAL_SECRET` | `PIPIPIIPIPI` |
| `CORS_ORIGIN` | `http://localhost:3000` |

### user-service

| Variable | Valeur |
|---|---|
| `PORT` | `3002` |
| `DATABASE_URL` | `postgres://user:user-password@pg-users:5432/users_db` |
| `AUTH_SERVICE_URL` | `http://auth-service:3001` |
| `PROFIL_SERVICE_URL` | `http://profil-service:3004` |
| `INTERNAL_SECRET` | `PIPIPIIPIPI` |
| `CORS_ORIGIN` | `http://localhost:3000` |

### post-service

| Variable | Valeur |
|---|---|
| `PORT` | `3003` |
| `MONGO_URI` | `mongodb://admin:breezy-mongo-2024@mongo-posts:27017/posts_db?authSource=admin` |
| `USER_SERVICE_URL` | `http://user-service:3002` |
| `PROFIL_SERVICE_URL` | `http://profil-service:3004` |
| `INTERNAL_SECRET` | `PIPIPIIPIPI` |
| `OPENROUTER_API_KEY` | clé réelle (commitée en clair — voir [Secrets](../securite/secrets-configuration.md)) |
| `CORS_ORIGIN` | `http://localhost:3000` |

### profil-service

| Variable | Valeur |
|---|---|
| `PORT` | `3004` |
| `MONGO_URI` | `mongodb://admin:breezy-mongo-2024@mongo-profils:27017/profils_db?authSource=admin` |
| `AUTH_SERVICE_URL` | `http://auth-service:3001` |
| `INTERNAL_SECRET` | `PIPIPIIPIPI` |
| `CORS_ORIGIN` | `http://localhost:3000` |

### seed

| Variable | Valeur |
|---|---|
| `GATEWAY_URL` | `http://gateway:3000/api` |
| `SEED_ROLE_MODE` | `psql` |
| `AUTH_DATABASE_URL` | `postgres://user:auth-password@pg-auth:5432/auth_db` |

---

## Volumes

| Volume | Montage | Utilité |
|---|---|---|
| `pg_auth_data` | `pg-auth:/var/lib/postgresql/data` | Persistance auth_db |
| `pg_users_data` | `pg-users:/var/lib/postgresql/data` | Persistance users_db |
| `mongo_posts_data` | `mongo-posts:/data/db` | Persistance posts_db |
| `mongo_profils_data` | `mongo-profils:/data/db` | Persistance profils_db |
| `uploads_data` | `post-service:/app/uploads` | Images uploadées (persistantes) |

!!! warning "Bind-mounts de développement + `NODE_ENV=production`"
    Chaque microservice monte aussi son code source en bind-mount (`../breezy-<svc>:/app`) avec
    un volume anonyme protégeant `node_modules`. Cette configuration **dev/hot-reload** coexiste
    avec `NODE_ENV=production` : configuration hybride à clarifier avant un vrai déploiement.

---

## Dépendances & ordre de démarrage

```yaml
auth-service:
  depends_on:
    pg-auth:
      condition: service_healthy
```

- Les 4 microservices attendent leur base (`service_healthy`).
- La gateway attend les 4 microservices (`service_started`).
- `seed` attend la gateway + les 4 bases.
- `restart: on-failure` sur les microservices ; `restart: "no"` sur `seed`.

---

## Dockerfiles

| Service | Particularité |
|---|---|
| auth / user / post / profil | `node:20-alpine`, `npm install`, `CMD npm start`, pas d'`EXPOSE` |
| gateway | idem + `ENV PORT=3000`, `EXPOSE 3000` |
| frontend | idem + `RUN npm run build`, `EXPOSE 3000` |
| nginx | `nginx:alpine`, copie `nginx.conf`, `EXPOSE 80` |
| seed | `node:20-alpine` + `apk add postgresql-client` (promotion des rôles via psql) |

!!! note "Pas de `npm ci`, pas de multi-stage"
    Tous les Dockerfiles utilisent `npm install` (installe aussi les devDependencies) et un seul
    stage. Aucun utilisateur non-root.

---

## Nginx

```nginx
http {
    limit_req_zone $binary_remote_addr zone=global:10m rate=30r/m;
    limit_req_zone $binary_remote_addr zone=auth:10m   rate=5r/m;
    client_max_body_size 5m;

    server {
        listen 80;
        location /api/ { proxy_pass http://gateway:3000; }   # sans slash final → URI complète transmise
        location /     { proxy_pass http://frontend:3000;
                         proxy_intercept_errors on;
                         error_page 404 = /index.html; }       # fallback SPA
    }
}
```

!!! warning "Rate limiting Nginx déclaré mais NON appliqué"
    Les zones `global` (30 r/m) et `auth` (5 r/m) sont **définies** mais aucune directive
    `limit_req` ne les active dans les `location`. Le rate limiting effectif est donc
    **uniquement** celui de la gateway (500/15min, 20/15min sur l'auth).

---

## Seed

Le conteneur `seed` peuple les bases via l'API publique de la gateway, puis promeut les rôles en
SQL direct.

- **12 comptes** : 3 admin, 3 modérateurs, 6 utilisateurs (emails `@breezy.test`, mot de passe
  commun `Breezy2024!`).
- **Déroulé** : attente de la gateway (`/health`) → `register` (ou `login`) des comptes →
  promotion des rôles (`UPDATE users SET role=...` via `psql`, mode `SEED_ROLE_MODE=psql`) →
  re-login des comptes promus (pour un JWT avec le bon rôle) → posts → follows → likes →
  commentaires.
- Écrit un récapitulatif `seed/accounts.json`.

!!! note "HTTP uniquement"
    Nginx écoute en HTTP sur le port 80, sans TLS. Voir [Limites & évolutions](../soutenance/limites.md)
    pour les prérequis production (HTTPS, monitoring, migrations, etc.).
