# Limites & Évolutions

## Limites identifiées

### Fonctionnalités manquantes

| Fonctionnalité | Impact | Difficulté estimée |
|----------------|--------|-------------------|
| **Messagerie privée** | Le frontend a les pages mais aucun backend. Fonctionne uniquement en mode mock. | Élevée (nouveau service, WebSocket pour le temps réel) |
| **Changement de mot de passe** | Le frontend appelle `POST /auth/change-password` qui n'existe pas. | Faible (1 route à ajouter dans l'auth-service) |
| **Réinitialisation de mot de passe** | Le bouton "Oublié ?" affiche un faux message sans rien envoyer. | Moyenne (nécessite un service email) |
| **Repost / Partage** | Le frontend a `toggleRepost()` mais aucune route backend. | Moyenne |
| **Modification de post** | Le frontend a `updatePost()` mais aucune route `PUT /posts/:id`. | Faible |
| **Confirmation email** | Aucune vérification que l'email est valide. | Moyenne (service email) |

### Divergences frontend/backend

| Problème | Détail |
|----------|--------|
| **Validation du mot de passe** | Frontend : min 6 chars. Backend : min 8 chars + 1 majuscule + 1 chiffre. Un formulaire peut passer côté client mais être rejeté par le serveur. |
| **Route de mise à jour du profil** | Le frontend appelle `PUT /users/:id` (user-service) mais la route réelle est `PUT /profiles/:userId` (profil-service). |
| **Recherche de posts** | Le frontend utilise le paramètre `q` mais le backend attend `tag`. |
| **Routes de profil avancées** | `getUserReplies`, `getUserMedia`, `getUserLikes`, `getUserReposts` appellent des routes qui n'existent pas dans le backend. |
| **Header `x-user-username`** | Le post-service et profil-service lisent `x-user-username` depuis les headers, mais la Gateway ne propage pas ce header. |

### Limitations techniques

| Limitation | Détail |
|-----------|--------|
| **Communication synchrone uniquement** | Pas de message broker. Si un service est lent, ça ralentit toute la chaîne. Les appels non bloquants atténuent le problème mais ne le résolvent pas. |
| **Pas de cache** | Aucun Redis. Chaque requête de feed fait un appel au user-service + une requête MongoDB. |
| **Pas de pagination du feed par cursor** | Pagination par `skip/limit` : plus on avance dans les pages, plus c'est lent (MongoDB doit scanner les documents précédents). |
| **Pas de WebSocket** | Les notifications et messages ne sont pas temps réel. Il faut rafraîchir la page pour les voir. |
| **Pas de upload de fichiers** | Les `media_urls` et `avatar_url` sont des URLs brutes. Pas de service d'upload. |
| **`localStorage` pour le JWT** | Vulnérable aux attaques XSS (un script malveillant peut lire le token). |
| **Pas de migration de BDD** | `sequelize.sync({ alter: true })` modifie le schéma au démarrage. En production, il faudrait des migrations versionnées. |
| **INTERNAL_SECRET unique** | Le même secret est partagé entre tous les services. Si compromis, tous les appels internes sont exposés. |

### Bugs connus

| Bug | Détail |
|-----|--------|
| **Feed vide si user-service down** | Comportement voulu mais l'utilisateur ne sait pas pourquoi son feed est vide. Pas de message d'erreur. |
| **Compteur likes_count peut être négatif** | Le code fait `Math.max(0, updated.likes_count)` côté réponse mais ne corrige pas la valeur en base. |
| **`x-user-id` vs `sub` dans le JWT** | La Gateway lit `req.user.id` mais le claim JWT est `sub`. Fonctionne car jsonwebtoken expose les claims directement, mais le code pourrait être plus explicite. |

---

## Évolutions possibles

### Court terme (améliorations rapides)

1. **Ajouter les routes manquantes** : `PUT /posts/:id` (modification), `POST /auth/change-password` (changement de mot de passe)
2. **Corriger les divergences frontend/backend** : aligner les paramètres de recherche, les routes de profil, la validation du mot de passe
3. **Ajouter les tests pour post-service et profil-service** : actuellement 0 test sur ces deux services
4. **Propager `x-user-username` depuis la Gateway** : ajouter le header dans les appels proxy pour que les services backend puissent l'utiliser

### Moyen terme (architecture)

1. **Message broker (RabbitMQ/Redis Streams)** : remplacer les appels HTTP inter-services par des événements asynchrones pour une meilleure résilience
2. **Cache Redis** : mettre en cache les résultats du feed, les profils fréquemment consultés, les compteurs
3. **WebSocket (Socket.io)** : notifications et messages en temps réel sans polling
4. **Service d'upload** : intégrer un service de stockage (S3, Cloudinary) pour les avatars et médias
5. **Pagination par cursor** : remplacer `skip/limit` par un cursor basé sur `_id` ou `created_at` pour de meilleures performances

### Long terme (production)

1. **CI/CD** : pipeline GitLab/GitHub Actions avec tests, lint, build Docker, déploiement automatique
2. **Monitoring** : Prometheus + Grafana pour les métriques, ELK pour les logs centralisés
3. **HTTPS** : certificat SSL/TLS avec Let's Encrypt
4. **2FA/MFA** : authentification à deux facteurs (TOTP)
5. **Migrations de BDD** : remplacer `sequelize.sync({ alter: true })` par des migrations Sequelize versionnées
6. **API versioning** : préfixer les routes avec `/v1/` pour gérer les évolutions sans casser les clients
7. **Kubernetes** : orchestration avancée pour le déploiement en production

---

## Ce qui a bien été fait

| Point fort | Détail |
|-----------|--------|
| **Sécurité JWT** | Rotation des refresh tokens, détection de vol, cookie httpOnly, hash SHA-256 |
| **Transactions atomiques** | Follow/unfollow avec compteurs cohérents via transactions Sequelize |
| **Rate limiting double couche** | Nginx + Gateway, avec limites spécifiques pour l'authentification |
| **Résilience des appels inter-services** | Try/catch avec timeouts, l'opération principale n'échoue jamais à cause d'un service tiers |
| **Mode mock frontend** | Développement frontend complètement indépendant du backend |
| **Tests d'intégration** | Couverture solide de l'auth-service et du user-service avec des cas edge (ban, vol de token, self-follow) |
| **Séparation des bases** | Chaque service a sa propre BDD, jamais d'accès direct à la BDD d'un autre |
| **Docker Compose complet** | Infrastructure reproductible avec un seul `docker-compose up` |
