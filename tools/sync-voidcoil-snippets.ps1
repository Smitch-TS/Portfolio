Param(
  [Parameter(Mandatory = $false)]
  [string]$SourceRoot = 'C:\Users\goths\OneDrive\Documents\GitHub Repos\TestRepo\dev5-team-project-2509-team-green',

  [Parameter(Mandatory = $false)]
  [string]$HtmlPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function HtmlEncode([string]$text) {
  return [System.Net.WebUtility]::HtmlEncode($text)
}

function Normalize-Newlines([string]$s) {
  return ($s -replace "`r`n", "`n")
}

function Extract-BraceBlock {
  Param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$StartRegex
  )

  $raw = Get-Content -LiteralPath $Path -Raw
  $arr = (Normalize-Newlines $raw) -split "`n"

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

    foreach ($ch in $line.ToCharArray()) {
      if ($ch -eq '{') { $depth++; $started = $true }
      elseif ($ch -eq '}') { if ($started) { $depth-- } }
    }

    if ($started -and $depth -le 0) { break }
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

  if ($Html -notmatch $pattern) { throw "Snippet markers not found for $Id" }

  $encoded = HtmlEncode($Snippet).TrimEnd()
  $replacement = "$start`n$encoded`n$end"

  return [regex]::Replace($Html, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }, 1)
}

if (-not $HtmlPath) {
  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
  $HtmlPath = Join-Path $repoRoot 'project-voidcoil.html'
}

if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "SourceRoot not found: $SourceRoot" }
if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "HtmlPath not found: $HtmlPath" }

$ppvRoot = Join-Path $SourceRoot 'PPV_Project'
$uiCpp = Join-Path $ppvRoot 'Source\DRAW\UserInterface.cpp'
$gameplayCpp = Join-Path $ppvRoot 'Source\GAME\GameplayComponents.cpp'
$levelDO = Join-Path $ppvRoot 'Source\DRAW\Utility\load_data_oriented.h'

if (-not (Test-Path -LiteralPath $uiCpp)) { throw "Missing file: $uiCpp" }
if (-not (Test-Path -LiteralPath $gameplayCpp)) { throw "Missing file: $gameplayCpp" }
if (-not (Test-Path -LiteralPath $levelDO)) { throw "Missing file: $levelDO" }

# --- snippet rules ---
$uiMainMenu = Extract-BraceBlock -Path $uiCpp -StartRegex '^\s*void\s+MainMenu\s*\('
$uiSettings = Extract-BraceBlock -Path $uiCpp -StartRegex '^\s*void\s+SettingsMenu\s*\('
$uiHighScoreInput = Extract-BraceBlock -Path $uiCpp -StartRegex '^\s*void\s+HighScoreInputScreen\s*\('

$playSfx = Extract-BraceBlock -Path $gameplayCpp -StartRegex '^\s*void\s+PlaySoundEffect\s*\('
$playMusic = Extract-BraceBlock -Path $gameplayCpp -StartRegex '^\s*void\s+PlayMusic\s*\('
$audio = "$playSfx`n`n$playMusic"

$vibrate = Extract-BraceBlock -Path $gameplayCpp -StartRegex '^\s*void\s+VibrateController\s*\(\s*entt::registry&\s+registry\s*\)\s*$'

$pauseToggle = Extract-BraceBlock -Path $uiCpp -StartRegex '^\s*if\s*\(\(inputState\[0\]\s*>\s*0\.0f\s*\|\|\s*inputState\[1\]\s*>\s*0\.0f\)\s*&&\s*inputDelay\s*<=\s*0\.0f\)\s*$'

$levelTransition = Extract-BraceBlock -Path $gameplayCpp -StartRegex '^\s*if\s*\(registry\.view<Enemy>\(\)\.empty\(\)\)\s*$'

$unload = Extract-BraceBlock -Path $levelDO -StartRegex '^\s*void\s+UnloadLevel\s*\(\)\s*\{'

$html = Get-Content -LiteralPath $HtmlPath -Raw
$html = Normalize-Newlines $html
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-ui-mainmenu' -Snippet $uiMainMenu
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-ui-settings' -Snippet $uiSettings
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-ui-highscore-input' -Snippet $uiHighScoreInput
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-audio-play' -Snippet $audio
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-input-vibration' -Snippet $vibrate
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-ui-input-toggle' -Snippet $pauseToggle
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-level-transition' -Snippet $levelTransition
$html = Replace-SnippetBlock -Html $html -Id 'code-vc-level-unload' -Snippet $unload

# Write back with UTF-8 (no BOM)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($HtmlPath, $html, $utf8NoBom)

Write-Host "Updated snippets in: $HtmlPath"
