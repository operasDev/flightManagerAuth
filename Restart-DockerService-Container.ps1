# Script PowerShell pour redémarrer le service Docker et un conteneur spécifique

# --- Paramètres (à modifier si nécessaire) ---
$serviceName = "docker"          # Nom du service Docker
$maxRetriesService = 3         # Nombre maximal de tentatives de redémarrage du service
$retryDelayServiceSeconds = 30  # Délai entre les tentatives de redémarrage du service (en secondes)
$logFilePath = "C:\DockerLogs\DockerRestartLog.txt"  # Chemin complet du fichier journal
$containerId = "4a44bb53b292"  # ID du conteneur à redémarrer
$forceServiceRestart = $false   # Si $true, redémarre le service même s'il est déjà en cours d'exécution
$forceContainerRestart = $true # Redémarre toujours le conteneur. Mettre à false pour utiliser docker start
$dockerExecutable = "$Env:ProgramFiles\Docker\docker " # A adapter si besoin !
$dockerCommandTimeout = 60      # Délai d'expiration pour les commandes Docker (en secondes)

# --- Fonctions utilitaires ---

# Fonction pour écrire dans le fichier journal avec timestamp
function Write-Log {
    param(
        [string]$message,
        [string]$logType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$logType] $message"
    Add-Content -Path $logFilePath -Value $logEntry
}

# Fonction pour exécuter une commande Docker avec timeout et gestion des erreurs
function Invoke-DockerCommand {
  param(
    [string]$command,
    [int]$timeout = $dockerCommandTimeout
  )
  $process = Start-Process -FilePath $dockerExecutable -ArgumentList $command -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\docker_output.txt" -RedirectStandardError "$env:TEMP\docker_error.txt"
    Wait-Process -Id $process.Id -Timeout $timeout -ErrorAction SilentlyContinue | Out-Null

    if($process.ExitCode -ne 0 -or !(Test-Path "$env:TEMP\docker_output.txt") -or !(Test-Path "$env:TEMP\docker_error.txt")){
        Write-Log "La commande Docker a échoué ou un fichier temporaire est manquant." -logType ERROR
        if(Test-Path "$env:TEMP\docker_error.txt"){
            $errorOutput = Get-Content -Path "$env:TEMP\docker_error.txt" -Raw -ErrorAction SilentlyContinue
             if ($errorOutput) {
                Write-Log "Erreur Docker: $errorOutput" -logType ERROR
            }
        }
        return $false
    }

    $output = Get-Content -Path "$env:TEMP\docker_output.txt" -Raw
    $errors = Get-Content -Path "$env:TEMP\docker_error.txt" -Raw

    if ($errors) {
        Write-Log "Erreur Docker: $errors" -logType ERROR
        return $false
    }

    if ($output) {
      Write-Log "Sortie de la commande Docker : $output"
    }

    Remove-Item "$env:TEMP\docker_output.txt", "$env:TEMP\docker_error.txt" -Force -ErrorAction SilentlyContinue
    return $true
}

# --- Script principal ---

# Création du répertoire du fichier journal s'il n'existe pas
$logDir = Split-Path -Path $logFilePath -Parent
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

Write-Log "Début du script de redémarrage du service Docker et du conteneur"

# --- 1. Gestion du service Docker ---

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Log "Le service '$serviceName' n'existe pas." -logType ERROR
    exit 1  # Quitte le script si le service n'existe pas
}

if ($forceServiceRestart -or $service.Status -ne 'Running') {
    Write-Log "Le service Docker n'est pas en cours d'exécution ou un redémarrage forcé est demandé."

    for ($i = 1; $i -le $maxRetriesService; $i++) {
         if($service.Status -eq 'Running'){
            Write-Log "Arrêt du service '$serviceName' (essai $i/$maxRetriesService)..."
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                Write-Log "Attente que '$serviceName' s'arrête..."
                Start-Sleep -Seconds 5 # Attendre un peu pour que le service s'arrête complètement
                if((Get-Service -Name $serviceName).Status -ne 'Stopped'){
                    Write-Log "Le service '$serviceName' ne s'est pas arrêté correctement." -logType WARNING
                }
                else{
                    Write-Log "Service '$serviceName' arrêté avec succès."
                }
            }
            catch {
                Write-Log "Impossible d'arrêter le service '$serviceName': $($_.Exception.Message)" -logType ERROR
            }
        }
        Write-Log "Tentative de démarrage du service '$serviceName' (essai $i/$maxRetriesService)..."
        try {
            Start-Service -Name $serviceName -ErrorAction Stop
            Write-Log "Service '$serviceName' démarré avec succès."
            break  # Sort de la boucle si le démarrage réussit
        }
        catch {
            Write-Log "Impossible de démarrer le service '$serviceName': $($_.Exception.Message)" -logType ERROR
            if ($i -lt $maxRetriesService) {
                Write-Log "Attente de $retryDelayServiceSeconds secondes avant la prochaine tentative..."
                Start-Sleep -Seconds $retryDelayServiceSeconds
            }
        }
    }

    if ((Get-Service $serviceName).Status -ne 'Running') {
        Write-Log "Impossible de démarrer le service '$serviceName' après $maxRetriesService tentatives." -logType ERROR
        # On pourrait ajouter ici une action, comme envoyer un email d'alerte
    }
}
else{
     Write-Log "Le service '$serviceName' est déjà en cours d'exécution."
}

# --- 2. Redémarrage du conteneur ---

# Vérification que le conteneur existe
$containerStatus = & $dockerExecutable inspect --format='{{.State.Status}}' $containerId 2>&1 | Out-String
$containerStatus = $containerStatus.Trim()

if ($containerStatus) {
    Write-Log "Redémarrage du conteneur '$containerId'..."
     if ($containerStatus -eq "running" -and $forceContainerRestart) {
        if (Invoke-DockerCommand "restart $containerId") {
            Write-Log "Conteneur '$containerId' redémarré avec succès."
        }
        else {
            Write-Log "Erreur lors du redémarrage du conteneur '$containerId'." -logType ERROR
        }
     }
     elseif($containerStatus -eq "exited" -or $containerStatus -eq "created" -or $containerStatus -eq "paused"){
        if (Invoke-DockerCommand "start $containerId") {
            Write-Log "Conteneur '$containerId' démarré avec succès."
        }
        else {
            Write-Log "Erreur lors du démarrage du conteneur '$containerId'." -logType ERROR
        }
     }
     elseif($containerStatus -eq 'running'){
        Write-Log "Le conteneur est déjà en cours d'exécution"
     }
}
else {
    Write-Log "Le conteneur avec l'ID '$containerId' n'existe pas." -logType ERROR
}

Write-Log "Fin du script"
exit 0