# ================================================================
#  Imprime um cupom de TESTE da senha do sorteio (não gasta senha de verdade).
#  Use para escolher a impressora e conferir o tamanho do cupom.
#  Atalho: TestarSenha.bat
# ================================================================
$ErrorActionPreference = 'Stop'
$Pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
function Registrar([string]$msg) { Write-Host $msg }
$Cfg = ([IO.File]::ReadAllText((Join-Path $Pasta 'config.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
. (Join-Path $Pasta 'senha.ps1')

Write-Host ''
Write-Host 'Impressoras instaladas neste computador:'
Add-Type -AssemblyName System.Drawing
foreach ($p in [System.Drawing.Printing.PrinterSettings]::InstalledPrinters) { Write-Host ('  - ' + $p) }
Write-Host ''
$imp = [string]$Cfg.sorteio.impressora
if ($imp) { Write-Host ('Impressora do config.json: ' + $imp) } else { Write-Host 'Impressora do config.json: (vazia) - será usada a impressora padrão do Windows.' }

$exemplo = [pscustomobject]@{
  codigo = 'TESTE2345'; venda = 'teste'; valor = 40
  titulo = [string]$Cfg.sorteio.titulo_teste
  cadastro_ate = (Get-Date).AddDays(20); sorteio_em = (Get-Date).AddDays(22)
}
if (-not $exemplo.titulo) { $exemplo.titulo = 'Cesta de Natal da Padaria Silmar' }
Write-Host 'Imprimindo o cupom de teste...'
ImprimirSenha $exemplo
Write-Host 'Pronto. Se não saiu nada, veja o arquivo registro.log desta pasta.'
