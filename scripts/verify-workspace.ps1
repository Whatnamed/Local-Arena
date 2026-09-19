[CmdletBinding()]
param(
    [string]$PackageRoot,
    [string]$ExpectedPackageVersion = "1.4.3.3"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot "dependencies.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot "VpkTools.ps1")
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Missing $Label`: $Path"
    }
}

function Get-JsonCount([string]$RelativePath) {
    $path = Join-Path $repo $RelativePath
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($path))
        try {
            if ($document.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
                return $document.RootElement.GetArrayLength()
            }
            if ($document.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                $count = 0
                foreach ($property in $document.RootElement.EnumerateObject()) { $count++ }
                return $count
            }
            return 1
        }
        finally {
            $document.Dispose()
        }
    }
    catch {
        Add-Failure "Invalid JSON $RelativePath`: $($_.Exception.Message)"
        return -1
    }
}

$base = if ($manifest.upstream.sourceCommit) { $manifest.upstream.sourceCommit } else { $manifest.upstream.baseCommit }

$localBuildConfig = Join-Path $repo ".local-build.ps1"
if ($env:GITHUB_ACTIONS -ne "true" -and -not (Test-Path -LiteralPath $localBuildConfig -PathType Leaf)) {
    Add-Failure "Local build configuration is missing; run the workspace setup before building."
}
$buildScript = Get-Content -LiteralPath (Join-Path $repo "scripts/build.ps1") -Raw
$privateToolLabel = "portable" + "-toolchain"
if ($buildScript.Contains($privateToolLabel, [StringComparison]::OrdinalIgnoreCase)) {
    Add-Failure "Build scripts must not expose the local tool directory name."
}

& git -C $repo cat-file -e "$base^{commit}" 2>$null
$baseAvailable = $LASTEXITCODE -eq 0
if (-not $baseAvailable -and $env:GITHUB_ACTIONS -eq "true") {
    & git -C $repo fetch --no-tags --depth=1 $manifest.upstream.repository $base
    if ($LASTEXITCODE -eq 0) {
        & git -C $repo cat-file -e "$base^{commit}" 2>$null
        $baseAvailable = $LASTEXITCODE -eq 0
    }
}
if (-not $baseAvailable) {
    Add-Failure "Pinned upstream commit is unavailable: $base"
}
else {
    $upstreamModules = @(
        "addons/counterstrikesharp/plugins/BotAI",
        "addons/counterstrikesharp/plugins/BotAimImprover",
        "addons/counterstrikesharp/plugins/BotBuy",
        "addons/counterstrikesharp/plugins/BotControllerImpl",
        "addons/counterstrikesharp/plugins/BotHiderImpl",
        "addons/counterstrikesharp/plugins/BotRandomizer",
        "addons/counterstrikesharp/plugins/BotState",
        "addons/counterstrikesharp/plugins/NadeSystem",
        "addons/counterstrikesharp/plugins/RoundDamageRecap",
        "overrides"
    )
    $changed = @(
        foreach ($module in $upstreamModules) {
            & git -C $repo diff --ignore-space-at-eol --quiet $base -- $module
            if ($LASTEXITCODE -eq 1) {
                & git -C $repo diff --ignore-space-at-eol --name-only $base -- $module
            }
            elseif ($LASTEXITCODE -ne 0) {
                Add-Failure "Unable to compare upstream enhanced-bot module: $module"
            }
        }
    )
    $allowedUpstreamChanges = @(
        "addons/counterstrikesharp/plugins/BotAimImprover/BotAimImprover.cs",
        "addons/counterstrikesharp/plugins/BotAimImprover/BotAimImprover.csproj",
        "addons/counterstrikesharp/plugins/BotBuy/BotBuy.cs",
        "addons/counterstrikesharp/plugins/BotBuy/BotBuy.csproj",
        "addons/counterstrikesharp/plugins/BotRandomizer/BotRandomizer.cs",
        "addons/counterstrikesharp/plugins/BotRandomizer/Cosmetics/CosmeticModels.cs",
        "addons/counterstrikesharp/plugins/BotRandomizer/bot_randomizer_options.json",
        "addons/counterstrikesharp/plugins/BotControllerImpl/BotControllerImpl.csproj",
        "addons/counterstrikesharp/plugins/BotControllerImpl/BotController.NativeApi.cs",
        "addons/counterstrikesharp/plugins/BotControllerImpl/BotControllerApiImpl.cs",
        "addons/counterstrikesharp/plugins/BotControllerImpl/BotControllerCapability.cs",
        "addons/counterstrikesharp/plugins/BotControllerImpl/BotControllerImplPlugin.cs",
        "addons/counterstrikesharp/plugins/BotControllerImpl/MotionRecording.cs",
        "addons/counterstrikesharp/plugins/BotControllerImpl/ReplayDriver.cs",
        "addons/counterstrikesharp/plugins/BotHiderImpl/BotHiderImpl.csproj",
        "addons/counterstrikesharp/plugins/BotHiderImpl/BotHiderImplPlugin.cs",
        "addons/counterstrikesharp/plugins/NadeSystem/NadeSystem.cs",
        "addons/counterstrikesharp/plugins/NadeSystem/NadeSystem.csproj",
        "addons/counterstrikesharp/plugins/RoundDamageRecap/RoundDamageRecap.cs",
        "addons/counterstrikesharp/plugins/RoundDamageRecap/RoundDamageRecap.csproj",
        "overrides/Low/botprofile.db",
        "overrides/Medium/botprofile.db",
        "overrides/High/botprofile.db"
    )
    $unexpectedChanges = @($changed | Where-Object { $_ -notin $allowedUpstreamChanges })
    if ($unexpectedChanges.Count -gt 0) {
        Add-Failure "Upstream enhanced-bot modules were modified: $($unexpectedChanges -join ', ')"
    }
}

