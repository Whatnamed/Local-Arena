using PlayerKnifeCustomizer;
using System.Text.Json;

static KnifePreset Preset(int paint, int count = 0) => new()
{
    Paint = paint,
    Seed = 0,
    Wear = 0.01f,
    StatTrakEnabled = true,
    StatTrakCount = count,
};

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
Require(HumanEconPolicy.Quality(HumanItemKind.Gun, false, false) == 4 &&
        HumanEconPolicy.Quality(HumanItemKind.Knife, false, false) == 3 &&
        HumanEconPolicy.Quality(HumanItemKind.Glove, false, false) == 3 &&
        HumanEconPolicy.Quality(HumanItemKind.Gun, true, false) == 9 &&
        HumanEconPolicy.Quality(HumanItemKind.Gun, false, true) == 12,
    "Human item kinds must keep distinct normal, StatTrak and Souvenir qualities.");
Require(HumanEconPolicy.AccountId(76_561_197_960_265_728UL + 12345) == 12345,
    "Custom item account identity must use the low Steam account ID.");
using (var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "weapon_skins.json"))))
{
    foreach (var (defIndex, paint) in new[] { (16, 632), (36, 258) })
    {
        var entry = catalog.RootElement.EnumerateArray().FirstOrDefault(item =>
            item.GetProperty("weapon_defindex").GetInt32() == defIndex &&
            item.GetProperty("paint").GetInt32() == paint);
        Require(entry.ValueKind == JsonValueKind.Object && entry.GetProperty("legacy_model").GetBoolean(),
            $"Configured defindex {defIndex} paint {paint} must resolve legacy_model from the shared catalog.");
    }
}
// Test the weapon preset resolver
var config = new KnifeConfig();
config.Loadouts.Ct.GunPresets[16] = Preset(309);
config.Loadouts.T.GunPresets[7] = Preset(661);
config.Loadouts.Ct.GunPresets[9] = Preset(344, 10);
config.Loadouts.T.GunPresets[9] = Preset(279, 20);
config.SharedWeaponLinks[9] = false;

Require(WeaponPresetResolver.TryResolveGunPreset(config, 16, CosmeticTeam.T, out var m4) && m4.Paint == 309,
    "A CT-exclusive weapon must resolve the CT preset after a T pickup.");
Require(WeaponPresetResolver.TryResolveGunPreset(config, 7, CosmeticTeam.Ct, out var ak) && ak.Paint == 661,
    "A T-exclusive weapon must resolve the T preset after a CT pickup.");
Require(WeaponPresetResolver.TryResolveGunPreset(config, 9, CosmeticTeam.Ct, out var ctAwp) && ctAwp.Paint == 344,
    "An unlinked shared weapon must resolve the current CT preset.");
Require(WeaponPresetResolver.TryResolveGunPreset(config, 9, CosmeticTeam.T, out var tAwp) && tAwp.Paint == 279,
    "An unlinked shared weapon must resolve the current T preset.");
Require(!WeaponPresetResolver.TryResolveGunPreset(config, 9, null, out _),
    "A spectator or unknown team must not receive a cosmetic preset.");

Require(KnifeShortcutCycle.GetNextKnifeDefIndex(507) == 515 &&
        KnifeShortcutCycle.GetNextKnifeDefIndex(512) == 507,
    "The default quick-knife cycle must use the documented order and wrap around.");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(507, [515, 507, 526]) == 526,
    "A configured quick-knife list must control the next target.");
Require(GiveNamedItemPhaseResolver.Resolve("weapon_knife_karambit", 507) == CosmeticApplyPhase.Knife &&
        GiveNamedItemPhaseResolver.Resolve("weapon_ak47", 7) == CosmeticApplyPhase.Guns &&
        GiveNamedItemPhaseResolver.Resolve(null, 0) == (CosmeticApplyPhase.Knife | CosmeticApplyPhase.Guns),
    "GiveNamedItem return inspection must select knife, gun, or conservative combined phases.");

