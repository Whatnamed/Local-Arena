using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Threading;
using CounterStrikeSharp.API;
using CounterStrikeSharp.API.Core;
using CounterStrikeSharp.API.Core.Attributes.Registration;
using CounterStrikeSharp.API.Modules.Commands;
using CounterStrikeSharp.API.Modules.Memory;
using CounterStrikeSharp.API.Modules.Memory.DynamicFunctions;
using CounterStrikeSharp.API.Modules.Timers;
using CounterStrikeSharp.API.Modules.Utils;
using Microsoft.Extensions.Logging;

namespace PlayerKnifeCustomizer;

public readonly record struct StickerAttribute(string Name, float Value);
public readonly record struct CharmNativePlacement(uint PlacementId, float X, float Y, float Z);

public static class PresetWearClamp
{
    /// <summary>Returns true when the preset had to be moved inside its band.</summary>
    public static bool Clamp(KnifePreset preset, WeaponSkinEntry? skin)
    {
        if (skin is null) return false;
        float clamped = Math.Clamp(preset.Wear, skin.MinWear, skin.MaxWear);
        if (clamped.Equals(preset.Wear)) return false;
        preset.Wear = clamped;
        return true;
    }
}

/// <summary>
/// The one CounterStrikeSharp setting this runtime cannot work without. Guideline
/// mode blocks every economic item field a cosmetic preset writes — the entity
/// quality, the fallback paint kit, seed and wear, the item id and the initialized
/// flag — so knives, gloves and guns all need it disabled. The Panel reconciles the
/// setting before it launches a local cosmetics session; this class only reads it,
/// because a Mod that started without a Panel launch must say why it stays inert.
/// </summary>
public static class CosmeticRuntimeRequirement
{
    public const string GuidelineSettingName = "FollowCS2ServerGuidelines";

    /// <summary>The setting as CounterStrikeSharp reads it, or null when the file is
    /// absent, unparsable, or holds a non-boolean value. CounterStrikeSharp defaults
    /// the setting to enabled when it has no configuration file, so null is not safe.</summary>
    public static bool? ReadGuidelineSetting(string coreJsonPath)
    {
        if (!File.Exists(coreJsonPath)) return null;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(coreJsonPath));
            if (!document.RootElement.TryGetProperty(GuidelineSettingName, out var setting)) return null;
            return setting.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                _ => null,
            };
        }
        catch (JsonException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    public static bool AllowsCosmeticWrites(bool? followCs2ServerGuidelines) => followCs2ServerGuidelines == false;

    public static string BlockReason(bool? followCs2ServerGuidelines) => followCs2ServerGuidelines switch
    {
        true => $"{GuidelineSettingName} is enabled, so CounterStrikeSharp refuses the economic item fields cosmetics write. Launch CS2 from the Local Cosmetics Panel, or set {GuidelineSettingName} to false in addons/counterstrikesharp/configs/core.json.",
        null => $"{GuidelineSettingName} could not be read from addons/counterstrikesharp/configs/core.json, so CounterStrikeSharp keeps its safe default and refuses the economic item fields cosmetics write. Launch CS2 from the Local Cosmetics Panel.",
        _ => $"{GuidelineSettingName} holds a value that is not a boolean, so CounterStrikeSharp keeps its safe default and refuses the economic item fields cosmetics write.",
    };
}

/// <summary>
/// Rotation rules for the optional quick-knife command. The list is user ordered
/// and each knife keeps its own saved preset, so advancing the rotation only
/// moves which defindex is the team's default knife.
/// </summary>
public static class KnifeShortcutPolicy
{
    public const int MaxShortcuts = 16;

    public static bool TryAdvance(
        bool enabled,
        IReadOnlyCollection<ushort> shortcuts,
        ushort current,
        out ushort next)
    {
        next = 0;
        if (!enabled || shortcuts.Count == 0) return false;
        int index = -1;
        int position = 0;
        foreach (ushort defIndex in shortcuts)
        {
            if (defIndex == current) { index = position; break; }
            position++;
        }
        next = index < 0
            ? shortcuts.First()
            : shortcuts.ElementAt((index + 1) % shortcuts.Count);
        return next != 0;
    }
}

public static class StickerFailurePolicy
{
    public static bool ShouldRestoreBaseSkin(bool stickerApplySucceeded) => !stickerApplySucceeded;
}

public static class StickerAttributePlanner
{
    public static float EncodeUInt32(uint value) => BitConverter.Int32BitsToSingle(unchecked((int)value));

    public static bool TryBuild(
        ushort defIndex,
        bool enabled,
        IEnumerable<StickerPreset>? stickers,
        IReadOnlySet<uint> validIds,
        IReadOnlyDictionary<ushort, uint> schemaCounts,
        out List<StickerAttribute> attributes,
        out string error)
    {
        attributes = new List<StickerAttribute>();
        error = string.Empty;
        var ordered = (stickers ?? []).OrderBy(sticker => sticker.Slot).ToArray();
        if (ordered.Length == 0) return true;
        if (defIndex is >= 500 and <= 526)
            return Fail("knife stickers are not supported", out error);
        if (ordered.Length > 5)
            return Fail("a weapon cannot have more than five stickers", out error);
        if (!schemaCounts.TryGetValue(defIndex, out uint schemaCount) || schemaCount == 0)
            return Fail("stickers are not supported for this weapon", out error);
        if (!enabled) return true;

        var slots = new HashSet<byte>();
        foreach (var sticker in ordered)
        {
            if (sticker.Slot > 4 || !slots.Add(sticker.Slot))
                return Fail("sticker slots must be unique and between 0 and 4", out error);
            if (sticker.Id == 0 || !validIds.Contains(sticker.Id))
                return Fail("unknown sticker id", out error);
            if (sticker.Schema >= schemaCount)
                return Fail("sticker schema is not supported for this weapon", out error);
            if (!float.IsFinite(sticker.Wear) || sticker.Wear is < 0f or > 1f ||
                !float.IsFinite(sticker.Scale) || sticker.Scale is < 0.1f or > 2f ||
                !float.IsFinite(sticker.Rotation) || sticker.Rotation is < 0f or > 360f ||
                !float.IsFinite(sticker.OffsetX) || sticker.OffsetX is < -1f or > 1f ||
                !float.IsFinite(sticker.OffsetY) || sticker.OffsetY is < -1f or > 1f)
                return Fail("sticker values are outside the supported range", out error);

            string prefix = $"sticker slot {sticker.Slot}";
            attributes.Add(new StickerAttribute($"{prefix} id", EncodeUInt32(sticker.Id)));
            attributes.Add(new StickerAttribute($"{prefix} schema", EncodeUInt32(sticker.Schema)));
            if (sticker.CustomPosition)
            {
                attributes.Add(new StickerAttribute($"{prefix} offset x", sticker.OffsetX));
                attributes.Add(new StickerAttribute($"{prefix} offset y", sticker.OffsetY));
            }
            attributes.Add(new StickerAttribute($"{prefix} wear", sticker.Wear));
            attributes.Add(new StickerAttribute($"{prefix} scale", sticker.Scale));
            attributes.Add(new StickerAttribute($"{prefix} rotation", sticker.Rotation));
        }
        return true;

        static bool Fail(string message, out string target)
        {
            target = message;
            return false;
        }
    }
}

public static class CharmAttributePlanner
{
    public static bool TryBuild(
        ushort defIndex,
        bool enabled,
        CharmPreset? charm,
        IReadOnlySet<uint> validIds,
        IReadOnlyDictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>> placements,
        out List<StickerAttribute> attributes,
        out string error)
    {
        attributes = new List<StickerAttribute>();
        error = string.Empty;
        if (charm == null) return true;
        if (defIndex is >= 500 and <= 526)
            return Fail("knife charms are not supported", out error);
        if (!placements.TryGetValue(defIndex, out var weaponPlacements))
            return Fail("charms are not supported for this weapon", out error);
        if (!enabled) return true;
        if (charm.Id == 0 || !validIds.Contains(charm.Id))
            return Fail("unknown charm id", out error);
        if (charm.Seed < 0)
            return Fail("charm seed is outside the supported range", out error);
        if (!weaponPlacements.TryGetValue(charm.PlacementId, out var placement))
            return Fail("charm placement is not supported for this weapon", out error);
        if (!float.IsFinite(placement.X) || !float.IsFinite(placement.Y) || !float.IsFinite(placement.Z))
            return Fail("charm placement contains non-finite coordinates", out error);

        const string prefix = "keychain slot 0";
        attributes.Add(new StickerAttribute($"{prefix} id", StickerAttributePlanner.EncodeUInt32(charm.Id)));
        attributes.Add(new StickerAttribute($"{prefix} seed", BitConverter.Int32BitsToSingle(charm.Seed)));
        attributes.Add(new StickerAttribute($"{prefix} offset x", placement.X));
        attributes.Add(new StickerAttribute($"{prefix} offset y", placement.Y));
        attributes.Add(new StickerAttribute($"{prefix} offset z", placement.Z));
        return true;

        static bool Fail(string message, out string target)
        {
            target = message;
            return false;
        }
    }
}

public static class DecorationConfigPolicy
{
    public static bool CanPreserveStickers(
        ushort defIndex,
        bool allowDecorations,
        IReadOnlyCollection<StickerPreset> stickers,
        IReadOnlySet<uint> validIds,
        IReadOnlyDictionary<ushort, uint> schemaCounts)
    {
        if (!allowDecorations) return stickers.Count == 0;
        IReadOnlySet<uint> validationIds = validIds.Count > 0
            ? validIds
            : stickers.Where(sticker => sticker.Id > 0).Select(sticker => sticker.Id).ToHashSet();
        IReadOnlyDictionary<ushort, uint> validationSchemas = schemaCounts.Count > 0
            ? schemaCounts
            : new Dictionary<ushort, uint> { [defIndex] = 64 };
        return StickerAttributePlanner.TryBuild(
            defIndex, true, stickers, validationIds, validationSchemas, out _, out _);
    }

    public static bool CanPreserveCharm(
        ushort defIndex,
        bool allowDecorations,
        CharmPreset? charm,
        IReadOnlySet<uint> validIds,
        IReadOnlyDictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>> placements)
    {
        if (!allowDecorations || charm == null) return false;
        if (validIds.Count == 0 || placements.Count == 0)
            return charm.Id > 0 && charm.Seed >= 0;
        return CharmAttributePlanner.TryBuild(
            defIndex, true, charm, validIds, placements, out _, out _);
    }
}

public static class AgentModelPolicy
{
    public static bool IsAllowed(
        CosmeticTeam team,
        string? model,
        IReadOnlyDictionary<CosmeticTeam, HashSet<string>> validModels) =>
        string.IsNullOrEmpty(model) ||
        validModels.TryGetValue(team, out var teamModels) && teamModels.Contains(model);
}

public sealed class PlayerKnifeCustomizerPlugin : BasePlugin
{
    private static readonly bool DecorationReleaseEnabled = true;

