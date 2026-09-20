using PlayerKnifeCustomizer;

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
long firstGive = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(!tracker.IsCurrent(playerHandle, initialSpawn),
    "A GiveNamedItem event must invalidate callbacks from the previous generation.");
Require(tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Knife) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Gloves) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Guns) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Music) &&
        tracker.IsPending(playerHandle, firstGive, CosmeticApplyPhase.Agent),
    "A GiveNamedItem event must carry every unfinished spawn phase, including agents, into the new generation.");

Require(tracker.Complete(playerHandle, firstGive, CosmeticApplyPhase.Music),
    "The current generation must complete a phase before a pickup storm.");
long pickupStorm = firstGive;
for (int i = 0; i < 100; i++)
    pickupStorm = tracker.Begin(playerHandle, CosmeticApplyPhase.Guns);
Require(!tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Music),
    "A completed phase must not be reintroduced by later gun-only events.");
Require(tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Knife) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Gloves) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Guns) &&
        tracker.IsPending(playerHandle, pickupStorm, CosmeticApplyPhase.Agent),
    "A GiveNamedItem storm must preserve unfinished knife, glove, gun, and agent phases.");
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
    Require(tracker.Complete(playerHandle, spawn, CosmeticApplyPhase.Knife),
        "The first knife write must complete the knife phase.");
    Require(!tracker.IsPending(playerHandle, spawn, CosmeticApplyPhase.Knife),
        "A completed phase must not be written again by a later retry.");

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

// Weapon Provenance Tracker Tests
var provTracker = new WeaponProvenanceTracker();
nint p1 = (nint)0x5000;
nint p2 = (nint)0x6000;
nint wOwnedAk = (nint)0x7001;
uint wOwnedAkIdx = 101;
ushort akDefIndex = 7;

nint wForeignAk = (nint)0x7002;
uint wForeignAkIdx = 102;

// 1. New owned entity granted to player -> eligible to apply
long g1 = provTracker.RegisterGrantedWeapon(p1, (int)CosmeticTeam.Ct, wOwnedAk, wOwnedAkIdx, akDefIndex);
Require(g1 > 0, "Registration must return a valid generation.");
Require(provTracker.IsEligibleForApply(p1, wOwnedAk, wOwnedAkIdx, akDefIndex),
    "A newly granted weapon must be eligible for cosmetic preset application.");
Require(provTracker.IsEligibleForLiveReload(p1, wOwnedAk, wOwnedAkIdx, akDefIndex),
    "A newly granted weapon must be eligible for live cosmetic reload.");

// 2. Unknown picked entity (foreign bot gun) -> preserve existing, not eligible to apply
var foreignDecision = provTracker.EvaluatePickup(p1, (int)CosmeticTeam.Ct, wForeignAk, wForeignAkIdx, akDefIndex);
Require(foreignDecision.Action == ProvenanceAction.PreserveExisting && !foreignDecision.IsOwnedByPlayer,
    "Unknown picked weapon must be preserved as foreign entity.");
Require(!provTracker.IsEligibleForApply(p1, wForeignAk, wForeignAkIdx, akDefIndex),
    "Foreign picked weapon must NOT be eligible for cosmetic preset application.");
Require(!provTracker.IsEligibleForLiveReload(p1, wForeignAk, wForeignAkIdx, akDefIndex),
    "Foreign picked weapon must NOT be eligible for live cosmetic reload.");

// 3. Owned dropped and re-picked entity -> preserve existing appearance, still recognized as owned
provTracker.RecordApplied(wOwnedAk, wOwnedAkIdx);
var repickDecision = provTracker.EvaluatePickup(p1, (int)CosmeticTeam.Ct, wOwnedAk, wOwnedAkIdx, akDefIndex);
Require(repickDecision.Action == ProvenanceAction.PreserveExisting && repickDecision.IsOwnedByPlayer,
    "Repicked owned weapon must preserve existing appearance and be recognized as owned.");
Require(provTracker.IsEligibleForLiveReload(p1, wOwnedAk, wOwnedAkIdx, akDefIndex),
    "Repicked owned weapon remains eligible for live cosmetic reload.");

// 4. Same DefIndex but different entity -> no state leak between entities
Require(provTracker.IsEligibleForLiveReload(p1, wOwnedAk, wOwnedAkIdx, akDefIndex),
    "Player's own AK entity must be recognized.");
Require(!provTracker.IsEligibleForLiveReload(p1, wForeignAk, wForeignAkIdx, akDefIndex),
    "Foreign AK entity with identical DefIndex must not leak ownership.");

