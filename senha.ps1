# ================================================================
#  Senha do sorteio da Cesta de Natal - Padaria Silmar
#  Carregado pelo TelaCliente.ps1 (e pelo TestarSenha.ps1).
#   - Quando a venda é finalizada, pede uma senha ao servidor (em segundo plano,
#     sem travar a tela do cliente). O servidor só dá senha se a venda do PDV
#     for de valor igual ou maior que o mínimo do sorteio.
#   - Imprime o cupom com a senha e o QR Code na impressora do caixa.
#  Precisa de: config.json -> "sorteio" e o arquivo sorteio.chave nesta pasta
#  (a chave NÃO vai para o GitHub). Guia: docs/SORTEIO_CESTA.md no repositório
#  da loja, e o LEIA-ME.txt desta pasta.
# ================================================================

$ArqChaveSorteio = Join-Path $Pasta 'sorteio.chave'
$script:QrOk = $false
$script:JobSenha = $null
$script:JobSenhaInicio = $null
$script:UltimaSenhaEm = [DateTime]::MinValue

try {
  Add-Type -AssemblyName System.Drawing
  if (-not ('QrSenha' -as [type])) {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Pasta 'qr.cs'), [Text.Encoding]::UTF8))
  }
  if (-not ('SenhaImpressa' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Pasta 'senha.cs'), [Text.Encoding]::UTF8))
  }
  $script:QrOk = $true
} catch {
  Registrar ('Senha do sorteio: não consegui carregar o QR/impressão: ' + $_.Exception.Message)
}

# Só funciona com o sorteio ligado no config.json E com a chave nesta pasta
function SorteioAtivo {
  $s = $Cfg.sorteio
  if (-not $s) { return $false }
  if (-not [bool]$s.ativo) { return $false }
  return (Test-Path -LiteralPath $ArqChaveSorteio)
}

# Roda em outro processo (Start-Job): fala com o servidor e tenta de novo enquanto a venda nova
# ainda não apareceu na ConnectPlug ("aguardando"). Devolve o resultado em JSON.
$BlocoSenha = {
  param($url, $anon, $chave, $pedido, $tentativas, $espera)
  $ErrorActionPreference = 'Stop'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
  $corpo = [Text.Encoding]::UTF8.GetBytes((@{ action = 'sorteio-senha'; chave = $chave; pedido = $pedido } | ConvertTo-Json -Compress))
  $cab = @{ apikey = $anon; Authorization = ('Bearer ' + $anon) }
  $ultimo = $null
  for ($i = 1; $i -le $tentativas; $i++) {
    try {
      $r = Invoke-RestMethod -Method Post -Uri $url -Headers $cab -ContentType 'application/json; charset=utf-8' -Body $corpo -TimeoutSec 20
      $ultimo = $r
      if ($r.ok) { break }
      if ($r.motivo -ne 'aguardando') { break }
    } catch {
      $ultimo = @{ ok = $false; motivo = 'erro'; error = [string]$_.Exception.Message }
    }
    if ($i -lt $tentativas) { Start-Sleep -Seconds $espera }
  }
  if (-not $ultimo) { $ultimo = @{ ok = $false; motivo = 'sem_resposta' } }
  $ultimo | ConvertTo-Json -Compress -Depth 5
}

# Chamado quando o PDV avisa "A venda foi finalizada com sucesso"
function IniciarSenha {
  try {
    if (-not (SorteioAtivo)) { return }
    if ($script:JobSenha) { Registrar 'Senha do sorteio: ainda há um pedido em andamento; ignorei este.'; return }
    # o mesmo aviso pode aparecer duas vezes no registro do PDV
    if (((Get-Date) - $script:UltimaSenhaEm).TotalSeconds -lt 15) { return }
    $s = $Cfg.sorteio
    $url = [string]$s.funcao_url
    $anon = [string]$s.chave_publica
    if ((-not $url) -or (-not $anon)) { Registrar 'Senha do sorteio: faltam funcao_url e chave_publica em config.json (sorteio).'; return }
    $chave = ([IO.File]::ReadAllText($ArqChaveSorteio)).Trim()
    $tent = [int]$s.tentativas
    if ($tent -lt 1) { $tent = 6 }
    $script:UltimaSenhaEm = Get-Date
    $pedido = [Guid]::NewGuid().ToString('N')
    $script:JobSenha = Start-Job -ScriptBlock $BlocoSenha -ArgumentList $url, $anon, $chave, $pedido, $tent, 4
    $script:JobSenhaInicio = Get-Date
    Registrar ('Senha do sorteio: pedido ' + $pedido.Substring(0, 8) + ' enviado.')
  } catch {
    Registrar ('Senha do sorteio: não consegui pedir a senha: ' + $_.Exception.Message)
  }
}