    public override string ModuleName => "PlayerCosmetics";
    public override string ModuleVersion => "0.5.0";
    public override string ModuleAuthor => "CS2BotImproverPlus contributors";
    public override string ModuleDescription => "Applies Panel-defined player cosmetic presets";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        NumberHandling = JsonNumberHandling.AllowReadingFromString,
    };

    private readonly Dictionary<ushort, HashSet<int>> _validPaints = new();
    private readonly HashSet<uint> _validStickers = new();
    private readonly Dictionary<ushort, uint> _stickerSchemaCounts = new();
    private readonly HashSet<uint> _validCharms = new();
    private readonly Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>> _charmPlacements = new();
    private readonly Dictionary<CosmeticTeam, HashSet<string>> _agentModels = new();
    private readonly Dictionary<ushort, List<WeaponSkinEntry>> _skinCatalog = new();
    private readonly HashSet<(ushort DefIndex, int Paint)> _legacyPaints = new();
    private KnifeConfig _config = new();
    private MemoryFunctionVoid<nint, string, float>? _setAttrByName;

    /// <summary>
    /// Set once at load from the CounterStrikeSharp guideline setting. While it is
    /// false, every preset write would throw per weapon, so the pipeline refuses up
    /// front and the reason is logged a single time.
    /// </summary>
    private bool _econWritesAllowed = true;
    private ulong _nextItemId = 0xC5200000;
    private readonly ApplyErrorThrottle _applyErrorThrottle = new(TimeSpan.FromSeconds(30));
    private int _loadedConfigSchema = KnifeConfig.CurrentSchemaVersion;
    private int _loadedGunConfigSchema = KnifeConfig.CurrentSchemaVersion;
    private bool _stickersSanitizedDuringLoad;
    private readonly ApplyGenerationTracker _applyTracker = new();
    private readonly WeaponProvenance _provenance = new();
    private readonly ConfigReloadGate _reloadGate = new(ConfigDebounceMilliseconds);
    private readonly object _debounceLock = new();
    private System.Threading.Timer? _reloadDebounce;
    private FileSystemWatcher? _configWatcher;
    private PanelIsolationMarker? _isolationMarker;
    private bool _panelLaunchSession;
    private bool _unloading;

    /// <summary>
    /// Gun presets to refresh on the next owned-weapon pass. Only the live-reload
    /// path sets it; a grant or spawn pass leaves it empty and applies everything
    /// the player was just given.
    /// </summary>
    private IReadOnlyCollection<ushort> _ownedGunFilter = Array.Empty<ushort>();

    private const int ConfigDebounceMilliseconds = 150;


    private const string ConfigFileName = "player_knife_presets.json";
    private const string GunConfigFileName = "player_gun_presets.json";
    private string ConfigPath => Path.Combine(ModuleDirectory, ConfigFileName);
    private string GunConfigPath => Path.Combine(ModuleDirectory, GunConfigFileName);
    private string CatalogPath => Path.Combine(ModuleDirectory, "weapon_skins.json");
    private string StickerCatalogPath => Path.Combine(ModuleDirectory, "sticker_ids.json");
    private string PlayerCosmeticCatalogPath => Path.Combine(ModuleDirectory, "player_cosmetic_catalog.json");

    /// <summary>CounterStrikeSharp's own configuration, two levels above this plugin directory.</summary>
    private string CoreConfigPath => Path.GetFullPath(Path.Combine(ModuleDirectory, "..", "..", "configs", "core.json"));

    public override void Load(bool hotReload)
    {
        _unloading = false;
        BeginLaunchIsolation();
        LoadCatalog();
        LoadStickerCatalog();
        LoadPlayerCosmeticCatalog();
        LoadConfig();
        StartConfigWatcher();

        AddCommand("css_cs2bi_knives_reload", "Reload player knife presets", OnReloadCommand);
        AddCommand("css_cs2bi_knives_status", "Show player knife preset status", OnStatusCommand);
        AddCommand("css_cs2bi_knife_next", "Switch to the next knife in the configured quick-knife rotation", OnKnifeNextCommand);

        try
        {
            _setAttrByName = new MemoryFunctionVoid<nint, string, float>(
                RuntimeInformation.IsOSPlatform(OSPlatform.Linux)
                    ? "55 48 89 E5 41 57 41 56 49 89 FE 41 55 41 54 53 48 89 F3 48 83 EC ? F3 0F 11 85"
                    : "40 53 55 41 56 48 81 EC 90 00 00 00");
        }
        catch (Exception ex)
        {
            Logger.LogError("[PlayerKnifeCustomizer] Attribute signature unavailable: {Message}", ex.Message);
            _setAttrByName = null;
        }

        var guidelineSetting = CosmeticRuntimeRequirement.ReadGuidelineSetting(CoreConfigPath);
        _econWritesAllowed = CosmeticRuntimeRequirement.AllowsCosmeticWrites(guidelineSetting);
        if (!_econWritesAllowed)
            Logger.LogError("[PlayerKnifeCustomizer] {Reason}",
                CosmeticRuntimeRequirement.BlockReason(guidelineSetting));

        RegisterEventHandler<EventPlayerSpawn>(OnPlayerSpawn);
        RegisterEventHandler<EventRoundMvp>(OnRoundMvp, HookMode.Pre);
        RegisterEventHandler<EventPlayerDeath>(OnPlayerDeath);
        RegisterEventHandler<EventPlayerTeam>(OnPlayerTeam);
        RegisterEventHandler<EventPlayerDisconnect>(OnPlayerDisconnect);
        RegisterEventHandler<EventRoundEnd>(OnRoundEnd);
        RegisterListener<Listeners.OnMapStart>(OnMapStart);
        RegisterListener<Listeners.OnMapEnd>(OnMapEnd);
        VirtualFunctions.GiveNamedItemFunc.Hook(OnGiveNamedItemPost, HookMode.Post);
        Logger.LogInformation("[PlayerKnifeCustomizer] Loaded generation-safe pipeline; enabled={Enabled}, signature={Signature}, catalog={Catalog}, panel_launch={PanelLaunch}, econ_writes={EconWrites}",
            _config.Enabled, _setAttrByName != null, _skinCatalog.Values.Sum(skins => skins.Count), _panelLaunchSession, _econWritesAllowed);
    }

    public override void Unload(bool hotReload)
    {
        _unloading = true;
        _applyTracker.CancelAll();
        StopConfigWatcher();
        VirtualFunctions.GiveNamedItemFunc.Unhook(OnGiveNamedItemPost, HookMode.Post);
        // The Panel keeps the project search path in gameinfo.gi only for as long
        // as this runtime is up. Restoring on a real shutdown (not on a hot
        // reload) is what makes the next plain Steam launch clean again.
        if (_panelLaunchSession && !hotReload) FinishLaunchIsolation("plugin unload");
        _panelLaunchSession = false;
    }

    private void OnMapEnd()
    {
        _applyTracker.CancelAll();
        _provenance.Clear();
    }

    /// <summary>
    /// Reads and consumes the Panel's one-shot launch ticket. A live ticket means
    /// this runtime was started by an explicit local cosmetics launch, so restoring
    /// <c>gameinfo.gi</c> on shutdown is ours to do. A marker whose ticket is
    /// missing or expired means the opposite: the Mod came up without a Panel
    /// launch, so the search path is a leftover and is cleaned up right away. No
    /// marker at all is never our line to remove, so nothing is touched.
    /// </summary>
    private void BeginLaunchIsolation()
    {
        string markerPath = Path.Combine(ModuleDirectory, PanelIsolationMarker.MarkerFileName);
        try
        {
            if (!File.Exists(markerPath)) return;
            if (!PanelIsolationMarker.TryRead(File.ReadAllText(markerPath), out PanelIsolationMarker? marker) ||
                marker is null)
            {
                Logger.LogWarning("[PlayerCosmetics] Ignoring unreadable launch marker {Path}", markerPath);
                return;
            }
            _isolationMarker = marker;
            File.Delete(markerPath);
            if (!marker.HasLiveTicket(DateTimeOffset.UtcNow.ToUnixTimeSeconds()))
            {
                FinishLaunchIsolation("runtime loaded outside a Panel launch");
                return;
            }
            _panelLaunchSession = true;
        }
        catch (Exception ex)
        {
            Logger.LogError(ex, "[PlayerCosmetics] Launch isolation handshake failed");
        }
    }

    private void FinishLaunchIsolation(string reason)
    {
        PanelIsolationMarker? marker = _isolationMarker;
        _isolationMarker = null;
        if (marker is null) return;
        try
        {
            if (!File.Exists(marker.GameinfoPath)) return;
            string current = File.ReadAllText(marker.GameinfoPath);
            string restored = GameinfoIsolation.StripOwnedPaths(current, marker.SearchPaths);
            if (restored == current) return;
            WriteGameinfoVerified(marker.GameinfoPath, restored);
            Logger.LogInformation("[PlayerCosmetics] Restored clean gameinfo.gi ({Reason})", reason);
        }
        catch (Exception ex)
        {
            Logger.LogError(ex, "[PlayerCosmetics] Could not restore gameinfo.gi; the next launch may load this Mod without the Panel");
        }
    }

    private static void WriteGameinfoVerified(string path, string content)
    {
        string temp = path + ".cs2bi-tmp";
        File.WriteAllText(temp, content);
        File.Move(temp, path, true);
        if (File.ReadAllText(path) != content)
            throw new InvalidDataException($"gameinfo.gi did not read back as written: {path}");
    }

    private void StartConfigWatcher()
    {
        try
        {
            var watcher = new FileSystemWatcher(ModuleDirectory)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
            };
            watcher.Changed += OnConfigFileEvent;
            watcher.Created += OnConfigFileEvent;
            watcher.Renamed += OnConfigFileEvent;
            watcher.EnableRaisingEvents = true;
            _configWatcher = watcher;
        }
        catch (Exception ex)
        {
            Logger.LogError(ex, "[PlayerCosmetics] Live configuration watching is unavailable; presets apply on the next spawn");
        }
    }

    private void StopConfigWatcher()
    {
        FileSystemWatcher? watcher = _configWatcher;
        _configWatcher = null;
        if (watcher is not null)
        {
            watcher.EnableRaisingEvents = false;
            watcher.Changed -= OnConfigFileEvent;
            watcher.Created -= OnConfigFileEvent;
            watcher.Renamed -= OnConfigFileEvent;
            watcher.Dispose();
        }
        lock (_debounceLock)
        {
            _reloadDebounce?.Dispose();
            _reloadDebounce = null;
        }
        _reloadGate.Reset();
    }

    /// <summary>
    /// Raised on a worker thread. It only records that something changed and
    /// restarts the single debounce timer; all file parsing and every entity write
    /// stays on the game thread behind <see cref="Server.NextFrame"/>.
    /// </summary>
    private void OnConfigFileEvent(object sender, FileSystemEventArgs args)
    {
        if (_unloading) return;
        string name = Path.GetFileName(args.Name ?? string.Empty);
        if (!name.Equals(ConfigFileName, StringComparison.OrdinalIgnoreCase) &&
            !name.Equals(GunConfigFileName, StringComparison.OrdinalIgnoreCase))
            return;
        _reloadGate.Signal();
        lock (_debounceLock)
        {
            if (_unloading) return;
            try
            {
                _reloadDebounce ??= new System.Threading.Timer(_ => Server.NextFrame(ReloadIfPending),
                    null, Timeout.Infinite, Timeout.Infinite);
                _reloadDebounce.Change(ConfigDebounceMilliseconds, Timeout.Infinite);
            }
            catch (ObjectDisposedException)
            {
                // Unload won the race; nothing further is scheduled.
            }
        }
    }

    private void ReloadIfPending()
    {
        if (_unloading || !_reloadGate.TryBeginWork()) return;
        ReloadFromDisk();
        if (_reloadGate.HasPendingWork())
        {
            _reloadGate.Signal();
            lock (_debounceLock) _reloadDebounce?.Change(ConfigDebounceMilliseconds, Timeout.Infinite);
        }
    }

    private void ReloadFromDisk()
    {
        var snapshot = new ConfigSnapshot(_config, _loadedConfigSchema, _loadedGunConfigSchema);
        LoadConfig(snapshot);
        if (ReferenceEquals(_config, snapshot.Config)) return;
        CosmeticConfigDiff diff = CosmeticConfigDiff.Compute(snapshot.Config, _config);
        if (diff.ChangesNothing) return;
        _ownedGunFilter = diff.ChangedGunDefIndexes;
        ApplyChangedSections(diff.Sections);
    }

    private void ApplyChangedSections(CosmeticChangeSection sections)
    {
        CosmeticApplyPhase phases = CosmeticApplyPhase.None;
        if (sections.HasFlag(CosmeticChangeSection.Agent)) phases |= CosmeticApplyPhase.Agent;
        if (sections.HasFlag(CosmeticChangeSection.Knife)) phases |= CosmeticApplyPhase.Knife;
        if (sections.HasFlag(CosmeticChangeSection.Gloves)) phases |= CosmeticApplyPhase.Gloves;
        if (sections.HasFlag(CosmeticChangeSection.Guns)) phases |= CosmeticApplyPhase.OwnedGuns;
        if (sections.HasFlag(CosmeticChangeSection.Music)) phases |= CosmeticApplyPhase.Music;
        if (phases == CosmeticApplyPhase.None) return;
        int scheduled = 0;
        foreach (CCSPlayerController player in Utilities.GetPlayers())
        {
            if (!CanApplyToPlayer(player)) continue;
            ScheduleApplyPipeline(player!.Handle, phases);
            scheduled++;
        }
        Logger.LogInformation("[PlayerCosmetics] Applied live configuration change sections={Sections} guns={Guns} players={Players}",
            sections, _ownedGunFilter.Count, scheduled);
    }

    private void OnMapStart(string _)
    {
        _applyTracker.CancelAll();
        if (!_config.Enabled || !_config.AgentsEnabled) return;
        int failures = 0;
        string lastError = string.Empty;
        foreach (string model in _agentModels.Values.SelectMany(models => models))
        {
            try { Server.PrecacheModel(model); }
            catch (Exception ex) { failures++; lastError = ex.Message; }
        }
        if (failures > 0)
            LogApplyError("agent precache", new InvalidOperationException($"{failures} models failed; last error: {lastError}"));
    }

    private HookResult OnGiveNamedItemPost(DynamicHook hook)
    {
        if (_setAttrByName == null || !_config.Enabled) return HookResult.Continue;
        try
        {
            var itemServices = hook.GetParam<CCSPlayer_ItemServices>(0);
            var player = GetPlayerFromItemServices(itemServices);
            if (!CanApplyToPlayer(player)) return HookResult.Continue;
            nint playerHandle = player!.Handle;
            long generation = _applyTracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
            // The returned econ item is not safe for native attribute writes while this hook is active.
            ScheduleApplyCallbacks(playerHandle, generation);
        }
        catch (Exception ex)
        {
            LogApplyError("purchased weapon", ex);
        }
        return HookResult.Continue;
    }

    private static CCSPlayerController? GetPlayerFromItemServices(CCSPlayer_ItemServices itemServices)
    {
        var pawn = itemServices.Pawn.Value;
        if (pawn == null || !pawn.IsValid || pawn.Controller.Value == null || !pawn.Controller.IsValid)
            return null;
        var player = new CCSPlayerController(pawn.Controller.Value.Handle);
        return player.IsValid ? player : null;
    }

    public HookResult OnPlayerSpawn(EventPlayerSpawn @event, GameEventInfo _)
    {
        var player = @event.Userid;
        if (!CanApplyToPlayer(player)) return HookResult.Continue;
        ScheduleApplyPipeline(player!.Handle, CosmeticApplyPhase.All);
        return HookResult.Continue;
    }

    public HookResult OnRoundMvp(EventRoundMvp @event, GameEventInfo _)
    {
        var player = @event.Userid;
        if (!CanApplyToPlayer(player) || _config.MusicKitId <= 0)
            return HookResult.Continue;

        ApplyMusicKit(player!);
        @event.Musickitid = _config.MusicKitId;
        @event.Nomusic = 0;
        return HookResult.Continue;
    }

    private void ApplyMusicKit(CCSPlayerController player)
    {
        if (!CanApplyToPlayer(player) || _config.MusicKitId <= 0)
            return;

        player.MusicKitID = _config.MusicKitId;
        Utilities.SetStateChanged(player, "CCSPlayerController", "m_iMusicKitID");
    }

    public HookResult OnPlayerDeath(EventPlayerDeath @event, GameEventInfo _)
    {
        var attacker = @event.Attacker;
        var victim = @event.Userid;
        if (victim is { IsValid: true } && victim.Handle != nint.Zero)
            _applyTracker.Cancel(victim.Handle);
        if (!CanApplyToPlayer(attacker) || victim == null || !victim.IsValid || attacker == victim)
            return HookResult.Continue;

        var weapon = attacker!.PlayerPawn.Value?.WeaponServices?.ActiveWeapon.Value;
        if (weapon == null || !weapon.IsValid)
            return HookResult.Continue;

        var team = GetCosmeticTeam(attacker);
        if (team == null) return HookResult.Continue;
        ushort defIndex = weapon.AttributeManager?.Item?.ItemDefinitionIndex ?? 0;
        if (!TryGetPreset(defIndex, team.Value, out var preset) || !preset.StatTrakEnabled)
            return HookResult.Continue;

        preset.StatTrakCount++;
        ApplyStatTrak(weapon, preset);
        SaveConfig();
        return HookResult.Continue;
    }

    private HookResult OnPlayerTeam(EventPlayerTeam @event, GameEventInfo _)
    {
        var player = @event.Userid;
        if (CanApplyToPlayer(player))
            ScheduleApplyPipeline(player!.Handle, CosmeticApplyPhase.All);
        return HookResult.Continue;
    }

    private HookResult OnPlayerDisconnect(EventPlayerDisconnect @event, GameEventInfo _)
    {
        var player = @event.Userid;
        if (player != null && player.Handle != nint.Zero)
        {
            _applyTracker.Cancel(player.Handle);
            _provenance.ForgetPlayer(player.Handle);
        }
        return HookResult.Continue;
    }

    private HookResult OnRoundEnd(EventRoundEnd @event, GameEventInfo _)
    {
        _applyTracker.CancelAll();
        return HookResult.Continue;
    }

    private void ScheduleApplyPipeline(nint playerHandle, CosmeticApplyPhase phases)
    {
        if (playerHandle == nint.Zero || phases == CosmeticApplyPhase.None) return;
        long generation = _applyTracker.Begin(playerHandle, phases);
        ScheduleApplyCallbacks(playerHandle, generation);
    }

    private void ScheduleApplyCallbacks(nint playerHandle, long generation)
    {
        Server.NextFrame(() => RunApplyPipeline(playerHandle, generation, false));
        for (int index = 0; index < ApplyPipelineContext.RetryDelays.Length; index++)
        {
            bool finalAttempt = index == ApplyPipelineContext.RetryDelays.Length - 1;
            AddTimer(ApplyPipelineContext.RetryDelays[index],
                () => RunApplyPipeline(playerHandle, generation, finalAttempt),
                TimerFlags.STOP_ON_MAPCHANGE);
        }
    }

    private void RunApplyPipeline(nint playerHandle, long generation, bool finalAttempt)
    {
        if (!_applyTracker.IsCurrent(playerHandle, generation) ||
            !_applyTracker.HasPending(playerHandle, generation))
            return;

        var player = ResolvePlayer(playerHandle);
        if (!CanApplyToPlayer(player))
        {
            if (finalAttempt) _applyTracker.MarkRetryExhausted(playerHandle, generation);
            return;
        }
        var team = GetCosmeticTeam(player);
        var pawn = player!.PlayerPawn.Value;
        if (!ApplyPipelineContext.IsReady(
                player.PawnIsAlive,
                pawn is { IsValid: true },
                pawn?.Handle ?? nint.Zero,
                team))
        {
            if (finalAttempt) _applyTracker.MarkRetryExhausted(playerHandle, generation);
            return;
        }
        var readyPawn = pawn!;
        var readyTeam = team!.Value;
        if (!_applyTracker.TryBindContext(playerHandle, generation, readyPawn.Handle, (int)readyTeam))
            return;

        TryApplyPhase(playerHandle, generation, CosmeticApplyPhase.Agent,
            () => TryApplyAgent(readyPawn, readyTeam), "agent pipeline");
        TryApplyPhase(playerHandle, generation, CosmeticApplyPhase.Knife,
            () => TryApplyDefaultKnife(readyPawn, readyTeam), "knife pipeline");
        TryApplyPhase(playerHandle, generation, CosmeticApplyPhase.Gloves,
            () => TryApplyGlove(playerHandle, readyPawn, readyTeam), "glove pipeline");
        const CosmeticApplyPhase gunPhases = CosmeticApplyPhase.Guns | CosmeticApplyPhase.OwnedGuns;
        bool gunsPending = _applyTracker.IsPending(playerHandle, generation, gunPhases);
        TryApplyPhase(playerHandle, generation, CosmeticApplyPhase.Guns,
            () => TryApplyGunPresets(playerHandle, readyPawn, readyTeam), "gun pipeline");
        TryApplyPhase(playerHandle, generation, CosmeticApplyPhase.OwnedGuns,
            () => TryApplyOwnedGuns(readyPawn, readyTeam, _ownedGunFilter), "owned gun refresh");
        if (gunsPending && !_applyTracker.IsPending(playerHandle, generation, gunPhases))
            TryControlledReequip(player, readyPawn, readyTeam, generation);
        TryApplyPhase(playerHandle, generation, CosmeticApplyPhase.Music,
            () => { ApplyMusicKit(player); return true; }, "music pipeline");
        if (finalAttempt) _applyTracker.MarkRetryExhausted(playerHandle, generation);
    }

    private void TryApplyPhase(nint playerHandle, long generation, CosmeticApplyPhase phase,
        Func<bool> apply, string operation)
    {
        if (!_applyTracker.IsPending(playerHandle, generation, phase)) return;
        try
        {
            if (apply()) _applyTracker.Complete(playerHandle, generation, phase);
        }
        catch (Exception ex)
        {
            LogApplyError(operation, ex);
        }
    }

    private bool TryApplyAgent(CCSPlayerPawn pawn, CosmeticTeam team)
    {
        if (!_config.AgentsEnabled) return true;
        string model = _config.Loadouts.For(team).AgentModel;
        if (string.IsNullOrEmpty(model)) return true;
        if (!AgentModelPolicy.IsAllowed(team, model, _agentModels))
        {
            LogApplyError($"agent for {team}", new InvalidDataException("Agent model is unavailable in the local catalog"));
            return true;
        }
        if (!pawn.IsValid) return false;
        pawn.SetModel(model);
        Utilities.SetStateChanged(pawn, "CBaseModelEntity", "m_clrRender");
        return true;
    }

    private bool TryApplyDefaultKnife(CCSPlayerPawn pawn, CosmeticTeam team)
    {
        var weapons = pawn.WeaponServices?.MyWeapons;
        if (weapons == null) return false;
        var loadout = _config.Loadouts.For(team);

        foreach (var handle in weapons)
        {
            var weapon = handle.Value;
            if (weapon == null || !weapon.IsValid || !IsKnifeName(weapon.DesignerName)) continue;
            var item = weapon.AttributeManager?.Item;
            if (item == null || !HasReadyAttributeLists(item)) return false;

            ushort target = loadout.DefaultKnifeDefIndex;
            if (target > 0 && loadout.KnifePresets.TryGetValue(target, out var targetPreset))
            {
                weapon.AcceptInput("ChangeSubclass", value: target.ToString());
                item.ItemDefinitionIndex = target;
                return ApplyPreset(weapon, target, targetPreset);
            }

            ushort current = item.ItemDefinitionIndex;
            return !TryGetPreset(current, team, out var currentPreset) ||
                   ApplyPreset(weapon, current, currentPreset);
        }

        return false;
    }

    private bool TryApplyGunPresets(nint playerHandle, CCSPlayerPawn pawn, CosmeticTeam team)
    {
        var weapons = pawn.WeaponServices?.MyWeapons;
        if (weapons == null) return false;
        bool ready = true;
        foreach (var handle in weapons)
        {
            var weapon = handle.Value;
            if (weapon == null || !weapon.IsValid || IsKnifeName(weapon.DesignerName)) continue;
            ushort defIndex = weapon.AttributeManager?.Item?.ItemDefinitionIndex ?? 0;
            if (defIndex == 0) continue;
            // A weapon that is in the inventory at spawn, or that GiveNamedItem just
            // handed over, was created for this player. That is what makes a preset
            // apply to it; an entity picked up off the ground is never claimed here.
            _provenance.RecordGrant(playerHandle, weapon.Handle, defIndex, weapon.DesignerName);
            if (!TryGetPreset(defIndex, team, out var preset)) continue;
            if (!ApplyPreset(weapon, defIndex, preset)) ready = false;
        }
        return ready;
    }

    private bool TryApplyOwnedGuns(CCSPlayerPawn pawn, CosmeticTeam team, IReadOnlyCollection<ushort> onlyDefIndexes)
    {
        var weapons = pawn.WeaponServices?.MyWeapons;
        if (weapons == null) return false;
        HashSet<ushort>? filter = onlyDefIndexes as HashSet<ushort> ?? (onlyDefIndexes.Count > 0 ? new HashSet<ushort>(onlyDefIndexes) : null);
        bool ready = true;
        foreach (var handle in weapons)
        {
            var weapon = handle.Value;
            if (weapon == null || !weapon.IsValid || IsKnifeName(weapon.DesignerName)) continue;
            ushort defIndex = weapon.AttributeManager?.Item?.ItemDefinitionIndex ?? 0;
            if (defIndex == 0 || !_provenance.IsOwned(weapon.Handle, defIndex, weapon.DesignerName)) continue;
            if (filter != null && !filter.Contains(defIndex)) continue;
            if (!TryGetPreset(defIndex, team, out var preset)) continue;
            if (!ApplyPreset(weapon, defIndex, preset)) ready = false;
        }
        return ready;
    }

    private void TryControlledReequip(CCSPlayerController player, CCSPlayerPawn pawn, CosmeticTeam team, long generation)
    {
        if (!DecorationReleaseEnabled || (!_config.StickersEnabled && !_config.CharmsEnabled)) return;
        var active = pawn.WeaponServices?.ActiveWeapon.Value;
        if (active == null || !active.IsValid || IsKnifeName(active.DesignerName)) return;
        ushort defIndex = active.AttributeManager?.Item?.ItemDefinitionIndex ?? 0;
        if (!TryGetPreset(defIndex, team, out var preset) || ((preset.Stickers?.Count ?? 0) == 0 && preset.Charm == null)) return;
        if (!_applyTracker.TryMarkReequip(player.Handle, generation)) return;

        player.ExecuteClientCommand("lastinv");
        nint playerHandle = player.Handle;
        Server.NextFrame(() =>
        {
            var current = ResolvePlayer(playerHandle);
            if (CanApplyToPlayer(current)) current!.ExecuteClientCommand("lastinv");
        });
    }

    private bool TryGetPreset(ushort defIndex, CosmeticTeam team, out KnifePreset preset)
    {
        if (IsKnifeDefIndex(defIndex))
            return _config.Loadouts.For(team).KnifePresets.TryGetValue(defIndex, out preset!);
        return WeaponPresetResolver.TryResolveGunPreset(_config, defIndex, team, out preset!);
    }

    private bool ApplyPreset(CBasePlayerWeapon weapon, ushort defIndex, KnifePreset preset)
    {
        if (!_econWritesAllowed || _setAttrByName == null || !weapon.IsValid || !ValidatePreset(defIndex, preset)) return false;

        try
        {
            var item = weapon.AttributeManager?.Item;
            if (item == null || !HasReadyAttributeLists(item)) return false;

            item.ItemDefinitionIndex = defIndex;
            item.EntityQuality = preset.SouvenirEnabled ? (byte)12
                : preset.StatTrakEnabled ? (byte)9 : (byte)3;
            item.CustomName = preset.NameTag ?? string.Empty;
            item.AttributeList.Attributes.RemoveAll();
            item.NetworkedDynamicAttributes.Attributes.RemoveAll();
            AssignItemId(item);

            weapon.FallbackPaintKit = preset.Paint;
            weapon.FallbackSeed = preset.Seed;
            weapon.FallbackWear = preset.Wear;

            SetTextureAttributes(item.NetworkedDynamicAttributes.Handle, preset);
            SetTextureAttributes(item.AttributeList.Handle, preset);
            if (preset.StatTrakEnabled && !preset.SouvenirEnabled) ApplyStatTrak(weapon, preset);
            if (DecorationReleaseEnabled &&
                StickerFailurePolicy.ShouldRestoreBaseSkin(TryApplyDecorations(defIndex, item, preset)))
                RestoreBaseAttributes(weapon, item, preset);

            Utilities.SetStateChanged(weapon, "CEconEntity", "m_AttributeManager");
            bool legacyModel = _legacyPaints.Contains((defIndex, preset.Paint));
            weapon.AcceptInput("SetBodygroup", value: $"body,{(legacyModel ? 1 : 0)}");
            return true;
        }
        catch (Exception ex)
        {
            LogApplyError($"defindex {defIndex}", ex);
            return false;
        }
    }

    private bool TryApplyGlove(nint playerHandle, CCSPlayerPawn pawn, CosmeticTeam team)
    {
        var preset = _config.Loadouts.For(team).Glove;
        if (!preset.Enabled) return true;
        if (!_econWritesAllowed || _setAttrByName == null || preset.DefIndex == 0 || preset.Paint <= 0) return false;

        try
        {
            var item = pawn.EconGloves;
            if (!HasReadyAttributeLists(item)) return false;
            item.NetworkedDynamicAttributes.Attributes.RemoveAll();
            item.AttributeList.Attributes.RemoveAll();
            item.ItemDefinitionIndex = preset.DefIndex;
            AssignItemId(item);

            SetTextureAttributes(item.NetworkedDynamicAttributes.Handle, preset.Paint, preset.Seed, preset.Wear);
            SetTextureAttributes(item.AttributeList.Handle, preset.Paint, preset.Seed, preset.Wear);
            item.Initialized = true;

            pawn.AcceptInput("SetBodygroup", value: "first_or_third_person,0");
            nint pawnHandle = pawn.Handle;
            AddTimer(0.20f, () =>
            {
                if (pawnHandle == nint.Zero) return;
                var player = ResolvePlayer(playerHandle);
                var currentPawn = player?.PlayerPawn.Value;
                if (player?.PawnIsAlive == true && currentPawn is { IsValid: true } && currentPawn.Handle == pawnHandle)
                    currentPawn.AcceptInput("SetBodygroup", value: "first_or_third_person,1");
            }, TimerFlags.STOP_ON_MAPCHANGE);
            return true;
        }
        catch (Exception ex)
        {
            LogApplyError("gloves", ex);
            return false;
        }
    }

    private void SetTextureAttributes(nint handle, KnifePreset preset)
    {
        SetTextureAttributes(handle, preset.Paint, preset.Seed, preset.Wear);
    }

    private void SetTextureAttributes(nint handle, int paint, int seed, float wear)
    {
        if (handle == nint.Zero) return;
        _setAttrByName!.Invoke(handle, "set item texture prefab", paint);
        _setAttrByName.Invoke(handle, "set item texture seed", seed);
        _setAttrByName.Invoke(handle, "set item texture wear", wear);
    }

    private bool TryApplyDecorations(ushort defIndex, CEconItemView item, KnifePreset preset)
    {
        if (!DecorationReleaseEnabled) return true;
        var attributes = new List<StickerAttribute>();
        if (StickerAttributePlanner.TryBuild(
                defIndex, _config.StickersEnabled, preset.Stickers, _validStickers, _stickerSchemaCounts,
                out var stickerAttributes, out string stickerError))
            attributes.AddRange(stickerAttributes);
        else
        {
            LogApplyError($"stickers for defindex {defIndex}", new InvalidDataException(stickerError));
        }
        if (CharmAttributePlanner.TryBuild(
                defIndex, _config.CharmsEnabled, preset.Charm, _validCharms, _charmPlacements,
                out var charmAttributes, out string charmError))
            attributes.AddRange(charmAttributes);
        else
        {
            LogApplyError($"charm for defindex {defIndex}", new InvalidDataException(charmError));
        }
        if (attributes.Count == 0) return true;

        try
        {
            nint handle = item.NetworkedDynamicAttributes.Handle;
            foreach (var attribute in attributes)
                _setAttrByName!.Invoke(handle, attribute.Name, attribute.Value);
            return true;
        }
        catch (Exception ex)
        {
            LogApplyError($"decorations for defindex {defIndex}", ex);
            return false;
        }
    }

    private void RestoreBaseAttributes(CBasePlayerWeapon weapon, CEconItemView item, KnifePreset preset)
    {
        item.AttributeList.Attributes.RemoveAll();
        item.NetworkedDynamicAttributes.Attributes.RemoveAll();
        SetTextureAttributes(item.NetworkedDynamicAttributes.Handle, preset);
        SetTextureAttributes(item.AttributeList.Handle, preset);
        if (preset.StatTrakEnabled && !preset.SouvenirEnabled) ApplyStatTrak(weapon, preset);
    }

    private void ApplyStatTrak(CBasePlayerWeapon weapon, KnifePreset preset)
    {
        if (_setAttrByName == null) return;
        var item = weapon.AttributeManager?.Item;
        if (item == null || !HasReadyAttributeLists(item)) return;

        nint networkedHandle = item.NetworkedDynamicAttributes.Handle;
        nint attributeHandle = item.AttributeList.Handle;
        if (networkedHandle == nint.Zero || attributeHandle == nint.Zero) return;

        float count = BitConverter.Int32BitsToSingle(preset.StatTrakCount);
        _setAttrByName.Invoke(networkedHandle, "kill eater", count);
        _setAttrByName.Invoke(networkedHandle, "kill eater score type", 0);
        _setAttrByName.Invoke(attributeHandle, "kill eater", count);
        _setAttrByName.Invoke(attributeHandle, "kill eater score type", 0);
        Utilities.SetStateChanged(weapon, "CEconEntity", "m_AttributeManager");
    }

    private bool ValidatePreset(ushort defIndex, KnifePreset preset)
    {
        if (preset.Paint <= 0 || preset.Seed is < 0 or > 1000 || preset.Wear is < 0 or > 1)
            return false;
        if (_validPaints.TryGetValue(defIndex, out var paints) && !paints.Contains(preset.Paint))
            return false;
        if (preset.StatTrakEnabled && preset.SouvenirEnabled)
            return false;
        WeaponSkinEntry? skin = FindSkin(defIndex, preset.Paint);
        if (skin == null) return IsKnifeDefIndex(defIndex);
        return (!preset.StatTrakEnabled || skin.StatTrak) &&
               (!preset.SouvenirEnabled || skin.Souvenir) &&
               preset.Wear >= skin.MinWear && preset.Wear <= skin.MaxWear;
    }

    private bool CanApplyToPlayer(CCSPlayerController? player) =>
        _config.Enabled && _config.ApplyToHumanPlayers && player is { IsValid: true, IsBot: false, IsHLTV: false };

    private static CCSPlayerController? ResolvePlayer(nint handle)
    {
        if (handle == nint.Zero) return null;
        try
        {
            var player = new CCSPlayerController(handle);
            return player.IsValid ? player : null;
        }
        catch
        {
            return null;
        }
    }

    private static CosmeticTeam? GetCosmeticTeam(CCSPlayerController? player) => player?.Team switch
    {
        CsTeam.CounterTerrorist => CosmeticTeam.Ct,
        CsTeam.Terrorist => CosmeticTeam.T,
        _ => null,
    };

    private static bool IsKnifeName(string? name) =>
        !string.IsNullOrWhiteSpace(name) && (name.Contains("knife", StringComparison.OrdinalIgnoreCase)
                                             || name.Contains("bayonet", StringComparison.OrdinalIgnoreCase));

    private static bool IsKnifeDefIndex(ushort defIndex) => defIndex is >= 500 and <= 526;

    private static bool HasReadyAttributeLists(CEconItemView item) =>
        item.AttributeList.Handle != nint.Zero &&
        item.NetworkedDynamicAttributes.Handle != nint.Zero;

    private void AssignItemId(CEconItemView item)
    {
        ulong id = unchecked(_nextItemId++);
        item.ItemID = id;
        item.ItemIDLow = (uint)(id & 0xFFFFFFFF);
        item.ItemIDHigh = (uint)(id >> 32);
    }

    private void LoadConfig(ConfigSnapshot? restoreOnFailure = null)
    {
        try
        {
            _loadedConfigSchema = KnifeConfig.CurrentSchemaVersion;
            _loadedGunConfigSchema = KnifeConfig.CurrentSchemaVersion;
            _stickersSanitizedDuringLoad = false;
            if (!File.Exists(ConfigPath))
            {
                _config = new KnifeConfig();
                LoadGunConfig();
                SaveConfig();
                return;
            }

            string text = File.ReadAllText(ConfigPath);
            bool stickersSanitized;
            using (var document = JsonDocument.Parse(text))
            {
                _loadedConfigSchema = document.RootElement.TryGetProperty("schema_version", out var schema)
                    ? schema.GetInt32() : 1;
                if (_loadedConfigSchema is < 1 or > KnifeConfig.CurrentSchemaVersion)
                    throw new InvalidDataException($"Unsupported cosmetics schema {_loadedConfigSchema}");
                bool isTeamSchema = _loadedConfigSchema is 2 or 3 or 4 or 5 && document.RootElement.TryGetProperty("loadouts", out _);
                if (_loadedConfigSchema is 2 or 3 or 4 or 5 && !isTeamSchema)
                    throw new InvalidDataException($"Cosmetics schema {_loadedConfigSchema} has no team loadouts");
                text = SanitizeConfigStickerFields(text, gunFile: false, out stickersSanitized);
                if (isTeamSchema)
                    _config = JsonSerializer.Deserialize<KnifeConfig>(text, JsonOptions) ?? new KnifeConfig();
                else
                {
                    var legacy = JsonSerializer.Deserialize<LegacyKnifeConfig>(text, JsonOptions) ?? new LegacyKnifeConfig();
                    _config = KnifeConfig.FromLegacy(legacy);
                }
            }
            LoadGunConfig();
            _config.Normalize();
            bool agentsSanitized = SanitizeAgentModels();
            bool wearsClamped = ClampCatalogWears();
            _applyErrorThrottle.Reset();
            if (_loadedConfigSchema < KnifeConfig.CurrentSchemaVersion ||
                _loadedGunConfigSchema < KnifeConfig.CurrentSchemaVersion || stickersSanitized ||
                _stickersSanitizedDuringLoad || agentsSanitized || wearsClamped)
                SaveConfig();
        }
        catch (Exception ex)
        {
            if (restoreOnFailure is not null)
            {
                // A save that has not fully landed must not cost the running
                // session the appearance it already has.
                ConfigSnapshot snapshot = restoreOnFailure.Value;
                _config = snapshot.Config;
                _loadedConfigSchema = snapshot.ConfigSchema;
                _loadedGunConfigSchema = snapshot.GunSchema;
            }
            else
            {
                _config = new KnifeConfig();
                LoadGunConfig();
            }
            Logger.LogError("[PlayerKnifeCustomizer] Config load failed: {Message}", ex.Message);
        }
    }

    private void SaveConfig()
    {
        _config.Normalize();
        BackupVersionedFile(ConfigPath, _loadedConfigSchema);
        BackupVersionedFile(GunConfigPath, _loadedGunConfigSchema);
        WriteJsonAtomic(ConfigPath, _config);
        SaveGunConfig();
        _loadedConfigSchema = KnifeConfig.CurrentSchemaVersion;
        _loadedGunConfigSchema = KnifeConfig.CurrentSchemaVersion;
    }

    private void LoadGunConfig()
    {
        if (!File.Exists(GunConfigPath))
            return;
        try
        {
            string text = File.ReadAllText(GunConfigPath);
            using var document = JsonDocument.Parse(text);
            _loadedGunConfigSchema = document.RootElement.TryGetProperty("schema_version", out var schema)
                ? schema.GetInt32() : 1;
            if (_loadedGunConfigSchema is < 1 or > KnifeConfig.CurrentSchemaVersion)
                throw new InvalidDataException($"Unsupported gun cosmetics schema {_loadedGunConfigSchema}");
            text = SanitizeConfigStickerFields(text, gunFile: true, out bool stickersSanitized);
            if (_loadedGunConfigSchema is 2 or 3 or 4 or 5)
            {
                var guns = JsonSerializer.Deserialize<TeamGunConfig>(text, JsonOptions) ?? new TeamGunConfig();
                _config.Loadouts.Ct.GunPresets = guns.Ct ?? new Dictionary<ushort, KnifePreset>();
                _config.Loadouts.T.GunPresets = guns.T ?? new Dictionary<ushort, KnifePreset>();
                _config.SharedWeaponLinks = guns.SharedWeaponLinks ?? new Dictionary<ushort, bool>();
            }
            else
            {
                var legacy = JsonSerializer.Deserialize<Dictionary<ushort, KnifePreset>>(text, JsonOptions)
                    ?? new Dictionary<ushort, KnifePreset>();
                _config.ApplyLegacyGuns(legacy);
            }
            _config.Normalize();
            _stickersSanitizedDuringLoad |= stickersSanitized;
        }
        catch (Exception ex)
        {
            Logger.LogError("[PlayerKnifeCustomizer] Gun preset config load failed: {Message}", ex.Message);
        }
    }

    private void SaveGunConfig()
    {
        WriteJsonAtomic(GunConfigPath, TeamGunConfig.From(_config));
    }

    private string SanitizeConfigStickerFields(string text, bool gunFile, out bool changed)
    {
        JsonNode root = JsonNode.Parse(text) ?? throw new InvalidDataException("Cosmetics configuration is empty");
        changed = false;
        if (gunFile)
        {
            if (_loadedGunConfigSchema is 2 or 3 or 4 or 5)
            {
                changed |= SanitizePresetMap(root["ct"], allowDecorations: true, _loadedGunConfigSchema < 4);
                changed |= SanitizePresetMap(root["t"], allowDecorations: true, _loadedGunConfigSchema < 4);
            }
            else
                changed |= SanitizePresetMap(root, allowDecorations: true, migrateSchema: true);
        }
        else
        {
            changed |= SanitizePresetMap(root["presets"], allowDecorations: false, _loadedConfigSchema < 4);
            changed |= SanitizePresetMap(root["gun_presets"], allowDecorations: true, _loadedConfigSchema < 4);
            foreach (string side in new[] { "ct", "t" })
            {
                JsonNode? loadout = root["loadouts"]?[side];
                changed |= SanitizePresetMap(loadout?["knife_presets"], allowDecorations: false, _loadedConfigSchema < 4);
                changed |= SanitizePresetMap(loadout?["gun_presets"], allowDecorations: true, _loadedConfigSchema < 4);
            }
        }
        return root.ToJsonString(JsonOptions);
    }

    private bool SanitizePresetMap(JsonNode? node, bool allowDecorations, bool migrateSchema)
    {
        if (node is not JsonObject presets) return false;
        bool changed = false;
        foreach (var (key, value) in presets.ToArray())
        {
            if (value is not JsonObject preset || !ushort.TryParse(key, out ushort defIndex)) continue;
            if (preset.TryGetPropertyValue("stickers", out JsonNode? stickerNode))
            {
                bool valid = false;
                try
                {
                    if (allowDecorations && migrateSchema && stickerNode is JsonArray legacyStickers
                        && _stickerSchemaCounts.TryGetValue(defIndex, out uint schemaCount))
                    {
                        foreach (JsonNode? nodeEntry in legacyStickers)
                        {
                            if (nodeEntry is not JsonObject sticker || sticker.ContainsKey("schema")) continue;
                            uint slot = sticker["slot"]?.GetValue<uint>() ?? 0;
                            sticker["schema"] = Math.Min(slot, schemaCount - 1);
                            changed = true;
                        }
                    }
                    var stickers = stickerNode.Deserialize<List<StickerPreset>>(JsonOptions) ?? new List<StickerPreset>();
                    valid = DecorationConfigPolicy.CanPreserveStickers(
                        defIndex, allowDecorations, stickers, _validStickers, _stickerSchemaCounts);
                }
                catch (Exception ex) when (ex is JsonException or InvalidOperationException)
                {
                    valid = false;
                }
                if (!valid)
                {
                    preset["stickers"] = new JsonArray();
                    changed = true;
                }
            }
            if (preset.TryGetPropertyValue("charm", out JsonNode? charmNode) && charmNode != null)
            {
                bool valid;
                try
                {
                    var charm = charmNode.Deserialize<CharmPreset>(JsonOptions);
                    valid = DecorationConfigPolicy.CanPreserveCharm(
                        defIndex, allowDecorations, charm, _validCharms, _charmPlacements);
                }
                catch (JsonException)
                {
                    valid = false;
                }
                if (!valid)
                {
                    preset["charm"] = null;
                    changed = true;
                }
            }
        }
        return changed;
    }

    private static void WriteJsonAtomic<T>(string path, T value)
    {
        string temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(value, JsonOptions));
        File.Move(temp, path, true);
    }

    private static void BackupVersionedFile(string path, int sourceSchema)
    {
        if (sourceSchema >= KnifeConfig.CurrentSchemaVersion || !File.Exists(path)) return;
        int version = Math.Max(1, sourceSchema);
        string backup = path + $".v{version}.bak";
        if (!File.Exists(backup)) File.Copy(path, backup);
    }

    private void LoadCatalog()
    {
        _validPaints.Clear();
        _skinCatalog.Clear();
        _legacyPaints.Clear();
        if (!File.Exists(CatalogPath)) return;

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(CatalogPath));
            foreach (var entry in document.RootElement.EnumerateArray())
            {
                ushort defIndex = (ushort)ReadInt(entry.GetProperty("weapon_defindex"));
                int paint = ReadInt(entry.GetProperty("paint"));
                if (defIndex == 0 || paint <= 0) continue;
                var skin = new WeaponSkinEntry
                {
                    WeaponDefIndex = defIndex,
                    Paint = paint,
                    Name = entry.TryGetProperty("name", out var name) ? name.GetString() ?? $"Paint Kit {paint}" : $"Paint Kit {paint}",
                    MinWear = entry.TryGetProperty("min_wear", out var minWear) ? minWear.GetSingle() : 0f,
                    MaxWear = entry.TryGetProperty("max_wear", out var maxWear) ? maxWear.GetSingle() : 1f,
                    StatTrak = entry.TryGetProperty("stattrak", out var statTrak) && statTrak.GetBoolean(),
                    Souvenir = entry.TryGetProperty("souvenir", out var souvenir) && souvenir.GetBoolean(),
                };
                if (entry.TryGetProperty("legacy_model", out var legacy) && legacy.GetBoolean())
                    _legacyPaints.Add((defIndex, paint));
                if (!_validPaints.TryGetValue(defIndex, out var paints))
                    _validPaints[defIndex] = paints = new HashSet<int>();
                paints.Add(paint);
                if (!_skinCatalog.TryGetValue(defIndex, out var skins))
                    _skinCatalog[defIndex] = skins = new List<WeaponSkinEntry>();
                skins.Add(skin);
            }
            foreach (var skins in _skinCatalog.Values)
                skins.Sort((left, right) => string.Compare(left.Name, right.Name, StringComparison.CurrentCulture));
        }
        catch (Exception ex)
        {
            Logger.LogError("[PlayerKnifeCustomizer] Skin catalog load failed: {Message}", ex.Message);
        }

        static int ReadInt(JsonElement element) => element.ValueKind == JsonValueKind.Number
            ? element.GetInt32()
            : int.TryParse(element.GetString(), out int value) ? value : 0;
    }

    private void LoadStickerCatalog()
    {
        _validStickers.Clear();
        if (!File.Exists(StickerCatalogPath)) return;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(StickerCatalogPath));
            foreach (var entry in document.RootElement.EnumerateArray())
            {
                if (!entry.TryGetProperty("id", out var idElement)) continue;
                uint id = idElement.ValueKind == JsonValueKind.Number
                    ? idElement.GetUInt32()
                    : uint.TryParse(idElement.GetString(), out uint value) ? value : 0;
                if (id > 0) _validStickers.Add(id);
            }
        }
        catch (Exception ex)
        {
            Logger.LogError("[PlayerKnifeCustomizer] Sticker catalog load failed: {Message}", ex.Message);
        }
    }

    private void LoadPlayerCosmeticCatalog()
    {
        _stickerSchemaCounts.Clear();
        _validCharms.Clear();
        _charmPlacements.Clear();
        _agentModels.Clear();
        if (!File.Exists(PlayerCosmeticCatalogPath)) return;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(PlayerCosmeticCatalogPath));
            var root = document.RootElement;
            if (root.GetProperty("schema_version").GetInt32() != 1)
                throw new InvalidDataException("Unsupported player cosmetic catalog schema");
            var schemaCounts = new Dictionary<ushort, uint>();
            var validCharms = new HashSet<uint>();
            var charmPlacements = new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>();
            var agentModels = new Dictionary<CosmeticTeam, HashSet<string>>
            {
                [CosmeticTeam.Ct] = new(StringComparer.OrdinalIgnoreCase),
                [CosmeticTeam.T] = new(StringComparer.OrdinalIgnoreCase),
            };
            foreach (var idElement in root.GetProperty("charm_ids").EnumerateArray())
            {
                uint id = idElement.GetUInt32();
                if (id == 0 || !validCharms.Add(id))
                    throw new InvalidDataException("Player cosmetic catalog contains an invalid charm id");
            }
            var agentRoot = root.GetProperty("agent_models");
            foreach (var (team, key, prefix) in new[]
            {
                (CosmeticTeam.Ct, "ct", "agents\\models\\ctm_"),
                (CosmeticTeam.T, "t", "agents\\models\\tm_"),
            })
            {
                foreach (var modelElement in agentRoot.GetProperty(key).EnumerateArray())
                {
                    string model = modelElement.GetString() ?? string.Empty;
                    if (!model.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ||
                        !model.EndsWith(".vmdl", StringComparison.OrdinalIgnoreCase) ||
                        model.Contains("..", StringComparison.Ordinal) ||
                        model.Contains('/') ||
                        !agentModels[team].Add(model))
                        throw new InvalidDataException("Player cosmetic catalog contains an invalid agent model");
                }
                if (agentModels[team].Count == 0)
                    throw new InvalidDataException("Player cosmetic catalog contains no agent models for a team");
            }
            foreach (var weapon in root.GetProperty("weapons").EnumerateObject())
            {
                if (!ushort.TryParse(weapon.Name, out ushort defIndex) || defIndex == 0)
                    throw new InvalidDataException("Player cosmetic catalog contains an invalid weapon id");
                uint schemaCount = weapon.Value.GetProperty("sticker_schema_count").GetUInt32();
                if (schemaCount == 0 || !schemaCounts.TryAdd(defIndex, schemaCount))
                    throw new InvalidDataException("Player cosmetic catalog contains an invalid sticker schema count");
                var placements = new Dictionary<uint, CharmNativePlacement>();
                foreach (var entry in weapon.Value.GetProperty("charm_positions").EnumerateArray())
                {
                    uint placementId = entry.GetProperty("placement_id").GetUInt32();
                    float x = entry.GetProperty("x").GetSingle();
                    float y = entry.GetProperty("y").GetSingle();
                    float z = entry.GetProperty("z").GetSingle();
                    if (!float.IsFinite(x) || !float.IsFinite(y) || !float.IsFinite(z)
                        || !placements.TryAdd(placementId, new CharmNativePlacement(placementId, x, y, z)))
                        throw new InvalidDataException("Player cosmetic catalog contains an invalid charm placement");
                }
                if (placements.Count > 0) charmPlacements.Add(defIndex, placements);
            }
            foreach (var pair in schemaCounts) _stickerSchemaCounts.Add(pair.Key, pair.Value);
            foreach (uint id in validCharms) _validCharms.Add(id);
            foreach (var pair in charmPlacements) _charmPlacements.Add(pair.Key, pair.Value);
            foreach (var pair in agentModels) _agentModels.Add(pair.Key, pair.Value);
        }
        catch (Exception ex)
        {
            _stickerSchemaCounts.Clear();
            _validCharms.Clear();
            _charmPlacements.Clear();
            _agentModels.Clear();
            Logger.LogError("[PlayerKnifeCustomizer] Player cosmetic catalog load failed: {Message}", ex.Message);
        }
    }

    /// <summary>
    /// Pulls every preset back into the wear band its own PaintKit publishes.
    /// A preset saved by a newer Panel, hand-edited, or carried over from a catalog
    /// that has since tightened would otherwise be refused silently at apply time.
    /// PaintKits absent from the catalog are left alone, since there is no range to
    /// clamp against.
    /// </summary>
    private bool ClampCatalogWears()
    {
        bool changed = false;
        foreach (CosmeticTeam team in new[] { CosmeticTeam.Ct, CosmeticTeam.T })
        {
            var loadout = _config.Loadouts.For(team);
            foreach (var (defIndex, preset) in loadout.KnifePresets.Concat(loadout.GunPresets))
                changed |= PresetWearClamp.Clamp(preset, FindSkin(defIndex, preset.Paint));
        }
        return changed;
    }

    private bool SanitizeAgentModels()
    {
        if (_agentModels.Count == 0) return false;
        bool changed = false;
        foreach (var (team, loadout) in new[]
        {
            (CosmeticTeam.Ct, _config.Loadouts.Ct),
            (CosmeticTeam.T, _config.Loadouts.T),
        })
        {
            if (AgentModelPolicy.IsAllowed(team, loadout.AgentModel, _agentModels)) continue;
            loadout.AgentModel = string.Empty;
            changed = true;
        }
        return changed;
    }

    private WeaponSkinEntry? FindSkin(ushort defIndex, int paint) =>
        _skinCatalog.TryGetValue(defIndex, out var skins)
            ? skins.FirstOrDefault(skin => skin.Paint == paint)
            : null;

    private void OnReloadCommand(CCSPlayerController? player, CommandInfo command)
    {
        LoadCatalog();
        LoadStickerCatalog();
        LoadPlayerCosmeticCatalog();
        LoadConfig();
        string restart = _config.Enabled && _setAttrByName == null ? "; restart CS2 to initialize runtime hooks" : string.Empty;
        command.ReplyToCommand($"[PlayerKnifeCustomizer] reloaded; enabled={_config.Enabled}, stickers={DecorationReleaseEnabled && _config.StickersEnabled}, charms={DecorationReleaseEnabled && _config.CharmsEnabled}, agents={DecorationReleaseEnabled && _config.AgentsEnabled}, sticker_catalog={_validStickers.Count}, charm_catalog={_validCharms.Count}, agent_catalog={_agentModels.Values.Sum(models => models.Count)}, ct_knives={_config.Loadouts.Ct.KnifePresets.Count}, t_knives={_config.Loadouts.T.KnifePresets.Count}, ct_guns={_config.Loadouts.Ct.GunPresets.Count}, t_guns={_config.Loadouts.T.GunPresets.Count}, music={_config.MusicKitId}{restart}");
    }

    private void OnKnifeNextCommand(CCSPlayerController? player, CommandInfo command)
    {
        if (!CanApplyToPlayer(player)) return;
        CosmeticTeam? team = GetCosmeticTeam(player);
        if (team is null)
        {
            command.ReplyToCommand("[PlayerCosmetics] Pick a side before using the knife shortcut.");
            return;
        }
        var loadout = _config.Loadouts.For(team.Value);
        if (!KnifeShortcutPolicy.TryAdvance(_config.KnifeShortcutEnabled, _config.ShortcutKnifeDefIndexes,
                loadout.DefaultKnifeDefIndex, out ushort next))
        {
            command.ReplyToCommand(_config.KnifeShortcutEnabled
                ? "[PlayerCosmetics] Configure at least one shortcut knife in the Panel."
                : "[PlayerCosmetics] The knife shortcut is disabled in the Panel.");
            return;
        }
        loadout.DefaultKnifeDefIndex = next;
        SaveConfig();
        ScheduleApplyPipeline(player!.Handle, CosmeticApplyPhase.Knife);
        command.ReplyToCommand($"[PlayerCosmetics] Knife shortcut -> defindex {next}.");
    }

    private void OnStatusCommand(CCSPlayerController? player, CommandInfo command)
    {
        command.ReplyToCommand($"[PlayerKnifeCustomizer] enabled={_config.Enabled}, stickers={DecorationReleaseEnabled && _config.StickersEnabled}, charms={DecorationReleaseEnabled && _config.CharmsEnabled}, agents={DecorationReleaseEnabled && _config.AgentsEnabled}, signature={(_setAttrByName == null ? "missing" : "loaded")}, econ_writes={(_econWritesAllowed ? "allowed" : "blocked-by-guidelines")}, ct_knives={_config.Loadouts.Ct.KnifePresets.Count}, t_knives={_config.Loadouts.T.KnifePresets.Count}, ct_guns={_config.Loadouts.Ct.GunPresets.Count}, t_guns={_config.Loadouts.T.GunPresets.Count}, music={_config.MusicKitId}, catalog={_skinCatalog.Values.Sum(skins => skins.Count)}, sticker_catalog={_validStickers.Count}, charm_catalog={_validCharms.Count}, agent_catalog={_agentModels.Values.Sum(models => models.Count)}, active_generations={_applyTracker.ActiveCount}, schedules={_applyTracker.Schedules}, phase_completions={_applyTracker.PhaseCompletions}, retry_exhaustions={_applyTracker.RetryExhaustions}, context_invalidations={_applyTracker.ContextInvalidations}");
    }

    private void LogApplyError(string operation, Exception ex)
    {
        ApplyErrorDecision decision = _applyErrorThrottle.Check(operation, DateTimeOffset.UtcNow);
        if (!decision.ShouldLog) return;
        Logger.LogError(ex,
            "[PlayerKnifeCustomizer] Apply failed during {Operation}; suppressed_since_last={Suppressed}: {Message}",
            operation, decision.Suppressed, ex.Message);
    }
}