var plannerLoadout = new TeamLoadout();
// A failed or pending refresh cannot allow overlapping shortcut commands.
var refreshGate = new KnifeRefreshGate();
var instant = DateTimeOffset.UtcNow;
Require(refreshGate.TryBegin(player: (nint)0x1000, pawn: 42, team: (int)CosmeticTeam.Ct,
        now: instant, out long firstRefresh) &&
        !refreshGate.TryBegin((nint)0x1000, 42, (int)CosmeticTeam.Ct,
            instant.AddMilliseconds(1), out _),
    "Rapid shortcut presses must not overlap a knife refresh.");
Require(refreshGate.IsCurrent((nint)0x1000, 42, (int)CosmeticTeam.Ct, firstRefresh) &&
        !refreshGate.IsCurrent((nint)0x1000, 43, (int)CosmeticTeam.Ct, firstRefresh),
    "The refresh request must be bound to its Pawn and team.");
refreshGate.Complete((nint)0x1000, firstRefresh);
Require(!refreshGate.TryBegin((nint)0x1000, 42, (int)CosmeticTeam.Ct,
        instant.AddMilliseconds(200), out _),
    "Completing a refresh must retain its short debounce.");
Require(refreshGate.TryBegin((nint)0x1000, 42, (int)CosmeticTeam.Ct,
        instant.AddMilliseconds(400), out long secondRefresh) &&
        !refreshGate.IsCurrent((nint)0x1000, 42, (int)CosmeticTeam.Ct, firstRefresh),
    "A later shortcut may start once, and old callbacks must stay stale.");
refreshGate.Cancel((nint)0x1000);
Require(!refreshGate.IsCurrent((nint)0x1000, 42, (int)CosmeticTeam.Ct, secondRefresh),
    "Death, team change or disconnect must cancel an in-flight refresh.");

string knifeSource = File.ReadAllText(Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
    "..", "..", "..", "..", "PlayerKnifeCustomizer", "PlayerKnifeCustomizer.cs")));
int mutationStart = knifeSource.IndexOf("private KnifeApplyOutcome ApplyExistingKnife(", StringComparison.Ordinal);
int mutationEnd = knifeSource.IndexOf("private static string? FindSafeNonKnifeSlot(", mutationStart, StringComparison.Ordinal);
Require(mutationStart >= 0 && mutationEnd > mutationStart, "The existing-entity knife path must be present.");
string mutation = knifeSource[mutationStart..mutationEnd];
Require(!knifeSource.Contains("RemovePlayerItem(", StringComparison.Ordinal) &&
        !knifeSource.Contains("GiveNamedItem<", StringComparison.Ordinal) &&
        !knifeSource.Contains("weapon.Remove()", StringComparison.Ordinal),
    "Human cosmetic apply must not detach, give or destroy a knife entity.");
Require(mutation.Split("ExecuteClientCommand(", StringSplitOptions.None).Length - 1 == 2 &&
        mutation.Contains("ExecuteClientCommand(safeSlot)", StringComparison.Ordinal) &&
        mutation.Contains("ExecuteClientCommand(\"slot3\")", StringComparison.Ordinal),
    "One knife update may issue at most one safe-slot command and one slot3 command.");

var planner = KnifeReplacementPlanner.Plan(507, null, plannerLoadout);
Require(planner.IsValid && planner.TargetDefIndex == 515 && planner.IsVanilla &&
        plannerLoadout.KnifePresets.Count == 0,
    "A vanilla quick-knife plan must not create a preset before mutation succeeds.");
plannerLoadout.KnifePresets[515] = Preset(568);
var configuredPlan = KnifeReplacementPlanner.Plan(507, null, plannerLoadout);
Require(configuredPlan.IsValid && !configuredPlan.IsVanilla && configuredPlan.Preset.Paint == 568 &&
        !ReferenceEquals(configuredPlan.Preset, plannerLoadout.KnifePresets[515]),
    "A configured quick-knife plan must clone the preset without mutating loadout state.");

tAwp.StatTrakCount++;
Require(config.Loadouts.T.GunPresets[9].StatTrakCount == 21 && config.Loadouts.Ct.GunPresets[9].StatTrakCount == 10,
    "StatTrak must update only the resolved team preset.");

