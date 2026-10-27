# ================================================================
#  Tela do Cliente - Padaria Silmar
#  Vigia o Connectplug PDV e controla a segunda tela (vista do cliente).
#   - Lê o registro (CPLOG) do Connectplug em tempo real
#   - Copia a lista de itens e o total da tela do caixa
#   - Serve a página da tela do cliente em http://127.0.0.1:<porta>/
#   - Abre o Edge em tela cheia no monitor do cliente
# ================================================================

$ErrorActionPreference = 'Stop'
$Pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Pasta) { $Pasta = 'C:\TelaCliente' }

# ---------- instância única ----------
$criado = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\TelaClientePadariaSilmar', [ref]$criado)
if (-not $criado) { exit }

# ---------- registro de eventos (para manutenção) ----------
$ArqRegistro = Join-Path $Pasta 'registro.log'
function Registrar([string]$msg) {
  try {
    if ((Test-Path $ArqRegistro) -and ((Get-Item $ArqRegistro).Length -gt 2MB)) {
      Move-Item $ArqRegistro ($ArqRegistro + '.antigo') -Force
    }
    $linha = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' | ' + $msg
    [IO.File]::AppendAllText($ArqRegistro, $linha + "`r`n", [Text.Encoding]::UTF8)
  } catch {}
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class TelaCli {
  [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int v);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

  public static void DpiReal() {
    try { SetProcessDpiAwareness(2); } catch { try { SetProcessDPIAware(); } catch { } }
  }

  public static void Focar(IntPtr h) {
    if (h == IntPtr.Zero) return;
    keybd_event(0x12, 0, 0, UIntPtr.Zero);
    if (IsIconic(h)) ShowWindow(h, 9);
    SetForegroundWindow(h);
    keybd_event(0x12, 0, 2, UIntPtr.Zero);
  }

  static ImageCodecInfo jpeg;
  static ImageCodecInfo Jpeg() {
    if (jpeg == null) foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders()) if (c.MimeType == "image/jpeg") jpeg = c;
    return jpeg;
  }

  // Copia uma área da tela; devolve JPEG e uma "impressão digital" para saber se mudou
  public static byte[] Capturar(int x, int y, int w, int h, long qualidade, out long marca) {
    using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
      using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
      marca = Marca(bmp);
      using (MemoryStream ms = new MemoryStream()) {
        EncoderParameters p = new EncoderParameters(1);
        p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, qualidade);
        bmp.Save(ms, Jpeg(), p);
        return ms.ToArray();
      }
    }
  }

  // Igual a Capturar, mas só gera a imagem se a tela mudou (devolve null se não mudou).
  // Em PNG o texto sai sem perdas: as bordas das letras ficam limpas para a ampliação.
  public static byte[] CapturarSeMudou(int x, int y, int w, int h, long anterior, bool png, long qualidade, out long marca) {
    using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
      using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
      marca = Marca(bmp);
      if (marca == anterior) return null;
      using (MemoryStream ms = new MemoryStream()) {
        if (png) { bmp.Save(ms, ImageFormat.Png); }
        else {
          EncoderParameters p = new EncoderParameters(1);
          p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, qualidade);
          bmp.Save(ms, Jpeg(), p);
        }
        return ms.ToArray();
      }
    }
  }

  static long Marca(Bitmap bmp) {
    BitmapData d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    try {
      int n = d.Stride * d.Height;
      byte[] b = new byte[n];
      Marshal.Copy(d.Scan0, b, 0, n);
      long hsh = 1469598103934665603L;
      for (int i = 0; i < n; i += 7) { hsh ^= b[i]; hsh *= 1099511628211L; }
      return hsh;
    } finally { bmp.UnlockBits(d); }
  }

  // Conta pixels escuros (texto) numa faixa: diz se há item na primeira linha da lista
  public static int Escuros(int x, int y, int w, int h) {
    using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
      using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
      BitmapData d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      try {
        int n = d.Stride * h; byte[] b = new byte[n];
        Marshal.Copy(d.Scan0, b, 0, n);
        int cont = 0;
        for (int yy = 0; yy < h; yy += 2) {
          int lin = yy * d.Stride;
          for (int xx = 0; xx < w; xx += 2) {
            int i = lin + xx * 3;
            if (b[i] + b[i + 1] + b[i + 2] < 330) cont++;
          }
        }
        return cont;
      } finally { bmp.UnlockBits(d); }
    }
  }
}
"@

