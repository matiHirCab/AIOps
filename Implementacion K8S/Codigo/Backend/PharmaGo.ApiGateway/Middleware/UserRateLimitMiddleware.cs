using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Primitives;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace PharmaGo.ApiGateway.Middleware
{
    /// <summary>
    /// Fixed window rate limiting by authenticated user, with IP fallback for public endpoints.
    /// </summary>
    public class UserRateLimitMiddleware
    {
        private readonly RequestDelegate _next;
        private readonly IMemoryCache _cache;
        private readonly ILogger<UserRateLimitMiddleware> _logger;
        private readonly IConfiguration _configuration;

        public UserRateLimitMiddleware(
            RequestDelegate next,
            IMemoryCache cache,
            ILogger<UserRateLimitMiddleware> logger,
            IConfiguration configuration)
        {
            _next = next;
            _cache = cache;
            _logger = logger;
            _configuration = configuration;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            if (IsWhitelisted(context))
            {
                await _next(context);
                return;
            }

            var identifier = GetUserIdentifier(context);

            if (!CheckRateLimit(identifier, out var reason))
            {
                _logger.LogWarning("Rate limit exceeded for {Identifier}: {Reason}", identifier, reason);

                context.Response.StatusCode = (int)HttpStatusCode.TooManyRequests;
                context.Response.Headers["X-RateLimit-Reason"] = reason;
                context.Response.Headers["Retry-After"] = "60";
                await context.Response.WriteAsJsonAsync(new
                {
                    error = "Too many requests",
                    message = reason,
                    retryAfter = "60 seconds"
                });
                return;
            }

            await _next(context);
        }

        private bool IsWhitelisted(HttpContext context)
        {
            if (HttpMethods.IsOptions(context.Request.Method))
            {
                return true;
            }

            var path = context.Request.Path.Value ?? "/";
            var whitelist = _configuration
                .GetSection("RateLimiting:UserEndpointWhitelist")
                .Get<string[]>() ?? Array.Empty<string>();

            return whitelist.Any(pattern => MatchesEndpoint(pattern, path));
        }

        private static bool MatchesEndpoint(string pattern, string path)
        {
            if (string.IsNullOrWhiteSpace(pattern))
            {
                return false;
            }

            if (pattern.EndsWith("/*", StringComparison.Ordinal))
            {
                var prefix = pattern[..^1];
                return path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
            }

            return string.Equals(pattern, path, StringComparison.OrdinalIgnoreCase);
        }

        private string GetUserIdentifier(HttpContext context)
        {
            if (context.Request.Headers.TryGetValue("Authorization", out var authHeader)
                && TryGetBearerToken(authHeader, out var token))
            {
                return $"user:token:{HashIdentifier(token)}";
            }

            if (context.Request.Headers.TryGetValue("X-User-Id", out var userId)
                && !StringValues.IsNullOrEmpty(userId))
            {
                return $"user:{userId}";
            }

            return $"ip:{GetClientIp(context)}";
        }

        private static bool TryGetBearerToken(StringValues authHeader, out string token)
        {
            var value = authHeader.ToString();
            const string bearerPrefix = "Bearer ";

            if (value.StartsWith(bearerPrefix, StringComparison.OrdinalIgnoreCase))
            {
                token = value[bearerPrefix.Length..].Trim();
                return !string.IsNullOrWhiteSpace(token);
            }

            token = string.Empty;
            return false;
        }

        private static string GetClientIp(HttpContext context)
        {
            if (context.Request.Headers.TryGetValue("X-Forwarded-For", out var forwardedFor))
            {
                var firstForwardedIp = forwardedFor.ToString().Split(',')[0].Trim();
                if (!string.IsNullOrWhiteSpace(firstForwardedIp))
                {
                    return firstForwardedIp;
                }
            }

            if (context.Request.Headers.TryGetValue("X-Real-IP", out var realIp)
                && !StringValues.IsNullOrEmpty(realIp))
            {
                return realIp.ToString();
            }

            return context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        }

        private static string HashIdentifier(string value)
        {
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
            return Convert.ToHexString(bytes);
        }

        private bool CheckRateLimit(string identifier, out string reason)
        {
            var now = DateTime.UtcNow;
            var maxRequestsPerMinute = _configuration.GetValue("RateLimiting:MaxRequestsPerMinute", 100);
            var maxRequestsPerHour = _configuration.GetValue("RateLimiting:MaxRequestsPerHour", 1000);

            var minuteKey = $"{identifier}:minute:{now:yyyyMMddHHmm}";
            var minuteCount = _cache.GetOrCreate(minuteKey, entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1);
                return 0;
            });

            if (minuteCount >= maxRequestsPerMinute)
            {
                reason = $"Exceeded {maxRequestsPerMinute} requests per minute";
                return false;
            }

            var hourKey = $"{identifier}:hour:{now:yyyyMMddHH}";
            var hourCount = _cache.GetOrCreate(hourKey, entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1);
                return 0;
            });

            if (hourCount >= maxRequestsPerHour)
            {
                reason = $"Exceeded {maxRequestsPerHour} requests per hour";
                return false;
            }

            _cache.Set(minuteKey, minuteCount + 1, TimeSpan.FromMinutes(1));
            _cache.Set(hourKey, hourCount + 1, TimeSpan.FromHours(1));

            reason = string.Empty;
            return true;
        }
    }

    public static class UserRateLimitMiddlewareExtensions
    {
        public static IApplicationBuilder UseUserRateLimit(this IApplicationBuilder builder)
        {
            return builder.UseMiddleware<UserRateLimitMiddleware>();
        }
    }
}
