# Limites actuelles et evolutions

---

## Limitations actuelles

### 1. Gateway = single point of failure

La Gateway est le seul point d'entree de toutes les requetes API. Si elle est indisponible, l'ensemble de l'application est inaccessible.

- **Impact** : aucune requete API ne peut aboutir
- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js` -- une seule instance Express (ligne 225)
- **Solution** : load balancing avec plusieurs instances de Gateway derriere Nginx

### 2. Pas de CI/CD automatise

Les workflows GitHub Actions existent mais ne sont pas completement operationalises.

- **Auth-service** : `.github/workflows/ci.yml` (tests Jest avec PostgreSQL)
- **User-service** : `.github/workflows/ci.yml` (tests Jest avec PostgreSQL)
- **Infra** : `.github/workflows/ci.yml` (docker compose up, verifie que les conteneurs demarrent)
- **Manquant** : pas de deploiement automatique, pas de staging/production, pas de publication d'images Docker

### 3. Pas de HTTPS en production

Nginx ecoute en HTTP sur le port 80, sans certificat SSL/TLS.

- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-infra\nginx\nginx.conf`, ligne 26 (`listen 80;`)
- **Risque** : les mots de passe et JWT transitent en clair
- **Solution** : Let's Encrypt avec Certbot ou un reverse proxy comme Caddy

### 4. Pas de monitoring / logging centralise

Tous les logs sont en console (`console.log`, `console.warn`, `console.error`). Pas de stockage persistant, pas d'alerting.

- **Auth** : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\controllers\auth.controller.js`, ligne 67 (`console.error`)
- **Post** : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, ligne 70 (`console.error`)
- **Solution** : ELK Stack (Elasticsearch, Logstash, Kibana) ou Loki + Grafana

### 5. NODE_ENV=test dans Docker desactive le rate limiting

Le docker-compose definit `NODE_ENV=test` pour la Gateway, ce qui desactive tous les limiteurs de taux.

```javascript
const isTest = process.env.NODE_ENV === 'test';
const globalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: isTest ? 999999 : 500,  // 999999 en test
});
```

- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 16-43
- **docker-compose.yml** : `C:\Users\barto\Desktop\breezy projet\breezy-infra\docker-compose.yml`, ligne 37 (`NODE_ENV=test`)
- **Risque** : pas de protection contre le brute-force en environnement Docker
- **Correction** : remplacer par `NODE_ENV=development`

### 6. sequelize.sync({ alter: true }) est dangereux en production

Les services auth et user utilisent `sequelize.sync({ alter: true })` au demarrage, ce qui modifie automatiquement le schema de la base pour correspondre aux modeles.

```javascript
const connectDB = async () => {
    await sequelize.authenticate();
    console.log('[Auth DB] Connexion PostgreSQL OK');
    await sequelize.sync({ alter: true });  // DANGEREUX en production
};
```

- **Auth** : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\config\database.js`, ligne 12
- **User** : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\src\config\database.js`, ligne 12
- **Risque** : peut supprimer des colonnes, modifier des types, ou echouer sur des tables volumineuses
- **Correction** : utiliser des migrations Sequelize explicites

### 7. Pas de tests pour post-service et profil-service

Seuls auth-service et user-service ont des tests Jest.

- **Tests existants** : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\tests\auth.test.js` (integration)
- **Tests existants** : `C:\Users\barto\Desktop\breezy projet\breezy-user-service\tests\user.test.js` (integration)
- **Post** : pas de dossier `tests/`, pas de tests
- **Profil** : pas de dossier `tests/`, pas de tests (package.json a `test: jest` mais aucun test ecrit)

### 8. Feed vide si user-service est down

Si le user-service est indisponible lors du chargement du feed, la liste des abonnements est vide et le feed affiche uniquement les posts de l'utilisateur courant. Aucun message n'alerte l'utilisateur de cette degradation.

- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 117-129
- **Fallback** : ligne 128 (`console.warn` suivi de `followingIds = []`)
- **Amelioration** : ajouter un etat "Abonnements temporairement indisponibles" dans l'UI

### 9. Pas de pagination par curseur (offset-based uniquement)

Toute la pagination est offset-based (`skip/limit`), ce qui devient inefficace sur de grands volumes :
- Les posts sautes sont toujours lus par MongoDB
- L'ajout de nouveaux posts en tete de liste peut causer des doublons
- Pas stable pour un feed en temps reel

- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 114-115 (`skip = (page - 1) * limit`)

### 10. Pas de mot de passe oublie

Il n'existe pas de flux de reinitialisation de mot de passe.

- **Routes existantes** : `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\routes\auth.routes.js` -- pas de route `/forgot-password` ou `/reset-password`
- **Frontend** : pas de page dediee

---

## Bugs connus (du code)

### 1. likes_count peut theoriquement devenir negatif

Si deux requetes `unlike` sont envoyees simultanement pour le meme post par le meme utilisateur, la deuxieme pourrait faire passer `likes_count` en dessous de zero. Le `Math.max(0, ...)` corrige en lecture mais pas en ecriture.

```javascript
const updated = await Post.findByIdAndUpdate(postId, { $inc: { likes_count: -1 } }, { new: true });
return res.json({ likes_count: Math.max(0, updated.likes_count) });
```

- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\like.controller.js`, lignes 55-60
- **Risque** : le compteur en base peut devenir negatif, seul l'affichage est corrige

### 2. Pas de verification que x-user-id provient bien de la Gateway

Chaque service backend lit les headers `x-user-*` sans verifier qu'ils proviennent de la Gateway. Un service intermediaire compromis pourrait injecter des headers frauduleux.

- **Code typical** : `C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 10-11
- **Risque** : si un service est compromis, il peut usurper n'importe quel utilisateur
- **Solution possible** : signer les headers avec une cle partagee entre Gateway et services

### 3. Les headers x-user-* ne sont pas signes

Contrairement a un JWT, les headers HTTP injectes par la Gateway ne contiennent pas de signature. Un service backend qui appelle un autre service backend pourrait mentir sur son identite.

- **Code** : `C:\Users\barto\Desktop\breezy projet\breezy-infra\gateway\src\index.js`, lignes 111-113 (headers en clair)
- **Solution** : utiliser un token JWT interne pour les communications inter-services, ou signer les headers avec HMAC

---

## Fonctionnalites manquantes

### Messagerie directe (Fx22)
- Routes definies dans le frontend (`/messages`, `/messages/[convId]`)
- Composants UI existants (`ConversationList`, `MessageThread`, `MessageInput`)
- Pas de backend implemente pour la messagerie

### Mot de passe oublie (Fx23)
- Pas de route `/forgot-password`
- Pas de route `/reset-password`
- Pas d'envoi d'email