[TelaCli]::DpiReal()

# ---------- configuração ----------
$ArqConfig = Join-Path $Pasta 'config.json'
function LerConfig {
  $txt = [IO.File]::ReadAllText($ArqConfig, [Text.Encoding]::UTF8)
  return ($txt | ConvertFrom-Json)
}
$Cfg = LerConfig
$CfgData = (Get-Item $ArqConfig).LastWriteTime

$Porta = [int]$Cfg.porta
if (-not $Porta) { $Porta = 8765 }

# ---------- estado da tela ----------
$Estado = @{
  cena        = 'promo'   # promo | itens | qr
  rota        = ''
  pago        = $false
  qrAte       = $null
  qrDesde     = $null
  cenaDesde   = Get-Date
  vazioDesde  = $null
  vItens      = 0
  vTotal      = 0
  marcaItens  = 0
  marcaTotal  = 0
  jpgItens    = $null
  jpgTotal    = $null
  tipoCap     = 'image/png'
}

function MudarCena([string]$nova, [string]$motivo) {
  if ($Estado.cena -eq $nova) { return }
  Registrar ("Cena: " + $Estado.cena + " -> " + $nova + "  (" + $motivo + ")")
  $Estado.cena = $nova
  $Estado.cenaDesde = Get-Date
  $Estado.vazioDesde = $null
  if ($nova -eq 'qr') { $Estado.qrDesde = Get-Date }
  if ($nova -eq 'itens') {
    # Descarta a imagem da venda anterior e captura a atual na hora
    $Estado.jpgItens = $null; $Estado.jpgTotal = $null; $Estado.marcaItens = 0L; $Estado.marcaTotal = 0L
    try { CapturarItens } catch {}
  }
  if ($nova -ne 'qr') { $Estado.qrAte = $null }
}

# ---------- leitura do registro do Connectplug ----------
$PastaLogs = Join-Path $env:APPDATA 'ConnectPlug PDV\logs'
$Log = @{ arquivo = ''; pos = 0L; resto = '' }

function ArquivoLogDeHoje {
  $hoje = Join-Path $PastaLogs ((Get-Date -Format 'yyyy-MM-dd') + '_CPLOG.log')
  if (Test-Path $hoje) { return $hoje }
  $ult = Get-ChildItem -Path $PastaLogs -Filter '*_CPLOG.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($ult) { return $ult.FullName }
  return ''
}

function LerNovasLinhas {
  $arq = ArquivoLogDeHoje
  if (-not $arq) { return @() }
  if ($arq -ne $Log.arquivo) {
    $primeira = ($Log.arquivo -eq '')
    $Log.arquivo = $arq; $Log.pos = 0L; $Log.resto = ''
    if ($primeira) {
      # Na partida: só descobre em que tela o PDV está, sem disparar trocas antigas
      $linhas = LerDoArquivo
      foreach ($l in $linhas) { if ($l -match 'Mudando para a rota "([^"]+)"') { $Estado.rota = $Matches[1] } }
      Registrar ("Lendo registro: " + $arq + " | rota atual: " + $Estado.rota)
      return @()
    }
    Registrar ("Novo arquivo de registro: " + $arq)
  }
  return LerDoArquivo
}