[Flags]
public enum CosmeticApplyPhase
{
    None = 0,
    Knife = 1,
    Gloves = 2,
    Guns = 4,
    Music = 8,
    Agent = 16,

    /// <summary>
    /// Re-apply presets only to the weapons this plugin can prove the player owns,
    /// which is what a live preset edit is allowed to touch. Unlike <see cref="Guns"/>
    /// it never claims a weapon the player walked into, so a gun picked up off the
    /// ground keeps the appearance it arrived with.
    /// </summary>
    OwnedGuns = 32,

    /// <summary>Everything a fresh grant owns; deliberately excludes
    /// <see cref="OwnedGuns"/>, which is only ever scheduled by a live reload.</summary>
    All = Knife | Gloves | Guns | Music | Agent,
}

/// <summary>
/// The configuration as it stood before a reload attempt, so a rejected save can
/// leave the running session exactly as it found it.
/// </summary>
public readonly record struct ConfigSnapshot(KnifeConfig Config, int ConfigSchema, int GunSchema);

public sealed class ApplyGenerationTracker
{
    private sealed class State
    {
        public required long Generation { get; init; }
        public required CosmeticApplyPhase Pending { get; set; }
        public nint PawnHandle { get; set; }
        public int? Team { get; set; }
        public bool ExhaustionRecorded { get; set; }
        public bool ReequipIssued { get; set; }
    }

