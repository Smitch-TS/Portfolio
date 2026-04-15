Param(
  [Parameter(Mandatory = $false)]
  [string]$SourceRoot = 'C:\Perforce\GDBS\CAPSTONE\03\NullForgeStudio\PotionPanic',

  [Parameter(Mandatory = $false)]
  [string]$HtmlPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function HtmlEncode([string]$text) {
  return [System.Net.WebUtility]::HtmlEncode($text)
}

function Extract-BraceBlock {
  Param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$StartRegex
  )

  $lines = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $arr = $lines -replace "`r`n", "`n" -split "`n"

  $startIndex = -1
  for ($i = 0; $i -lt $arr.Length; $i++) {
    if ($arr[$i] -match $StartRegex) { $startIndex = $i; break }
  }
  if ($startIndex -lt 0) { throw "Start pattern not found in ${Path}: $StartRegex" }

  $out = New-Object System.Collections.Generic.List[string]
  $depth = 0
  $started = $false

  for ($i = $startIndex; $i -lt $arr.Length; $i++) {
    $line = $arr[$i]
    $out.Add($line)

    # Count braces character-by-character (ignores quotes/comments; good enough for Unreal-style code)
    foreach ($ch in $line.ToCharArray()) {
      if ($ch -eq '{') {
        $depth++
        $started = $true
      }
      elseif ($ch -eq '}') {
        if ($started) { $depth-- }
      }
    }

    if ($started -and $depth -le 0) {
      break
    }
  }

  return ($out -join "`n")
}

function Replace-SnippetBlock {
  Param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Snippet
  )

  $start = "<!-- SNIP:$Id START -->"
  $end = "<!-- SNIP:$Id END -->"
  $pattern = "(?s)$([regex]::Escape($start)).*?$([regex]::Escape($end))"

  if ($Html -notmatch $pattern) {
    throw "Snippet markers not found for $Id"
  }

  $encoded = HtmlEncode($Snippet).TrimEnd()
  $replacement = "$start`n$encoded`n$end"

  return [regex]::Replace($Html, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }, 1)
}

function Normalize-Newlines([string]$s) {
  return ($s -replace "`r`n", "`n")
}

if (-not $HtmlPath) {
  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
  $HtmlPath = Join-Path $repoRoot 'project-potion-panic.html'
}

if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "SourceRoot not found: $SourceRoot" }
if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "HtmlPath not found: $HtmlPath" }

$playingGameStateCpp = Join-Path $SourceRoot 'Source\PotionPanic\Private\Actors\PlayingGameState.cpp'
$potionDataTypesH = Join-Path $SourceRoot 'Source\PotionPanic\Public\Utility\PotionDataTypes.h'
$myGameInstanceCpp = Join-Path $SourceRoot 'Source\PotionPanic\Private\Utility\MyGameInstance.cpp'
$requestPopupCpp = Join-Path $SourceRoot 'Source\PotionPanic\Private\Widgets\RequestPopup.cpp'
$lobbyStartScreenCpp = Join-Path $SourceRoot 'Source\PotionPanic\Private\Widgets\LobbyStartScreen.cpp'

if (-not (Test-Path -LiteralPath $playingGameStateCpp)) { throw "Missing file: $playingGameStateCpp" }
if (-not (Test-Path -LiteralPath $potionDataTypesH)) { throw "Missing file: $potionDataTypesH" }
if (-not (Test-Path -LiteralPath $myGameInstanceCpp)) { throw "Missing file: $myGameInstanceCpp" }
if (-not (Test-Path -LiteralPath $requestPopupCpp)) { throw "Missing file: $requestPopupCpp" }
# LobbyStartScreen.cpp is no longer required for snippet sync (kept here if you want it later)

# --- Snippet extraction rules ---
$coreStart = Extract-BraceBlock -Path $playingGameStateCpp -StartRegex '^\s*void\s+APlayingGameState::StartRoundTimer\s*\('
$coreUpdate = Extract-BraceBlock -Path $playingGameStateCpp -StartRegex '^\s*void\s+APlayingGameState::UpdateTimers\s*\('
$coreLoop = "$coreStart`n`n$coreUpdate"

$recipes = Extract-BraceBlock -Path $potionDataTypesH -StartRegex '^\s*struct\s+FPotionRecipe\b'

$requests = Extract-BraceBlock -Path $playingGameStateCpp -StartRegex '^\s*void\s+APlayingGameState::GenerateNewRequest\s*\('

$uiRequestPopup = Extract-BraceBlock -Path $requestPopupCpp -StartRegex '^\s*void\s+URequestPopup::UpdateRequest\s*\('
$uiSettings = Extract-BraceBlock -Path $myGameInstanceCpp -StartRegex '^\s*void\s+UMyGameInstance::LoadSettingsSaveData\s*\('

$archLoadRequests = Extract-BraceBlock -Path $playingGameStateCpp -StartRegex '^\s*void\s+APlayingGameState::LoadPossibleRequests\s*\('

$persistSlot = Extract-BraceBlock -Path $myGameInstanceCpp -StartRegex '^\s*void\s+UMyGameInstance::ChangeCurrentSaveSlot\s*\('
$persistProgress = Extract-BraceBlock -Path $myGameInstanceCpp -StartRegex '^\s*void\s+UMyGameInstance::UpdateSavedGameData\s*\('

$cheatAddScore = Extract-BraceBlock -Path $playingGameStateCpp -StartRegex '^\s*void\s+APlayingGameState::CheatAddScore\s*\('
$cheatPause = Extract-BraceBlock -Path $playingGameStateCpp -StartRegex '^\s*void\s+APlayingGameState::CheatPauseTimer\s*\('
$toolsCheats = "$cheatAddScore`n`n$cheatPause"

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$html = Normalize-Newlines $html
$html = Replace-SnippetBlock -Html $html -Id 'code-core-loop' -Snippet $coreLoop
$html = Replace-SnippetBlock -Html $html -Id 'code-recipes' -Snippet $recipes
$html = Replace-SnippetBlock -Html $html -Id 'code-requests' -Snippet $requests

$html = Replace-SnippetBlock -Html $html -Id 'code-ui-request-popup' -Snippet $uiRequestPopup
$html = Replace-SnippetBlock -Html $html -Id 'code-ui-settings' -Snippet $uiSettings

$html = Replace-SnippetBlock -Html $html -Id 'code-arch-load-requests' -Snippet $archLoadRequests

$html = Replace-SnippetBlock -Html $html -Id 'code-persist-slot' -Snippet $persistSlot
$html = Replace-SnippetBlock -Html $html -Id 'code-persist-progress' -Snippet $persistProgress

$html = Replace-SnippetBlock -Html $html -Id 'code-tools-cheats' -Snippet $toolsCheats

# Write back with UTF-8 (no BOM)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($HtmlPath, $html, $utf8NoBom)

Write-Host "Updated snippets in: $HtmlPath"
