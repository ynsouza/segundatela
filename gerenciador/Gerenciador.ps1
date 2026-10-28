# ================================================================
#  Gerenciador da Segunda Tela - Padaria Silmar
#  Roda neste computador e abre no navegador (http://127.0.0.1:8766/).
#   - Edita o config.json e as fotos (cardapio e divulgacao)
#   - Mostra a prévia da tela do cliente com a página de verdade
#   - Publica no GitHub; o PC do caixa baixa sozinho
# ================================================================

param([switch]$SemNavegador)   # para testes: não abre o navegador

$ErrorActionPreference = 'Stop'
$Aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$Raiz = Split-Path -Parent $Aqui                 # pasta do repositório (a mesma do PC do caixa)
$Porta = 8766
$Url = "http://127.0.0.1:$Porta/"

$criado = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\GerenciadorSegundaTelaSilmar', [ref]$criado)
if (-not $criado) { if (-not $SemNavegador) { Start-Process $Url }; exit }   # já está aberto: só mostra no navegador

$ArqConfig = Join-Path $Raiz 'config.json'
$Pastas = @{ cardapio = (Join-Path $Raiz 'cardapio'); divulgacao = (Join-Path $Raiz 'divulgacao') }
$ExtImg = @('.jpg', '.jpeg', '.png', '.webp', '.gif')
$ExtVid = @('.mp4', '.webm')
$Tipos = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'
  '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.svg' = 'image/svg+xml'; '.mp4' = 'video/mp4'; '.webm' = 'video/webm'
  '.woff2' = 'font/woff2'; '.txt' = 'text/plain; charset=utf-8'
}
$Previa = 'promo'
$Utf8 = New-Object Text.UTF8Encoding $false

# ---------- git ----------
function RodarGit([string[]]$argumentos) {
  $antes = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $saida = (& git.exe -C $Raiz @argumentos 2>&1 | Out-String).Trim(); return @{ ok = ($LASTEXITCODE -eq 0); saida = $saida } }
  finally { $ErrorActionPreference = $antes }
}

function Situacao {
  $pend = (RodarGit @('status', '--porcelain')).saida
  $n = @($pend -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch 'versao\.json$' }).Count
  # mudanças já guardadas aqui, mas que ainda não foram para o GitHub
  $adiante = 0; $a = RodarGit @('rev-list', '--count', 'origin/main..HEAD'); if ($a.ok) { $adiante = [int]$a.saida }
  $ult = (RodarGit @('log', '-1', '--format=%cd|%s', '--date=format:%d/%m/%Y %H:%M', 'origin/main')).saida -split '\|', 2
  return @{ pendentes = $n + $adiante; ultima_data = $ult[0]; ultima_msg = $(if ($ult.Count -gt 1) { $ult[1] } else { '' }) }
}

function Publicar {
  $s = Situacao
  if ($s.pendentes -eq 0) { return @{ ok = $true; msg = 'Nada para publicar: tudo já está no ar.' } }
  & (Join-Path $Raiz 'gerar-versao.ps1') | Out-Null
  $r = RodarGit @('add', '-A'); if (-not $r.ok) { return @{ ok = $false; msg = $r.saida } }
  if ((RodarGit @('status', '--porcelain')).saida) {
    $r = RodarGit @('commit', '-m', ('Atualização pelo gerenciador em ' + (Get-Date -Format 'dd/MM/yyyy HH:mm'))); if (-not $r.ok) { return @{ ok = $false; msg = $r.saida } }
  }
  $r = RodarGit @('push', 'origin', 'HEAD')
  if (-not $r.ok) {
    # alguém publicou antes (por exemplo, o Claude): junta as mudanças e tenta de novo
    $p = RodarGit @('pull', '--rebase', 'origin', 'main')
    if (-not $p.ok) { RodarGit @('rebase', '--abort') | Out-Null; return @{ ok = $false; msg = 'Não consegui juntar com a versão do GitHub: ' + $p.saida } }
    & (Join-Path $Raiz 'gerar-versao.ps1') | Out-Null
    RodarGit @('commit', '-am', 'Atualiza a lista de versão') | Out-Null
    $r = RodarGit @('push', 'origin', 'HEAD')
    if (-not $r.ok) { return @{ ok = $false; msg = $r.saida } }
  }
  return @{ ok = $true; msg = 'Publicado! O PC do caixa recebe em até uns 15 minutos.' }
}