    private readonly Dictionary<nint, State> _states = new();
    private long _nextGeneration;
    public int ContextInvalidations { get; private set; }
    public long Schedules { get; private set; }
    public long PhaseCompletions { get; private set; }
    public long RetryExhaustions { get; private set; }
    public int ActiveCount => _states.Count;

    public long Begin(nint playerHandle, CosmeticApplyPhase phases)
    {
        long generation = ++_nextGeneration;
        if (_states.TryGetValue(playerHandle, out var previous))
            phases |= previous.Pending;
        _states[playerHandle] = new State { Generation = generation, Pending = phases };
        Schedules++;
        return generation;
    }

    public bool IsCurrent(nint playerHandle, long generation) =>
        _states.TryGetValue(playerHandle, out var state) && state.Generation == generation;

    public bool TryBindContext(nint playerHandle, long generation, nint pawnHandle, int team)
    {
        if (!_states.TryGetValue(playerHandle, out var state) || state.Generation != generation)
            return false;
        if ((state.PawnHandle != nint.Zero && state.PawnHandle != pawnHandle) ||
            (state.Team.HasValue && state.Team.Value != team))
        {
            ContextInvalidations++;
            _states.Remove(playerHandle);
            return false;
        }
        state.PawnHandle = pawnHandle;
        state.Team = team;
        return true;
    }