config.Loadouts.T.GunPresets.Remove(9);
config.SharedWeaponLinks[9] = true;
Require(WeaponPresetResolver.TryResolveGunPreset(config, 9, CosmeticTeam.T, out var linkedAwp) && linkedAwp.Paint == 344,
    "A linked shared weapon must fall back to the configured side.");

var validStickerIds = new HashSet<uint> { 1, 2, 3, 4, 5, 6 };
var stickerSchemaCounts = new Dictionary<ushort, uint> { [7] = 4, [9] = 5 };
var customSticker = new StickerPreset
{
    Slot = 0, Id = 1, Schema = 2, Wear = 0.25f, Scale = 1.2f, Rotation = 45f,
    OffsetX = -0.4f, OffsetY = 0.7f, CustomPosition = true,
};
Require(StickerAttributePlanner.TryBuild(7, true, [customSticker], validStickerIds, stickerSchemaCounts, out var attributes, out var stickerError),
    $"A valid sticker plan must build: {stickerError}");
Require(attributes.Select(attribute => attribute.Name).SequenceEqual([
    "sticker slot 0 id", "sticker slot 0 schema", "sticker slot 0 offset x", "sticker slot 0 offset y",
    "sticker slot 0 wear", "sticker slot 0 scale", "sticker slot 0 rotation",
]), "Sticker attributes must use the exact CS2 attribute names and deterministic order.");
Require(unchecked((uint)BitConverter.SingleToInt32Bits(attributes[0].Value)) == customSticker.Id,
    "Sticker IDs must be encoded by reinterpreting uint bits as float bits.");
Require(unchecked((uint)BitConverter.SingleToInt32Bits(attributes[1].Value)) == customSticker.Schema
    && attributes[2].Value == customSticker.OffsetX && attributes[3].Value == customSticker.OffsetY,
    "Custom positions must preserve the selected weapon schema and bounded X/Y offsets.");

customSticker.CustomPosition = false;
Require(StickerAttributePlanner.TryBuild(7, true, [customSticker], validStickerIds, stickerSchemaCounts, out attributes, out _)
    && attributes.Any(attribute => attribute.Name.EndsWith("schema"))
    && attributes.All(attribute => !attribute.Name.Contains("offset")),
    "Default sticker placement must emit its schema without custom offsets.");
Require(StickerAttributePlanner.TryBuild(7, false, [customSticker], validStickerIds, stickerSchemaCounts, out attributes, out _)
    && attributes.Count == 0,
    "Disabling the feature must preserve configuration without emitting sticker attributes.");
Require(!StickerAttributePlanner.TryBuild(515, false, [customSticker], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("knife"),
    "Knife stickers must be rejected even while sticker application is disabled.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        Enumerable.Range(0, 6).Select(index => new StickerPreset { Slot = (byte)index, Id = (uint)(index + 1), Scale = 1f }),
        validStickerIds, stickerSchemaCounts, out _, out stickerError) && stickerError.Contains("more than five"),
    "A weapon must reject more than five stickers.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        [new StickerPreset { Slot = 0, Id = 1, Scale = 1f }, new StickerPreset { Slot = 0, Id = 2, Scale = 1f }],
        validStickerIds, stickerSchemaCounts, out _, out stickerError) && stickerError.Contains("unique"),
    "Duplicate sticker slots must be rejected.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        [new StickerPreset { Slot = 0, Id = 999, Scale = 1f }], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("unknown"),
    "Unknown sticker IDs must be rejected before native writes.");
