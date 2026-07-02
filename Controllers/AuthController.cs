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
            // Prioriser appsettings.json, sinon fallback sur variables d'environnement
            _ldapServer = config["LdapSettings:Server"] ?? Environment.GetEnvironmentVariable("LDAP_SERVER") ?? "";
            _ldapDomain = config["LdapSettings:Domain"] ?? Environment.GetEnvironmentVariable("LDAP_DOMAIN") ?? "";
            _ldapPort = config.GetValue<int>("LdapSettings:Port", 636); // 636 par défaut pour LDAPS
            _ldapUseSsl = config.GetValue<bool>("LdapSettings:UseSsl", true);
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
            try
            {
                string bindDn = $"{username}@{domain}";
                using (var ldapConnection = new LdapConnection(new LdapDirectoryIdentifier(_ldapServer, _ldapPort)))
                {
                    ldapConnection.SessionOptions.SecureSocketLayer = _ldapUseSsl;
                    ldapConnection.AuthType = AuthType.Basic;
                    ldapConnection.SessionOptions.ProtocolVersion = 3;
                    ldapConnection.Credential = new NetworkCredential(bindDn, password);
                    ldapConnection.Bind(); // Teste la connexion

                    _logger.LogInformation("[Linux] Authentification LDAP réussie pour {Username}", username);
                    return true;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Linux] ❌ Erreur LDAP lors de l'authentification de {Username}", username);
                return false;
            }
        }
    
    }

    
    
    public class LoginRequest
    {
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }

}