    public bool IsPending(nint playerHandle, long generation, CosmeticApplyPhase phase) =>
        _states.TryGetValue(playerHandle, out var state) && state.Generation == generation &&
        (state.Pending & phase) != 0;

    public bool HasPending(nint playerHandle, long generation) =>
        _states.TryGetValue(playerHandle, out var state) && state.Generation == generation &&
        state.Pending != CosmeticApplyPhase.None;

    public bool Complete(nint playerHandle, long generation, CosmeticApplyPhase phase)
    {
        if (!_states.TryGetValue(playerHandle, out var state) || state.Generation != generation)
            return false;
        state.Pending &= ~phase;
        PhaseCompletions++;
        return true;
    }

    public bool MarkRetryExhausted(nint playerHandle, long generation)
    {
        if (!_states.TryGetValue(playerHandle, out var state) || state.Generation != generation ||
            state.Pending == CosmeticApplyPhase.None || state.ExhaustionRecorded)
            return false;
        state.ExhaustionRecorded = true;
        RetryExhaustions++;
        return true;
    }

    public bool TryMarkReequip(nint playerHandle, long generation)
    {
        if (!_states.TryGetValue(playerHandle, out var state) || state.Generation != generation || state.ReequipIssued)
            return false;
        state.ReequipIssued = true;
        return true;
    }