$botAiProject = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/BotAI/BotAI.csproj") -Raw
if ($botAiProject -match 'Tmp\\ArchiveV02\\Common') {
    Add-Failure "BotAI still references the machine-specific Common.dll path."
}

$botAimImprover = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/BotAimImprover/BotAimImprover.cs") -Raw
$botBehaviorPolicy = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/shared/MatchCore/BotBehaviorPolicy.cs") -Raw
if ($botAimImprover -match 'MemoryFunction|DynamicHook|\.Hook\(' -or
    $botAimImprover -match 'WindowsOffsets|LinuxOffsets|ReadIntPtr|ReadInt32|ReadByte' -or
    $botAimImprover -notmatch 'RegisterListener<Listeners\.OnTick>\(OnTick\)' -or
    $botAimImprover -notmatch 'pawn\?\.Bot' -or
    $botAimImprover -notmatch 'bot\.TargetSpot' -or
    $botAimImprover -notmatch 'BotAimPolicy\.SelectPriority' -or
    $botAimImprover -notmatch 'AimPointIndex' -or
    $botAimImprover -notmatch 'TargetSpot write verification failed' -or
    $botBehaviorPolicy -notmatch 'BotAimMode\.Head when string\.Equals\(weapon, "weapon_awp"' -or
    $botBehaviorPolicy -notmatch 'BotAimMode\.Head => BotAimPriority\.Head') {
    Add-Failure "BotAimImprover must use managed CCSBot schema targeting without native function hooks or manual offsets."
}
$panelBackend = Get-Content -LiteralPath (Join-Path $repo "Panel/src-tauri/src/lib.rs") -Raw
if ($panelBackend -match 'aim_supported: true' -or
    $panelBackend -notmatch 'aim_supported,' -or
    $panelBackend -notmatch '\.csbip/aim-runtime\.json' -or
    $panelBackend -notmatch 'aim_override_count') {
    Add-Failure "Panel backend must expose the managed bot aim modes on Windows."
}

$botBuy = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/BotBuy/BotBuy.cs") -Raw
if (([regex]::Matches($botBuy, 'AddTimer\(').Count -ne 1) -or
    ([regex]::Matches($botBuy, 'ScheduleRound\(').Count -lt 12) -or
    $botBuy -notmatch 'BotCallbackGeneration' -or
    $botBuy -notmatch 'TimerFlags\.STOP_ON_MAPCHANGE' -or
    $botBuy -notmatch 'ResolvePlayer\(userId\)' -or
    $botBuy -notmatch 'ManagedMatchRuntimeStore\.IsPurchasingAllowed' -or
    $botBuy -notmatch 'HasWeapon\(player, oldItem\)') {
    Add-Failure "BotBuy no longer guards delayed callbacks against invalid CounterStrikeSharp controllers."
}

