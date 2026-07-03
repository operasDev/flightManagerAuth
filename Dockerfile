# Utilisation du SDK .NET 9 sur Ubuntu Jammy pour construire l'application
FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS build-env
WORKDIR /app

# Copie du fichier .csproj et restauration des dépendances
COPY *.csproj ./
RUN dotnet restore

# Copie du reste du code et compilation
COPY . ./
RUN dotnet publish -c Release -o out

# Utilisation de l'image de base de .NET 9 Runtime sur Ubuntu Jammy pour l'exécution
FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble AS runtime
WORKDIR /app

# Installer les dépendances LDAP et créer les symlinks pour .NET 9
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap2 \
    && ln -s /usr/lib/x86_64-linux-gnu/libldap.so.2 /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0 \
    && ln -s /usr/lib/x86_64-linux-gnu/liblber.so.2 /usr/lib/x86_64-linux-gnu/liblber-2.5.so.0 \
    && rm -rf /var/lib/apt/lists/*

# Copier l'application compilée
COPY --from=build-env /app/out .

# Certificat SSL géré par Nginx
# Configurer l'utilisateur non-root par défaut pour plus de sécurité
USER $APP_UID

# Exposer le port HTTP (8080)
EXPOSE 8080

# Démarrer l'application (HTTP uniquement, le HTTPS est géré par Nginx)
ENV ASPNETCORE_URLS="http://+:8080"
ENTRYPOINT ["dotnet", "flightManagerAuth.dll"]
