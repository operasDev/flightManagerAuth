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

# Installer les dépendances LDAP
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap2 \
    && rm -rf /var/lib/apt/lists/*

# Copier l'application compilée
COPY --from=build-env /app/out .

# Copier le certificat SSL
COPY edvwildcard.pfx .

# Configurer l'utilisateur non-root par défaut pour plus de sécurité
USER $APP_UID

# Exposer les ports HTTP (8080) et HTTPS (8443)
EXPOSE 8080
EXPOSE 8443

# Démarrer l'application
ENV ASPNETCORE_URLS="http://+:8080;https://+:8443"
ENTRYPOINT ["dotnet", "flightManagerAuth.dll"]