$nadeSystem = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/NadeSystem/NadeSystem.cs") -Raw
if ($nadeSystem -notmatch 'if \(!bot\.IsValid\) return;' -or
    $nadeSystem -notmatch 'botPawn = bot\.PlayerPawn\?\.Value;' -or
    $nadeSystem -notmatch 'catch \(Exception\)\s*\{\s*return;\s*\}') {
    Add-Failure "NadeSystem no longer guards delayed callbacks against disconnected bot pawns."
}
if ($nadeSystem -notmatch '_botNadesMode == "less"' -or
    $nadeSystem -notmatch 'LessModeAllows\(' -or
    $nadeSystem -notmatch 'IncrementBotCount\(') {
    Add-Failure "NadeSystem no longer contains the upstream 1.4.3 Less mode limits."
}
$nadeDataRoot = Join-Path $repo "addons/counterstrikesharp/plugins/NadeSystem/grenades"
$nadeDataFiles = @(Get-ChildItem -LiteralPath $nadeDataRoot -Filter "*.json" -File -ErrorAction SilentlyContinue)
if ($nadeDataFiles.Count -ne 48) {
    Add-Failure "NadeSystem must ship the frozen 48-file grenade catalog; found $($nadeDataFiles.Count)."
}
foreach ($nadeDataFile in $nadeDataFiles) {
    try {
        $nadeEntries = @(Get-Content -LiteralPath $nadeDataFile.FullName -Raw | ConvertFrom-Json)
        if ($nadeEntries.Count -eq 0) {
            Add-Failure "NadeSystem grenade catalog is empty: $($nadeDataFile.Name)"
        }
    }
    catch {
        Add-Failure "NadeSystem grenade catalog is invalid: $($nadeDataFile.Name): $($_.Exception.Message)"
    }
}

$matchCoordinator = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlusMatchCoordinator/PlusMatchCoordinator.cs") -Raw
if ($matchCoordinator -notmatch 'private void EnsureInitialHumanSide\(\)' -or
    $matchCoordinator -notmatch 'if \(human\.Team != target\) human\.SwitchTeam\(target\);' -or
    ([regex]::Matches($matchCoordinator, 'EnsureInitialHumanSide\(\);').Count -ne 2) -or
    ([regex]::Matches($matchCoordinator, '\.SwitchTeam\(').Count -ne 1)) {
    Add-Failure "PlusMatchCoordinator may force the local player back to the initial side after halftime."
}

$roundDamageRecap = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/RoundDamageRecap/RoundDamageRecap.cs") -Raw
if ($roundDamageRecap -notmatch 'PlusManagedPaths\.ActiveMatchPath' -or
    $roundDamageRecap -notmatch 'PlusMatchCoordinator owns match statistics') {
    Add-Failure "RoundDamageRecap no longer yields PLUS match statistics ownership."
}

$matchPanel = Get-Content -LiteralPath (Join-Path $repo "Panel/src/panels/MatchPanel.tsx") -Raw
if ($matchPanel -notmatch 'localStorage\.getItem\("cs2bi\.matchDemoV2"\) === "1"' -or
    $matchPanel -notmatch 'match\.demoWarning') {
    Add-Failure "Match Panel no longer keeps GOTV opt-in with a performance warning."
}

$requiredSources = @(
    "Panel/src-tauri/src/lib.rs",
    "Panel/src/panels/KnifePresetModal.tsx",
    "Panel/src/panels/GlovePresetModal.tsx",
    "Panel/src/panels/WeaponPresetModal.tsx",
    "Panel/src/panels/MusicKitPresetModal.tsx",
    "Panel/src/panels/StickersPanel.tsx",
    "Panel/src/panels/StickersPanel.css",
    "Panel/src/data/stickerCatalog.json",
    "Panel/src/data/stickerCatalog.source.json",
    "Panel/src/data/stickerWeaponIds.json",
    "Panel/src/data/cosmeticPlacements.json",
    "Panel/src/data/charmCatalog.json",
    "Panel/src/data/agentCatalog.json",
    "Panel/src/lib/stickerEditor.ts",
    "scripts/generate-sticker-catalog.mjs",
    "scripts/generate-player-cosmetic-placements.mjs",
    "scripts/test-sticker-editor.mjs",
    "addons/counterstrikesharp/plugins/BotRandomizer/BotRandomizer.cs",
    "addons/counterstrikesharp/plugins/BotRandomizer/Cosmetics/CosmeticModels.cs",
    "addons/counterstrikesharp/plugins/BotRandomizer/charm_placements.json",
    "addons/counterstrikesharp/plugins/BotRandomizer/cosmetic_catalog.json",
    "addons/counterstrikesharp/plugins/BotControllerImpl/BotControllerImplPlugin.cs",
    "addons/counterstrikesharp/plugins/BotRandomizer/bot_randomizer_options.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.cs",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
    "addons/counterstrikesharp/plugins/BotHiderImpl/BotHiderImplPlugin.cs",
    "addons/counterstrikesharp/plugins/TeamLineupInjector/TeamLineupInjector.cs",
    "addons/counterstrikesharp/plugins/TeamLineupInjector/TeamLineupInjector.csproj",
    "addons/counterstrikesharp/plugins/OfflineMatchTelemetry/OfflineMatchTelemetry.cs",
    "addons/counterstrikesharp/plugins/OfflineMatchTelemetry/OfflineMatchTelemetry.csproj"
)
foreach ($relative in $requiredSources) {
    Assert-File (Join-Path $repo $relative) $relative
}

