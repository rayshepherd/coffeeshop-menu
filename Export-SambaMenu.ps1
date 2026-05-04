# ============================================================
#  Export-SambaMenu.ps1
#  Exports SambaPOS V5 menu (categories + items + prices)
#  to menu.json for the GitHub Pages online menu.
#
#  HOW TO USE:
#    1. Edit the $config section below to match your setup
#    2. Run once manually to test: Right-click > Run with PowerShell
#    3. Optionally schedule via Task Scheduler to auto-update
#
#  OUTPUT: menu.json in the same folder as this script
# ============================================================

# ── CONFIG ──────────────────────────────────────────────────
$config = @{
    # SQL Server instance name (check in SSMS if unsure)
    SqlInstance   = "localhost\SQLEXPRESS"

    # SambaPOS database name (usually SambaPOS5)
    Database      = "SambaPOS5"

    # Where to write the output JSON
    # Change this to your local GitHub repo path:
    # e.g. "C:\Users\YourName\my-menu-repo\docs\menu.json"
    OutputPath    = "$PSScriptRoot\..\docs\menu.json"

    # Your restaurant name (shown on the menu page)
    RestaurantName = "My Restaurant"

    # Currency symbol
    Currency      = "$"

    # Tax rate percentage (0 if prices are already tax-inclusive)
    TaxRate       = 0

    # Menu name to export from SambaPOS (leave empty for ALL menus)
    MenuName      = ""
}
# ── END CONFIG ───────────────────────────────────────────────

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
}

Write-Log "Starting SambaPOS menu export..."

# Build connection string (Windows Auth — same account running SambaPOS)
$connStr = "Server=$($config.SqlInstance);Database=$($config.Database);Integrated Security=True;TrustServerCertificate=True;"

# SQL query — pulls menu categories and items with prices
# Adjust column/table names if your SambaPOS schema differs
$sql = @"
SELECT
    mg.Name           AS CategoryName,
    mg.SortOrder      AS CategorySort,
    mg.Tag            AS CategoryTag,
    mi.Name           AS ItemName,
    mi.Id             AS ItemId,
    mi.Tag            AS ItemTag,
    ISNULL(mp.Price, 0) AS Price,
    ISNULL(mi.Barcode, '') AS Barcode
FROM
    MenuItemGroups mg
    INNER JOIN MenuItems mi ON mi.MenuItemGroupId = mg.Id
    LEFT JOIN MenuItemPortions mp ON mp.MenuItemId = mi.Id
WHERE
    (@MenuName = '' OR mg.Name IN (
        SELECT mg2.Name FROM MenuItemGroups mg2
        WHERE mg2.Name = @MenuName
    ))
ORDER BY
    mg.SortOrder, mg.Name, mi.Name
"@

try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("@MenuName", $config.MenuName) | Out-Null

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $table   = New-Object System.Data.DataTable
    $adapter.Fill($table) | Out-Null
    $conn.Close()

    Write-Log "Query returned $($table.Rows.Count) rows."

    # Group rows into categories > items structure
    $categories = [ordered]@{}

    foreach ($row in $table.Rows) {
        $cat  = $row.CategoryName
        $item = @{
            id       = [int]$row.ItemId
            name     = $row.ItemName
            price    = [math]::Round([double]$row.Price, 2)
            tag      = $row.ItemTag
            barcode  = $row.Barcode
            # Placeholder image — replace with real URL once you have photos
            image    = ""
            description = ""
        }

        if (-not $categories.Contains($cat)) {
            $categories[$cat] = @{
                name  = $cat
                sort  = [int]$row.CategorySort
                tag   = $row.CategoryTag
                items = @()
            }
        }
        $categories[$cat].items += $item
    }

    # Build final JSON payload
    $menu = @{
        restaurant  = $config.RestaurantName
        currency    = $config.Currency
        taxRate     = $config.TaxRate
        updatedAt   = (Get-Date -Format "o")
        categories  = ($categories.Values | Sort-Object { $_.sort })
    }

    $json = $menu | ConvertTo-Json -Depth 10 -Compress:$false

    # Ensure output directory exists
    $outDir = Split-Path $config.OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $json | Out-File -FilePath $config.OutputPath -Encoding UTF8 -Force
    Write-Log "Menu exported to: $($config.OutputPath)"
    Write-Log "Categories: $($categories.Count)  |  Items: $($table.Rows.Count)"

} catch {
    Write-Log "ERROR: $_"
    exit 1
}

Write-Log "Done! Push your repo to GitHub to update the live menu."