# ---------- arquivos ----------
function NomeSeguro([string]$nome) {
  if (-not $nome -or $nome -match '\.\.|[\\/:*?"<>|]' -or $nome.Length -gt 150) { return $null }
  return $nome
}

function ListaPasta([string]$pasta) {
  $l = New-Object System.Collections.ArrayList
  if (Test-Path $Pastas[$pasta]) {
    foreach ($f in (Get-ChildItem -LiteralPath $Pastas[$pasta] -File | Sort-Object Name)) {
      $ext = $f.Extension.ToLower()
      if ($ExtImg -contains $ext -or $ExtVid -contains $ext) { [void]$l.Add(@{ nome = $f.Name; tamanho = $f.Length; video = ($ExtVid -contains $ext) }) }
    }
  }
  return ,$l
}

# Igual ao agente do caixa: para a prévia funcionar com a página de verdade
function ListaPromocoes($cfg) {
  $itens = New-Object System.Collections.ArrayList
  foreach ($f in (ListaPasta 'divulgacao')) {
    [void]$itens.Add(@{ tipo = $(if ($f.video) { 'video' } else { 'imagem' }); arquivo = '/div/' + [Uri]::EscapeDataString($f.nome); nome = [IO.Path]::GetFileNameWithoutExtension($f.nome) })
  }
  foreach ($p in $cfg.promocoes) { [void]$itens.Add(@{ tipo = 'texto'; titulo = $p.titulo; descricao = $p.descricao; preco = $p.preco; selo = $p.selo }) }
  $card = New-Object System.Collections.ArrayList
  foreach ($f in (ListaPasta 'cardapio')) { if (-not $f.video) { [void]$card.Add(@{ arquivo = '/cardapio-img/' + [Uri]::EscapeDataString($f.nome); nome = [IO.Path]::GetFileNameWithoutExtension($f.nome) }) } }
  return @{ itens = $itens; cardapio = $card }
}

function LerConfig { return ([IO.File]::ReadAllText($ArqConfig, [Text.Encoding]::UTF8) | ConvertFrom-Json) }

# ---------- servidor ----------
function Responder($ns, [int]$cod, [string]$tipo, [byte[]]$corpo) {
  $txtCod = @{ 200 = 'OK'; 400 = 'Bad Request'; 404 = 'Not Found'; 500 = 'Error' }[$cod]
  if (-not $corpo) { $corpo = New-Object byte[] 0 }
  $cab = "HTTP/1.1 $cod $txtCod`r`nContent-Type: $tipo`r`nContent-Length: " + $corpo.Length + "`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
  $b = [Text.Encoding]::ASCII.GetBytes($cab)
  $ns.Write($b, 0, $b.Length)
  if ($corpo.Length) { $ns.Write($corpo, 0, $corpo.Length) }
  $ns.Flush()
}
function Json($ns, $obj) { Responder $ns 200 $Tipos['.json'] ($Utf8.GetBytes(($obj | ConvertTo-Json -Depth 8 -Compress))) }
function Arquivo($ns, [string]$c) {
  if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { Responder $ns 200 ($Tipos[[IO.Path]::GetExtension($c).ToLower()]) ([IO.File]::ReadAllBytes($c)) }
  else { Responder $ns 404 'text/plain' $null }
}