function LerDoArquivo {
  $fs = $null
  try {
    $fs = [IO.File]::Open($Log.arquivo, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
    if ($fs.Length -lt $Log.pos) { $Log.pos = 0L; $Log.resto = '' }
    if ($fs.Length -eq $Log.pos) { return @() }
    [void]$fs.Seek($Log.pos, [IO.SeekOrigin]::Begin)
    $n = [int]($fs.Length - $Log.pos)
    $buf = New-Object byte[] $n
    $lidos = $fs.Read($buf, 0, $n)
    $Log.pos += $lidos
    $txt = $Log.resto + [Text.Encoding]::UTF8.GetString($buf, 0, $lidos)
    $partes = $txt -split "`n"
    $Log.resto = $partes[-1]
    if ($partes.Count -le 1) { return @() }
    return $partes[0..($partes.Count - 2)]
  } catch { return @() } finally { if ($fs) { $fs.Dispose() } }
}

function ProcessarLinha([string]$l) {
  if ($l -match 'Mudando para a rota "([^"]+)"') {
    $rota = $Matches[1]
    $Estado.rota = $rota
    if ($rota -like 'checkout*') {
      MudarCena 'qr' ('PDV entrou no pagamento: ' + $rota)
    } elseif ($rota -eq 'cashier') {
      # Voltou do pagamento sem finalizar -> volta a mostrar os itens
      if ($Estado.cena -eq 'qr' -and -not $Estado.pago) { MudarCena 'itens' 'voltou do pagamento' }
    } else {
      if ($Estado.cena -eq 'itens') { MudarCena 'promo' ('PDV saiu do caixa: ' + $rota) }
    }
    return
  }
  if ($l -like '*Uma nova venda foi iniciada*') {
    $Estado.pago = $false
    MudarCena 'itens' 'nova venda'
    return
  }
  if ($l -like '*A venda foi finalizada com sucesso*') {
    $Estado.pago = $true
    if ($Estado.cena -ne 'qr') { MudarCena 'qr' 'venda finalizada' }
    $seg = [int]$Cfg.qr_segundos_apos_pagamento
    if ($seg -le 0) { $seg = 30 }
    $Estado.qrAte = (Get-Date).AddSeconds($seg)
    Registrar ("Venda finalizada. QR até " + $Estado.qrAte.ToString('HH:mm:ss'))
    return
  }
}

# ---------- captura da tela do caixa ----------
function Area($a) { return @{ x = [int]$a.x; y = [int]$a.y; w = [int]$a.largura; h = [int]$a.altura } }

function CapturarItens {
  $q = [long]$Cfg.qualidade_imagem; if (-not $q) { $q = 88 }
  # PNG (sem perdas) por padrão; "formato_captura": "jpg" no config.json volta ao formato antigo
  $png = ([string]$Cfg.formato_captura -ne 'jpg')
  $Estado.tipoCap = $(if ($png) { 'image/png' } else { 'image/jpeg' })
  $a = Area $Cfg.area_itens
  $m = 0L
  $img = [TelaCli]::CapturarSeMudou($a.x, $a.y, $a.w, $a.h, $Estado.marcaItens, $png, $q, [ref]$m)
  if ($img) { $Estado.marcaItens = $m; $Estado.jpgItens = $img; $Estado.vItens++; SalvarDiagnostico }
  $a = Area $Cfg.area_total
  $m = 0L
  $img = [TelaCli]::CapturarSeMudou($a.x, $a.y, $a.w, $a.h, $Estado.marcaTotal, $png, $q, [ref]$m)
  if ($img) { $Estado.marcaTotal = $m; $Estado.jpgTotal = $img; $Estado.vTotal++ }
}

# Guarda as últimas fotos da tela do caixa durante as vendas (para descobrir problemas depois)
$PastaDiag = Join-Path $Pasta 'diagnostico'
$UltimoDiag = [DateTime]::MinValue
function SalvarDiagnostico {
  if ($Cfg.diagnostico -eq $false) { return }
  if (((Get-Date) - $UltimoDiag).TotalSeconds -lt 1.5) { return }
  $script:UltimoDiag = Get-Date
  try {
    if (-not (Test-Path $PastaDiag)) { New-Item -ItemType Directory -Path $PastaDiag -Force | Out-Null }
    $tela = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $m = 0L
    $jpg = [TelaCli]::Capturar($tela.X, $tela.Y, $tela.Width, $tela.Height, 75, [ref]$m)
    [IO.File]::WriteAllBytes((Join-Path $PastaDiag ('caixa_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '.jpg')), $jpg)
    $velhos = Get-ChildItem -Path $PastaDiag -Filter 'caixa_*.jpg' | Sort-Object Name -Descending | Select-Object -Skip 60
    foreach ($v in $velhos) { Remove-Item $v.FullName -Force -ErrorAction SilentlyContinue }
  } catch {}
}

function TemItemNaTela {
  $a = Area $Cfg.area_deteccao
  $lim = [int]$Cfg.deteccao_minimo; if (-not $lim) { $lim = 25 }
  return ([TelaCli]::Escuros($a.x, $a.y, $a.w, $a.h) -ge $lim)
}

function VerificarTela {
  $agora = Get-Date
  $noCaixa = ($Estado.rota -eq 'cashier')
  if ($noCaixa) {
    $tem = TemItemNaTela
    if ($tem) {
      $Estado.vazioDesde = $null
      if ($Estado.cena -eq 'promo') { $Estado.pago = $false; MudarCena 'itens' 'item apareceu na tela' }
      elseif ($Estado.cena -eq 'qr' -and $Estado.pago) { $Estado.pago = $false; MudarCena 'itens' 'nova venda durante o QR' }
    } else {
      if ($Estado.cena -eq 'itens') {
        if (-not $Estado.vazioDesde) { $Estado.vazioDesde = $agora }
        elseif (($agora - $Estado.vazioDesde).TotalSeconds -ge 4 -and ($agora - $Estado.cenaDesde).TotalSeconds -ge 4) {
          MudarCena 'promo' 'lista ficou vazia (venda cancelada)'
        }
      }
    }
  }
  if ($Estado.cena -eq 'qr') {
    if ($Estado.qrAte -and $agora -ge $Estado.qrAte) { MudarCena 'promo' 'tempo do QR terminou' }
    elseif (-not $Estado.qrAte -and $Estado.qrDesde -and ($agora - $Estado.qrDesde).TotalMinutes -ge 10) { MudarCena 'promo' 'pagamento parado há 10 min' }
  }
}

# ---------- arquivos de divulgação ----------
$PastaDiv = Join-Path $Pasta 'divulgacao'
$ExtImg = @('.jpg', '.jpeg', '.png', '.webp', '.gif')
$ExtVid = @('.mp4', '.webm')

function ListaPromocoes {
  $itens = New-Object System.Collections.ArrayList
  if (Test-Path $PastaDiv) {
    $arqs = Get-ChildItem -Path $PastaDiv -File | Sort-Object Name
    foreach ($f in $arqs) {
      $ext = $f.Extension.ToLower()
      $tipo = $null
      if ($ExtImg -contains $ext) { $tipo = 'imagem' } elseif ($ExtVid -contains $ext) { $tipo = 'video' }
      if ($tipo) { [void]$itens.Add(@{ tipo = $tipo; arquivo = '/div/' + [Uri]::EscapeDataString($f.Name); nome = [IO.Path]::GetFileNameWithoutExtension($f.Name) }) }
    }
  }
  foreach ($p in $Cfg.promocoes) {
    [void]$itens.Add(@{ tipo = 'texto'; titulo = $p.titulo; descricao = $p.descricao; preco = $p.preco; selo = $p.selo })
  }
  return ,$itens
}

# Fotos de produtos do cardápio de encomendas (pasta "cardapio")
$PastaCard = Join-Path $Pasta 'cardapio'
function ListaCardapio {
  $fotos = New-Object System.Collections.ArrayList
  if (Test-Path $PastaCard) {
    foreach ($f in (Get-ChildItem -Path $PastaCard -File | Sort-Object Name)) {
      if ($ExtImg -contains $f.Extension.ToLower()) {
        [void]$fotos.Add(@{ arquivo = '/cardapio-img/' + [Uri]::EscapeDataString($f.Name); nome = [IO.Path]::GetFileNameWithoutExtension($f.Name) })
      }
    }
  }
  return ,$fotos
}

function ArquivoLogo {
  foreach ($n in @('logo.png', 'logo.jpg', 'logo.jpeg', 'logo.svg', 'logo.webp')) {
    $c = Join-Path $Pasta $n
    if (Test-Path $c) { return $c }
  }
  return $null
}

# ---------- servidor local ----------
$Tipos = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'
  '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.svg' = 'image/svg+xml'; '.mp4' = 'video/mp4'; '.webm' = 'video/webm'
  '.woff2' = 'font/woff2'
}

function Responder($ns, [int]$cod, [string]$tipo, [byte[]]$corpo) {
  $txtCod = @{ 200 = 'OK'; 404 = 'Not Found'; 500 = 'Error' }[$cod]
  if (-not $corpo) { $corpo = New-Object byte[] 0 }
  $cab = "HTTP/1.1 $cod $txtCod`r`nContent-Type: $tipo`r`nContent-Length: " + $corpo.Length + "`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
  $b = [Text.Encoding]::ASCII.GetBytes($cab)
  $ns.Write($b, 0, $b.Length)
  if ($corpo.Length) { $ns.Write($corpo, 0, $corpo.Length) }
  $ns.Flush()
}

function Json($obj) { return [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 5 -Compress)) }

function ArquivoSeguro([string]$base, [string]$nome) {
  $nome = [Uri]::UnescapeDataString($nome)
  if ($nome -match '\.\.|[\\/:*?"<>|]') { return $null }
  $c = Join-Path $base $nome
  if (Test-Path $c -PathType Leaf) { return $c }
  return $null
}

function Atender($cli) {
  $ns = $null
  try {
    $cli.ReceiveTimeout = 800; $cli.SendTimeout = 3000
    $ns = $cli.GetStream()
    $t = [Diagnostics.Stopwatch]::StartNew()
    while (-not $ns.DataAvailable -and $t.ElapsedMilliseconds -lt 200) { Start-Sleep -Milliseconds 5 }
    if (-not $ns.DataAvailable) { return }
    $buf = New-Object byte[] 8192
    $n = $ns.Read($buf, 0, $buf.Length)
    if ($n -le 0) { return }
    $req = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
    $partes = ($req -split "`r`n")[0] -split ' '
    if ($partes.Count -lt 2) { return }
    $cam = ($partes[1] -split '\?')[0]

    switch -Regex ($cam) {
      '^/$' {
        Responder $ns 200 $Tipos['.html'] ([IO.File]::ReadAllBytes((Join-Path $Pasta 'web\index.html'))); break
      }
      '^/estado$' {
        $s = @{ cena = $Estado.cena; vi = $Estado.vItens; vt = $Estado.vTotal; qr = [string]$Cfg.qr_link
                qrTitulo = [string]$Cfg.qr_titulo; qrTexto = [string]$Cfg.qr_texto; slide = [int]$Cfg.tempo_slide_segundos
                nome = [string]$Cfg.nome_loja; logo = [bool](ArquivoLogo); logoNome = (Test-Path (Join-Path $Pasta 'logo-nome.png')); cardapio = [string]$Cfg.cardapio_link; encomendas = $Cfg.encomendas; layout = $Cfg.layout; pagina = [string](Get-Item (Join-Path $Pasta 'web\index.html')).LastWriteTime.Ticks }
        Responder $ns 200 $Tipos['.json'] (Json $s); break
      }
      '^/cap/itens\.jpg$' { if ($Estado.jpgItens) { Responder $ns 200 $Estado.tipoCap $Estado.jpgItens } else { Responder $ns 404 'text/plain' $null }; break }
      '^/cap/total\.jpg$' { if ($Estado.jpgTotal) { Responder $ns 200 $Estado.tipoCap $Estado.jpgTotal } else { Responder $ns 404 'text/plain' $null }; break }
      '^/promocoes$' { Responder $ns 200 $Tipos['.json'] (Json @{ itens = (ListaPromocoes); cardapio = (ListaCardapio) }); break }
      '^/logo$' {
        $lg = ArquivoLogo
        if ($lg) { Responder $ns 200 $Tipos[[IO.Path]::GetExtension($lg).ToLower()] ([IO.File]::ReadAllBytes($lg)) }
        else { Responder $ns 404 'text/plain' $null }
        break
      }
      '^/logo-nome$' {
        $ln = Join-Path $Pasta 'logo-nome.png'
        if (Test-Path $ln) { Responder $ns 200 'image/png' ([IO.File]::ReadAllBytes($ln)) } else { Responder $ns 404 'text/plain' $null }
        break
      }
      '^/cardapio-img/(.+)$' {
        $f = ArquivoSeguro $PastaCard $Matches[1]
        if ($f) { Responder $ns 200 $Tipos[[IO.Path]::GetExtension($f).ToLower()] ([IO.File]::ReadAllBytes($f)) } else { Responder $ns 404 'text/plain' $null }
        break
      }
      '^/div/(.+)$' {
        $f = ArquivoSeguro $PastaDiv $Matches[1]
        if ($f) { Responder $ns 200 $Tipos[[IO.Path]::GetExtension($f).ToLower()] ([IO.File]::ReadAllBytes($f)) } else { Responder $ns 404 'text/plain' $null }
        break
      }
      '^/web/(.+)$' {
        $f = ArquivoSeguro (Join-Path $Pasta 'web') $Matches[1]
        if ($f) { Responder $ns 200 $Tipos[[IO.Path]::GetExtension($f).ToLower()] ([IO.File]::ReadAllBytes($f)) } else { Responder $ns 404 'text/plain' $null }
        break
      }
      default { Responder $ns 404 'text/plain' $null }
    }
  } catch {
    Registrar ("Erro ao atender pedido: " + $_.Exception.Message)
  } finally {
    if ($ns) { $ns.Dispose() }
    $cli.Close()
  }
}

# ---------- Edge em tela cheia no monitor do cliente ----------
$PerfilEdge = Join-Path $Pasta 'perfil-edge'
function CaminhoEdge {
  foreach ($c in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

function TelaDoCliente {
  $telas = [System.Windows.Forms.Screen]::AllScreens
  $n = [int]$Cfg.tela_cliente
  if ($n -ge 1 -and $n -le $telas.Count) { return $telas[$n - 1] }
  $sec = $telas | Where-Object { -not $_.Primary } | Select-Object -First 1
  return $sec
}

function EdgeAberto {
  $p = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*perfil-edge*' }
  return [bool]$p
}

function FocarPDV {
  $pdv = Get-Process -Name 'ConnectPlug PDV' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($pdv) { [TelaCli]::Focar($pdv.MainWindowHandle) }
}

function AbrirEdge {
  $edge = CaminhoEdge
  if (-not $edge) { Registrar 'Edge não encontrado.'; return }
  $tela = TelaDoCliente
  if (-not $tela) { Registrar 'Segunda tela não encontrada. Tentando de novo em instantes.'; return }
  $x = $tela.Bounds.X + 100; $y = $tela.Bounds.Y + 100
  $url = "http://127.0.0.1:$Porta/"
  $argsEdge = @("--kiosk", $url, "--edge-kiosk-type=fullscreen", "--no-first-run", "--no-default-browser-check",
            "--user-data-dir=`"$PerfilEdge`"", "--window-position=$x,$y", "--autoplay-policy=no-user-gesture-required",
            "--disable-features=Translate,msEdgeSidebarV2", "--disable-pinch", "--overscroll-history-navigation=0")
  Start-Process -FilePath $edge -ArgumentList $argsEdge | Out-Null
  Registrar ("Edge aberto na tela " + $tela.DeviceName + " (" + $tela.Bounds.Width + "x" + $tela.Bounds.Height + ")")
  Start-Sleep -Milliseconds 3500
  FocarPDV
}

# ---------- atualização automática pelo GitHub ----------
# O repositório tem um "versao.json" com a lista de arquivos e a impressão digital (SHA-256) de cada um.
# Só baixa o que mudou, confere cada arquivo e só então troca. O que é substituído vai para "versao-anterior".
# Se o config.json não tiver "atualizacao", usa o repositório padrão. Para desligar: "atualizacao": { "repositorio": "" }
$RepoPadrao = 'ynsouza/segundatela'
$ArqVersao = Join-Path $Pasta 'versao.json'
$PastaNova = Join-Path $Pasta 'atualizando'
$PastaAnterior = Join-Path $Pasta 'versao-anterior'
$ArqPendente = Join-Path $Pasta 'atualizacao-pendente'
$PastasGeridas = @('cardapio', 'divulgacao')   # foto que sair do repositório sai também do caixa
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function ConfigAtualizacao {
  $a = $Cfg.atualizacao
  $repo = $RepoPadrao; $ramo = 'main'; $min = 10
  if ($a) {
    if ($a.PSObject.Properties['repositorio']) { $repo = [string]$a.repositorio }
    if ([string]$a.ramo) { $ramo = [string]$a.ramo }
    if ([int]$a.minutos -gt 0) { $min = [int]$a.minutos }
  }
  if ($repo -notmatch '^[\w.-]+/[\w.-]+$' -or $repo -like 'USUARIO/*') { $repo = '' }
  $base = 'https://raw.githubusercontent.com/' + $repo + '/' + $ramo + '/'
  if ($a -and [string]$a.endereco) { $base = ([string]$a.endereco).TrimEnd('/') + '/'; if (-not $repo) { $repo = 'endereco' } }   # para testes
  return @{ repo = $repo; base = $base; minutos = $min }
}

function BaixarBytes([string]$url) {
  $req = [Net.HttpWebRequest]::Create($url)
  $req.Timeout = 15000; $req.ReadWriteTimeout = 15000; $req.UserAgent = 'TelaCliente-PadariaSilmar'
  $resp = $req.GetResponse()
  try { $ms = New-Object IO.MemoryStream; $resp.GetResponseStream().CopyTo($ms); return ,$ms.ToArray() } finally { $resp.Close() }
}

function Sha256Bytes([byte[]]$b) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { return (($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $h.Dispose() }
}

function Sha256Arquivo([string]$c) {
  if (Test-Path -LiteralPath $c -PathType Leaf) { return (Get-FileHash -LiteralPath $c -Algorithm SHA256).Hash.ToLower() }
  return ''
}

function UrlDoRepo($ca, [string]$caminho) {
  $partes = ($caminho -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }
  return $ca.base + ($partes -join '/')
}

function CaminhoLocal([string]$caminho) {
  if (-not $caminho -or $caminho -match '\.\.|^[\\/]|:') { return $null }
  return Join-Path $Pasta ($caminho -replace '/', '\')
}

function GuardarAnterior([string]$arquivo) {
  $bak = Join-Path $PastaAnterior $arquivo.Substring($Pasta.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
  Copy-Item -LiteralPath $arquivo -Destination $bak -Force
}

function ProcurarAtualizacao {
  $ca = ConfigAtualizacao
  if (-not $ca.repo) { return }
  $txt = [Text.Encoding]::UTF8.GetString((BaixarBytes ((UrlDoRepo $ca 'versao.json') + '?t=' + [DateTime]::UtcNow.Ticks)))
  $rem = $txt | ConvertFrom-Json
  if (-not $rem.versao -or -not $rem.arquivos) { return }
  $versaoLocal = ''
  if (Test-Path $ArqVersao) { try { $versaoLocal = [string](([IO.File]::ReadAllText($ArqVersao) | ConvertFrom-Json).versao) } catch {} }
  if ([string]$rem.versao -eq $versaoLocal) { return }
  Registrar ('Atualização encontrada: ' + $versaoLocal + ' -> ' + $rem.versao)

  # 1) baixa e confere tudo antes de mexer em qualquer arquivo
  if (Test-Path $PastaNova) { Remove-Item $PastaNova -Recurse -Force }
  $trocar = New-Object System.Collections.ArrayList
  $doRepo = @{}
  foreach ($f in $rem.arquivos) {
    $dest = CaminhoLocal ([string]$f.caminho)
    if (-not $dest) { throw ('caminho inválido no versao.json: ' + $f.caminho) }
    $doRepo[$dest.ToLower()] = $true
    $sha = ([string]$f.sha256).ToLower()
    if ((Sha256Arquivo $dest) -eq $sha) { continue }
    $b = BaixarBytes (UrlDoRepo $ca ([string]$f.caminho))
    if ((Sha256Bytes $b) -ne $sha) { throw ('arquivo veio diferente do esperado: ' + $f.caminho) }
    $tmp = Join-Path $PastaNova ($f.caminho -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $tmp) | Out-Null
    [IO.File]::WriteAllBytes($tmp, $b)
    [void]$trocar.Add(@{ novo = $tmp; dest = $dest })
  }
  $remover = New-Object System.Collections.ArrayList
  foreach ($p in $PastasGeridas) {
    $dir = Join-Path $Pasta $p
    if (Test-Path $dir) {
      foreach ($arq in (Get-ChildItem -LiteralPath $dir -File)) {
        if ($arq.Name -ne '.mantenha' -and -not $doRepo[$arq.FullName.ToLower()]) { [void]$remover.Add($arq.FullName) }
      }
    }
  }

  # 2) guarda a versão atual em "versao-anterior" e troca (o programa por último)
  if (Test-Path $PastaAnterior) { Remove-Item $PastaAnterior -Recurse -Force }
  $novoPrograma = $null
  foreach ($t in $trocar) {
    if (Test-Path -LiteralPath $t.dest) { GuardarAnterior $t.dest }
    if ($t.dest -eq $MeuArquivo) { $novoPrograma = $t.novo; continue }
    New-Item -ItemType Directory -Force -Path (Split-Path $t.dest) | Out-Null
    Move-Item -LiteralPath $t.novo -Destination $t.dest -Force
  }
  foreach ($r in $remover) { GuardarAnterior $r; Remove-Item -LiteralPath $r -Force }
  [IO.File]::WriteAllText($ArqVersao, $txt, (New-Object Text.UTF8Encoding $false))
  if ($novoPrograma) {
    # iniciar.vbs volta para a versão anterior se o programa novo não conseguir iniciar
    [IO.File]::WriteAllText($ArqPendente, [string]$rem.versao)
    Move-Item -LiteralPath $novoPrograma -Destination $MeuArquivo -Force   # o laço principal percebe e reinicia
  }
  Remove-Item $PastaNova -Recurse -Force -ErrorAction SilentlyContinue
  Registrar ('Atualizado para a versão ' + $rem.versao + ': ' + $trocar.Count + ' arquivo(s) novo(s), ' + $remover.Count + ' removido(s).')
}

# ---------- partida ----------
Registrar "==== Tela do Cliente iniciada ===="
$servidor = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Porta)
try { $servidor.Start() } catch { Registrar ("Não consegui abrir a porta " + $Porta + ": " + $_.Exception.Message); exit }

# Espera o Windows terminar de ligar as telas
Start-Sleep -Seconds 2

$relLog = [Diagnostics.Stopwatch]::StartNew()
$relCap = [Diagnostics.Stopwatch]::StartNew()
$relDet = [Diagnostics.Stopwatch]::StartNew()
$relEdge = [Diagnostics.Stopwatch]::StartNew()
$relCfg = [Diagnostics.Stopwatch]::StartNew()
$relAtu = [Diagnostics.Stopwatch]::StartNew()
$primeiraBusca = $true
$relVivo = [Diagnostics.Stopwatch]::StartNew()
$primeiroEdge = $true
$MeuArquivo = Join-Path $Pasta 'TelaCliente.ps1'
$MinhaVersao = (Get-Item $MeuArquivo).LastWriteTime

while ($true) {
  try {
    while ($servidor.Pending()) { Atender ($servidor.AcceptTcpClient()) }

    if ($relLog.ElapsedMilliseconds -ge 150) {
      $relLog.Restart()
      foreach ($l in (LerNovasLinhas)) { ProcessarLinha $l }
    }

    if ($Estado.cena -eq 'itens' -and $relCap.ElapsedMilliseconds -ge 250) {
      $relCap.Restart()
      CapturarItens
    }

    if ($relDet.ElapsedMilliseconds -ge 400) {
      $relDet.Restart()
      VerificarTela
    }

    if ($primeiroEdge -or $relEdge.Elapsed.TotalSeconds -ge 15) {
      $relEdge.Restart()
      if (-not (EdgeAberto)) { AbrirEdge }
      $primeiroEdge = $false
    }

    if ($relCfg.Elapsed.TotalSeconds -ge 5) {
      $relCfg.Restart()
      if ((Get-Item $MeuArquivo).LastWriteTime -ne $MinhaVersao) {
        Registrar 'Programa atualizado. Reiniciando...'
        $servidor.Stop(); $mutex.ReleaseMutex(); $mutex.Dispose()
        Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + (Join-Path $Pasta 'iniciar.vbs') + '"')
        exit
      }
      $d = (Get-Item $ArqConfig).LastWriteTime
      if ($d -ne $CfgData) { $CfgData = $d; $Cfg = LerConfig; Registrar 'Configuração recarregada.' }
    }

    # Programa novo funcionando há 1 minuto: a atualização deu certo
    if ($relVivo -and $relVivo.Elapsed.TotalSeconds -ge 60) {
      $relVivo = $null
      if (Test-Path $ArqPendente) { Remove-Item $ArqPendente -Force -ErrorAction SilentlyContinue; Registrar 'Versão nova confirmada.' }
    }

    # Procura atualização 1 min depois de ligar e depois a cada N min, só fora de venda
    $esperaAtu = $(if ($primeiraBusca) { 60 } else { (ConfigAtualizacao).minutos * 60 })
    if ($Estado.cena -eq 'promo' -and $relAtu.Elapsed.TotalSeconds -ge $esperaAtu) {
      $relAtu.Restart(); $primeiraBusca = $false
      try { ProcurarAtualizacao } catch {
        Registrar ('Atualização não concluída (tento de novo mais tarde): ' + $_.Exception.Message)
        Remove-Item $PastaNova -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {
    Registrar ("Erro: " + $_.Exception.Message + " | linha " + $_.InvocationInfo.ScriptLineNumber)
    Start-Sleep -Milliseconds 500
  }
  Start-Sleep -Milliseconds 20
}