    public void Cancel(nint playerHandle) => _states.Remove(playerHandle);
    public void CancelAll() => _states.Clear();
}

public static class ApplyPipelineContext
{
    // Deathmatch and retake can publish player_spawn before the replacement
    // Pawn and its econ services are fully live. Keep retries bounded while
    // allowing the replacement Pawn enough time to become authoritative.
    public static readonly float[] RetryDelays = [0.10f, 0.25f, 0.50f, 0.90f];

    public static bool IsReady(bool pawnAlive, bool pawnValid, nint pawnHandle, CosmeticTeam? team) =>
        pawnAlive && pawnValid && pawnHandle != nint.Zero && team.HasValue;
}

public readonly record struct ApplyErrorDecision(bool ShouldLog, int Suppressed);

public sealed class ApplyErrorThrottle(TimeSpan interval)
{
    private sealed class Entry
    {
        public required DateTimeOffset LastLogged { get; set; }
        public int Suppressed { get; set; }
    }

    private readonly Dictionary<string, Entry> _entries = new(StringComparer.Ordinal);

    public void Reset() => _entries.Clear();

    public ApplyErrorDecision Check(string operation, DateTimeOffset now)
    {
        if (!_entries.TryGetValue(operation, out Entry? entry))
        {
            _entries[operation] = new Entry { LastLogged = now };
            return new ApplyErrorDecision(true, 0);
        }
        if (now - entry.LastLogged < interval)
        {
            entry.Suppressed++;
            return new ApplyErrorDecision(false, entry.Suppressed);
        }

        int suppressed = entry.Suppressed;
        entry.LastLogged = now;
        entry.Suppressed = 0;
        return new ApplyErrorDecision(true, suppressed);
    }
}

