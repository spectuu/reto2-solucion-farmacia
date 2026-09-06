# Caracterizacion Reto 2: corre cada insumo contra el bin AS-IS (fe7dd82) y
# contra el bin TO-BE, compara la salida estandar byte a byte (SHA-256) y deja
# un diff por caso cuando difiere.
#
#   -ProductosTxt <ruta>  sustituye productos.txt en la copia del TO-BE
#                         (modo estricto: mismos datos que el AS-IS).
#   -ProductosTxtAmbos <ruta>  sustituye productos.txt en las DOS copias.
#                         Es lo que necesita un caso de archivo mal formado:
#                         si el archivo entra en un solo bin, la comparacion
#                         no significa nada.
#
# Ambos bins se copian a una carpeta temporal para no tocar bin\ del proyecto.
# Los casos que corren sin uno de los archivos de datos lo declaran en su
# nombre (ver Determinar-ArchivoOmitido) y corren sin el en las dos copias.

param(
    [Parameter(Mandatory = $true)][string]$BinAsis,
    [Parameter(Mandatory = $true)][string]$BinTobe,
    [Parameter(Mandatory = $true)][string]$Insumos,
    [Parameter(Mandatory = $true)][string]$Salidas,
    [string]$ProductosTxt = '',
    [string]$ProductosTxtAmbos = ''
)

$ErrorActionPreference = 'Stop'

function Preparar-Directorio([string]$ruta) {
    if (Test-Path $ruta) { Remove-Item -Recurse -Force $ruta }
    New-Item -ItemType Directory -Force $ruta | Out-Null
}

function Copiar-Bin([string]$bin, [string]$destino, [string]$sinArchivo) {
    Preparar-Directorio $destino
    Copy-Item (Join-Path $bin '*') $destino -Recurse
    if ($sinArchivo -ne '') { Remove-Item (Join-Path $destino $sinArchivo) -Force }
    return $destino
}

# Que archivo de datos NO debe existir para este caso. La convencion es el
# nombre del insumo, para no mantener una lista aparte: 11-archivo-faltante
# (heredado del Reto 1) corre sin productos.txt y 15-archivo-clientes-faltante
# corre sin clientes.txt. Se comprueba clientes primero porque su nombre
# tambien contiene 'archivo' y 'faltante'.
function Determinar-ArchivoOmitido([string]$caso) {
    if ($caso -match 'clientes-faltante') { return 'clientes.txt' }
    if ($caso -match 'archivo-faltante')  { return 'productos.txt' }
    return ''
}

function Ejecutar-Caso([string]$bin, [string]$insumo, [string]$salida, [string]$errores) {
    $proceso = Start-Process `
        -FilePath (Join-Path $bin 'AppFarmaciaConsola.exe') `
        -WorkingDirectory $bin `
        -RedirectStandardInput $insumo `
        -RedirectStandardOutput $salida `
        -RedirectStandardError $errores `
        -NoNewWindow -Wait -PassThru
    return $proceso.ExitCode
}

$dirA = Join-Path $Salidas 'as-is'
$dirT = Join-Path $Salidas 'to-be'
$dirD = Join-Path $Salidas 'diff'
Preparar-Directorio $dirA
Preparar-Directorio $dirT
Preparar-Directorio $dirD

$temp = Join-Path $env:TEMP ('carac-reto2-' + [System.Guid]::NewGuid().ToString('N'))
$binA = Copiar-Bin $BinAsis (Join-Path $temp 'asis') ''
$binT = Copiar-Bin $BinTobe (Join-Path $temp 'tobe') ''
if ($ProductosTxt -ne '') {
    Copy-Item $ProductosTxt (Join-Path $binT 'productos.txt') -Force
}
if ($ProductosTxtAmbos -ne '') {
    Copy-Item $ProductosTxtAmbos (Join-Path $binA 'productos.txt') -Force
    Copy-Item $ProductosTxtAmbos (Join-Path $binT 'productos.txt') -Force
}

# Una copia por archivo de datos omitido, creada solo si algun caso la pide.
$binSin = @{}
function Bin-SinArchivo([string]$origen, [string]$etiqueta, [string]$archivo) {
    $clave = $etiqueta + '/' + $archivo
    if (-not $binSin.ContainsKey($clave)) {
        $destino = Join-Path $temp ($etiqueta + '-sin-' + $archivo.Replace('.txt', ''))
        $binSin[$clave] = Copiar-Bin $origen $destino $archivo
    }
    return $binSin[$clave]
}

$filas = @()
foreach ($insumo in (Get-ChildItem $Insumos -Filter '*.txt' | Sort-Object Name)) {
    $caso = [System.IO.Path]::GetFileNameWithoutExtension($insumo.Name)
    $bA = $binA; $bT = $binT
    $omitido = Determinar-ArchivoOmitido $caso
    if ($omitido -ne '') {
        $bA = Bin-SinArchivo $binA 'asis' $omitido
        $bT = Bin-SinArchivo $binT 'tobe' $omitido
    }

    $sA = Join-Path $dirA ($caso + '.txt')
    $sT = Join-Path $dirT ($caso + '.txt')
    $eA = Join-Path $dirA ($caso + '.stderr.txt')
    $eT = Join-Path $dirT ($caso + '.stderr.txt')

    $cA = Ejecutar-Caso $bA $insumo.FullName $sA $eA
    $cT = Ejecutar-Caso $bT $insumo.FullName $sT $eT

    $hA = (Get-FileHash $sA -Algorithm SHA256).Hash
    $hT = (Get-FileHash $sT -Algorithm SHA256).Hash

    if ($hA -eq $hT) {
        $veredicto = 'IDENTICA'
    } else {
        $veredicto = 'DIFIERE'
        $d = Join-Path $dirD ($caso + '.diff')
        cmd /c ('git -c core.autocrlf=false diff --no-index --text -- "' + $sA + '" "' + $sT + '" 2>nul') | Out-File $d -Encoding utf8
    }
    $filas += [pscustomobject]@{ Caso = $caso; Salida = $veredicto; ExitAsis = $cA; ExitTobe = $cT }
    Write-Host ('{0}  {1}  exit {2}/{3}' -f $caso.PadRight(30), $veredicto, $cA, $cT)
}

if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }

$md = @()
$md += '| Caso | Salida estandar | Exit AS-IS | Exit TO-BE |'
$md += '|---|---|---|---|'
foreach ($f in $filas) { $md += ('| ' + $f.Caso + ' | ' + $f.Salida + ' | ' + $f.ExitAsis + ' | ' + $f.ExitTobe + ' |') }
$md -join "`r`n" | Out-File (Join-Path $Salidas 'resumen.md') -Encoding utf8

$identicas = @($filas | Where-Object { $_.Salida -eq 'IDENTICA' }).Count
Write-Host ('')
Write-Host ('IDENTICAS: {0} / {1}' -f $identicas, $filas.Count)