# Lê o pedido inteiro (cabeçalho + corpo), inclusive fotos e vídeos enviados
function LerPedido($ns) {
  $buf = New-Object byte[] 65536; $ms = New-Object IO.MemoryStream; $fimCab = -1
  while ($fimCab -lt 0) {
    $n = $ns.Read($buf, 0, $buf.Length); if ($n -le 0) { return $null }
    $ms.Write($buf, 0, $n)
    $tudo = $ms.ToArray(); for ($i = [Math]::Max(0, $tudo.Length - $n - 3); $i -le $tudo.Length - 4; $i++) { if ($tudo[$i] -eq 13 -and $tudo[$i + 1] -eq 10 -and $tudo[$i + 2] -eq 13 -and $tudo[$i + 3] -eq 10) { $fimCab = $i; break } }
    if ($ms.Length -gt 65536 -and $fimCab -lt 0) { return $null }
  }
  $tudo = $ms.ToArray()
  $cab = [Text.Encoding]::ASCII.GetString($tudo, 0, $fimCab)
  $linhas = $cab -split "`r`n"; $p = $linhas[0] -split ' '
  $tam = 0; foreach ($l in $linhas) { if ($l -match '^Content-Length:\s*(\d+)') { $tam = [long]$Matches[1] } }
  if ($tam -gt 120MB) { return $null }
  $corpo = New-Object IO.MemoryStream
  $ini = $fimCab + 4; if ($tudo.Length -gt $ini) { $corpo.Write($tudo, $ini, $tudo.Length - $ini) }
  while ($corpo.Length -lt $tam) { $n = $ns.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $corpo.Write($buf, 0, $n) }
  $alvo = $p[1]; $q = @{}
  $partes = $alvo -split '\?', 2
  if ($partes.Count -gt 1) { foreach ($kv in ($partes[1] -split '&')) { $a = $kv -split '=', 2; if ($a.Count -eq 2) { $q[$a[0]] = [Uri]::UnescapeDataString($a[1].Replace('+', ' ')) } } }
  return @{ metodo = $p[0]; caminho = $partes[0]; q = $q; corpo = $corpo.ToArray() }
}

