<#
.SYNOPSIS
    Regenerates docs/*.html (and optionally PDF) from docs/*.md.

.DESCRIPTION
    Markdown is the single source of truth for CTP Job Cards documentation.
    This script discovers every .md file under docs/ and produces a matching
    .html file with the shared stylesheet linked. PDF generation is opt-in
    via -Pdf to keep the default fast.

    docs/index.html is the handwritten hub and is never overwritten.

.PARAMETER Pdf
    Also regenerate PDFs (requires a working pandoc PDF engine — usually
    wkhtmltopdf or a LaTeX install).

.PARAMETER Check
    Generate to a temp directory and diff against committed HTML; exit non-zero
    if any file would change. Used by CI to enforce that committed HTML
    matches the markdown source.

.EXAMPLE
    pwsh tools/build-docs.ps1
    pwsh tools/build-docs.ps1 -Pdf
    pwsh tools/build-docs.ps1 -Check
#>

[CmdletBinding()]
param(
    [switch]$Pdf,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$docsDir  = Join-Path $repoRoot 'docs'
$cssPath  = Join-Path $docsDir 'docs.css'

if (-not (Test-Path $docsDir)) {
    throw "docs/ directory not found at $docsDir"
}

# Locate pandoc — required.
$pandoc = Get-Command pandoc -ErrorAction SilentlyContinue
if (-not $pandoc) {
    Write-Host "pandoc not found on PATH." -ForegroundColor Red
    Write-Host "Install via: winget install --id JohnMacFarlane.Pandoc" -ForegroundColor Yellow
    Write-Host "Or:          choco install pandoc" -ForegroundColor Yellow
    exit 1
}

# Discover .md files (skip the hub by definition — index.html is handwritten).
$markdownFiles = Get-ChildItem -Path $docsDir -Filter '*.md' -File

if ($markdownFiles.Count -eq 0) {
    Write-Host "No markdown files found in $docsDir" -ForegroundColor Yellow
    exit 0
}

# Where outputs land (real dir vs. temp for -Check).
$outDir = if ($Check) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "ctp-docs-build-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    # Copy the stylesheet so the relative CSS reference resolves and the
    # generated HTML matches what the in-tree build produces byte-for-byte.
    Copy-Item $cssPath -Destination (Join-Path $tmp 'docs.css')
    $tmp
} else {
    $docsDir
}

# Always relative — keeps committed and check-mode HTML byte-identical.
$cssRel = 'docs.css'

$failed = 0
foreach ($md in $markdownFiles) {
    $name    = [IO.Path]::GetFileNameWithoutExtension($md.Name)
    $htmlOut = Join-Path $outDir "$name.html"
    $title   = $name -replace '_', ' ' -replace '\b(\w)', { $args[0].Value.ToUpper() }

    Write-Host "→ $($md.Name) → $name.html"

    & $pandoc.Path `
        --from=gfm `
        --to=html5 `
        --standalone `
        --metadata="title=$title" `
        --css=$cssRel `
        --output=$htmlOut `
        $md.FullName

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  pandoc failed for $($md.Name)" -ForegroundColor Red
        $failed++
    }

    if ($Pdf -and -not $Check) {
        $pdfOut = Join-Path $outDir "$name.pdf"
        Write-Host "  + $name.pdf"
        & $pandoc.Path `
            --from=gfm `
            --output=$pdfOut `
            $md.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  pandoc PDF failed for $($md.Name) — install a PDF engine (wkhtmltopdf or LaTeX)." -ForegroundColor Yellow
        }
    }
}

if ($Check) {
    Write-Host ""
    Write-Host "Diffing temp build against committed HTML..."
    $drift = 0
    foreach ($md in $markdownFiles) {
        $name      = [IO.Path]::GetFileNameWithoutExtension($md.Name)
        $tempHtml  = Join-Path $outDir "$name.html"
        $committed = Join-Path $docsDir "$name.html"

        if (-not (Test-Path $committed)) {
            Write-Host "  MISSING: $name.html is not committed" -ForegroundColor Red
            $drift++
            continue
        }

        $tempContent = Get-Content $tempHtml -Raw
        $commContent = Get-Content $committed -Raw
        if ($tempContent -ne $commContent) {
            Write-Host "  DRIFT:   $name.html differs from regenerated output" -ForegroundColor Red
            $drift++
        }
    }

    Remove-Item -Recurse -Force $outDir

    if ($drift -gt 0) {
        Write-Host ""
        Write-Host "$drift file(s) out of sync. Run 'pwsh tools/build-docs.ps1' locally and commit the result." -ForegroundColor Red
        exit 1
    }
    Write-Host "All HTML matches markdown source." -ForegroundColor Green
}

if ($failed -gt 0) { exit 1 }