$playerCosmetics = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.cs") -Raw
$botRandomizer = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/BotRandomizer/BotRandomizer.cs") -Raw
$botRandomizerModels = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/BotRandomizer/Cosmetics/CosmeticModels.cs") -Raw
if ($botRandomizer -notmatch 'LoadOptions\(\);' -or
    $botRandomizer -notmatch '_options\.Skins && _weaponItemViews\?\.NativeAvailable' -or
    $botRandomizer -notmatch 'includeStickers: true' -or
    $botRandomizer -notmatch 'includeCharms: true' -or
    $botRandomizer -notmatch 'IsBot: true, IsHLTV: false' -or
    $botRandomizerModels -notmatch 'JsonPropertyName\("skins"\)' -or
    $botRandomizerModels -notmatch 'JsonPropertyName\("profiles"\)' -or
    $botRandomizerModels -notmatch 'JsonPropertyName\("agents"\)' -or
    $botRandomizerModels -notmatch 'JsonPropertyName\("music"\)') {
    Add-Failure "BotRandomizer no longer combines upstream Bot cosmetics with Local Arena feature gates."
}
if ($playerCosmetics -notmatch 'IsBot: false, IsHLTV: false' -or
    $playerCosmetics -notmatch 'DecorationReleaseEnabled = true' -or
    $playerCosmetics -notmatch 'CharmAttributePlanner' -or
    -not $playerCosmetics.Contains('CosmeticApplyPhase.Agent') -or
    -not $playerCosmetics.Contains('pawn.SetModel(model)') -or
    $playerCosmetics -notmatch 'player_cosmetic_catalog.json') {
    Add-Failure "Player cosmetics must remain human-only with catalog-validated sticker, charm, and agent planning."
}
$giveHookStart = $playerCosmetics.IndexOf("private HookResult OnGiveNamedItemPost", [StringComparison]::Ordinal)
$nextMethodStart = $playerCosmetics.IndexOf("private static CCSPlayerController? GetPlayerFromItemServices", [StringComparison]::Ordinal)
if ($giveHookStart -lt 0 -or $nextMethodStart -le $giveHookStart) {
    Add-Failure "PlayerCosmetics purchased-weapon lifecycle guard is missing."
}
else {
    $giveHook = $playerCosmetics.Substring($giveHookStart, $nextMethodStart - $giveHookStart)
    if ($giveHook -notmatch "_applyTracker\.Begin\(playerHandle, CosmeticApplyPhase\.Guns\)" -or
        $giveHook -notmatch "ScheduleApplyCallbacks\(playerHandle, generation\)" -or
        $giveHook -match "ApplyPreset\(" -or
        $giveHook -match "_setAttrByName.*Invoke") {
        Add-Failure "PlayerCosmetics GiveNamedItem hook must defer native writes into the bounded generation pipeline."
    }
}
if ($playerCosmetics -notmatch "Server\.NextFrame\(\(\) => RunApplyPipeline\(playerHandle, generation, false\)\)" -or
    $playerCosmetics -notmatch "RetryDelays = \[0\.10f, 0\.25f, 0\.50f, 0\.90f\]" -or
    $playerCosmetics -notmatch "finalAttempt = index == ApplyPipelineContext\.RetryDelays\.Length - 1" -or
    $playerCosmetics -notmatch "player\.PawnIsAlive" -or
    $playerCosmetics -notmatch "TryBindContext\(playerHandle, generation, readyPawn\.Handle, \(int\)readyTeam\)") {
    Add-Failure "PlayerCosmetics generation pipeline no longer has bounded retries and Pawn/team context validation."
}
if ($playerCosmetics -notmatch "private static bool HasReadyAttributeLists\(CEconItemView item\)" -or
    ([regex]::Matches($playerCosmetics, "HasReadyAttributeLists\(item\)").Count -lt 3)) {
    Add-Failure "PlayerCosmetics native attribute handles are not validated at every write entry point."
}
if ($playerCosmetics -notmatch '"sticker slot \{sticker\.Slot\}"' -or
    $playerCosmetics -notmatch "BitConverter\.Int32BitsToSingle" -or
    $playerCosmetics -notmatch "TryMarkReequip\(player\.Handle, generation\)" -or
    ([regex]::Matches($playerCosmetics, 'ExecuteClientCommand\("lastinv"\)').Count -ne 2)) {
    Add-Failure "PlayerCosmetics sticker attributes or single-generation re-equip fallback are incomplete."
}
if ($playerCosmetics -match "RegisterListener<Listeners\.OnEntitySpawned>" -or
    $playerCosmetics -match "TryApplyDroppedKnife" -or
    $playerCosmetics -match "Server\.NextWorldUpdate") {
    Add-Failure "PlayerCosmetics must not retain raw entity pointers across world updates for dropped knives."
}

