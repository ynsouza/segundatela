# Gera o versao.json (lista de arquivos + impressão digital SHA-256) antes de publicar no GitHub.
# O caixa compara essa lista com os arquivos dele e baixa só o que mudou.
$Pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$Fora = @('versao.json', 'gerar-versao.ps1', 'registro.log', 'registro.log.antigo', 'atualizacao-pendente')
$PastasFora = @('.git', 'diagnostico', 'perfil-edge', 'versao-anterior', 'atualizando')

$arquivos = Get-ChildItem -LiteralPath $Pasta -Recurse -File | Where-Object {
  $rel = $_.FullName.Substring($Pasta.Length + 1)
  $topo = ($rel -split '\\')[0]
  -not ($Fora -contains $rel) -and -not ($PastasFora -contains $topo) -and $_.Name -notlike '.git*'
} | Sort-Object FullName | ForEach-Object {
  [ordered]@{
    caminho = $_.FullName.Substring($Pasta.Length + 1) -replace '\\', '/'
    sha256  = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
  }
}

$versao = [ordered]@{ versao = (Get-Date -Format 'yyyy-MM-dd-HHmmss'); arquivos = @($arquivos) }
[IO.File]::WriteAllText((Join-Path $Pasta 'versao.json'), ($versao | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
'versao.json gerado: ' + $versao.versao + ' (' + @($arquivos).Count + ' arquivos)'
