# PowerShell XSD

An attempt at XML Schema Definitions for PowerShell Format.ps1xml and Types.ps1xml files,
to provide a better editing experience with autocompletion and validation.

Format.xsd is automatically generated from parsing the reference documentation.
To regenerate it, make sure to download the PowerShell-Docs git submodule  with `git submodule update --init`,
then run `./generate.ps1`.
