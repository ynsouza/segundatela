// Gerador de QR Code (modo byte, correção de erro M, versões 1 a 10 — até 213 bytes).
// Usado pela impressão da senha do sorteio (senha.ps1). Sem dependências.
// Escrito em C# 5 para compilar no Windows PowerShell 5.1 (Add-Type).
using System;
using System.Collections.Generic;
using System.Text;

public static class QrSenha
{
    // Códigos de correção de erro (nível M) por bloco e quantidade de blocos, versões 1..10
    static readonly int[] EccPorBloco = { 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26 };
    static readonly int[] Blocos      = { 0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5 };

    // Devolve a matriz de módulos (true = escuro). Lança exceção se o texto não couber na versão 10.
    public static bool[,] Gerar(string texto)
    {
        byte[] dados = Encoding.UTF8.GetBytes(texto);
        int ver = 0;
        for (int v = 1; v <= 10; v++)
        {
            int cap = CodigosDeDados(v) - (v <= 9 ? 2 : 3);   // 4 bits de modo + contagem (8 ou 16 bits) ≈ 2 ou 3 bytes
            if (dados.Length <= cap) { ver = v; break; }
        }
        if (ver == 0) throw new ArgumentException("Texto longo demais para o QR Code.");

        int tamanho = ver * 4 + 17;
        int numDados = CodigosDeDados(ver);

        // 1) fluxo de bits: modo byte (0100), contagem, dados, terminador, preenchimento
        List<int> bits = new List<int>();
        AddBits(bits, 4, 4);
        AddBits(bits, dados.Length, ver <= 9 ? 8 : 16);
        foreach (byte b in dados) AddBits(bits, b, 8);
        int capBits = numDados * 8;
        AddBits(bits, 0, Math.Min(4, capBits - bits.Count));
        AddBits(bits, 0, (8 - bits.Count % 8) % 8);
        for (int pad = 0xEC; bits.Count < capBits; pad ^= 0xEC ^ 0x11) AddBits(bits, pad, 8);
        byte[] cw = new byte[numDados];
        for (int i = 0; i < bits.Count; i++) cw[i >> 3] |= (byte)(bits[i] << (7 - (i & 7)));

        // 2) Reed-Solomon por bloco e intercalação
        byte[] final = Intercalar(cw, ver);

        // 3) desenha: padrões fixos, dados e a melhor máscara
        bool[,] modulos = new bool[tamanho, tamanho];
        bool[,] funcao = new bool[tamanho, tamanho];
        DesenharFuncao(modulos, funcao, ver, tamanho);
        DesenharDados(modulos, funcao, final, tamanho);

        int melhorMascara = 0; long melhorPenal = long.MaxValue;
        for (int m = 0; m < 8; m++)
        {
            Mascara(modulos, funcao, m, tamanho);
            DesenharFormato(modulos, m, tamanho);
            long p = Penalidade(modulos, tamanho);
            if (p < melhorPenal) { melhorPenal = p; melhorMascara = m; }
            Mascara(modulos, funcao, m, tamanho);   // desfaz (XOR)
        }
        Mascara(modulos, funcao, melhorMascara, tamanho);
        DesenharFormato(modulos, melhorMascara, tamanho);
        return modulos;
    }

    static void AddBits(List<int> l, int valor, int n)
    {
        for (int i = n - 1; i >= 0; i--) l.Add((valor >> i) & 1);
    }

    static int ModulosBrutos(int ver)
    {
        int r = (16 * ver + 128) * ver + 64;
        if (ver >= 2) { int na = ver / 7 + 2; r -= (25 * na - 10) * na - 55; if (ver >= 7) r -= 36; }
        return r;
    }

    static int CodigosDeDados(int ver)
    {
        return ModulosBrutos(ver) / 8 - EccPorBloco[ver] * Blocos[ver];
    }

