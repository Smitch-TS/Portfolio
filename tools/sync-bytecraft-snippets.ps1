Param(
  [Parameter(Mandatory = $false)]
  [string]$SourceRoot = 'C:\Users\goths\OneDrive\Documents\GitHub Repos\TestRepo\ByteCraft',

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
  $HtmlPath = Join-Path $repoRoot 'project-operation-starfall.html'
}

if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "SourceRoot not found: $SourceRoot" }
if (-not (Test-Path -LiteralPath $HtmlPath)) { throw "HtmlPath not found: $HtmlPath" }

$weaponStats = Join-Path $SourceRoot 'Assets\Scripts\Weapons & Damage Scripts\weaponStats.cs'
$damage = Join-Path $SourceRoot 'Assets\Scripts\Weapons & Damage Scripts\damage.cs'
$menuTabs = Join-Path $SourceRoot 'Assets\Scripts\UI\MenuTabGroup.cs'
$enemyAI = Join-Path $SourceRoot 'Assets\Scripts\Enemy Related Scripts\EnemyAI.cs'
foreach ($p in @($weaponStats, $damage, $menuTabs, $enemyAI)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing file: $p" }
}

# --- snippet rules ---
$weapon = Extract-BraceBlock -Path $weaponStats -StartRegex '^\s*public\s+class\s+weaponStats\b'
$seeking = Extract-BraceBlock -Path $damage -StartRegex '^\s*private\s+void\s+SeekEnemy\s*\('
$uiTabs = Extract-BraceBlock -Path $menuTabs -StartRegex '^\s*public\s+void\s+OnTabSelect\s*\('
$aiSeeking = Extract-BraceBlock -Path $enemyAI -StartRegex '^\s*bool\s+canSeePlayer\s*\('
$meleeEnemy = Extract-BraceBlock -Path $enemyAI -StartRegex '^\s*void\s+meleeAttack\s*\('
$aiPathingA = Extract-BraceBlock -Path $enemyAI -StartRegex '^\s*void\s+checkRoam\s*\('
$aiPathingB = Extract-BraceBlock -Path $enemyAI -StartRegex '^\s*void\s+setPathRoam\s*\('
$aiPathing = "$aiPathingA`n`n$aiPathingB"

$html = Get-Content -LiteralPath $HtmlPath -Raw
$html = Normalize-Newlines $html
$html = Replace-SnippetBlock -Html $html -Id 'code-bc-weapon-stats' -Snippet $weapon
$html = Replace-SnippetBlock -Html $html -Id 'code-bc-seeking-projectile' -Snippet $seeking
$html = Replace-SnippetBlock -Html $html -Id 'code-bc-ui-tabs' -Snippet $uiTabs
$html = Replace-SnippetBlock -Html $html -Id 'code-bc-ai-seeking' -Snippet $aiSeeking
$html = Replace-SnippetBlock -Html $html -Id 'code-bc-melee-enemy' -Snippet $meleeEnemy
$html = Replace-SnippetBlock -Html $html -Id 'code-bc-ai-pathing' -Snippet $aiPathing

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($HtmlPath, $html, $utf8NoBom)

Write-Host "Updated snippets in: $HtmlPath"
