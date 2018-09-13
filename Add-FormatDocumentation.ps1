# Takes FormatWithoutDocs.xsd, adds documentation annotations
# parsed from the PowerShell docs repo to it and saves the result in Format.xsd

using namespace System.Xml
using namespace System.Text
using namespace System.IO

[CmdletBinding()]
param()

if (-not (Test-Path "$PSScriptRoot/PowerShell-Docs")) {
    throw "PowerShell-Docs git submodule not found. Run git submodule update --init to download"
}

$index = "$PSScriptRoot/PowerShell-Docs/developer/format/format-schema-xml-reference.md"

[xml]$doc = [xml](Get-Content -Raw FormatWithoutDocs.xsd)

$xmlSchemaNamespace = 'http://www.w3.org/2001/XMLSchema'
$xs = 'xs'

$formatElements = Get-Content $index |
    ForEach-Object {
    if ($_ -match '\[(?<Name>\w+) Element.*]\((?<File>.+)\)') {
        [PSCustomObject]@{
            Name = $Matches.Name
            File = $Matches.File
        }
    }
} |
    Sort-Object -Property Name -Unique |
    ForEach-Object {
    $name = $_.Name
    $file = $_.File
    $children = @()
    [string[]]$parents = @()
    [string]$description = $null

    Write-Verbose "Element $name from documentation"

    $docs = Get-Content -Raw (Join-Path (Split-Path $index -Parent) $file)

    # Get documentation
    if ($docs -match "(?smi)^# $name.*?\r?\n\r?\n(.+?)\r?\n\r?\n") {
        $description = $Matches[1] -ireplace '<[^>]+>', '' # strip HTML
    } else {
        Write-Warning "No documentation found for element: $file"
    }

    # Get child elements
    if ($docs -match '(?smi)^### Child Elements\r?\n\r?\n(.+?)\r?\n\r?\n') {
        $table = $Matches[1]
        if ($table -ne 'None.') {
            $children = $table -split '\r?\n' | Select-Object -Skip 2 | ForEach-Object {
                if (-not ($_ -match '^\|(?:\[|`)(\w+).*\|(.+)\|')) {
                    Write-Warning "Child elements table row did not match: $_"
                }
                $childName = $Matches[1]
                $childDescription = $Matches[2] -ireplace '<[^>]+>', '' # strip HTML like <br> tags
                $requried = ($childDescription -imatch 'Required')
                $optional = ($childDescription -imatch 'Optional')
                if ($requried -eq $optional) {
                    Write-Warning "Child element $childName of $name is neither required nor optional"
                }
                [PSCustomObject]@{
                    Name        = $childName
                    Description = $childDescription
                    Required    = $requried
                    Optional    = $optional
                }
            }
        }
    } else {
        Write-Warning "Child elements did not match: $file"
    }

    # Get parent elements
    if ($docs -match '(?smi)^### Parent Elements\r?\n\r?\n(.+?)\r?\n\r?\n') {
        $table = $Matches[1]
        if ($table -ne 'None.') {
            $parents = $table -split '\r?\n' | Select-Object -Skip 2 | ForEach-Object {
                if (-not ($_ -match '^\|(?:\[|`)(\w+) Element')) {
                    Write-Warning "Child elements table row did not match: $_"
                }
                $Matches[1]
            }
        }
    } else {
        Write-Warning "Parent elements did not match: $file"
    }

    [pscustomobject]@{
        Name        = $name
        Description = $description
        Children    = $children
        Parents     = $parents
    }
}

# Missing from the index file, docs page is incomplete
$formatElements += [PSCustomObject]@{
    Name        = 'PropertyCountForTable'
    Description = 'Specifies the minimum number of properties that an object must have to display the object in a table view.'
    Children    = @()
    Parents     = @('DefaultSettings')
}

$formatElementsByName = $formatElements | Group-Object -AsHashTable -Property Name

foreach ($topLevelNode in $doc.schema.ChildNodes) {

    Write-Verbose "XSD node $($topLevelNode.name)"
    if (-not $formatElementsByName.ContainsKey($topLevelNode.name)) {
        Write-Warning "Could not find element in documentation for type `"$($topLevelNode.name)`""
        continue
    }

    $elementData = $formatElementsByName[$topLevelNode.name]

    # Add documentation
    if ($elementData.Description) {
        $annotation = $topLevelNode.PrependChild($doc.CreateElement($xs, 'annotation', $xmlSchemaNamespace))
        $documentationEl = $annotation.AppendChild($doc.CreateElement($xs, 'documentation', $xmlSchemaNamespace))
        $documentationEl.InnerText = $elementData.Description
    }

    # Element has child elements (within a xs:sequence/xs:all/xs:choice)
    foreach ($childElement in $topLevelNode.GetElementsByTagName('element', $xmlSchemaNamespace)) {
        # $childElement is an xs:element
        $childData = $elementData.Children | Where-Object { $_.Name -eq $childElement.name }
        if (-not $childData) {
            Write-Error "Could not find data for child `"$($childElement.name)`" of element `"$($elementData.Name)`""
            continue
        }
        $annotation = $childElement.PrependChild($doc.CreateElement($xs, 'annotation', $xmlSchemaNamespace))
        $documentationEl = $annotation.AppendChild($doc.CreateElement($xs, 'documentation', $xmlSchemaNamespace))
        $documentationEl.InnerText = $childData.Description
    }
}

$using = @()
try {
    $streamWriter = [StreamWriter]::new("$PWD/Format.xsd", $false, [UTF8Encoding]::new($false))
    $using += $streamWriter
    $settings = [XmlWriterSettings]::new()
    $settings.NewLineChars = "`n"
    $settings.Encoding = [Encoding]::UTF8
    $settings.Indent = $true
    $settings.NewLineOnAttributes = $false
    $xmlWriter = [XmlWriter]::Create($streamWriter, $settings)
    $using += $xmlWriter
    $doc.Save($xmlWriter)
    $xmlWriter.Close()
} finally {
    $using | ForEach-Object Dispose
}