function Atender($cli) {
  $ns = $null
  try {
    $cli.ReceiveTimeout = 15000; $cli.SendTimeout = 15000
    $ns = $cli.GetStream()
    $r = LerPedido $ns
    if (-not $r) { return }
    $cam = $r.caminho; $q = $r.q
    switch -Regex ($cam) {
      '^/$' { Arquivo $ns (Join-Path $Aqui 'gerenciador.html'); break }
      '^/tela/?$' { Arquivo $ns (Join-Path $Raiz 'web\index.html'); break }

      # --- o que a página da tela pede (prévia) ---
      '^/estado$' {
        $cfg = LerConfig
        Json $ns @{ cena = $script:Previa; vi = 0; vt = 0; qr = [string]$cfg.qr_link; qrTitulo = [string]$cfg.qr_titulo; qrTexto = [string]$cfg.qr_texto
                    slide = [int]$cfg.tempo_slide_segundos; nome = [string]$cfg.nome_loja; logo = (Test-Path (Join-Path $Raiz 'logo.png')); logoNome = (Test-Path (Join-Path $Raiz 'logo-nome.png'))
                    cardapio = [string]$cfg.cardapio_link; encomendas = $cfg.encomendas; layout = $cfg.layout
                    tema = $(if ([string]$cfg.tema) { [string]$cfg.tema } else { 'natal' }); temas = $cfg.temas; efeitos = $cfg.efeitos
                    pagina = [string](Get-Item (Join-Path $Raiz 'web\index.html')).LastWriteTime.Ticks }
        break
      }
      '^/promocoes$' { Json $ns (ListaPromocoes (LerConfig)); break }
      '^/logo$' { Arquivo $ns (Join-Path $Raiz 'logo.png'); break }
      '^/logo-nome$' { Arquivo $ns (Join-Path $Raiz 'logo-nome.png'); break }
      '^/(div|cardapio-img|foto/divulgacao|foto/cardapio)/(.+)$' {
        $pasta = $(if ($Matches[1] -match 'div') { 'divulgacao' } else { 'cardapio' })
        $nome = NomeSeguro ([Uri]::UnescapeDataString($Matches[2]))
        Arquivo $ns $(if ($nome) { Join-Path $Pastas[$pasta] $nome } else { $null }); break
      }
      '^/web/(.+)$' { $nome = NomeSeguro ([Uri]::UnescapeDataString($Matches[1])); Arquivo $ns $(if ($nome) { Join-Path (Join-Path $Raiz 'web') $nome } else { $null }); break }

      # --- gerenciador ---
      '^/api/config$' {
        if ($r.metodo -eq 'POST') {
          $txt = $Utf8.GetString($r.corpo)
          try { $null = $txt | ConvertFrom-Json } catch { Responder $ns 400 'text/plain; charset=utf-8' ($Utf8.GetBytes('Configuração inválida')); break }
          [IO.File]::WriteAllText($ArqConfig, $txt, $Utf8)
          Json $ns @{ ok = $true; situacao = (Situacao) }
        } else { Responder $ns 200 $Tipos['.json'] ([IO.File]::ReadAllBytes($ArqConfig)) }
        break
      }
      '^/api/previa$' { if ($q.cena -in @('promo', 'qr')) { $script:Previa = $q.cena }; Json $ns @{ ok = $true }; break }
      '^/api/fotos$' { Json $ns @{ cardapio = (ListaPasta 'cardapio'); divulgacao = (ListaPasta 'divulgacao') }; break }
      '^/api/foto$' {
        $pasta = $q.pasta; $nome = NomeSeguro $q.nome
        $ext = $(if ($nome) { [IO.Path]::GetExtension($nome).ToLower() } else { '' })
        if (-not $Pastas.ContainsKey($pasta) -or -not $nome -or -not ($ExtImg -contains $ext -or $ExtVid -contains $ext) -or $r.corpo.Length -eq 0) { Responder $ns 400 'text/plain' $null; break }
        if (-not (Test-Path $Pastas[$pasta])) { New-Item -ItemType Directory -Path $Pastas[$pasta] | Out-Null }
        [IO.File]::WriteAllBytes((Join-Path $Pastas[$pasta] $nome), $r.corpo)
        Json $ns @{ ok = $true; situacao = (Situacao) }; break
      }
      '^/api/renomear$' {
        $pasta = $q.pasta; $de = NomeSeguro $q.de; $para = NomeSeguro $q.para
        if (-not $Pastas.ContainsKey($pasta) -or -not $de -or -not $para) { Responder $ns 400 'text/plain' $null; break }
        $a = Join-Path $Pastas[$pasta] $de; $b = Join-Path $Pastas[$pasta] $para
        if ((Test-Path -LiteralPath $a) -and $de -ne $para) {
          if ($de.ToLower() -eq $para.ToLower()) { $tmp = $a + '.tmp'; Move-Item -LiteralPath $a -Destination $tmp; Move-Item -LiteralPath $tmp -Destination $b }
          elseif (-not (Test-Path -LiteralPath $b)) { Move-Item -LiteralPath $a -Destination $b }
          else { Responder $ns 400 'text/plain; charset=utf-8' ($Utf8.GetBytes('Já existe uma foto com esse nome')); break }
        }
        Json $ns @{ ok = $true; situacao = (Situacao) }; break
      }
      '^/api/apagar$' {
        $pasta = $q.pasta; $nome = NomeSeguro $q.nome
        if (-not $Pastas.ContainsKey($pasta) -or -not $nome) { Responder $ns 400 'text/plain' $null; break }
        $c = Join-Path $Pastas[$pasta] $nome
        if (Test-Path -LiteralPath $c) { Remove-Item -LiteralPath $c -Force }   # continua guardada no histórico do GitHub
        Json $ns @{ ok = $true; situacao = (Situacao) }; break
      }
      '^/api/situacao$' { Json $ns (Situacao); break }
      '^/api/publicar$' { $res = Publicar; $res.situacao = (Situacao); Json $ns $res; break }
      '^/api/desfazer$' {
        # volta tudo para a última versão publicada
        RodarGit @('reset', '--hard', 'HEAD') | Out-Null
        RodarGit @('clean', '-fd', '--', 'cardapio', 'divulgacao') | Out-Null
        Json $ns @{ ok = $true; situacao = (Situacao) }; break
      }
      '^/api/sair$' { Json $ns @{ ok = $true }; $script:Sair = $true; break }
      default { Responder $ns 404 'text/plain' $null }
    }
  } catch {
    try { Responder $ns 500 'text/plain; charset=utf-8' ($Utf8.GetBytes($_.Exception.Message)) } catch {}
  } finally {
    if ($ns) { $ns.Dispose() }
    $cli.Close()
  }
}

# ---------- partida ----------
$servidor = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Porta)
$servidor.Start()
RodarGit @('pull', '--ff-only', 'origin', 'main') | Out-Null   # pega o que foi publicado por outro lugar
if (-not $SemNavegador) { Start-Process $Url }
$Sair = $false
$parado = [Diagnostics.Stopwatch]::StartNew()
while (-not $Sair) {
  if ($servidor.Pending()) { $parado.Restart(); Atender ($servidor.AcceptTcpClient()) }
  else { Start-Sleep -Milliseconds 15 }
  if ($parado.Elapsed.TotalHours -ge 3) { break }   # esquecido aberto: fecha sozinho
}
$servidor.Stop(); $mutex.ReleaseMutex()
