# ============================================================
#  Export-SambaMenu.ps1
#  Exports SambaPOS V5 menu (categories + items + portions/prices)
#  to menu.json for the GitHub Pages online menu.
# ============================================================

# ── CONFIG ──────────────────────────────────────────────────
$config = @{
    SqlInstance    = "localhost"
    Database       = "SambaPOS"
    OutputPath     = "C:\Users\SambaPOS Server\Documents\files\menu.json"
    RestaurantName = "DJ LAB Cafe"
    Currency       = "$"
    TaxRate        = 0
    MenuName       = ""
}
# ── END CONFIG ───────────────────────────────────────────────

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
}

Write-Log "Starting SambaPOS menu export..."

$connStr = "Server=$($config.SqlInstance);Database=$($config.Database);Integrated Security=True;TrustServerCertificate=True;"

$sql = @"
SELECT
    cat.Name             AS CategoryName,
    cat.SortOrder        AS CategorySort,
    mi.Name              AS ItemName,
    mi.Id                AS ItemId,
    mi.Description       AS ItemDescription,
    mi.Tag               AS ItemTag,
    mp.Name              AS PortionName,
    ISNULL(mip.Price, 0) AS Price
FROM
    ScreenMenuCategories cat
    INNER JOIN ScreenMenuItems smi ON smi.ScreenMenuCategoryId = cat.Id
    INNER JOIN MenuItems mi        ON mi.Id = smi.MenuItemId
    LEFT  JOIN MenuItemPortions mp ON mp.MenuItemId = mi.Id
    LEFT  JOIN MenuItemPrices mip  ON mip.MenuItemPortionId = mp.Id
WHERE
    (@MenuName = '' OR cat.Name = @MenuName)
ORDER BY
    cat.SortOrder, cat.Name, smi.SortOrder, mp.Id
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

    $categories = [ordered]@{}
    $itemMap     = [ordered]@{}

    foreach ($row in $table.Rows) {
        $cat      = $row.CategoryName
        $itemKey  = "$cat|$($row.ItemId)"
        $portion  = $row.PortionName
        $price    = [math]::Round([double]$row.Price, 2)
        $isNormal = ($portion -eq "Normal")

        if (-not $categories.Contains($cat)) {
            $categories[$cat] = @{
                name  = $cat
                sort  = [int]$row.CategorySort
                items = [System.Collections.ArrayList]@()
            }
        }

        if (-not $itemMap.Contains($itemKey)) {
            $newItem = [ordered]@{
                id          = [int]$row.ItemId
                name        = $row.ItemName
                tag         = $row.ItemTag
                image       = ""
                description = $row.ItemDescription
                price       = $null
                portions    = [System.Collections.ArrayList]@()
            }
            $itemMap[$itemKey] = $newItem
            $categories[$cat].items.Add($newItem) | Out-Null
        }

        $item = $itemMap[$itemKey]

        if ($isNormal) {
            $item.price = $price
        } else {
            $item.portions.Add([ordered]@{
                name  = $portion
                price = $price
            }) | Out-Null
        }
    }

    # Finalise: if item has named portions, remove price; if no portions, remove portions array
    foreach ($cat in $categories.Values) {
        foreach ($item in $cat.items) {
            if ($item.portions.Count -gt 0) {
                $item.Remove("price")
            } else {
                $item.Remove("portions")
            }
        }
    }

    $menu = [ordered]@{
        restaurant  = $config.RestaurantName
        currency    = $config.Currency
        taxRate     = $config.TaxRate
        updatedAt   = (Get-Date -Format "o")
        categories  = ($categories.Values | Sort-Object { $_.sort })
    }

    $json = $menu | ConvertTo-Json -Depth 10 -Compress:$false

    $outDir = Split-Path $config.OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $json | Out-File -FilePath $config.OutputPath -Encoding UTF8 -Force
    Write-Log "Menu exported to: $($config.OutputPath)"
    Write-Log "Categories: $($categories.Count)  |  Items: $($itemMap.Count)"

} catch {
    Write-Log "ERROR: $_"
    exit 1
}

Write-Log "Done! Push your repo to GitHub to update the live menu."
