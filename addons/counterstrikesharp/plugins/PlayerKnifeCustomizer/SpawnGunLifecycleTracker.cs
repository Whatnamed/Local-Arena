namespace PlayerKnifeCustomizer;

public enum SpawnGunRefreshState
{
    Idle,
    Pending,
    Settling,
    Running,
    Completed,
    NoWork
}

public enum SettlementAction
{
    WaitKnifeBusy,
    StartRunning,
    RetryLater,
    MarkNoWork
}

public static class EconReadinessPolicy
{
    public const int MaxRetries = 3;
    public const float RetryDelay = 0.05f;

    public static bool ShouldRetry(bool isReady, int currentRetryCount) =>
        !isReady && currentRetryCount < MaxRetries;
}

public sealed class SpawnGunLifecycleTracker
{
    public sealed class PlayerState
    {
        public long SpawnRevision { get; set; }
        public SpawnGunRefreshState State { get; set; } = SpawnGunRefreshState.Idle;
        public nint PawnHandle { get; set; }
        public uint PawnRawHandle { get; set; }
        public int Team { get; set; }
        public ulong SteamId { get; set; }
        public long ConfigRevision { get; set; }
        public int SettlementAttempts { get; set; }
        public bool SettlementScheduled { get; set; }
    }

    private readonly Dictionary<nint, PlayerState> _states = new();
    private long _nextSpawnRevision;

    public long NextSpawnRevision => _nextSpawnRevision;
    public int ActiveCount => _states.Count;

    public long OnPlayerSpawn(nint playerHandle)
    {
        if (playerHandle == nint.Zero) return 0;
        long revision = ++_nextSpawnRevision;
        _states[playerHandle] = new PlayerState
        {
            SpawnRevision = revision,
            State = SpawnGunRefreshState.Pending,
            PawnHandle = nint.Zero,
            PawnRawHandle = 0,
            Team = 0,
            SteamId = 0,
            ConfigRevision = 0,
            SettlementAttempts = 0,
            SettlementScheduled = false
        };
        return revision;
    }

    public long GetSpawnRevision(nint playerHandle) =>
        _states.TryGetValue(playerHandle, out var state) ? state.SpawnRevision : 0;

    public SpawnGunRefreshState GetState(nint playerHandle) =>
        _states.TryGetValue(playerHandle, out var state) ? state.State : SpawnGunRefreshState.Idle;

    public bool TryBindAuthoritativePawn(
        nint playerHandle,
        long spawnRevision,
        nint pawnHandle,
        uint pawnRawHandle,
        int team,
        ulong steamId,
        long configRevision,
        bool hasConfiguredGunPresets)
    {
        if (playerHandle == nint.Zero || pawnHandle == nint.Zero || pawnRawHandle == 0)
            return false;

        if (!_states.TryGetValue(playerHandle, out var state) || state.SpawnRevision != spawnRevision)
            return false;

        if (!hasConfiguredGunPresets)
        {
            state.State = SpawnGunRefreshState.NoWork;
            return false;
        }

        if (state.State == SpawnGunRefreshState.Pending)
        {
            state.PawnHandle = pawnHandle;
            state.PawnRawHandle = pawnRawHandle;
            state.Team = team;
            state.SteamId = steamId;
            state.ConfigRevision = configRevision;
            state.State = SpawnGunRefreshState.Settling;
            state.SettlementAttempts = 0;
            return true;
        }

        if (state.State == SpawnGunRefreshState.Settling)
        {
            if (state.PawnHandle == pawnHandle &&
                state.PawnRawHandle == pawnRawHandle &&
                state.Team == team &&
                state.SteamId == steamId &&
                state.ConfigRevision == configRevision)
            {
                return true;
            }
            Invalidate(playerHandle);
            return false;
        }

        return false;
    }

    public bool TryScheduleSettlement(nint playerHandle, long spawnRevision)
    {
        if (_states.TryGetValue(playerHandle, out var state) &&
            state.SpawnRevision == spawnRevision &&
            state.State == SpawnGunRefreshState.Settling &&
            !state.SettlementScheduled)
        {
            state.SettlementScheduled = true;
            return true;
        }
        return false;
    }

    public bool CanAttemptSettlement(
        nint playerHandle,
        long spawnRevision,
        uint pawnRawHandle,
        int team,
        ulong steamId,
        long configRevision)
    {
        return _states.TryGetValue(playerHandle, out var state) &&
               state.SpawnRevision == spawnRevision &&
               state.State == SpawnGunRefreshState.Settling &&
               state.PawnRawHandle == pawnRawHandle &&
               state.Team == team &&
               state.SteamId == steamId &&
               state.ConfigRevision == configRevision;
    }

    public SettlementAction EvaluateSettlement(
        nint playerHandle,
        long spawnRevision,
        uint pawnRawHandle,
        int team,
        ulong steamId,
        long configRevision,
        bool isKnifeBusy,
        bool hasMatchingConfiguredGuns,
        bool isFinalAttempt)
    {
        if (!CanAttemptSettlement(playerHandle, spawnRevision, pawnRawHandle, team, steamId, configRevision))
            return SettlementAction.RetryLater;

        if (isKnifeBusy)
            return SettlementAction.WaitKnifeBusy;

        if (hasMatchingConfiguredGuns)
        {
            if (TryStartRunning(playerHandle, spawnRevision))
                return SettlementAction.StartRunning;
            return SettlementAction.RetryLater;
        }

        if (isFinalAttempt)
        {
            MarkNoWork(playerHandle, spawnRevision);
            return SettlementAction.MarkNoWork;
        }

        return SettlementAction.RetryLater;
    }

    public bool TryStartRunning(nint playerHandle, long spawnRevision)
    {
        if (_states.TryGetValue(playerHandle, out var state) &&
            state.SpawnRevision == spawnRevision &&
            state.State == SpawnGunRefreshState.Settling)
        {
            state.State = SpawnGunRefreshState.Running;
            return true;
        }
        return false;
    }

    public void MarkNoWork(nint playerHandle, long spawnRevision)
    {
        if (_states.TryGetValue(playerHandle, out var state) &&
            state.SpawnRevision == spawnRevision &&
            state.State == SpawnGunRefreshState.Settling)
        {
            state.State = SpawnGunRefreshState.NoWork;
        }
    }

    public void Complete(nint playerHandle, long spawnRevision)
    {
        if (_states.TryGetValue(playerHandle, out var state) &&
            state.SpawnRevision == spawnRevision &&
            state.State == SpawnGunRefreshState.Running)
        {
            state.State = SpawnGunRefreshState.Completed;
        }
    }

    public void Invalidate(nint playerHandle)
    {
        _states.Remove(playerHandle);
    }

    public void InvalidateAll()
    {
        _states.Clear();
    }
}
