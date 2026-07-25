using Dapper;
using Miningcore.Extensions;
using Miningcore.Mining;

namespace Miningcore.Persistence.Postgres;

internal static class PostgresVersion
{
    public const int MinimumSupportedServerVersionNum = 180000;
    public static readonly Version MinimumSupportedVersion = new(18, 0);

    public static bool IsSupportedServerVersion(string serverVersionNum)
    {
        if(!int.TryParse(serverVersionNum, out var parsedVersion))
            return false;

        return parsedVersion >= MinimumSupportedServerVersionNum;
    }

    public static Version ParseServerVersionNum(string serverVersionNum)
    {
        if(!int.TryParse(serverVersionNum, out var parsedVersion))
            return null;

        var major = parsedVersion / 10000;
        var minor = parsedVersion / 100 % 100;
        return new Version(major, minor);
    }

    public static async Task EnsureSupportedServerVersionAsync(IConnectionFactory cf)
    {
        const string query = "SHOW server_version_num";
        var serverVersionNum = await cf.Run(async con => await con.ExecuteScalarAsync<string>(query));

        if(IsSupportedServerVersion(serverVersionNum))
            return;

        var parsedVersion = ParseServerVersionNum(serverVersionNum);
        var versionText = parsedVersion?.ToString() ?? serverVersionNum ?? "unknown";

        throw new PoolStartupException($"PostgreSQL {MinimumSupportedVersion} or newer is required. Connected server reports version {versionText} (server_version_num={serverVersionNum ?? "unknown"}).");
    }
}
