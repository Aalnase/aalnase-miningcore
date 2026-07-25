using Miningcore.Native;

namespace Miningcore.Crypto.Hashing.Algorithms;

[Identifier("lyra2-rev2")]
public unsafe class Lyra2Rev2 : IHashAlgorithm
{
    public void Digest(ReadOnlySpan<byte> data, Span<byte> result, params object[] extra)
    {
        throw new NotSupportedException("Lyra2REv2 is intentionally unsupported in this Aalnase fork. coins.json keeps legacy examples, but Monacoin/Verge-Lyra pools must not be enabled unless Lyra2REv2 is restored and re-verified.");
    }
}