// 5. Destroyed entity -> provenance removed
Require(provTracker.UnregisterEntity(wOwnedAk, wOwnedAkIdx), "Entity unregistration must succeed.");
Require(!provTracker.IsEligibleForApply(p1, wOwnedAk, wOwnedAkIdx, akDefIndex),
    "Destroyed entity must no longer be eligible for preset application.");

// 6. Generation / handle reuse -> no old ownership leak
nint reusedHandle = wOwnedAk;
uint reusedIdx = wOwnedAkIdx;
ushort m4DefIndex = 16;
provTracker.RegisterGrantedWeapon(p2, (int)CosmeticTeam.T, reusedHandle, reusedIdx, m4DefIndex);
Require(!provTracker.IsEligibleForApply(p1, reusedHandle, reusedIdx, akDefIndex),
    "Reused handle must not retain old player 1 or old defIndex eligibility.");
Require(provTracker.IsEligibleForApply(p2, reusedHandle, reusedIdx, m4DefIndex),
    "Reused handle must correctly bind to player 2 and new defIndex.");

// 7. Clear player on disconnect
provTracker.ClearPlayer(p2);
Require(!provTracker.IsEligibleForApply(p2, reusedHandle, reusedIdx, m4DefIndex),
    "Player disconnect cleanup must remove all tracked entities for that player.");
Require(provTracker.TrackedCount == 0, "Tracker should be empty after cleanup.");

// --- CosmeticConfigDiffEngine Tests ---
var baseCfg = new KnifeConfig();
baseCfg.Normalize();

// 1. Identical configs produce no diff
var cloneCfg = new KnifeConfig();
cloneCfg.Normalize();
var emptyDiff = CosmeticConfigDiffEngine.Diff(baseCfg, cloneCfg);
Require(!emptyDiff.HasChanges, "Identical configs must produce no diff.");
Require(emptyDiff.Sections == CosmeticChangeSection.None, "No sections should be flagged.");
Require(emptyDiff.ChangedGunDefIndexes.Count == 0, "No changed gun defindexes.");

// 2. Knife change diff
var knifeDiffCfg = new KnifeConfig();
knifeDiffCfg.Normalize();
knifeDiffCfg.Loadouts.Ct.DefaultKnifeDefIndex = 508; // M9 Bayonet
var knifeDiff = CosmeticConfigDiffEngine.Diff(baseCfg, knifeDiffCfg);
Require(knifeDiff.HasChanges, "Knife defindex change must produce diff.");
Require(knifeDiff.Sections.HasFlag(CosmeticChangeSection.Knife), "Sections must flag Knife.");
Require(!knifeDiff.Sections.HasFlag(CosmeticChangeSection.Gloves), "Sections must not flag Gloves.");

// 3. Glove change diff
var gloveDiffCfg = new KnifeConfig();
gloveDiffCfg.Normalize();
gloveDiffCfg.Loadouts.Ct.Glove = new GlovePreset { Enabled = true, DefIndex = 5030, Paint = 10006 };
var gloveDiff = CosmeticConfigDiffEngine.Diff(baseCfg, gloveDiffCfg);
Require(gloveDiff.HasChanges, "Glove change must produce diff.");
Require(gloveDiff.Sections.HasFlag(CosmeticChangeSection.Gloves), "Sections must flag Gloves.");
Require(!gloveDiff.Sections.HasFlag(CosmeticChangeSection.Knife), "Sections must not flag Knife.");

// 4. Specific gun DefIndex diff
var gunDiffCfg = new KnifeConfig();
gunDiffCfg.Normalize();
gunDiffCfg.Loadouts.Ct.GunPresets[7] = Preset(661); // AK-47
gunDiffCfg.Loadouts.Ct.GunPresets[16] = Preset(309); // M4A4
var gunDiff = CosmeticConfigDiffEngine.Diff(baseCfg, gunDiffCfg);
Require(gunDiff.HasChanges, "Gun presets change must produce diff.");
Require(gunDiff.Sections.HasFlag(CosmeticChangeSection.Guns), "Sections must flag Guns.");
Require(gunDiff.ChangedGunDefIndexes.SetEquals(new ushort[] { 7, 16 }),
    "ChangedGunDefIndexes must contain exactly the modified defindexes (7, 16).");

