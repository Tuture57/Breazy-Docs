# Limites & évolutions

Constats issus du code, sans jugement : ce qui est manquant/partiel, ce qui pourrait être
amélioré, et les évolutions possibles.

---

## Limitations actuelles

### 1. Gateway = point de défaillance unique

Toutes les requêtes API passent par une **seule instance** de gateway. Si elle tombe, Nginx
renvoie 502 et l'application devient inutilisable. → Load-balancer plusieurs instances derrière
Nginx.

### 2. Secrets commités dans le dépôt

`JWT_SECRET` et `INTERNAL_SECRET` (placeholders) et surtout une **vraie clé OpenRouter**
(`OPENROUTER_API_KEY`) sont commités en clair. La gateway a un fallback `JWT_SECRET || "defaultSecret"`.
→ Révoquer la clé, sortir les `.env` du versionnement, supprimer le fallback. Voir
[Secrets & configuration](../securite/secrets-configuration.md).

### 3. Pas de HTTPS

Nginx écoute en HTTP sur le port 80. Mots de passe et JWT transitent en clair, et les cookies
`secure`/`sameSite` n'ont pas d'effet réel. → Let's Encrypt / Caddy + redirection HTTP→HTTPS.

### 4. `sequelize.sync({ alter: true })` en production

Les services auth et user modifient automatiquement le schéma au démarrage (potentiellement
destructeur). → Migrations Sequelize explicites.

### 5. Rate limiting Nginx non appliqué

Les zones `global`/`auth` sont déclarées mais aucune directive `limit_req` ne les active. Seul le
rate limiting de la gateway est effectif. → Activer `limit_req` ou retirer les zones inutiles.

### 6. Headers `x-user-*` non signés

Les services font confiance aux headers injectés par la gateway sans vérifier leur origine. Un
service joignable directement permettrait l'usurpation. La seule protection est l'isolation
réseau. → JWT interne signé (HMAC) pour les appels service-à-service.

### 7. Monitoring / logging absent

Tous les logs sont en `console.*`, sans stockage ni alerting. → ELK / Loki + Grafana.

### 8. Pagination offset uniquement

`skip/limit` partout, inefficace sur de grands volumes et instable pour un feed temps réel. →
Pagination par curseur (`_id`/`created_at`).

### 9. Tests partiels

Seuls auth-service et user-service ont des tests Jest (et certains assertions divergent du code,
ex. `getFollowing`). Post et profil n'ont pas de tests réels. → `mongodb-memory-server` + tests
contrôleurs.

### 10. Configuration hybride dev/prod

`NODE_ENV=production` coexiste avec des bind-mounts de code source en volume. → Clarifier
(profil de build dédié à la prod).

---

## Fonctionnalités manquantes ou partielles

| Fonctionnalité | État |
|---|---|
| Messagerie (Fx22) | Composants frontend non connectés, aucun backend |
| Mot de passe oublié (Fx23) | Aucune route, aucun envoi d'email |
| UI de signalement (Fx19) | Route backend `report` existe, pas d'UI ni de filtrage |
| UI de modération / ban (Fx21) | Backend complet, aucun panneau admin |
| Notifications `comment`/`reply` | Types prévus dans le schéma, jamais générés |
| Upload avatar/bannière | Champs `avatar_url`/`banner_url` présents, lus en base64 côté front (pas via le service d'upload images) |

---

## Bugs / incohérences connus (du code)

- `likes_count` peut devenir **négatif en base** (seul l'affichage est borné par `Math.max(0, ...)`).
- `comments_count` peut **diverger** : décrément de 1 même quand des réponses sont supprimées en cascade.
- **Reposts non supprimés** à la suppression d'un post → orphelins.
- `x-user-username` non injecté pour le user-service → `from_username: undefined` dans la notif de follow.
- Recherche par tag : comparaison au `toLowerCase()` de la requête, mais tags non normalisés à la création.
- `report` ne renvoie pas de 404 pour un post inexistant.

---

## Évolutions court terme

1. Révoquer/retirer les secrets du dépôt et supprimer le fallback `defaultSecret`.
2. Activer HTTPS (Let's Encrypt).
3. Ajouter les healthchecks Docker sur les services applicatifs (le `GET /health` existe déjà).
4. Activer/retirer le rate limiting Nginx.
5. Tests pour post-service et profil-service ; corriger les tests divergents du user-service.

## Évolutions moyen terme

1. Message broker (RabbitMQ) pour les événements (`user.created`, `post.liked`, `user.banned`).
2. Pagination par curseur pour le feed.
3. Cache Redis (feeds, profils, listes de following).
4. Monitoring Prometheus/Grafana.
5. Recherche full-text (index `$text` MongoDB ou Elasticsearch) au lieu des regex.

## Évolutions long terme

1. Orchestration Kubernetes (auto-scaling, rolling updates, secrets via Vault).
2. CDN / stockage objet (S3 + URLs présignées) pour les médias, au lieu du disque local.
3. Migration TypeScript progressive (DTOs typés).
4. Authentification 2FA (TOTP).
5. Modération outillée (dashboard signalements, file de revue).
