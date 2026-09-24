namespace PlayerKnifeCustomizer;

// One knife mutation/refresh at a time per player, with a short command debounce.
public sealed class KnifeRefreshGate
{
    private sealed class State
    {
        public required uint Pawn { get; init; }
        public required int Team { get; init; }
        public required long Revision { get; init; }
        public required DateTimeOffset NextAllowed { get; init; }
        public bool Busy { get; set; } = true;
    }

    private readonly Dictionary<nint, State> _states = new();
    private long _nextRevision;

    public bool TryBegin(nint player, uint pawn, int team, DateTimeOffset now, out long revision)
    {
        revision = 0;
        if (player == nint.Zero || pawn == 0) return false;
        if (_states.TryGetValue(player, out var previous) &&
            previous.Pawn == pawn && previous.Team == team &&
            (previous.Busy || now < previous.NextAllowed))
            return false;

        revision = ++_nextRevision;
        _states[player] = new State
        {
            Pawn = pawn, Team = team, Revision = revision,
            NextAllowed = now.AddMilliseconds(350),
        };
        return true;
    }

    public bool IsBusy(nint player) =>
        _states.TryGetValue(player, out var state) && state.Busy;

    public bool IsCurrent(nint player, uint pawn, int team, long revision) =>
        _states.TryGetValue(player, out var state) && state.Busy &&
        state.Revision == revision && state.Pawn == pawn && state.Team == team;

    public void Complete(nint player, long revision)
    {
        if (_states.TryGetValue(player, out var state) && state.Revision == revision)
            state.Busy = false;
    }

    public void Cancel(nint player) => _states.Remove(player);
    public void CancelAll() => _states.Clear();
}