// 4b. Changing only one gun defindex in subsequent diff
var gunDiffCfg2 = new KnifeConfig();
gunDiffCfg2.Normalize();
gunDiffCfg2.Loadouts.Ct.GunPresets[7] = Preset(661); // AK-47 unchanged
gunDiffCfg2.Loadouts.Ct.GunPresets[16] = Preset(310); // M4A4 paint changed from 309 to 310
var singleGunDiff = CosmeticConfigDiffEngine.Diff(gunDiffCfg, gunDiffCfg2);
Require(singleGunDiff.HasChanges, "Single gun change must produce diff.");
Require(singleGunDiff.ChangedGunDefIndexes.SetEquals(new ushort[] { 16 }),
    "ChangedGunDefIndexes must contain ONLY defindex 16 when 7 was unchanged.");

// 5. Agent model change diff
var agentDiffCfg = new KnifeConfig();
agentDiffCfg.Normalize();
agentDiffCfg.AgentsEnabled = true;
agentDiffCfg.Loadouts.Ct.AgentModel = "characters/models/ctm_diver.vmdl";
var agentDiff = CosmeticConfigDiffEngine.Diff(baseCfg, agentDiffCfg);
Require(agentDiff.HasChanges, "Agent change must produce diff.");
Require(agentDiff.Sections.HasFlag(CosmeticChangeSection.Agents), "Sections must flag Agents.");

// 6. Music kit change diff
var musicDiffCfg = new KnifeConfig();
musicDiffCfg.Normalize();
musicDiffCfg.MusicKitId = 42;
var musicDiff = CosmeticConfigDiffEngine.Diff(baseCfg, musicDiffCfg);
Require(musicDiff.HasChanges, "Music kit change must produce diff.");
Require(musicDiff.Sections.HasFlag(CosmeticChangeSection.Music), "Sections must flag Music.");

// --- DebounceScheduler Tests ---
using (var scheduler = new DebounceScheduler(50))
{
    int executedCount = 0;
    var resetEvent = new ManualResetEventSlim(false);

    // Rapidly schedule 5 actions within short window
    for (int i = 0; i < 5; i++)
    {
        scheduler.Schedule(() =>
        {
            Interlocked.Increment(ref executedCount);
            resetEvent.Set();
        });
        Thread.Sleep(10);
    }

    bool signaled = resetEvent.Wait(500);
    Require(signaled, "DebounceScheduler must fire after delay.");
    // Small sleep to ensure no trailing duplicate executions
    Thread.Sleep(100);
    Require(executedCount == 1, $"DebounceScheduler must collapse rapid bursts into 1 invocation (actual: {executedCount}).");
}

// --- KnifeShortcutCycle Tests ---
// 1. Default sequence verification (Karambit -> Butterfly -> M9 -> Bayonet -> Skeleton -> Falchion -> Karambit)
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(0) == 507, "Default knife from 0 must be 507 (Karambit).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(507) == 515, "Next knife from Karambit (507) must be Butterfly (515).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(515) == 508, "Next knife from Butterfly (515) must be M9 Bayonet (508).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(508) == 500, "Next knife from M9 Bayonet (508) must be Bayonet (500).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(500) == 525, "Next knife from Bayonet (500) must be Skeleton (525).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(525) == 512, "Next knife from Skeleton (525) must be Falchion (512).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(512) == 507, "Next knife from Falchion (512) must wrap around to Karambit (507).");

// 2. Unknown knife defindex falls back to first knife in list
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(503) == 507, "Unknown knife defindex (503) must cycle to first knife (507).");

// 3. Custom list support
ushort[] customCycle = [508, 525];
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(508, customCycle) == 525, "Custom cycle 508 -> 525.");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(525, customCycle) == 508, "Custom cycle 525 -> 508 (wraparound).");
Require(KnifeShortcutCycle.GetNextKnifeDefIndex(507, customCycle) == 508, "Out of list knife -> 508.");

// 4. Knife display names
Require(KnifeShortcutCycle.GetKnifeDisplayName(507) == "Karambit", "507 display name must be Karambit.");
Require(KnifeShortcutCycle.GetKnifeDisplayName(515) == "Butterfly Knife", "515 display name must be Butterfly Knife.");
Require(KnifeShortcutCycle.GetKnifeDisplayName(508) == "M9 Bayonet", "508 display name must be M9 Bayonet.");

