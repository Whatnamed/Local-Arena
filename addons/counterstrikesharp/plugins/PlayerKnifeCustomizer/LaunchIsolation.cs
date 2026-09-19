using System.Text.Json;

namespace PlayerKnifeCustomizer;

/// <summary>
/// Reads the launch-isolation handshake the Panel leaves next to this plugin and,
/// from it, knows which file and which search-path lines it is allowed to rewrite.
/// Without a marker nothing here is authorised to touch gameinfo.gi, so a foreign
/// MetaMod installation is never cleaned up by us.
/// </summary>
public sealed record PanelIsolationMarker(
    string GameinfoPath,
    IReadOnlyList<string> SearchPaths,
    long? TicketExpiresAtUnix)
{
    public const string MarkerFileName = "panel_isolation.json";

    public bool HasLiveTicket(long nowUnix) =>
        TicketExpiresAtUnix.HasValue && TicketExpiresAtUnix.Value > nowUnix;

    public static bool TryRead(string json, out PanelIsolationMarker? marker)
    {
        marker = null;
        try
        {
            using var document = JsonDocument.Parse(json);
            if (!document.RootElement.TryGetProperty("gameinfo", out var gameinfo) ||
                gameinfo.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(gameinfo.GetString()))
                return false;
            if (!document.RootElement.TryGetProperty("search_paths", out var paths) ||
                paths.ValueKind != JsonValueKind.Array)
                return false;
            var entries = paths.EnumerateArray()
                .Where(entry => entry.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(entry.GetString()))
                .Select(entry => entry.GetString()!)
                .ToList();
            if (entries.Count == 0) return false;
            long? expiresAt = null;
            if (document.RootElement.TryGetProperty("ticket", out var ticket) &&
                ticket.ValueKind == JsonValueKind.Object &&
                ticket.TryGetProperty("expires_at_unix", out var expiry) &&
                expiry.TryGetInt64(out var parsed))
                expiresAt = parsed;
            marker = new PanelIsolationMarker(gameinfo.GetString()!, entries, expiresAt);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}

/// <summary>
/// Line-scoped removal of this project's SearchPath entries. Mirrors the Panel's
/// Rust implementation in launch_isolation.rs: the file is re-derived from what is
/// on disk, only exact <c>Game &lt;entry&gt;</c> lines that name an owned path are
/// dropped, and the newline style and trailing newline of the original are kept so
/// a Steam-updated gameinfo.gi stays otherwise identical.
/// </summary>
public static class GameinfoIsolation
{
    /// <returns>The text to write back, which may be identical to the input when
    /// this project owns no line in it.</returns>
    public static string StripOwnedPaths(string text, IReadOnlyCollection<string> ownedEntries)
    {
        if (ownedEntries.Count == 0 || text.Length == 0) return text;
        string newline = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        string[] raw = text.Split('\n');
        bool trailingNewline = raw[^1].Length == 0;
        int count = trailingNewline ? raw.Length - 1 : raw.Length;

        var kept = new List<string>(count);
        for (int index = 0; index < count; index++)
        {
            string line = raw[index].EndsWith('\r') ? raw[index][..^1] : raw[index];
            string? value = GamePathValue(line);
            if (value != null && Owned(ownedEntries, value)) continue;
            kept.Add(line);
        }
        string joined = string.Join(newline, kept);
        return trailingNewline ? joined + newline : joined;
    }

    private static bool Owned(IReadOnlyCollection<string> entries, string value)
    {
        foreach (string entry in entries)
            if (string.Equals(value, entry, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static string? GamePathValue(string line)
    {
        int comment = line.IndexOf("//", StringComparison.Ordinal);
        string content = comment >= 0 ? line[..comment] : line;
        string[] fields = content.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length != 2 || !fields[0].Equals("Game", StringComparison.OrdinalIgnoreCase)) return null;
        return fields[1];
    }
}
