using Miningcore.Native;

namespace Miningcore.Crypto.Hashing.Algorithms;

[Identifier("lyra2-rev3")]
public unsafe class Lyra2Rev3 : IHashAlgorithm
{
    public void Digest(ReadOnlySpan<byte> data, Span<byte> result, params object[] extra)
    {
        throw new NotSupportedException("Lyra2REv3 is intentionally unsupported in this Aalnase fork. coins.json keeps legacy examples, but Lyra2REv3 pools must not be enabled unless Lyra2REv3 is restored and re-verified.");
    }
}
