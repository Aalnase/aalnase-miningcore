using Miningcore.Persistence.Postgres;
using Xunit;

namespace Miningcore.Tests.Persistence.Postgres;

public class PostgresVersionTests
{
    [Theory]
    [InlineData("180000")]
    [InlineData("180001")]
    [InlineData("190000")]
    public void IsSupportedServerVersionAcceptsPostgres18OrNewer(string serverVersionNum)
    {
        Assert.True(PostgresVersion.IsSupportedServerVersion(serverVersionNum));
    }

    [Theory]
    [InlineData("170999")]
    [InlineData("160000")]
    [InlineData("")]
    [InlineData("PostgreSQL 17.5")]
    public void IsSupportedServerVersionRejectsOlderOrInvalidVersions(string serverVersionNum)
    {
        Assert.False(PostgresVersion.IsSupportedServerVersion(serverVersionNum));
    }

    [Theory]
    [InlineData("180000", 18, 0)]
    [InlineData("180004", 18, 0)]
    [InlineData("190123", 19, 1)]
    public void ParseServerVersionNumConvertsPostgresVersionNumber(string serverVersionNum, int expectedMajor, int expectedMinor)
    {
        var version = PostgresVersion.ParseServerVersionNum(serverVersionNum);

        Assert.NotNull(version);
        Assert.Equal(expectedMajor, version!.Major);
        Assert.Equal(expectedMinor, version.Minor);
    }
}