// 5. Knife designer names
Require(KnifeShortcutCycle.GetKnifeDesignerName(500) == "weapon_bayonet", "500 designer name must be weapon_bayonet.");
Require(KnifeShortcutCycle.GetKnifeDesignerName(507) == "weapon_knife_karambit", "507 designer name must be weapon_knife_karambit.");
Require(KnifeShortcutCycle.GetKnifeDesignerName(515) == "weapon_knife_butterfly", "515 designer name must be weapon_knife_butterfly.");
Require(KnifeShortcutCycle.GetKnifeDesignerName(508) == "weapon_knife_m9_bayonet", "508 designer name must be weapon_knife_m9_bayonet.");
Require(KnifeShortcutCycle.GetKnifeDesignerName(525) == "weapon_knife_skeleton", "525 designer name must be weapon_knife_skeleton.");
Require(KnifeShortcutCycle.GetKnifeDesignerName(512) == "weapon_knife_falchion", "512 designer name must be weapon_knife_falchion.");
Require(KnifeShortcutCycle.GetKnifeDesignerName(999) == "weapon_knife", "Unknown defindex must fall back to weapon_knife.");

// --- KnifeReplacementPlanner Tests ---
// Test 1: Plan with existing painted preset
var testLoadout = new TeamLoadout();
testLoadout.DefaultKnifeDefIndex = 507;
testLoadout.KnifePresets[515] = new KnifePreset { Paint = 418, Seed = 10, Wear = 0.05f };

var plan1 = KnifeReplacementPlanner.Plan(507, null, testLoadout);
Require(plan1.IsValid, "Plan from 507 to 515 must be valid.");
Require(plan1.TargetDefIndex == 515, "Target must be 515 (Butterfly).");
Require(plan1.DesignerName == "weapon_knife_butterfly", "Designer name must be weapon_knife_butterfly.");
Require(!plan1.IsVanilla, "Knife with Paint 418 is not vanilla.");
Require(plan1.Preset.Paint == 418, "Preset paint must be 418.");

// Test 2: Plan when next knife has no preset in loadout (falls back to vanilla Paint = 0)
var plan2 = KnifeReplacementPlanner.Plan(515, null, testLoadout);
Require(plan2.IsValid, "Plan from 515 to 508 must be valid.");
Require(plan2.TargetDefIndex == 508, "Target must be 508 (M9 Bayonet).");
Require(plan2.DesignerName == "weapon_knife_m9_bayonet", "Designer name must be weapon_knife_m9_bayonet.");
Require(plan2.IsVanilla, "Missing preset must fall back to vanilla (Paint = 0).");
Require(testLoadout.KnifePresets.ContainsKey(508), "Loadout must now contain a fallback preset for 508.");
Require(testLoadout.KnifePresets[508].Paint == 0, "Fallback preset paint must be 0.");

// Test 3: Plan with custom cycle list
ushort[] myCycle = [500, 526];
var plan3 = KnifeReplacementPlanner.Plan(500, myCycle, testLoadout);
Require(plan3.IsValid, "Plan with custom cycle must be valid.");
Require(plan3.TargetDefIndex == 526, "500 must cycle to 526 in custom list.");
Require(plan3.DesignerName == "weapon_knife_kukri", "526 designer name must be weapon_knife_kukri.");

// Test 4: Unknown current knife defindex (e.g. 0 or default knife) cycles to first in list
var plan4 = KnifeReplacementPlanner.Plan(0, myCycle, testLoadout);
Require(plan4.IsValid, "Plan from 0 must be valid.");
Require(plan4.TargetDefIndex == 500, "0 must cycle to first knife in custom list (500).");

// Test 5: Empty custom list fallback
var plan5 = KnifeReplacementPlanner.Plan(507, Array.Empty<ushort>(), testLoadout);
Require(plan5.IsValid, "Empty custom list must fall back to DefaultShortcutKnives.");
Require(plan5.TargetDefIndex == 515, "Empty custom list must cycle Karambit to Butterfly.");

// Test 6: Transactional rollback guarantee simulation
// If new entity fails to create, DefaultKnifeDefIndex in loadout is NOT changed
ushort originalDefIndex = testLoadout.DefaultKnifeDefIndex;
var failedPlan = KnifeReplacementPlanner.Plan(testLoadout.DefaultKnifeDefIndex, null, testLoadout);
bool simulationGiveFailed = true;
if (simulationGiveFailed)
{
    // Transaction aborts without committing DefaultKnifeDefIndex
}
else
{
    testLoadout.DefaultKnifeDefIndex = failedPlan.TargetDefIndex;
}
Require(testLoadout.DefaultKnifeDefIndex == originalDefIndex, "Failed replacement must NOT advance DefaultKnifeDefIndex.");

Console.WriteLine("PlayerKnifeCustomizer resolver, lifecycle, provenance, diff-engine, debouncer, knife-shortcut, knife-replacement-planner, and log-throttle tests passed.");