$jsonFiles = @(
    "addons/BotHider/bot_info.json",
    "addons/BotHider/gamedata.json",
    "addons/BotHider/map_whitelist.json",
    "Panel/src/data/gloveSkins.json",
    "Panel/src/data/musicKits.json",
    "Panel/src/data/skinImages.json",
    "Panel/src/data/skinNames.json",
    "Panel/src/data/weaponSkins.json",
    "Panel/src/data/stickerCatalog.json",
    "Panel/src/data/stickerWeaponIds.json",
    "Panel/src/data/cosmeticPlacements.json",
    "Panel/src/data/charmCatalog.json",
    "Panel/src/data/agentCatalog.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/skins_en.json",
    "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json",
    "addons/counterstrikesharp/plugins/BotRandomizer/charm_placements.json",
    "addons/counterstrikesharp/plugins/BotRandomizer/cosmetic_catalog.json"
)
$counts = @{}
foreach ($relative in $jsonFiles) {
    $counts[$relative] = Get-JsonCount $relative
}

$catalogA = Join-Path $repo "Panel/src/data/weaponSkins.json"
$catalogB = Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json"
if ((Get-FileHash -LiteralPath $catalogA -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $catalogB -Algorithm SHA256).Hash) {
    Add-Failure "Panel and plugin weapon catalogs are not identical."
}

$panelApi = Get-Content -LiteralPath (Join-Path $repo "Panel/src/lib/api.ts") -Raw
$panelPresets = Get-Content -LiteralPath (Join-Path $repo "Panel/src/panels/PresetsPanel.tsx") -Raw
$panelBackend = Get-Content -LiteralPath (Join-Path $repo "Panel/src-tauri/src/lib.rs") -Raw
if ($panelApi -notmatch '"less"' -or
    $panelPresets -notmatch 'value: "less"' -or
    $panelBackend -notmatch '"normal", "less", "off"') {
    Add-Failure "The Panel and Rust backend no longer expose the upstream NadeSystem Less mode."
}

