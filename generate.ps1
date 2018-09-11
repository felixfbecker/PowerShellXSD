using namespace System.Xml
using namespace System.Text
using namespace System.IO

[CmdletBinding()]
param()

if (-not (Test-Path "$PSScriptRoot/PowerShell-Docs")) {
    throw "PowerShell-Docs git submodule not found. Run git submodule update --init to download"
}

$index = "$PSScriptRoot/PowerShell-Docs/developer/format/format-schema-xml-reference.md"

[xml]$doc = [XmlDocument]::new()

$xmlSchemaNamespace = 'http://www.w3.org/2001/XMLSchema'
$xs = 'xs'

$doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'UTF-8', $null)) | Out-Null
$root = $doc.CreateNode('element', $xs, 'schema', $xmlSchemaNamespace)
$root.SetAttribute('attributeFormDefault', 'unqualified')
$root.SetAttribute('elementFormDefault', 'qualified')
# $root.SetAttribute('xsi:schemaLocation', 'http://www.w3.org/2001/XMLSchema http://www.w3.org/2001/XMLSchema.xsd')

$doc.AppendChild($root) | Out-Null

# Manual map from element name to content type (if scalar)
# This can't be parsed from the docs
$types = @{
    Name              = 'xs:string'
    CustomControlName = 'xs:string'
    Label             = 'xs:string'
    ScriptBlock       = 'xs:string'
    PropertyName      = 'xs:string'
    FormatString      = 'xs:string'
    TypeName          = 'xs:string'
    Text              = 'xs:string'
    SelectionSetName  = 'xs:string'

    ColumnNumber      = 'xs:integer'
    Width             = 'xs:integer'
    LeftIndent        = 'xs:integer'
    FirstLineIndent   = 'xs:integer'
    FirstLineHanging  = 'xs:integer'
}

$UNBOUNDED = 'unbounded'

# We can get minOccurs from required/optional hints, but we don't know about maxOccurs
$maxOccurs = @{
    Alignment              = 1
    AutoSize               = 1
    ColumnNumber           = 1
    Configuration          = 1
    Control                = $UNBOUNDED
    Controls               = 1
    CustomControl          = 1
    CustomControlName      = 1
    CustomEntries          = 1
    CustomEntry            = $UNBOUNDED
    CustomItem             = $UNBOUNDED
    DefaultSettings        = 1
    DisplayError           = 1
    EntrySelectedBy        = 1
    EnumerableExpansion    = 1
    EnumerableExpansions   = 1
    EnumerateCollection    = 1
    Expand                 = 1
    ExpressionBinding      = 1
    FirstLineHanging       = 1
    FirstLineIndent        = 1
    FormatString           = 1
    Frame                  = $UNBOUNDED
    GroupBy                = 1
    HideTableHeaders       = 1
    ItemSelectionCondition = 1
    Label                  = 1
    LeftIndent             = 1
    ListControl            = 1
    ListEntries            = 1
    ListEntry              = $UNBOUNDED
    ListItem               = $UNBOUNDED
    ListItems              = 1
    Name                   = 1
    NewLine                = $UNBOUNDED
    PropertyCountForTable  = 1 # Not in the index, but mentioned in DefaultSettings element
    PropertyName           = 1
    RightIndent            = 1
    ScriptBlock            = 1
    SelectionCondition     = 1
    SelectionSet           = 1
    SelectionSetName       = 1
    SelectionSets          = 1
    ShowError              = 1
    TableColumnHeader      = $UNBOUNDED
    TableColumnItem        = $UNBOUNDED
    TableColumnItems       = 1
    TableControl           = 1
    TableHeaders           = 1
    TableRowEntries        = 1
    TableRowEntry          = $UNBOUNDED
    Text                   = $UNBOUNDED
    TypeName               = $UNBOUNDED
    Types                  = 1
    View                   = $UNBOUNDED
    ViewDefinitions        = 1
    ViewSelectedBy         = 1
    WideControl            = 1
    WideEntries            = 1
    WideEntry              = 1
    WideItem               = $UNBOUNDED
    Width                  = 1
    Wrap                   = 1
    WrapTables             = 1
}

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
    [string[]]$enum = $null

    Write-Verbose "Element $name"

    $docs = Get-Content -Raw (Join-Path (Split-Path $index -Parent) $file)

    # Get documentation
    if ($docs -match "(?smi)^# $name.*?\r?\n\r?\n(.+?)\r?\n\r?\n") {
        $description = $Matches[1]
    } else {
        Write-Warning "No documentation found for element: $file"
    }

    # Get enumeration values if listed in the Syntax section
    if ($docs -match "<$name>.+,.+</$name>" -and $docs -match "<$name>(.+)</$name>") {
        $enum = $Matches[1] -split ',' | ForEach-Object Trim
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
                $childDescription = $Matches[2]
                $requried = ($childDescription -imatch 'Required')
                $optional = ($childDescription -imatch 'Optional')
                [PSCustomObject]@{
                    Name     = $childName
                    Required = $requried
                    Optional = $optional
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
        File        = $file
        Description = $description
        Docs        = $docs
        Children    = $children
        Parents     = $parents
        Enum        = $enum
    }
}


foreach ($formatElement in $formatElements) {
    $element = $root.AppendChild($doc.CreateElement($xs, 'element', $xmlSchemaNamespace))
    $element.SetAttribute('name', $formatElement.Name)

    # Add documentation
    if ($formatElement.Description) {
        $annotation = $element.AppendChild($doc.CreateElement($xs, 'annotation', $xmlSchemaNamespace))
        $documentationEl = $annotation.AppendChild($doc.CreateElement($xs, 'documentation', $xmlSchemaNamespace))
        $documentationEl.InnerText = $formatElement.Description
    }

    if ($types.ContainsKey($formatElement.Name)) {
        # Built-in type like xs:string
        $element.SetAttribute('type', $types[$formatElement.Name])
    } elseif ($formatElement.Enum) {
        # String enum (Expand, Align)
        $simpleType = $element.AppendChild($doc.CreateElement($xs, 'simpleType', $xmlSchemaNamespace))
        $restriction = $simpleType.AppendChild($doc.CreateElement($xs, 'restriction', $xmlSchemaNamespace))
        $restriction.SetAttribute('base', 'xs:string')
        foreach ($value in $formatElement.Enum) {
            $enumEl = $restriction.AppendChild($doc.CreateElement($xs, 'enumeration', $xmlSchemaNamespace))
            $enumEl.SetAttribute('value', $value)
        }
    } else {
        # Element with children or empty element
        $complexType = $element.AppendChild($doc.CreateElement($xs, 'complexType', $xmlSchemaNamespace))
        foreach ($child in $formatElement.Children | Sort-Object -Property Name -Unique) {
            $childElement = $complexType.AppendChild($doc.CreateElement($xs, 'element', $xmlSchemaNamespace))
            $childElement.SetAttribute('ref', $child.Name)
            if ($child.Required) {
                $childElement.SetAttribute('minOccurs', 1)
            }
            if ($child.Optional) {
                $childElement.SetAttribute('minOccurs', 0)
            }
            if ($maxOccurs.ContainsKey($child.Name)) {
                $childElement.SetAttribute('maxOccurs', $maxOccurs[$child.Name])
            } else {
                Write-Warning "maxOccurs unknown for element $($child.Name)"
            }
        }
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
