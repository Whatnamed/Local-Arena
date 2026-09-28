namespace PlayerKnifeCustomizer;

// Shortcut application is synchronous; only repeated key commands need suppression.
public sealed class KnifeShortcutDebounce
{
    private readonly Dictionary<nint, (uint Pawn, int Team, DateTimeOffset Until)> _last = new();

    public bool TryAcquire(nint player, uint pawn, int team, DateTimeOffset now)
    {
        if (player == nint.Zero || pawn == 0) return false;
        if (_last.TryGetValue(player, out var previous) && previous.Pawn == pawn &&
            previous.Team == team && now < previous.Until) return false;
        _last[player] = (pawn, team, now.AddMilliseconds(250));
        return true;
    }

    public void Cancel(nint player) => _last.Remove(player);
    public void CancelAll() => _last.Clear();
}