# Chamado a cada volta do laço principal: confere se a resposta chegou
function VerificarSenha {
  if (-not $script:JobSenha) { return }
  $j = $script:JobSenha
  if (($j.State -eq 'Running') -or ($j.State -eq 'NotStarted')) {
    if (((Get-Date) - $script:JobSenhaInicio).TotalSeconds -gt 90) {
      $script:JobSenha = $null
      Stop-Job $j -ErrorAction SilentlyContinue
      Remove-Job $j -Force -ErrorAction SilentlyContinue
      Registrar 'Senha do sorteio: o servidor demorou demais; desisti desta venda.'
    }
    return
  }
  $script:JobSenha = $null
  $estado = [string]$j.State
  try {
    $txt = ''
    if ($estado -eq 'Completed') { $txt = ((Receive-Job $j | Out-String)).Trim() }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
    if (-not $txt) { Registrar ('Senha do sorteio: sem resposta (' + $estado + ').'); return }
    $r = $txt | ConvertFrom-Json
    if ($r.ok -and $r.codigo) {
      Registrar ('Senha do sorteio: ' + $r.codigo + ' (venda de R$ ' + $r.valor + ')')
      ImprimirSenha $r
    } else {
      $m = [string]$r.motivo
      if ($r.error) { $m = $m + ' - ' + [string]$r.error }
      Registrar ('Senha do sorteio: nenhuma senha para esta venda (' + $m + ')')
    }
  } catch {
    Registrar ('Senha do sorteio: erro ao ler a resposta: ' + $_.Exception.Message)
  }
}

# Data que pode vir como texto ou como DateTime (o PS 5.1 converte sozinho) -> horário de Brasília
function DataBrasilia($v) {
  if ($v -is [DateTime]) { return $v }
  return ([DateTimeOffset]::Parse([string]$v)).ToOffset([TimeSpan]::FromHours(-3)).DateTime
}

function TextoPrazo($r) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $p = @()
  try { if ($r.cadastro_ate) { $d = DataBrasilia $r.cadastro_ate; $p += ('Cadastre até ' + $d.ToString('dd/MM', $inv) + ' às ' + $d.ToString('HH:mm', $inv)) } } catch {}
  try { if ($r.sorteio_em) { $d = DataBrasilia $r.sorteio_em; $p += ('Sorteio em ' + $d.ToString('dd/MM', $inv)) } } catch {}
  return ($p -join ' · ')
}

# Monta o cupom e manda para a impressora configurada (config.json -> sorteio.impressora; vazio = padrão do Windows)
function ImprimirSenha($r) {
  try {
    if (-not $script:QrOk) { Registrar 'Senha do sorteio: impressão indisponível (qr.cs/senha.cs não carregaram).'; return }
    $s = $Cfg.sorteio
    $d = New-Object DadosSenha
    $d.Codigo = ([string]$r.codigo).ToUpper()
    $site = [string]$s.site
    if (-not $site) { $site = 'https://padaria-silmar.vercel.app/cesta' }
    $d.Link = $site.TrimEnd('/') + '?s=' + $d.Codigo
    $d.LinkCurto = ($site -replace '^https?://', '').TrimEnd('/')
    if ([string]$r.titulo) { $d.Titulo = ([string]$r.titulo).ToUpper() }
    $d.Prazo = TextoPrazo $r
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $venda = ''
    if ($r.venda) { $venda = 'Venda nº ' + [string]$r.venda + ' · ' }
    $d.Rodape = $venda + (Get-Date).ToString('dd/MM/yyyy HH:mm', $inv)
    try { $d.Qr = [QrSenha]::Gerar($d.Link) } catch { Registrar ('Senha do sorteio: sem QR (' + $_.Exception.Message + ')') }
    $larg = [single]72
    if ([double]$s.papel_largura_mm -gt 0) { $larg = [single]$s.papel_largura_mm }
    $alt = [single]0
    if ([double]$s.papel_altura_mm -gt 0) { $alt = [single]$s.papel_altura_mm }
    $copias = [int]$s.copias
    if ($copias -lt 1) { $copias = 1 }
    for ($c = 1; $c -le $copias; $c++) { [SenhaImpressa]::Imprimir([string]$s.impressora, $larg, $alt, $d) }
    Registrar ('Senha do sorteio: cupom ' + $d.Codigo + ' enviado para a impressora ' + $(if ([string]$s.impressora) { [string]$s.impressora } else { '(padrão)' }) + '.')
  } catch {
    Registrar ('Senha do sorteio: NÃO imprimiu a senha ' + [string]$r.codigo + ': ' + $_.Exception.Message)
  }
}