$stickerSourcePath = Join-Path $repo "Panel/src/data/stickerCatalog.source.json"
try {
    $stickerSource = Get-Content -LiteralPath $stickerSourcePath -Raw | ConvertFrom-Json
    $stickerPanel = Join-Path $repo "Panel/src/data/stickerCatalog.json"
    $stickerPlugin = Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json"
    $stickerWeaponPanel = Join-Path $repo "Panel/src/data/stickerWeaponIds.json"
    $stickerWeaponPlugin = Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json"
    $stickerGenerator = Get-Content -LiteralPath (Join-Path $repo "scripts/generate-sticker-catalog.mjs") -Raw
    $panelHash = (Get-FileHash -LiteralPath $stickerPanel -Algorithm SHA256).Hash.ToLowerInvariant()
    $pluginHash = (Get-FileHash -LiteralPath $stickerPlugin -Algorithm SHA256).Hash.ToLowerInvariant()
    $weaponPanelHash = (Get-FileHash -LiteralPath $stickerWeaponPanel -Algorithm SHA256).Hash.ToLowerInvariant()
    $weaponPluginHash = (Get-FileHash -LiteralPath $stickerWeaponPlugin -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($stickerSource.schema_version -ne 1 -or
        $stickerSource.outputs.count -ne $counts["Panel/src/data/stickerCatalog.json"] -or
        $counts["Panel/src/data/stickerCatalog.json"] -ne $counts["addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json"] -or
        $panelHash -ne [string]$stickerSource.outputs.panel_sha256 -or
        $pluginHash -ne [string]$stickerSource.outputs.plugin_ids_sha256 -or
        $counts["Panel/src/data/stickerWeaponIds.json"] -ne $stickerSource.capabilities.supported_weapon_count -or
        $counts["Panel/src/data/stickerWeaponIds.json"] -ne $counts["addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json"] -or
        $weaponPanelHash -ne [string]$stickerSource.outputs.weapon_ids_sha256 -or
        $weaponPluginHash -ne [string]$stickerSource.outputs.weapon_ids_sha256 -or
        $stickerGenerator -notmatch [regex]::Escape([string]$stickerSource.commit) -or
        $stickerGenerator -notmatch [regex]::Escape([string]$stickerSource.capabilities.commit)) {
        Add-Failure "Sticker catalog source commits, counts, capabilities, or deterministic hashes do not match generated outputs."
    }
}
catch {
    Add-Failure "Sticker catalog metadata is invalid: $($_.Exception.Message)"
}

try {
    $panelPlacements = Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/cosmeticPlacements.json") -Raw | ConvertFrom-Json
    $panelCharms = @(Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/charmCatalog.json") -Raw | ConvertFrom-Json)
    $panelAgents = @(Get-Content -LiteralPath (Join-Path $repo "Panel/src/data/agentCatalog.json") -Raw | ConvertFrom-Json)
    $pluginCosmetics = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json") -Raw | ConvertFrom-Json
    $placementGenerator = Get-Content -LiteralPath (Join-Path $repo "scripts/generate-player-cosmetic-placements.mjs") -Raw
    if ($pluginCosmetics.schema_version -ne 1 -or
        $counts["Panel/src/data/cosmeticPlacements.json"] -ne 35 -or
        $panelCharms.Count -ne 81 -or
        @($panelAgents | Where-Object team -eq "ct").Count -ne 35 -or
        @($panelAgents | Where-Object team -eq "t").Count -ne 44 -or
        @($pluginCosmetics.charm_ids).Count -ne $panelCharms.Count -or
        @($pluginCosmetics.agent_models.ct).Count -ne 35 -or
        @($pluginCosmetics.agent_models.t).Count -ne 44 -or
        @($panelCharms | Where-Object { -not [string]::IsNullOrWhiteSpace($_.image) }).Count -ne 78 -or
        @($panelAgents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.image) }).Count -ne 63 -or
        [string]::IsNullOrWhiteSpace($pluginCosmetics.inventory_images.commit) -or
        @($pluginCosmetics.weapons.PSObject.Properties).Count -ne 35 -or
        $placementGenerator -notmatch "charmAnchors" -or
        $placementGenerator -notmatch "source_sha256" -or
        $placementGenerator -notmatch [regex]::Escape([string]$pluginCosmetics.inventory_images.commit)) {
        Add-Failure "Player cosmetic placement, charm, or agent outputs have unexpected counts."
    }
}
catch {
    Add-Failure "Player cosmetic placement metadata is invalid: $($_.Exception.Message)"
}

$teamLineupInjector = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/TeamLineupInjector/TeamLineupInjector.cs") -Raw
if ($teamLineupInjector -notmatch 'MatchSessionActive\(\)' -or
    $teamLineupInjector -notmatch 'config is not \{ Enabled: true \}' -or
    $teamLineupInjector -notmatch '"bot_kick"' -or
    $teamLineupInjector -notmatch 'RestoreBotQuota\(\)') {
    Add-Failure "TeamLineupInjector must check Enabled and MatchSessionActive before bot_kick."
}

$matchCatalog = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/PlusMatchCoordinator/match_catalog.json") -Raw | ConvertFrom-Json
$featuredPlayers = @($matchCatalog.teams | ForEach-Object { $_.players } | Sort-Object -Unique)

function Assert-BotProfileContent([string]$Profile, [string]$Label) {
    foreach ($player in $featuredPlayers) {
        if ($Profile -notmatch ('"' + [regex]::Escape($player) + '"')) {
            Add-Failure "$Label is missing featured player $player."
        }
    }
    foreach ($match in [regex]::Matches($Profile, '(?m)^\s*LookAngleMaxAccel(?:Normal|Attacking)\s*=\s*(\S+)')) {
        $token = $match.Groups[1].Value
        $value = 0.0
        $valid = [double]::TryParse(
            $token,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value
        )
        if (-not $valid -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 20000) {
            Add-Failure "$Label has invalid LookAngleMaxAccel value '$token'."
        }
    }
}

$botHiderImpl = Get-Content -LiteralPath (Join-Path $repo "addons/counterstrikesharp/plugins/BotHiderImpl/BotHiderImplPlugin.cs") -Raw
if ($botHiderImpl -notmatch "foreach \(int slot in managedSlots\)" -or
    $botHiderImpl -notmatch "player\.PlayerName = name" -or
    $botHiderImpl -notmatch 'ModuleVersion => "0\.3\.3"' -or
    $botHiderImpl -notmatch "EnsureBotInfoNameSource\(\)") {
    Add-Failure "BotHiderImpl no longer preserves the v0.3.3 managed-name integration."
}
$botHiderGameData = Get-Content -LiteralPath (Join-Path $repo "addons/BotHider/gamedata.json") -Raw
if ($botHiderGameData -notmatch '"CServerSideClient::SetName"' -or
    $botHiderGameData -notmatch '"CNetworkGameServer::PackEntities"') {
    Add-Failure "BotHider gamedata no longer contains the v0.3.3 name and identity targets."
}
foreach ($difficulty in @("Low", "Medium", "High")) {
    $profilePath = Join-Path $repo "overrides/$difficulty/botprofile.db"
    $profile = Get-Content -LiteralPath $profilePath -Raw
    Assert-BotProfileContent $profile "$difficulty botprofile.db"
}