public enum CosmeticTeam { Ct, T }

public enum WeaponAvailability { Ct, T, Shared }

public sealed class TeamLoadoutCollection
{
    [JsonPropertyName("ct")]
    public TeamLoadout Ct { get; set; } = new();

    [JsonPropertyName("t")]
    public TeamLoadout T { get; set; } = new();

    public TeamLoadout For(CosmeticTeam team) => team == CosmeticTeam.Ct ? Ct : T;
}

public sealed class TeamLoadout
{
    [JsonPropertyName("agent_model")]
    public string AgentModel { get; set; } = string.Empty;

    [JsonPropertyName("default_knife_defindex")]
    public ushort DefaultKnifeDefIndex { get; set; }

    [JsonPropertyName("knife_presets")]
    public Dictionary<ushort, KnifePreset> KnifePresets { get; set; } = new();

    [JsonPropertyName("glove")]
    public GlovePreset Glove { get; set; } = new();

    [JsonPropertyName("gun_presets")]
    public Dictionary<ushort, KnifePreset> GunPresets { get; set; } = new();

    public TeamLoadout Clone() => new()
    {
        AgentModel = AgentModel,
        DefaultKnifeDefIndex = DefaultKnifeDefIndex,
        KnifePresets = KnifePresets.ToDictionary(pair => pair.Key, pair => pair.Value.Clone()),
        Glove = Glove.Clone(),
        GunPresets = GunPresets.ToDictionary(pair => pair.Key, pair => pair.Value.Clone()),
    };

    public void Normalize()
    {
        AgentModel ??= string.Empty;
        KnifePresets ??= new Dictionary<ushort, KnifePreset>();
        GunPresets ??= new Dictionary<ushort, KnifePreset>();
        Glove ??= new GlovePreset();
        foreach (var preset in KnifePresets.Values.Concat(GunPresets.Values)) preset.Normalize();
        Glove.Normalize();
        if (DefaultKnifeDefIndex != 0 && !KnifePresets.ContainsKey(DefaultKnifeDefIndex))
            DefaultKnifeDefIndex = 0;
    }
}

public sealed class KnifeConfig
{
    public const int CurrentSchemaVersion = 5;

    [JsonPropertyName("schema_version")]
    public int SchemaVersion { get; set; } = CurrentSchemaVersion;

    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; }

    [JsonPropertyName("apply_to_human_players")]
    public bool ApplyToHumanPlayers { get; set; } = true;

    [JsonPropertyName("music_kit_id")]
    public int MusicKitId { get; set; }

    [JsonPropertyName("loadouts")]
    public TeamLoadoutCollection Loadouts { get; set; } = new();

    [JsonPropertyName("shared_weapon_links")]
    public Dictionary<ushort, bool> SharedWeaponLinks { get; set; } = new();

    [JsonPropertyName("stickers_enabled")]
    public bool StickersEnabled { get; set; }

    [JsonPropertyName("charms_enabled")]
    public bool CharmsEnabled { get; set; }

    [JsonPropertyName("agents_enabled")]
    public bool AgentsEnabled { get; set; }

    /// <summary>
    /// The optional quick-knife rotation. It is off unless the user turns it on in
    /// the Panel, and cycling only ever changes which knife model and saved preset
    /// the player carries; it never creates ground entities or rewrites key binds.
    /// </summary>
    [JsonPropertyName("knife_shortcut_enabled")]
    public bool KnifeShortcutEnabled { get; set; }

    [JsonPropertyName("shortcut_knife_defindexes")]
    public List<ushort> ShortcutKnifeDefIndexes { get; set; } = new();

    public static KnifeConfig FromLegacy(LegacyKnifeConfig legacy)
    {
        var baseLoadout = new TeamLoadout
        {
            DefaultKnifeDefIndex = legacy.DefaultKnifeDefIndex,
            KnifePresets = (legacy.Presets ?? new()).ToDictionary(pair => pair.Key, pair => pair.Value.Clone()),
            Glove = (legacy.Glove ?? new GlovePreset()).Clone(),
        };
        var config = new KnifeConfig
        {
            Enabled = legacy.Enabled,
            ApplyToHumanPlayers = legacy.ApplyToHumanPlayers,
            MusicKitId = legacy.MusicKitId,
            Loadouts = new TeamLoadoutCollection { Ct = baseLoadout.Clone(), T = baseLoadout.Clone() },
        };
        config.ApplyLegacyGuns(legacy.GunPresets ?? new Dictionary<ushort, KnifePreset>());
        config.Normalize();
        return config;
    }

    public void ApplyLegacyGuns(Dictionary<ushort, KnifePreset> guns)
    {
        Loadouts.Ct.GunPresets.Clear();
        Loadouts.T.GunPresets.Clear();
        foreach (var (defIndex, preset) in guns)
        {
            switch (WeaponPresetResolver.GetAvailability(defIndex))
            {
                case WeaponAvailability.Ct:
                    Loadouts.Ct.GunPresets[defIndex] = preset.Clone();
                    break;
                case WeaponAvailability.T:
                    Loadouts.T.GunPresets[defIndex] = preset.Clone();
                    break;
                default:
                    Loadouts.Ct.GunPresets[defIndex] = preset.Clone();
                    Loadouts.T.GunPresets[defIndex] = preset.Clone();
                    SharedWeaponLinks[defIndex] = true;
                    break;
            }
        }
    }

    public KnifeConfig Clone() => new()
    {
        SchemaVersion = SchemaVersion,
        Enabled = Enabled,
        ApplyToHumanPlayers = ApplyToHumanPlayers,
        MusicKitId = MusicKitId,
        Loadouts = new TeamLoadoutCollection { Ct = Loadouts.Ct.Clone(), T = Loadouts.T.Clone() },
        SharedWeaponLinks = new Dictionary<ushort, bool>(SharedWeaponLinks),
        StickersEnabled = StickersEnabled,
        CharmsEnabled = CharmsEnabled,
        AgentsEnabled = AgentsEnabled,
    };

    public void Normalize()
    {
        SchemaVersion = CurrentSchemaVersion;
        ShortcutKnifeDefIndexes ??= new List<ushort>();
        var shortcuts = new List<ushort>();
        foreach (ushort defIndex in ShortcutKnifeDefIndexes)
            if (defIndex != 0 && shortcuts.IndexOf(defIndex) < 0) shortcuts.Add(defIndex);
        ShortcutKnifeDefIndexes = shortcuts.Take(KnifeShortcutPolicy.MaxShortcuts).ToList();
        Loadouts ??= new TeamLoadoutCollection();
        Loadouts.Ct ??= new TeamLoadout();
        Loadouts.T ??= new TeamLoadout();
        SharedWeaponLinks ??= new Dictionary<ushort, bool>();
        MusicKitId = Math.Clamp(MusicKitId, 0, ushort.MaxValue);
        Loadouts.Ct.Normalize();
        Loadouts.T.Normalize();
        foreach (ushort defIndex in WeaponPresetResolver.SharedWeapons)
            SharedWeaponLinks.TryAdd(defIndex, true);
        foreach (var (defIndex, linked) in SharedWeaponLinks.ToArray())
        {
            if (!linked || WeaponPresetResolver.GetAvailability(defIndex) != WeaponAvailability.Shared) continue;
            bool hasCt = Loadouts.Ct.GunPresets.TryGetValue(defIndex, out var ct);
            bool hasT = Loadouts.T.GunPresets.TryGetValue(defIndex, out var t);
            if (hasCt && !hasT) Loadouts.T.GunPresets[defIndex] = ct!.CloneWithoutDecorations();
            else if (!hasCt && hasT) Loadouts.Ct.GunPresets[defIndex] = t!.CloneWithoutDecorations();
            else if (hasCt && hasT && !ct!.BaseValueEquals(t!)) t!.CopyBaseFrom(ct);
        }
    }
}

