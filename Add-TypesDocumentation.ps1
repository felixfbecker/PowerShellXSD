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

$aboutTypes = Get-Content -Raw "$PSScriptRoot/PowerShell-Docs/reference/6/Microsoft.PowerShell.Core/About/about_Types.ps1xml.md"

$xmlSchemaNamespace = 'http://www.w3.org/2001/XMLSchema'
$xs = 'xs'

[xml]$doc = [xml](Get-Content -Raw TypesWithoutDocs.xsd)

$extraDocs = @{
    Types = 'The `<Types>` tag encloses all of the types that are defined in the file. There should be only one pair of `<Types>` tags.'
    Type  = 'Each .NET Framework type mentioned in the file should be represented by a pair of `<Type>` tags.'
}

foreach ($elementNode in $doc.schema.GetElementsByTagName('element', $xmlSchemaNamespace) | Sort-Object -Property name -Unique) {

    $elementName = $elementNode.name

    Write-Verbose "XSD node $elementName"

    $description = if ($extraDocs.ContainsKey($elementName)) {
        $extraDocs[$elementName]
    } elseif ($aboutTypes -match "(?sm)``<$elementName>``:\s?(.*?)\r?\n\r?\n") {
        $Matches[1] -replace '\s+', ' '
    } else {
        Write-Warning "No documentation found for element `"$elementName`""
    }

    # Add documentation
    if ($description) {
        $annotation = $elementNode.PrependChild($doc.CreateElement($xs, 'annotation', $xmlSchemaNamespace))
        $documentationEl = $annotation.AppendChild($doc.CreateElement($xs, 'documentation', $xmlSchemaNamespace))
        $documentationEl.InnerText = $description
    }
}

$using = @()
try {
    $streamWriter = [StreamWriter]::new("$PWD/Types.xsd", $false, [UTF8Encoding]::new($false))
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
    $streamWriter.Write("`n") # write final new line
} finally {
    $using | ForEach-Object Dispose
}
