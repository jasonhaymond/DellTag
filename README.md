
# Get-DellAsset.ps1

## Synopsis

Retrieves Dell warranty and entitlement information by Service Tag.

## Description

Authenticates to the Dell TechDirect API with OAuth 2.0 and queries the Dell Asset Entitlements endpoint for a single Service Tag.

The script can:

- Display a summarized Dell asset and warranty result.
- Return the unmodified API response with `-Raw`.
- Export the summary to CSV with `-Csv`.
- Export the summary and entitlement details to JSON with `-Json`.

### Required Environment Variables

The following user environment variables must be configured:

```text
DELL_API_CLIENT_ID
DELL_API_CLIENT_SECRET
```

### Normal Output

The normal output consists of two types of PowerShell objects:

1. One summarized asset object.
2. Zero or more entitlement objects.

> **Important:**  
> This script queries warranty and entitlement data. It does not claim to return the complete original factory configuration or the original factory-installed operating system.

---

## Parameters

### `ServiceTag`

The Dell Service Tag to look up.

The value must contain 5 through 10 letters or numbers.

### `-Raw`

Returns the unmodified PowerShell object received from the Dell API.

The script does not format or export the response when this switch is used.

### `-Csv`

Exports the summarized asset result to a CSV file.

If `-ExportPath` is omitted, the file is written to the current user's Desktop as:

```text
Dell-SERVICETAG.csv
```

If the Desktop cannot be resolved, the current PowerShell directory is used.

### `-Json`

Exports the summarized asset result and all entitlement details to a JSON file.

If `-ExportPath` is omitted, the file is written to the current user's Desktop as:

```text
Dell-SERVICETAG.json
```

If the Desktop cannot be resolved, the current PowerShell directory is used.

### `-ExportPath`

Optional destination filename or path for `-Csv` or `-Json`.

If the path does not include an extension, the appropriate `.csv` or `.json` extension is appended. Missing parent directories are created.

This parameter requires either `-Csv` or `-Json`.

---

## Examples

### Standard Lookup

```powershell
.\Get-DellAsset.ps1 ABC1234
```

Looks up Service Tag `ABC1234` and writes the asset summary followed by its warranty entitlement objects to the PowerShell pipeline.

### Standard Lookup Using Named Parameter

```powershell
.\Get-DellAsset.ps1 -ServiceTag ABC1234
```

Performs the same standard lookup using the named parameter.

### Return Raw API Response

```powershell
.\Get-DellAsset.ps1 ABC1234 -Raw
```

Returns the unmodified Dell API response as a PowerShell object.

### Display Raw Response as JSON

```powershell
.\Get-DellAsset.ps1 ABC1234 -Raw | ConvertTo-Json -Depth 20
```

Displays the raw Dell API response as formatted JSON without saving it.

### Export Summary to CSV

```powershell
.\Get-DellAsset.ps1 ABC1234 -Csv
```

Exports the summarized asset result to:

```text
Dell-ABC1234.csv
```

on the Desktop.

### Export to JSON

```powershell
.\Get-DellAsset.ps1 ABC1234 -Json
```

Exports the asset summary and entitlement details