Require(!StickerAttributePlanner.TryBuild(7, true,
        [new StickerPreset { Slot = 0, Id = 1, Scale = float.NaN }], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("range"),
    "Non-finite sticker values must be rejected before native writes.");
Require(!StickerAttributePlanner.TryBuild(42, true, [customSticker], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("not supported"),
    "Weapons outside the fixed capability catalog must be rejected before native writes.");
customSticker.Schema = 4;
Require(!StickerAttributePlanner.TryBuild(7, true, [customSticker], validStickerIds, stickerSchemaCounts, out _, out stickerError)
    && stickerError.Contains("schema"),
    "Sticker schemas outside the selected weapon catalog must be rejected before native writes.");
customSticker.Schema = 2;

var validCharmIds = new HashSet<uint> { 37, 38 };
var charmPlacements = new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>
{
    [7] = new Dictionary<uint, CharmNativePlacement>
    {
        [3] = new CharmNativePlacement(3, 2.1f, 0.43f, 3.43f),
    },
};
var charm = new CharmPreset { Id = 37, PlacementId = 3, Seed = 12345 };
Require(CharmAttributePlanner.TryBuild(7, true, charm, validCharmIds, charmPlacements, out var charmAttributes, out var charmError)
    && charmAttributes.Select(attribute => attribute.Name).SequenceEqual([
        "keychain slot 0 id", "keychain slot 0 seed", "keychain slot 0 offset x",
        "keychain slot 0 offset y", "keychain slot 0 offset z",
    ]), $"A valid charm plan must resolve catalog-owned XYZ attributes: {charmError}");
Require(!CharmAttributePlanner.TryBuild(7, true, new CharmPreset { Id = 37, PlacementId = 99 }, validCharmIds, charmPlacements, out _, out charmError)
    && charmError.Contains("placement"), "Unknown charm placements must be rejected before native writes.");
Require(!CharmAttributePlanner.TryBuild(515, true, charm, validCharmIds, charmPlacements, out _, out charmError)
    && charmError.Contains("knife"), "Knife charms must be rejected before native writes.");
Require(DecorationConfigPolicy.CanPreserveStickers(
        7, true, [customSticker], new HashSet<uint>(), new Dictionary<ushort, uint>()),
    "A temporarily missing catalog must not erase structurally valid saved stickers.");
Require(DecorationConfigPolicy.CanPreserveCharm(
        7, true, charm, new HashSet<uint>(),
        new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>()),
    "A temporarily missing catalog must not erase a structurally valid saved charm.");
Require(!DecorationConfigPolicy.CanPreserveStickers(
        7, true, [new StickerPreset { Slot = 0, Id = 1, Scale = float.NaN }],
        new HashSet<uint>(), new Dictionary<ushort, uint>()),
    "Catalog fallback must still reject invalid sticker ranges.");
Require(!DecorationConfigPolicy.CanPreserveCharm(
        7, true, new CharmPreset { Id = 37, PlacementId = 3, Seed = -1 }, new HashSet<uint>(),
        new Dictionary<ushort, IReadOnlyDictionary<uint, CharmNativePlacement>>()),
    "Catalog fallback must still reject invalid charm ranges.");
const string ctAgent = "agents\\models\\ctm_fbi\\ctm_fbi.vmdl";
const string tAgent = "agents\\models\\tm_phoenix\\tm_phoenix.vmdl";
var agentModels = new Dictionary<CosmeticTeam, HashSet<string>>
{
    [CosmeticTeam.Ct] = new(StringComparer.OrdinalIgnoreCase) { ctAgent },
    [CosmeticTeam.T] = new(StringComparer.OrdinalIgnoreCase) { tAgent },
};
Require(AgentModelPolicy.IsAllowed(CosmeticTeam.Ct, ctAgent, agentModels),
    "A catalog-owned CT agent model must be accepted for CT.");
Require(!AgentModelPolicy.IsAllowed(CosmeticTeam.T, ctAgent, agentModels),
    "A CT agent model must never be accepted for T.");
Require(!AgentModelPolicy.IsAllowed(CosmeticTeam.Ct, "agents\\models\\ctm_unknown\\escape.vmdl", agentModels),
    "An unknown agent model must be rejected before SetModel.");
Require(AgentModelPolicy.IsAllowed(CosmeticTeam.Ct, string.Empty, agentModels),
    "An empty agent model must preserve the game default.");
Require(StickerFailurePolicy.ShouldRestoreBaseSkin(false) && !StickerFailurePolicy.ShouldRestoreBaseSkin(true),
    "A failed sticker plan or native write must restore the ordinary gun skin attributes.");

var linkedStickerConfig = new KnifeConfig();
linkedStickerConfig.Loadouts.Ct.GunPresets[9] = Preset(344);
linkedStickerConfig.Loadouts.Ct.GunPresets[9].Stickers = [customSticker.Clone()];
linkedStickerConfig.Loadouts.Ct.GunPresets[9].Charm = charm.Clone();
linkedStickerConfig.SharedWeaponLinks[9] = true;
linkedStickerConfig.Normalize();
Require(linkedStickerConfig.Loadouts.T.GunPresets[9].BaseValueEquals(linkedStickerConfig.Loadouts.Ct.GunPresets[9])
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Stickers.Count == 0
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Charm == null,
    "Shared CT/T normalization must copy only the base skin into a missing team preset.");
linkedStickerConfig.Loadouts.T.GunPresets[9].Paint = 279;
linkedStickerConfig.Loadouts.T.GunPresets[9].Stickers = [new StickerPreset { Slot = 1, Id = 2, Schema = 1, Scale = 1f }];
linkedStickerConfig.Loadouts.T.GunPresets[9].Charm = new CharmPreset { Id = 38, PlacementId = charm.PlacementId, Seed = 7 };
linkedStickerConfig.Normalize();
Require(linkedStickerConfig.Loadouts.T.GunPresets[9].Paint == 344
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Stickers.Single().Id == 2
    && linkedStickerConfig.Loadouts.T.GunPresets[9].Charm?.Id == 38,
    "Shared CT/T normalization must synchronize base skin fields without replacing team decorations.");

var tracker = new ApplyGenerationTracker();
nint playerHandle = (nint)0x1000;

long initialSpawn = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
Require(tracker.TryStartGloveOperation(playerHandle, initialSpawn) &&
        !tracker.TryStartGloveOperation(playerHandle, initialSpawn),
    "Scheduled apply retries must not queue duplicate glove NextFrame writes.");
long firstGive = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(!tracker.CompleteGloveOperation(playerHandle, initialSpawn) &&
        tracker.TryStartGloveOperation(playerHandle, firstGive) &&
        tracker.CompleteGloveOperation(playerHandle, firstGive),
    "A new generation must carry an unfinished glove phase and reject the stale callback.");
Require(!tracker.IsCurrent(playerHandle, initialSpawn),
    "A GiveNamedItem event must invalidate callbacks from the previous generation.");
Require(tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Knife) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Guns) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Music) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Agent),
    "A GiveNamedItem event must carry unfinished spawn phases into the new generation.");