    // ---------- Reed-Solomon ----------
    static int MulGf(int x, int y)
    {
        int z = 0;
        for (int i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >> 7) * 0x11D); z ^= ((y >> i) & 1) * x; }
        return z;
    }

    static byte[] DivisorRs(int grau)
    {
        byte[] r = new byte[grau];
        r[grau - 1] = 1;
        int raiz = 1;
        for (int i = 0; i < grau; i++)
        {
            for (int j = 0; j < grau; j++)
            {
                r[j] = (byte)MulGf(r[j], raiz);
                if (j + 1 < grau) r[j] ^= r[j + 1];
            }
            raiz = MulGf(raiz, 0x02);
        }
        return r;
    }

    static byte[] RestoRs(byte[] dados, int ini, int len, byte[] divisor)
    {
        byte[] r = new byte[divisor.Length];
        for (int k = 0; k < len; k++)
        {
            int fator = dados[ini + k] ^ r[0];
            Array.Copy(r, 1, r, 0, r.Length - 1);
            r[r.Length - 1] = 0;
            for (int i = 0; i < r.Length; i++) r[i] ^= (byte)MulGf(divisor[i], fator);
        }
        return r;
    }

    static byte[] Intercalar(byte[] dados, int ver)
    {
        int nb = Blocos[ver], ecc = EccPorBloco[ver], bruto = ModulosBrutos(ver) / 8;
        int blocosCurtos = nb - bruto % nb, tamCurto = bruto / nb;
        byte[] div = DivisorRs(ecc);
        byte[][] bl = new byte[nb][];
        int k = 0;
        for (int i = 0; i < nb; i++)
        {
            int len = tamCurto - ecc + (i < blocosCurtos ? 0 : 1);
            byte[] bloco = new byte[tamCurto + 1];   // dados + ecc (+1 espaço nos blocos curtos)
            int usado = 0;
            byte[] d = new byte[len];
            Array.Copy(dados, k, d, 0, len); k += len;
            byte[] e = RestoRs(d, 0, len, div);
            Array.Copy(d, 0, bloco, 0, len); usado = len;
            if (i < blocosCurtos) usado++;   // posição vazia no fim dos dados (não é transmitida)
            Array.Copy(e, 0, bloco, usado, ecc);
            bl[i] = bloco;
        }
        byte[] saida = new byte[bruto];
        int p = 0;
        for (int i = 0; i < tamCurto + 1; i++)
            for (int j = 0; j < nb; j++)
                if (i != tamCurto - ecc || j >= blocosCurtos) saida[p++] = bl[j][i];
        return saida;
    }

    // ---------- desenho ----------
    static void SetFuncao(bool[,] m, bool[,] f, int x, int y, bool escuro)
    {
        m[y, x] = escuro; f[y, x] = true;
    }

    static int[] PosicoesAlinhamento(int ver, int tamanho)
    {
        if (ver == 1) return new int[0];
        int n = ver / 7 + 2;
        int passo = (ver * 4 + n * 2 + 1) / (n * 2 - 2) * 2;
        int[] r = new int[n];
        r[0] = 6;
        for (int i = n - 1, pos = tamanho - 7; i >= 1; i--, pos -= passo) r[i] = pos;
        return r;
    }

    static void DesenharFuncao(bool[,] m, bool[,] f, int ver, int tamanho)
    {
        for (int i = 0; i < tamanho; i++)
        {
            SetFuncao(m, f, 6, i, i % 2 == 0);
            SetFuncao(m, f, i, 6, i % 2 == 0);
        }
        Localizador(m, f, 3, 3, tamanho);
        Localizador(m, f, tamanho - 4, 3, tamanho);
        Localizador(m, f, 3, tamanho - 4, tamanho);
        int[] al = PosicoesAlinhamento(ver, tamanho);
        for (int i = 0; i < al.Length; i++)
            for (int j = 0; j < al.Length; j++)
            {
                if ((i == 0 && j == 0) || (i == 0 && j == al.Length - 1) || (i == al.Length - 1 && j == 0)) continue;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++)
                        SetFuncao(m, f, al[i] + dx, al[j] + dy, Math.Max(Math.Abs(dx), Math.Abs(dy)) != 1);
            }
        DesenharFormato(m, 0, tamanho);   // reserva a área (volta a ser escrita depois)
        MarcarFormato(f, tamanho);
        if (ver >= 7)
        {
            int resto = ver;
            for (int i = 0; i < 12; i++) resto = (resto << 1) ^ ((resto >> 11) * 0x1F25);
            int bitsV = ver << 12 | resto;
            for (int i = 0; i < 18; i++)
            {
                bool b = ((bitsV >> i) & 1) != 0;
                int a = tamanho - 11 + i % 3, c = i / 3;
                SetFuncao(m, f, a, c, b);
                SetFuncao(m, f, c, a, b);
            }
        }
    }

    static void Localizador(bool[,] m, bool[,] f, int cx, int cy, int tamanho)
    {
        for (int dy = -4; dy <= 4; dy++)
            for (int dx = -4; dx <= 4; dx++)
            {
                int dist = Math.Max(Math.Abs(dx), Math.Abs(dy));
                int x = cx + dx, y = cy + dy;
                if (x >= 0 && x < tamanho && y >= 0 && y < tamanho) SetFuncao(m, f, x, y, dist != 2 && dist != 4);
            }
    }

    static void MarcarFormato(bool[,] f, int tamanho)
    {
        for (int i = 0; i < 9; i++) { f[8, i] = true; f[i, 8] = true; }
        for (int i = 0; i < 8; i++) { f[tamanho - 1 - i, 8] = true; f[8, tamanho - 1 - i] = true; }
        f[tamanho - 8, 8] = true;
    }

    static void DesenharFormato(bool[,] m, int mascara, int tamanho)
    {
        int dados = 0 << 3 | mascara;   // nível M = 00
        int resto = dados;
        for (int i = 0; i < 10; i++) resto = (resto << 1) ^ ((resto >> 9) * 0x537);
        int bits = (dados << 10 | resto) ^ 0x5412;
        for (int i = 0; i <= 5; i++) m[i, 8] = ((bits >> i) & 1) != 0;
        m[7, 8] = ((bits >> 6) & 1) != 0;
        m[8, 8] = ((bits >> 7) & 1) != 0;
        m[8, 7] = ((bits >> 8) & 1) != 0;
        for (int i = 9; i < 15; i++) m[8, 14 - i] = ((bits >> i) & 1) != 0;
        for (int i = 0; i < 8; i++) m[8, tamanho - 1 - i] = ((bits >> i) & 1) != 0;
        for (int i = 8; i < 15; i++) m[tamanho - 15 + i, 8] = ((bits >> i) & 1) != 0;
        m[tamanho - 8, 8] = true;   // módulo escuro fixo
    }

    static void DesenharDados(bool[,] m, bool[,] f, byte[] dados, int tamanho)
    {
        int i = 0;
        for (int dir = tamanho - 1; dir >= 1; dir -= 2)
        {
            if (dir == 6) dir = 5;
            for (int vert = 0; vert < tamanho; vert++)
                for (int j = 0; j < 2; j++)
                {
                    int x = dir - j;
                    bool cima = ((dir + 1) & 2) == 0;
                    int y = cima ? tamanho - 1 - vert : vert;
                    if (!f[y, x] && i < dados.Length * 8)
                    {
                        m[y, x] = ((dados[i >> 3] >> (7 - (i & 7))) & 1) != 0;
                        i++;
                    }
                }
        }
    }

    static void Mascara(bool[,] m, bool[,] f, int mascara, int tamanho)
    {
        for (int y = 0; y < tamanho; y++)
            for (int x = 0; x < tamanho; x++)
            {
                bool inv;
                switch (mascara)
                {
                    case 0: inv = (x + y) % 2 == 0; break;
                    case 1: inv = y % 2 == 0; break;
                    case 2: inv = x % 3 == 0; break;
                    case 3: inv = (x + y) % 3 == 0; break;
                    case 4: inv = (x / 3 + y / 2) % 2 == 0; break;
                    case 5: inv = x * y % 2 + x * y % 3 == 0; break;
                    case 6: inv = (x * y % 2 + x * y % 3) % 2 == 0; break;
                    default: inv = ((x + y) % 2 + x * y % 3) % 2 == 0; break;
                }
                if (inv && !f[y, x]) m[y, x] = !m[y, x];
            }
    }

    // ---------- penalidade (escolhe a máscara menos ruim) ----------
    static void HistAdd(int atual, int[] hist, int n)
    {
        if (hist[0] == 0) atual += n;   // a borda clara inicial conta como parte da primeira sequência
        for (int k = hist.Length - 1; k > 0; k--) hist[k] = hist[k - 1];
        hist[0] = atual;
    }

    static int ContaPadroes(int[] h)
    {
        int n = h[1];
        bool nucleo = n > 0 && h[2] == n && h[3] == n * 3 && h[4] == n && h[5] == n;
        return (nucleo && h[0] >= n * 4 && h[6] >= n ? 1 : 0) + (nucleo && h[6] >= n * 4 && h[0] >= n ? 1 : 0);
    }

    static int FimDaLinha(bool corAtual, int tam, int[] h, int n)
    {
        if (corAtual) { HistAdd(tam, h, n); tam = 0; }
        tam += n;   // borda clara final
        HistAdd(tam, h, n);
        return ContaPadroes(h);
    }

    static long Penalidade(bool[,] m, int n)
    {
        long r = 0;
        for (int pass = 0; pass < 2; pass++)
        {
            for (int a = 0; a < n; a++)
            {
                bool corSeq = false; int seq = 0;
                int[] hist = new int[7];
                for (int b = 0; b < n; b++)
                {
                    bool cor = pass == 0 ? m[a, b] : m[b, a];
                    if (cor == corSeq)
                    {
                        seq++;
                        if (seq == 5) r += 3; else if (seq > 5) r++;
                    }
                    else
                    {
                        HistAdd(seq, hist, n);
                        if (!corSeq) r += ContaPadroes(hist) * 40;
                        corSeq = cor; seq = 1;
                    }
                }
                r += FimDaLinha(corSeq, seq, hist, n) * 40;
            }
        }
        for (int y = 0; y < n - 1; y++)
            for (int x = 0; x < n - 1; x++)
                if (m[y, x] == m[y, x + 1] && m[y, x] == m[y + 1, x] && m[y, x] == m[y + 1, x + 1]) r += 3;
        int escuros = 0;
        for (int y = 0; y < n; y++) for (int x = 0; x < n; x++) if (m[y, x]) escuros++;
        int total = n * n;
        int k = (int)((Math.Abs(escuros * 20L - total * 10L) + total - 1) / total) - 1;
        r += k * 10L;
        return r;
    }
}
