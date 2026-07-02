using DotNetEnv; // Nécessite le package DotNetEnv
// Charge le fichier .env si présent (utile en dev)
Env.Load(); 
var builder = WebApplication.CreateBuilder(args);

// Lire les origines autorisées depuis appsettings.json ou variable d'environnement
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? new[] { "*" };

// Ajouter une politique CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAngularApp", policy =>
    {
        if (allowedOrigins.Contains("*"))
        {
            policy.SetIsOriginAllowed(_ => true) // Pour le dev, autorise tout
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        }
        else
        {
            policy.WithOrigins(allowedOrigins) // Pour la prod, restreint aux URLs
                  .AllowAnyHeader()
                  .AllowAnyMethod();
        }
    });
});

builder.Services.AddControllers();
var app = builder.Build();

// Utiliser la politique CORS
app.UseCors("AllowAngularApp");

app.MapControllers();
app.Run();