Require(tracker.Complete(playerHandle, firstGive, CosmeticApplyPhase.Music),
    "The current generation must complete a phase before a pickup storm.");
long pickupStorm = firstGive;
for (int i = 0; i < 100; i++)
    pickupStorm = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(!tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Music),
    "A completed phase must not be reintroduced by later gun-only events.");
Require(tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Knife) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Guns) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Agent),
    "A GiveNamedItem storm must preserve unfinished knife, gun, and agent phases.");
Require(tracker.MarkRetryExhausted(playerHandle, pickupStorm),
    "The final bounded attempt must record unfinished phases once.");
Require(!tracker.MarkRetryExhausted(playerHandle, pickupStorm) && tracker.RetryExhaustions == 1,
    "Repeated final callbacks must not duplicate retry exhaustion diagnostics.");
long retryAfterEvent = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(tracker.MarkRetryExhausted(playerHandle, retryAfterEvent) && tracker.RetryExhaustions == 2,
    "A later gameplay event must create a fresh bounded retry window.");
Require(tracker.TryMarkReequip(playerHandle, retryAfterEvent) && !tracker.TryMarkReequip(playerHandle, retryAfterEvent),
    "A generation must issue at most one controlled re-equip fallback.");
long nextReequipGeneration = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(tracker.TryMarkReequip(playerHandle, nextReequipGeneration),
    "A later gameplay generation may issue one new controlled re-equip fallback.");

