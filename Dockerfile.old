# Utilisation de l'image .NET SDK pour la compilation
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /app

# Copier les fichiers du projet et restaurer les dépendances
COPY ["flightManagerAuth.csproj", "./"]
COPY . .
RUN dotnet restore
# Compiler l'application en mode Release
RUN dotnet publish -c Release -o /app/publish

# Utilisation de l'image runtime pour exécuter l'application
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS runtime
WORKDIR /app

# Installer les dépendances LDAP
RUN apt-get update && apt-get install -y --no-install-recommends \
    libldap-2.5-0 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .

# Exposer le port de l'application
EXPOSE 5000
EXPOSE 5001

# Démarrer l'application
ENV ASPNETCORE_URLS=http://+:5000
ENTRYPOINT ["dotnet", "flightManagerAuth.dll"]