### UI de moderation
- Le flag `is_reported` existe sur les posts (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\models\post.model.js`, ligne 12)
- La route `POST /posts/:id/report` existe (`C:\Users\barto\Desktop\breezy projet\breezy-post-service\src\controllers\post.controller.js`, lignes 217-225)
- Mais il n'y a pas de dashboard moderateur ni de page de signalements

### Upload avatar/banniere
- L'UI du profil a un emplacement pour l'avatar et la banniere
- Les champs `avatar_url` et `banner_url` existent dans le profil model
- Mais l'upload d'image de profil n'est pas connecte au post-service

### Notifications de comment/reply
- Les types `'comment'` et `'reply'` sont definis dans le schema de notification (`C:\Users\barto\Desktop\breezy projet\breezy-profil-service\src\models\notification.model.js`, ligne 4)
- Mais ils ne sont pas generes par les controleurs de commentaires

---

## Evolutions court terme

### 1. Ajouter HTTPS avec Let's Encrypt
- Configurer Nginx avec Certbot pour obtenir des certificats SSL automatiques
- Rediriger HTTP vers HTTPS

### 2. Mettre en place CI/CD GitHub Actions
- Builder et pusher les images Docker vers un registry (DockerHub, GitHub Container Registry)
- Deploiement automatique sur un serveur de staging
- Tests automatiques avant merge sur `main`

### 3. Ajouter des healthchecks Docker sur les services applicatifs
- Chaque service a deja un endpoint `/health` (ex: `C:\Users\barto\Desktop\breezy projet\breezy-auth-service\src\app.js`, ligne 22)
- Mais ils ne sont pas configures dans `docker-compose.yml` avec `healthcheck`
- Actuellement, seules les bases de donnees ont des healthchecks

### 4. Corriger le NODE_ENV=test
- Remplacer `NODE_ENV=test` par `NODE_ENV=development` dans `docker-compose.yml` (ligne 37)
- Cela activera le rate limiting en environnement Docker

### 5. Ajouter des tests pour post-service et profil-service
- Tests Jest pour les controleurs post, like, comment
- Tests Jest pour les controleurs profil et notification
- Utiliser `mongodb-memory-server` pour les tests sans MongoDB externe

---

## Evolutions moyen terme

### 1. Message broker (RabbitMQ) pour les evenements inter-services
Remplacer les appels HTTP fire-and-forget par un bus d'evenements :
- `user.created` > creation du profil
- `post.liked` > notification
- `user.banned` > propagation du ban
- Decouplage total des services
- File d'attente garantissant la livraison

### 2. Pagination par curseur pour le feed
Remplacer `skip/limit` par `_id > cursor` ou `created_at < cursor` :
- Performances constantes quelque soit le nombre de pages
- Pas de doublons en cas d'ajout de nouveaux posts
- Ideal pour un feed en temps reel

### 3. Cache Redis pour le feed et les profils
Mettre en cache :
- Les feeds des utilisateurs (invalidation a la creation d'un post par un follow)
- Les profils utilisateur (TTR courte)
- Les listes de following (invalidees au follow/unfollow)

### 4. Monitoring avec Prometheus/Grafana
- Exposer des metriques Prometheus depuis chaque service
- Dashboard Grafana pour visualiser :
  - Taux de requetes par service
  - Temps de reponse (p50, p95, p99)
  - Taux d'erreur
  - Utilisation CPU/Memoire

### 5. Elasticsearch pour la recherche full-text
Remplacer la recherche regex MongoDB par Elasticsearch :
- Recherche full-text avec scoring
- Auto-completion
- Filtres avances (par date, type, etc.)

---

## Evolutions long terme

### 1. Passage a Kubernetes pour l'orchestration
- Deploiement avec auto-scaling horizontal
- Rolling updates sans interruption de service
- Gestion des secrets via Vault
- Service mesh (Istio) pour la securite inter-services

### 2. Service worker pour le support offline
- Mise en cache des ressources statiques
- File d'attente des actions hors-ligne (likes, posts)
- Synchronisation lors de la reconnexion

### 3. CDN pour les medias (S3/CloudFront)
- Upload direct depuis le client vers S3 (presigned URLs)
- Distribution via CDN pour les images
- Suppression du stockage disque local
- Redimensionnement automatique des images (thumbnails)

### 4. Migration TypeScript progressive
- Typage fort des interfaces (DTOs, reponses API)
- Detection des erreurs a la compilation
- Documentation vivante via les types
- Migration service par service, en commencant par la Gateway

### 5. Authentification 2FA
- TOTP (Time-based One-Time Password) via bibliotheque standard
- Backup codes pour la recuperation
- Option a activer dans les parametres du compte

### 6. Federation ActivityPub (interoperabilite avec Mastodon)
- Implementation du protocole ActivityPub
- Permettre aux utilisateurs Breezy de suivre des comptes Mastodon et vice-versa
- Federation du contenu
