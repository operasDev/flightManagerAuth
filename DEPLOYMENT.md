# Guide de Déploiement : FlightManagerAuth API

Ce document décrit l'architecture et les étapes nécessaires pour déployer l'API d'authentification `flightManagerAuth` (.NET 9) sur un serveur Linux (Ubuntu) via Docker.

---

## 1. Architecture Globale

L'API d'authentification a été conçue pour s'intégrer de manière sécurisée et centralisée dans l'infrastructure de l'entreprise :

- **Reverse Proxy SSL (Nginx)** : L'API .NET n'expose pas directement de port vers l'extérieur et ne gère pas ses propres certificats SSL (pour éviter les crashs de librairies cryptographiques sous Linux). 
- Nginx (le proxy gérant déjà le `mail-service`) s'occupe de la terminaison SSL. Il intercepte les requêtes `https://<domaine>/api/Auth/` et les transfère en HTTP (Port 8080) au conteneur `.NET`.
- **Réseau Virtuel Docker** : L'API tourne dans le réseau Docker interne `mail-service_mail-network`. Elle est totalement invisible depuis l'extérieur, sauf à travers Nginx.
- **LDAP (Active Directory)** : L'API communique directement avec le serveur Active Directory (`10.225.99.17`) pour valider les mots de passe des utilisateurs. Le code source intègre une vérification intelligente pour tester plusieurs formats de noms d'utilisateurs (`UPN`, `Domaine\User`, etc.) exigés par Linux.

---

## 2. Prérequis sur le Serveur Hôte

1. **Système d'exploitation :** Ubuntu 24.04 (ou supérieur).
2. **Logiciels installés :**
   - Docker & Docker Compose
   - Git
3. **Accès Réseau (Très important) :**
   - Le serveur hôte doit avoir l'autorisation (Pare-feu / Firewall) de joindre l'adresse IP de l'Active Directory sur le port `389` (LDAP non sécurisé) ou `636` (LDAPS sécurisé).

---

## 3. Configuration du fichier `.env`

Avant de compiler et de lancer l'application, créez un fichier `.env` à la racine du projet (`/home/secure/app/flightManagerAuth/`) contenant les identifiants LDAP :

```env
# Adresse IP ou DNS du serveur LDAP / Active Directory
LDAP_SERVER=10.225.99.17

# Nom de domaine de l'entreprise
LDAP_DOMAIN=edv-ops.com
```

*Note : L'API donne toujours la priorité à ces variables `.env` sur le fichier `appsettings.json`.*

---

## 4. Étapes de Déploiement (Mise à jour)

À chaque fois qu'une modification du code source C# est "pushée" sur le dépôt distant (GitHub), exécutez ces commandes sur le serveur cible pour déployer la nouvelle version :

### A. Mettre à jour le code source
```bash
cd /home/secure/app/flightManagerAuth
git pull origin main
```

### B. Recompiler l'image Docker
Cette commande reconstruit l'image `.NET`. Le Dockerfile se charge automatiquement d'installer `libldap2` et de créer les liens symboliques (symlinks) requis par .NET sur Linux.
```bash
docker build -t flight-manager-auth .
```

### C. Relancer le conteneur API
On supprime l'ancien conteneur et on lance le nouveau en l'attachant au bon réseau réseau Nginx :
```bash
# Supprimer l'ancien
docker rm -f flight_manager_auth

# Démarrer le nouveau
docker run -d \
  --name flight_manager_auth \
  --network mail-service_mail-network \
  --env-file .env \
  --restart unless-stopped \
  flight-manager-auth
```

### D. Redémarrer le cache DNS Nginx (Important)
À chaque recréation, Docker assigne une nouvelle adresse IP interne au conteneur `flight_manager_auth`. Nginx gardant en cache l'ancienne IP, **il faut impérativement redémarrer Nginx pour éviter l'erreur `502 Bad Gateway`**.
```bash
docker restart mail_nginx
```

---

## 5. Configuration Nginx (Rappel)

Si jamais le conteneur Nginx doit être recréé, voici le bloc de configuration exact à intégrer dans son fichier `default.conf` pour assurer la liaison avec l'API :

```nginx
# Dans le bloc "server { listen 443 ssl; ... }"
location /api/Auth/ {
    proxy_pass http://flight_manager_auth:8080/api/Auth/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection keep-alive;
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;
}
```

---

## 6. Dépannage rapide (Troubleshooting)

- **Erreur `504 Gateway Time-out` :** L'API n'arrive pas à joindre le serveur Active Directory. Vérifiez les règles du pare-feu avec l'équipe Réseau (ping / nc).
- **Erreur `502 Bad Gateway` :** Le conteneur Nginx a perdu le lien IP vers l'API. Faites simplement `docker restart mail_nginx`.
- **Problème de "Mot de passe incorrect" silencieux :** Assurez-vous que le Dockerfile contient toujours la commande `ln -s /usr/lib/x86_64-linux-gnu/libldap.so.2 /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0`. Si ce n'est pas le cas, .NET plantera sans faire de bruit lors de la connexion LDAP.