$trackedGenerated = @(& git -C $repo ls-files | Where-Object {
    $_ -match '(^|/)(bin|obj|node_modules|dist|target|artifacts|\.cache)/'
})
if ($trackedGenerated.Count -gt 0) {
    Add-Failure "Generated paths are tracked: $($trackedGenerated -join ', ')"
}

if ($PackageRoot) {
    $package = [IO.Path]::GetFullPath($PackageRoot)
    $requiredPackageFiles = @(
        "addons/metamod/bin/win64/server.dll",
        "addons/counterstrikesharp/bin/win64/counterstrikesharp.dll",
        "addons/metamod/counterstrikesharp.vdf",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/PlayerKnifeCustomizer.dll",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_ids.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/sticker_weapon_ids.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_cosmetic_catalog.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/skins_en.json",
        "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/weapon_skins.json",
        "cfg/cs2bi_quickknife.cfg",
        "plus-payload-manifest.json",
        "LocalArena.exe",
        "README.md",
        "README.zh-CN.md",
        "LICENSE"
    )
    foreach ($relative in $requiredPackageFiles) {
        Assert-File (Join-Path $package $relative) "package file $relative"
    }

    $forbiddenPackagePatterns = @(
        "gameinfo.gi",
        "BotAI", "BotAim", "BotBuy", "BotController", "BotHider", "BotRandomizer",
        "BotState", "NadeSystem", "RayTrace", "RoundDamageRecap",
        "PlusMatchCoordinator", "TeamLineup", "OfflineMatchTelemetry",
        "botprofile", "overrides", "open-rating", "rating-plus",
        "my_bot_ffa_config", "my_bot_normal_config", "bot_buy.cfg"
    )
    $packagedFiles = @(Get-ChildItem -LiteralPath $package -File -Recurse | ForEach-Object {
        [IO.Path]::GetRelativePath($package, $_.FullName).Replace("\", "/")
    })
    function Test-IsForbiddenPackagePath([string]$Path, [string]$Pattern) {
        if ($Pattern -eq "overrides") {
            return ($Path -match '(^|/)overrides(/|$)')
        }
        return ($Path -like "*$Pattern*")
    }
    foreach ($forbidden in $forbiddenPackagePatterns) {
        $forbiddenMatches = @($packagedFiles | Where-Object { Test-IsForbiddenPackagePath $_ $forbidden })
        if ($forbiddenMatches.Count -gt 0) {
            Add-Failure "Package contains forbidden component '$forbidden': $($forbiddenMatches -join ', ')"
        }
    }

    $previewNotice = Join-Path $package "PREVIEW-NOTICE.txt"
    if ($ExpectedPackageVersion -match '-Preview\.\d+$') {
        Assert-File $previewNotice "package preview notice"
    }
    elseif (Test-Path -LiteralPath $previewNotice) {
        Add-Failure "Official package must not contain PREVIEW-NOTICE.txt."
    }
    $packagedPanel = Join-Path $package "LocalArena.exe"
    $builtPanel = Join-Path $repo "Panel/src-tauri/target/release/cs2-bot-improver-plus-panel.exe"
    if (-not (Test-Path -LiteralPath $builtPanel)) {
        $builtPanel = Join-Path $repo "Panel/src-tauri/target-msvc/x86_64-pc-windows-msvc/release/cs2-bot-improver-plus-panel.exe"
    }
    if ((Test-Path -LiteralPath $packagedPanel) -and (Test-Path -LiteralPath $builtPanel) -and
        ((Get-FileHash -LiteralPath $packagedPanel -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $builtPanel -Algorithm SHA256).Hash)) {
        Add-Failure "Packaged Panel is not the current production Release build."
    }

    $payloadManifestPath = Join-Path $package "plus-payload-manifest.json"
    if (Test-Path -LiteralPath $payloadManifestPath) {
        try {
            $payloadManifest = Get-Content -LiteralPath $payloadManifestPath -Raw | ConvertFrom-Json
            if ($payloadManifest.schema_version -ne 1 -or $payloadManifest.package_version -ne $ExpectedPackageVersion) {
                Add-Failure "Package payload manifest has an unexpected schema or version."
            }
            $manifestPaths = @{}
            $manifestPolicies = @{}
            $manifestOwnership = @{}
            foreach ($entry in $payloadManifest.entries) {
                $relative = [string]$entry.path
                if ($manifestPaths.ContainsKey($relative)) {
                    Add-Failure "Package payload manifest contains a duplicate path: $relative"
                    continue
                }
                $manifestPaths[$relative] = $true
                $manifestPolicies[$relative] = [string]$entry.restore_policy
                $manifestOwnership[$relative] = [string]$entry.ownership
                if ($relative -notmatch '^(addons|cfg)/' -or $relative -match '(^|/)\.\.(/|$)') {
                    Add-Failure "Package payload manifest contains an unsafe path: $relative"
                    continue
                }
                $file = Join-Path $package $relative
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    Add-Failure "Package payload manifest references a missing file: $relative"
                    continue
                }
                $actualSize = (Get-Item -LiteralPath $file).Length
                $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualSize -ne [long]$entry.size -or $actualHash -ne ([string]$entry.sha256).ToLowerInvariant()) {
                    Add-Failure "Package payload manifest verification failed: $relative"
                }
            }
            $payloadFiles = foreach ($topLevel in @("addons", "cfg")) {
                $root = Join-Path $package $topLevel
                if (Test-Path -LiteralPath $root) {
                    Get-ChildItem -LiteralPath $root -File -Recurse | ForEach-Object {
                        [IO.Path]::GetRelativePath($package, $_.FullName).Replace("\", "/")
                    }
                }
            }
            foreach ($relative in $payloadFiles) {
                if (-not $manifestPaths.ContainsKey($relative)) {
                    Add-Failure "Package payload file is not tracked by the manifest: $relative"
                }
            }
            $expectedPreserveConfigs = @(
                "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_knife_presets.json",
                "addons/counterstrikesharp/plugins/PlayerKnifeCustomizer/player_gun_presets.json",
                "cfg/cs2bi_quickknife.cfg"
            )
            foreach ($relative in $expectedPreserveConfigs) {
                if ($manifestPolicies[$relative] -ne "preserve-config") {
                    Add-Failure "Mutable player configuration is not protected by preserve-config: $relative"
                }
            }
        }
        catch {
            Add-Failure "Package payload manifest is invalid: $($_.Exception.Message)"
        }
    }

    $pinnedRuntimeFiles = @(
        @{ Relative = "addons/metamod/bin/win64/server.dll"; Hash = $manifest.metamod.windowsLoaderSha256; Label = "Metamod" },
        @{ Relative = "addons/counterstrikesharp/bin/win64/counterstrikesharp.dll"; Hash = $manifest.counterStrikeSharp.windowsCoreSha256; Label = "CounterStrikeSharp" }
    )
    foreach ($runtime in $pinnedRuntimeFiles) {
        $runtimePath = Join-Path $package $runtime.Relative
        if (Test-Path -LiteralPath $runtimePath) {
            $runtimeHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($runtimeHash -ne $runtime.Hash.ToLowerInvariant()) {
                Add-Failure "$($runtime.Label) does not match the pinned engine-26 runtime: $runtimeHash"
            }
        }
    }

    $builtPlugins = @(
        @{ Name = "PlayerKnifeCustomizer"; Framework = "net10.0" }
    )
    foreach ($plugin in $builtPlugins) {
        $packageDll = Join-Path $package "addons/counterstrikesharp/plugins/$($plugin.Name)/$($plugin.Name).dll"
        $buildDll = Join-Path $repo "addons/counterstrikesharp/plugins/$($plugin.Name)/bin/Release/$($plugin.Framework)/$($plugin.Name).dll"
        if ((Test-Path -LiteralPath $packageDll) -and (Test-Path -LiteralPath $buildDll) -and
            ((Get-FileHash -LiteralPath $packageDll -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $buildDll -Algorithm SHA256).Hash)) {
            Add-Failure "Package $($plugin.Name) is not the current source build."
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host "Workspace verification passed."
Write-Host "Bot identities: $($counts['addons/BotHider/bot_info.json'])"
Write-Host "Weapon skins: $($counts['Panel/src/data/weaponSkins.json'])"
Write-Host "Glove skins: $($counts['Panel/src/data/gloveSkins.json'])"
Write-Host "Music kits: $($counts['Panel/src/data/musicKits.json'])"
if ($PackageRoot) { Write-Host "Package layout verified: $([IO.Path]::GetFullPath($PackageRoot))" }