public sealed class LegacyKnifeConfig
{
    [JsonPropertyName("enabled")] public bool Enabled { get; set; }
    [JsonPropertyName("apply_to_human_players")] public bool ApplyToHumanPlayers { get; set; } = true;
    [JsonPropertyName("default_knife_defindex")] public ushort DefaultKnifeDefIndex { get; set; }
    [JsonPropertyName("presets")] public Dictionary<ushort, KnifePreset> Presets { get; set; } = new();
    [JsonPropertyName("gun_presets")] public Dictionary<ushort, KnifePreset> GunPresets { get; set; } = new();
    [JsonPropertyName("music_kit_id")] public int MusicKitId { get; set; }
    [JsonPropertyName("glove")] public GlovePreset Glove { get; set; } = new();
}

public sealed class TeamGunConfig
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = KnifeConfig.CurrentSchemaVersion;
    [JsonPropertyName("ct")] public Dictionary<ushort, KnifePreset> Ct { get; set; } = new();
    [JsonPropertyName("t")] public Dictionary<ushort, KnifePreset> T { get; set; } = new();
    [JsonPropertyName("shared_weapon_links")] public Dictionary<ushort, bool> SharedWeaponLinks { get; set; } = new();

    public static TeamGunConfig From(KnifeConfig config) => new()
    {
        Ct = config.Loadouts.Ct.GunPresets,
        T = config.Loadouts.T.GunPresets,
        SharedWeaponLinks = config.SharedWeaponLinks,
    };
}

public static class WeaponPresetResolver
{
    private static readonly HashSet<ushort> CtOnly = [3, 8, 10, 16, 27, 32, 34, 38, 60, 61];
    private static readonly HashSet<ushort> TOnly = [4, 7, 11, 13, 17, 29, 30, 39];
    public static readonly ushort[] SharedWeapons = [1, 2, 9, 14, 19, 23, 24, 25, 26, 28, 31, 33, 35, 36, 40, 63, 64];

    public static WeaponAvailability GetAvailability(ushort defIndex) => CtOnly.Contains(defIndex)
        ? WeaponAvailability.Ct
        : TOnly.Contains(defIndex) ? WeaponAvailability.T : WeaponAvailability.Shared;

    public static bool HasAnyGunPreset(KnifeConfig config, ushort defIndex) =>
        config.Loadouts.Ct.GunPresets.ContainsKey(defIndex) || config.Loadouts.T.GunPresets.ContainsKey(defIndex);

    public static bool TryResolveGunPreset(KnifeConfig config, ushort defIndex, CosmeticTeam? currentTeam, out KnifePreset preset)
    {
        if (currentTeam == null)
        {
            preset = null!;
            return false;
        }
        var availability = GetAvailability(defIndex);
        var primary = availability switch
        {
            WeaponAvailability.Ct => config.Loadouts.Ct.GunPresets,
            WeaponAvailability.T => config.Loadouts.T.GunPresets,
            _ => config.Loadouts.For(currentTeam.Value).GunPresets,
        };
        if (primary.TryGetValue(defIndex, out preset!)) return true;
        if (availability == WeaponAvailability.Shared && config.SharedWeaponLinks.GetValueOrDefault(defIndex, true))
            return config.Loadouts.For(currentTeam == CosmeticTeam.Ct ? CosmeticTeam.T : CosmeticTeam.Ct)
                .GunPresets.TryGetValue(defIndex, out preset!);
        preset = null!;
        return false;
    }
}

public sealed class GlovePreset
{
    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; }

    [JsonPropertyName("defindex")]
    public ushort DefIndex { get; set; } = 5030;

    [JsonPropertyName("paint")]
    public int Paint { get; set; } = 10048;

    [JsonPropertyName("seed")]
    public int Seed { get; set; }

    [JsonPropertyName("wear")]
    public float Wear { get; set; } = 0.01f;

    public GlovePreset Clone() => new()
    {
        Enabled = Enabled, DefIndex = DefIndex, Paint = Paint, Seed = Seed, Wear = Wear,
    };

    public void Normalize()
    {
        Seed = Math.Clamp(Seed, 0, 1000);
        Wear = Math.Clamp(Wear, 0f, 1f);
        if (Enabled && DefIndex == 0 && Paint == 0)
        {
            DefIndex = 5030;
            Paint = 10048;
            Wear = 0.01f;
        }
    }
}

public sealed class KnifePreset
{
    [JsonPropertyName("paint")]
    public int Paint { get; set; }

    [JsonPropertyName("seed")]
    public int Seed { get; set; }

    [JsonPropertyName("wear")]
    public float Wear { get; set; } = 0.01f;

    [JsonPropertyName("name_tag")]
    public string? NameTag { get; set; } = string.Empty;

    [JsonPropertyName("stattrak_enabled")]
    public bool StatTrakEnabled { get; set; }

    [JsonPropertyName("stattrak_count")]
    public int StatTrakCount { get; set; }

    [JsonPropertyName("souvenir_enabled")]
    public bool SouvenirEnabled { get; set; }

    [JsonPropertyName("stickers")]
    public List<StickerPreset> Stickers { get; set; } = new();

    [JsonPropertyName("charm")]
    public CharmPreset? Charm { get; set; }

    public KnifePreset Clone() => new()
    {
        Paint = Paint, Seed = Seed, Wear = Wear, NameTag = NameTag,
        StatTrakEnabled = StatTrakEnabled, StatTrakCount = StatTrakCount,
        SouvenirEnabled = SouvenirEnabled,
        Stickers = (Stickers ?? []).Select(sticker => sticker.Clone()).ToList(),
        Charm = Charm?.Clone(),
    };

    public KnifePreset CloneWithoutDecorations() => new()
    {
        Paint = Paint, Seed = Seed, Wear = Wear, NameTag = NameTag,
        StatTrakEnabled = StatTrakEnabled, StatTrakCount = StatTrakCount,
        SouvenirEnabled = SouvenirEnabled,
        Stickers = [],
        Charm = null,
    };

    public bool BaseValueEquals(KnifePreset other) => Paint == other.Paint && Seed == other.Seed
        && Wear.Equals(other.Wear) && NameTag == other.NameTag
        && StatTrakEnabled == other.StatTrakEnabled && StatTrakCount == other.StatTrakCount
        && SouvenirEnabled == other.SouvenirEnabled;

    public void CopyBaseFrom(KnifePreset source)
    {
        Paint = source.Paint;
        Seed = source.Seed;
        Wear = source.Wear;
        NameTag = source.NameTag;
        StatTrakEnabled = source.StatTrakEnabled;
        StatTrakCount = source.StatTrakCount;
        SouvenirEnabled = source.SouvenirEnabled;
    }

    public bool ValueEquals(KnifePreset other) => BaseValueEquals(other)
        && (Stickers ?? []).Count == (other.Stickers ?? []).Count
        && (Stickers ?? []).Zip(other.Stickers ?? []).All(pair => pair.First.ValueEquals(pair.Second))
        && (Charm == null ? other.Charm == null : other.Charm != null && Charm.ValueEquals(other.Charm));

    public void Normalize()
    {
        Seed = Math.Clamp(Seed, 0, 1000);
        Wear = Math.Clamp(Wear, 0f, 1f);
        StatTrakCount = Math.Max(0, StatTrakCount);
        if (SouvenirEnabled) StatTrakEnabled = false;
        if (NameTag?.Length > 20) NameTag = NameTag[..20];
        Stickers ??= new List<StickerPreset>();
        Stickers = Stickers.OrderBy(sticker => sticker.Slot).ToList();
    }
}

public sealed class StickerPreset
{
    [JsonPropertyName("slot")] public byte Slot { get; set; }
    [JsonPropertyName("id")] public uint Id { get; set; }
    [JsonPropertyName("schema")] public uint Schema { get; set; }
    [JsonPropertyName("wear")] public float Wear { get; set; }
    [JsonPropertyName("scale")] public float Scale { get; set; } = 1f;
    [JsonPropertyName("rotation")] public float Rotation { get; set; }
    [JsonPropertyName("offset_x")] public float OffsetX { get; set; }
    [JsonPropertyName("offset_y")] public float OffsetY { get; set; }
    [JsonPropertyName("custom_position")] public bool CustomPosition { get; set; }

    public StickerPreset Clone() => new()
    {
        Slot = Slot,
        Id = Id,
        Schema = Schema,
        Wear = Wear,
        Scale = Scale,
        Rotation = Rotation,
        OffsetX = OffsetX,
        OffsetY = OffsetY,
        CustomPosition = CustomPosition,
    };

    public bool ValueEquals(StickerPreset other) => Slot == other.Slot && Id == other.Id && Schema == other.Schema
        && Wear.Equals(other.Wear) && Scale.Equals(other.Scale) && Rotation.Equals(other.Rotation)
        && OffsetX.Equals(other.OffsetX) && OffsetY.Equals(other.OffsetY)
        && CustomPosition == other.CustomPosition;
}

public sealed class CharmPreset
{
    [JsonPropertyName("id")] public uint Id { get; set; }
    [JsonPropertyName("placement_id")] public uint PlacementId { get; set; }
    [JsonPropertyName("seed")] public int Seed { get; set; }

    public CharmPreset Clone() => new() { Id = Id, PlacementId = PlacementId, Seed = Seed };
    public bool ValueEquals(CharmPreset other) => Id == other.Id
        && PlacementId == other.PlacementId && Seed == other.Seed;
}

public sealed class WeaponSkinEntry
{
    public ushort WeaponDefIndex { get; init; }
    public int Paint { get; init; }
    public string Name { get; init; } = string.Empty;
    public float MinWear { get; init; }
    public float MaxWear { get; init; } = 1f;
    public bool StatTrak { get; init; }
    public bool Souvenir { get; init; }
}
