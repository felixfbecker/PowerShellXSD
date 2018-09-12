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

# Make schema a schema instance itself
$xmlSchemaInstanceNamespace = 'http://www.w3.org/2001/XMLSchema-instance'
$attribute = $doc.CreateAttribute('xsi', 'schemaLocation', $xmlSchemaInstanceNamespace);
$attribute.InnerText = 'http://www.w3.org/2001/XMLSchema http://www.w3.org/2001/XMLSchema.xsd'
$root.SetAttributeNode($attribute) | Out-Null
$doc.AppendChild($root) | Out-Null

$root.AppendChild($doc.CreateComment(' Custom type definitions ')) | Out-Null

# Manual map from element name to content type (if scalar)
# This can't be parsed from the docs
$types = @{
    Name                = 'xs:string'
    CustomControlName   = 'xs:string'
    Label               = 'xs:string'
    ScriptBlock         = 'xs:string'
    PropertyName        = 'xs:string'
    FormatString        = 'xs:string'
    TypeName            = 'xs:string'
    Text                = 'xs:string'
    SelectionSetName    = 'xs:string'

    ColumnNumber        = 'xs:integer'
    Width               = 'xs:integer'
    LeftIndent          = 'xs:integer'
    FirstLineIndent     = 'xs:integer'
    FirstLineHanging    = 'xs:integer'

    ShowError           = 'boolean'
    DisplayError        = 'boolean'
    WrapTables          = 'boolean'
    OutOfBand           = 'boolean'
    AutoSize            = 'boolean'
    HideTableHeaders    = 'boolean'
    Wrap                = 'boolean'
    EnumerateCollection = 'boolean'
}
# Special type boolean
$simpleType = $root.AppendChild($doc.CreateElement($xs, 'simpleType', $xmlSchemaNamespace))
$simpleType.SetAttribute('name', 'boolean')
$restriction = $simpleType.AppendChild($doc.CreateElement($xs, 'restriction', $xmlSchemaNamespace))
# empty indicates "true"
foreach ($val in 'false', 'true', '') {
    $enumeration = $restriction.AppendChild($doc.CreateElement($xs, 'enumeration', $xmlSchemaNamespace))
    $enumeration.SetAttribute('value', $val)
}

$enums = @{
    Alignment = 'Left', 'Right', 'Center'
    Expand    = 'CoreOnly', 'EnumOnly', 'Both'
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

$groups = @{
    # PropertyName, ScriptBlock and FormatString are mutually exclusive
    # These will always be referenced through the Expression group with minOccurs=1 maxOccurs=1
    ScriptBlock  = 'Expression'
    PropertyName = 'Expression'
    FormatString = 'Expression'
}
$simpleType = $root.AppendChild($doc.CreateElement($xs, 'group', $xmlSchemaNamespace))
$simpleType.SetAttribute('name', 'Expression')
$choice = $simpleType.AppendChild($doc.CreateElement($xs, 'choice', $xmlSchemaNamespace))
foreach ($elementName in 'PropertyName', 'ScriptBlock', 'FormatString') {
    $el = $choice.AppendChild($doc.CreateElement($xs, 'element', $xmlSchemaNamespace))
    $el.SetAttribute('name', $elementName)
    $el.SetAttribute('type', $types[$elementName])
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

    Write-Verbose "Element $name"

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
        File        = $file
        Description = $description
        Docs        = $docs
        Children    = $children
        Parents     = $parents
    }
}


foreach ($formatElement in $formatElements) {

    if ($types.ContainsKey($formatElement.Name)) {
        # Built-in type like xs:string
        # Will be set on the xs:element directly
        continue
    }

    $documentationContainer = if ($enums.ContainsKey($formatElement.Name)) {
        # String enum (Expand, Alignment)
        $simpleType = $root.AppendChild($doc.CreateElement($xs, 'simpleType', $xmlSchemaNamespace))
        $simpleType.SetAttribute('name', $formatElement.Name)
        $restriction = $simpleType.AppendChild($doc.CreateElement($xs, 'restriction', $xmlSchemaNamespace))
        $restriction.SetAttribute('base', 'xs:string')
        foreach ($value in $enums[$formatElement.Name]) {
            $enumEl = $restriction.AppendChild($doc.CreateElement($xs, 'enumeration', $xmlSchemaNamespace))
            $enumEl.SetAttribute('value', $value)
        }
        $simpleType # documentation container to use
    } else {
        $complexType = $doc.CreateElement($xs, 'complexType', $xmlSchemaNamespace)
        if ($formatElement.Parents.Count -eq 0) {
            # The element is a top-level element
            $root.AppendChild($doc.CreateComment(' Top-level element ')) | Out-Null
            $elementElement = $root.AppendChild($doc.CreateElement($xs, 'element', $xmlSchemaNamespace))
            $elementElement.SetAttribute('name', $formatElement.Name)
            $elementElement.AppendChild($complexType) | Out-Null
            $elementElement # documentation container to use
        } else {
            # The element is a child element of another element and not allowed top-level
            $root.AppendChild($complexType) | Out-Null
            $complexType.SetAttribute('name', $formatElement.Name)
            $complexType # documentation container to use
        }
        # Element with children or empty element
        # By default, elements in PowerShell Format files can appear an arbitrary amount of times in any order
        # Individual restrictions per element are defined below
        $choiceElement = $complexType.AppendChild($doc.CreateElement($xs, 'choice', $xmlSchemaNamespace))
        $choiceElement.SetAttribute('minOccurs', 0)
        $choiceElement.SetAttribute('maxOccurs', $UNBOUNDED)
        $groupsAdded = @()
        foreach ($child in $formatElement.Children | Sort-Object -Property Name -Unique) {
            if ($groups.ContainsKey($child.Name)) {
                if (-not $groupsAdded -contains $groups[$child.Name]) {
                    $groupEl = $choiceElement.AppendChild($doc.CreateElement($xs, 'element', $xmlSchemaNamespace))
                    $groupEl.SetAttribute('ref', $groups[$child.Name])
                    $groupEl.SetAttribute('maxOccurs', 1)
                    $groupEl.SetAttribute('minOccurs', 1)
                }
            }

            $childElement = $choiceElement.AppendChild($doc.CreateElement($xs, 'element', $xmlSchemaNamespace))
            $childElement.SetAttribute('name', $child.Name)

            if ($types.ContainsKey($child.Name)) {
                # Simple type, reference the simple type
                $childElement.SetAttribute('type', $types[$child.Name])
            } else {
                # Defined type, reference the complexType that was defined for the name
                $childElement.SetAttribute('type', $child.Name)
            }

            if ($child.Description) {
                $annotation = $childElement.AppendChild($doc.CreateElement($xs, 'annotation', $xmlSchemaNamespace))
                $documentationEl = $annotation.AppendChild($doc.CreateElement($xs, 'documentation', $xmlSchemaNamespace))
                $documentationEl.InnerText = $child.Description
            }

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

    # Add documentation
    if ($formatElement.Description) {
        $annotation = $documentationContainer.PrependChild($doc.CreateElement($xs, 'annotation', $xmlSchemaNamespace))
        $documentationEl = $annotation.AppendChild($doc.CreateElement($xs, 'documentation', $xmlSchemaNamespace))
        $documentationEl.InnerText = $formatElement.Description
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
