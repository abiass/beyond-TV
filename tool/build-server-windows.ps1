# Gera o pacote do servidor para Windows: executável, DLLs nativas e o
# dashboard compilado, prontos para descompactar e rodar.
#
# Uso (na raiz do repositório):
#   powershell -ExecutionPolicy Bypass -File tool\build-server-windows.ps1
#
# Resultado em dist\:
#   beyond-tv-server-<versão>-windows-x64\      pasta pronta para uso
#   beyond-tv-server-<versão>-windows-x64.zip   o mesmo, compactado

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

# O dart build e o Gradle se perdem em caminhos com acento ou espaço.
if ($root -match '[^\x21-\x7E]') {
  throw "Caminho com acento ou espaço: $root`nUse uma unidade virtual (subst X: `"$root`") e rode a partir de X:\. Veja o README."
}

$pubspec = Get-Content (Join-Path $root 'apps\server\pubspec.yaml')
$version = ($pubspec | Select-String '^version:\s*(\S+)').Matches[0].Groups[1].Value
$name = "beyond-tv-server-$version-windows-x64"
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name

function Invoke-Step([string]$title, [string]$dir, [scriptblock]$cmd) {
  Write-Host "==> $title" -ForegroundColor Cyan
  Push-Location $dir
  try {
    & $cmd
    if ($LASTEXITCODE -ne 0) { throw "Falhou: $title (código $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
}

# Sem CDN: o dashboard precisa abrir em redes sem internet.
Invoke-Step 'Dashboard (flutter build web)' (Join-Path $root 'apps\dashboard') {
  flutter build web --release --no-web-resources-cdn --no-wasm-dry-run
}

$cliOut = Join-Path $root 'apps\server\build\release-cli'
Invoke-Step 'Servidor (dart build cli)' (Join-Path $root 'apps\server') {
  dart build cli --output $cliOut
}

Write-Host "==> Montando $name" -ForegroundColor Cyan
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null

# bin\ e lib\ ficam lado a lado: o executável acha as DLLs em ..\lib.
Copy-Item -Recurse (Join-Path $cliOut 'bundle\bin') (Join-Path $out 'bin')
Copy-Item -Recurse (Join-Path $cliOut 'bundle\lib') (Join-Path $out 'lib')
Rename-Item (Join-Path $out 'bin\server.exe') 'beyond-tv-server.exe'
Copy-Item -Recurse (Join-Path $root 'apps\dashboard\build\web') (Join-Path $out 'web')
Copy-Item (Join-Path $root 'LICENSE') $out

# O .bat fica em ASCII: o cmd.exe não lê UTF-8 por padrão.
$bat = @'
@echo off
rem Inicia o servidor Beyond TV. Os dados ficam na pasta "data" ao lado.
cd /d "%~dp0"
bin\beyond-tv-server.exe --web-dir web --data-dir data %*
pause
'@
[IO.File]::WriteAllText((Join-Path $out 'Iniciar Beyond TV.bat'), $bat.Replace("`n", "`r`n"), [Text.Encoding]::ASCII)

$readme = @"
Beyond TV - servidor $version para Windows
==========================================

1. Dê dois cliques em "Iniciar Beyond TV.bat".
   Na primeira vez, o Windows pergunta sobre o firewall: permita o acesso
   em redes PRIVADAS (porta 8787/TCP e 8788/UDP).
2. Abra http://localhost:8787 no navegador e crie o administrador.
3. Instale o APK nas TVs e clique em "Adicionar TV" no painel.

Os dados (banco e mídias) ficam na pasta "data". Para atualizar o
servidor, troque os outros arquivos e mantenha a pasta "data".

Para ver as opções (porta, pasta de dados, nível de log):
  bin\beyond-tv-server.exe --help

Documentação: https://github.com/abiass/beyond-TV
"@
[IO.File]::WriteAllText((Join-Path $out 'LEIA-ME.txt'), $readme.Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding $true))

$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $out -DestinationPath $zip

Write-Host "==> Pronto: $zip" -ForegroundColor Green
