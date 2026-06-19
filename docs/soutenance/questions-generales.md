# Questions générales — Préparation soutenance

## Architecture & Design

### Q1 : Pourquoi avoir choisi une architecture microservices plutôt qu'un monolithe ?

**Réponse attendue :**

- **Séparation des responsabilités** : chaque service gère un domaine métier précis (authentification, profils, posts, notifications)
- **Scalabilité indépendante** : on peut scaler le post-service sans toucher à l'auth-service
- **Technologie adaptée** : PostgreSQL pour les données relationnelles (users, follows) et MongoDB pour les données documents (posts, notifications)
- **Développement en parallèle** : chaque membre peut travailler sur son service sans conflits
- **Résilience** : si le profil-service tombe, le reste de l'application continue de fonctionner

### Q2 : Pourquoi deux types de bases de données (PostgreSQL + MongoDB) ?

**Réponse attendue :**

- **PostgreSQL** pour les données qui nécessitent des relations et des transactions (users ↔ refresh_tokens, follows avec compteurs atomiques)
- **MongoDB** pour les données type document qui évoluent (posts avec tags/media variables, notifications avec types différents)
- C'est une approche **polyglot persistence** : chaque service choisit le moteur le plus adapté à ses besoins

### Q3 : Comment les services communiquent-ils entre eux ?

**Réponse attendue :**

- Communication **HTTP REST synchrone** (pas de message broker)
- Les appels inter-services sont protégés par un **`INTERNAL_SECRET`** (header `x-internal-secret`)
- Les appels sont **non bloquants** : si le service cible est indisponible, l'opération principale réussit quand même
- Exemples : sync user à l'inscription, propagation du ban, récupération des following pour le feed, envoi de notification au like

### Q4 : Quel est le rôle de l'API Gateway ?

**Réponse attendue :**

- **Vérification JWT** : les services ne vérifient jamais le token eux-mêmes
- **Injection de l'identité** : ajoute les headers `x-user-id` et `x-user-role` après vérification
- **Routage** : dirige `/api/auth/*`, `/api/users/*`, `/api/posts/*`, `/api/profils/*` vers les bons services
- **Rate limiting** : 100 req/15min global, 10 req/15min sur `/api/auth`
- **Point d'entrée unique** pour le frontend

### Q5 : Comment Docker Compose orchestre-t-il l'infrastructure ?

**Réponse attendue :**

- **11 conteneurs** sur un réseau bridge `breezy-network`
- Seul Nginx expose le port **80** vers l'extérieur
- Les services communiquent entre eux via leurs noms de conteneur (DNS Docker interne)
- Les bases de données ont des **volumes persistants** pour ne pas perdre les données au restart
- Le code source est monté en volume pour le hot-reload en développement

---

## Sécurité

### Q6 : Décrivez le flow d'authentification JWT complet

**Réponse attendue :**

1. L'utilisateur s'inscrit/se connecte → l'auth-service génère un **access token JWT** (15 min) et un **refresh token** (7 jours)
2. L'access token est retourné dans le body JSON, le refresh token dans un **cookie httpOnly**
3. Le frontend stocke l'access token dans **localStorage** et l'injecte via un intercepteur Axios
4. Pour chaque requête protégée, la **Gateway** vérifie le JWT et injecte les headers d'identité
5. Quand l'access token expire, le client appelle `POST /auth/refresh` avec le cookie
6. L'auth-service **révoque** l'ancien refresh token et en émet un nouveau (**rotation**)
7. Si un token déjà révoqué est présenté, **tous les tokens du compte** sont révoqués (détection de vol)

### Q7 : Pourquoi les refresh tokens sont hashés en SHA-256 ?

**Réponse attendue :**

- Si un attaquant accède à la base de données, il ne peut pas récupérer les tokens en clair
- Le hash est à sens unique : on peut vérifier si un token correspond mais pas retrouver le token
- C'est le même principe que pour les mots de passe (sauf qu'ici SHA-256 suffit car les tokens sont déjà aléatoires et longs)

### Q8 : Quelles protections contre les attaques courantes ?

| Attaque | Protection |
|---------|-----------|
| Brute force | Rate limiting double couche (Nginx + Gateway) |
| Vol de session | Rotation des refresh tokens + détection de réutilisation |
| XSS | Cookie httpOnly (le JS ne peut pas lire le refresh token) |
| CSRF | Cookie `sameSite: Strict` |
| Énumération de comptes | Message d'erreur identique pour email inexistant et mauvais mot de passe |
| Injection SQL | ORM Sequelize/Mongoose (requêtes paramétrées) |

### Q9 : Quelles faiblesses de sécurité avez-vous identifiées ?

**Réponse honnête (montre de la maturité) :**

- L'access token est dans `localStorage` → vulnérable au XSS (pas au CSRF, mais au XSS oui)
- Pas de confirmation email à l'inscription
- Pas de 2FA/MFA
- Le `INTERNAL_SECRET` est partagé entre tous les services → si compromis, tous les appels internes sont exposés
- Le changement et la réinitialisation de mot de passe ne sont pas implémentés
- Les headers `x-user-*` injectés par la Gateway ne sont pas signés → un service malveillant pourrait les forger

---

## Choix techniques

### Q10 : Pourquoi Express 5 pour les services et Express 4 pour la Gateway ?

**Réponse attendue :**

- Les services backend utilisent Express **5.2** (dernière version) pour bénéficier du support natif des async errors
- La Gateway utilise Express **4.19** pour la compatibilité avec `http-proxy-middleware` (version 3)
- C'est un choix pragmatique : la Gateway a été développée séparément avec ses propres dépendances

### Q11 : Pourquoi Sequelize pour PostgreSQL et Mongoose pour MongoDB ?

**Réponse attendue :**

- **Sequelize** : ORM mature pour les BDD relationnelles, gère les migrations, les transactions, et les associations
- **Mongoose** : ODM standard pour MongoDB, gère les schémas, la validation et les index
- Les deux sont les choix les plus populaires et documentés dans l'écosystème Node.js

### Q12 : Comment gérez-vous la synchronisation des données entre services ?

**Réponse attendue :**

- **Event-driven synchrone** : à l'inscription, l'auth-service appelle le user-service pour synchroniser le profil
- **Cohérence éventuelle** : si le user-service est indisponible, le compte est quand même créé dans l'auth-service
- **Risque assumé** : les données peuvent être temporairement désynchronisées (ex: `is_banned` dans les deux bases)
- **Amélioration possible** : utiliser un message broker (RabbitMQ, Kafka) pour garantir la livraison
