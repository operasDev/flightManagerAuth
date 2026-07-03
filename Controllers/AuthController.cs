using System.DirectoryServices.AccountManagement;
using System.DirectoryServices.Protocols;
using System.Net;
using Microsoft.AspNetCore.Mvc;
using System.Runtime.InteropServices; // Pour détecter l'OS

namespace FlightManagerApp.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly string _ldapServer;
        private readonly string _ldapDomain;
        private readonly int _ldapPort;
        private readonly bool _ldapUseSsl;
        private readonly ILogger<AuthController> _logger;

        public AuthController(IConfiguration config, ILogger<AuthController> logger)
        {
            _logger = logger;
            // Prioriser les variables d'environnement, sinon fallback sur appsettings.json
            _ldapServer = Environment.GetEnvironmentVariable("LDAP_SERVER") ?? config["LdapSettings:Server"] ?? "";
            _ldapDomain = Environment.GetEnvironmentVariable("LDAP_DOMAIN") ?? config["LdapSettings:Domain"] ?? "";
            _ldapPort = config.GetValue<int>("LdapSettings:Port", 389);
            _ldapUseSsl = config.GetValue<bool>("LdapSettings:UseSsl", false);
        }
        [HttpPost("login")]
        [Consumes("application/json")]
        public IActionResult Authenticate([FromBody] LoginRequest request)
        {
            bool isAuthenticated = AuthenticateUser(_ldapDomain, request.Username, request.Password);
            if (isAuthenticated)
            {
                return Ok(new { success = true, message = "Authentification réussie." });
            }
            return Unauthorized(new { success = false, message = "Le mot de pass ou le username est incorrect! " });
        }

        private bool AuthenticateUser(string domain, string username, string password)
        {
            if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password))
            {
                _logger.LogWarning("Tentative d'authentification avec nom d'utilisateur ou mot de passe vide.");
                return false;
            }

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                return AuthenticateWithWindows(domain, username, password);
            }
            else
            {
                return AuthenticateWithLdap(domain, username, password);
            }
        }

        private bool  AuthenticateWithWindows(string domain, string username, string password){
        try
            {
                using (var context = new PrincipalContext(ContextType.Domain, domain))
                {
                    return context.ValidateCredentials(username, password);
                }
            }
            catch(Exception ex)
            {
                _logger.LogError(ex, "Erreur lors de l'authentification Windows de {Username}", username);
                return false;
            }
        }

        private bool AuthenticateWithLdap(string domain, string username, string password)
        {
            // Essayer plusieurs formats de nom d'utilisateur car Linux est très strict sur le format LDAP
            string[] formatsToTry = new string[] 
            { 
                $"{username}@{domain}", // Format UPN (ex: hkoffi@edv-ops.com)
                $"{domain}\\{username}", // Format NT4 (ex: edv-ops.com\hkoffi)
                domain.Split('.')[0] + $"\\{username}", // Format NetBIOS (ex: edv-ops\hkoffi)
                username // Juste le nom d'utilisateur
            };

            foreach (var bindFormat in formatsToTry)
            {
                try
                {
                    using (var ldapConnection = new LdapConnection(new LdapDirectoryIdentifier(_ldapServer, _ldapPort)))
                    {
                        ldapConnection.SessionOptions.SecureSocketLayer = _ldapUseSsl;
                        ldapConnection.AuthType = AuthType.Basic;
                        ldapConnection.SessionOptions.ProtocolVersion = 3;
                        ldapConnection.Credential = new NetworkCredential(bindFormat, password);
                        ldapConnection.Bind(); // Teste la connexion

                        _logger.LogInformation("[Linux] Authentification LDAP réussie pour {Username} avec le format {Format}", username, bindFormat);
                        return true;
                    }
                }
                catch (LdapException ex) when (ex.ErrorCode == 49) // 49 = Invalid Credentials
                {
                    _logger.LogWarning("[Linux] Format LDAP {Format} rejeté (Credentials Invalid). Essai du suivant...", bindFormat);
                    continue; // Try next format
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "[Linux] Échec avec le format {Format}", bindFormat);
                    // On continue d'essayer les autres formats même s'il y a une autre erreur
                }
            }

            _logger.LogError("[Linux] ❌ Tous les formats de connexion LDAP ont échoué pour {Username}", username);
            return false;
        }
    
    }

    
    
    public class LoginRequest
    {
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }

}