tracker.CancelAll();
for (int i = 0; i < 1000; i++)
{
    nint firstPawn = (nint)(0x2000 + i * 2);
    nint replacementPawn = firstPawn + 1;

    long spawn = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
    Require(tracker.TryBindContext(playerHandle, spawn, firstPawn, (int)CosmeticTeam.Ct),
        "The current spawn generation must bind its initial pawn and team.");
    Require(tracker.TryStartKnifeOperation(playerHandle, spawn) &&
            !tracker.TryStartKnifeOperation(playerHandle, spawn),
        "One apply generation may start exactly one knife mutation.");
    Require(tracker.Complete(playerHandle, spawn, CosmeticApplyPhase.Knife),
        "Success or failure must terminate the knife phase.");
    Require(!tracker.IsPending(playerHandle, spawn, CosmeticApplyPhase.Knife) &&
            !tracker.TryStartKnifeOperation(playerHandle, spawn),
        "Scheduled 0.25/0.50/0.90 retries must not restart a failed knife operation.");

    long teamChange = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
    Require(!tracker.IsCurrent(playerHandle, spawn),
        "A team change must invalidate every callback from the old spawn generation.");
    Require(!tracker.Complete(playerHandle, spawn, CosmeticApplyPhase.Gloves),
        "A stale callback must not complete or write any phase.");
    Require(tracker.TryBindContext(playerHandle, teamChange, replacementPawn, (int)CosmeticTeam.T),
        "The replacement generation must bind the replacement pawn and team.");
    Require(!tracker.TryBindContext(playerHandle, teamChange, firstPawn, (int)CosmeticTeam.T),
        "A pawn replacement inside one generation must cancel that generation.");
    Require(!tracker.IsCurrent(playerHandle, teamChange),
        "A generation with a changed pawn must remain cancelled.");

    long pickup = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
    Require(tracker.TryBindContext(playerHandle, pickup, replacementPawn, (int)CosmeticTeam.T),
        "A pickup generation must bind the current pawn.");
    Require(tracker.Complete(playerHandle, pickup, CosmeticApplyPhase.Guns),
        "A pickup generation must complete its single gun phase.");
    Require(!tracker.HasPending(playerHandle, pickup),
        "A completed pickup generation must not schedule repeated native writes.");
}

tracker.CancelAll();
Require(!tracker.IsCurrent(playerHandle, 3000), "Map or round cleanup must cancel all generations.");
Require(tracker.ActiveCount == 0 && tracker.ContextInvalidations == 1000,
    "Lifecycle diagnostics must count invalidated Pawn contexts without retaining generations.");

Require(!ApplyPipelineContext.IsReady(false, true, (nint)0x3000, CosmeticTeam.Ct),
    "A dead Pawn exposed by an early deathmatch spawn callback must not bind the new generation.");
Require(ApplyPipelineContext.IsReady(true, true, (nint)0x3001, CosmeticTeam.Ct),
    "A live replacement Pawn must be accepted on a later bounded retry.");
Require(ApplyPipelineContext.RetryDelays[^1] >= 0.90f,
    "The bounded retry window must cover delayed deathmatch and retake respawns.");

for (int i = 0; i < 1000; i++)
{
    tracker.Cancel(playerHandle);
    long respawn = tracker.Begin(playerHandle, CosmeticApplyPhase.All);
    nint oldCorpse = (nint)(0x4000 + i * 2);
    nint newPawn = oldCorpse + 1;
    Require(!ApplyPipelineContext.IsReady(false, true, oldCorpse, CosmeticTeam.T),
        "A corpse must not become the bound context for a rapid respawn.");
    Require(tracker.TryBindContext(playerHandle, respawn, newPawn, (int)CosmeticTeam.T),
        "The live replacement Pawn must bind after death cancellation.");
    Require(tracker.Complete(playerHandle, respawn, CosmeticApplyPhase.All),
        "Every cosmetic phase must be eligible to complete after a rapid respawn.");
}

var throttle = new ApplyErrorThrottle(TimeSpan.FromSeconds(30));
var now = DateTimeOffset.UtcNow;
Require(throttle.Check("gun", now).ShouldLog, "The first native write error must be logged.");
Require(!throttle.Check("gun", now.AddSeconds(1)).ShouldLog,
    "Repeated errors inside the throttle window must be suppressed.");
var resumed = throttle.Check("gun", now.AddSeconds(31));
Require(resumed.ShouldLog && resumed.Suppressed == 1,
    "The next error record must report how many duplicate errors were suppressed.");

Console.WriteLine("PlayerKnifeCustomizer resolver, knife safety, and log-throttle tests passed.");
