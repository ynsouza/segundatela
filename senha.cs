// Desenho e impressão do cupom da senha do sorteio (impressora térmica do caixa).
// Escrito em C# 5 para compilar no Windows PowerShell 5.1 (Add-Type -ReferencedAssemblies System.Drawing).
// As medidas são em centésimos de polegada (padrão da impressão do Windows): 100 = 1 polegada.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Printing;

public class DadosSenha
{
    public string Loja = "PADARIA SILMAR";
    public string Titulo = "SORTEIO DA CESTA DE NATAL";
    public string Codigo = "";       // sem hífen, ex.: K7M29QXP
    public string Link = "";         // o que vai dentro do QR Code
    public string LinkCurto = "";    // o que a pessoa digita no navegador
    public string Prazo = "";        // "Cadastre até 20/12 às 23:00 · Sorteio em 22/12"
    public string Rodape = "";       // "Venda nº 1234 · 22/11/2026 14:35"
    public string Aviso = "Guarde este cupom!";
    public bool[,] Qr = null;
}

public static class SenhaImpressa
{
    static string Formata(string c)
    {
        return c.Length > 4 ? c.Substring(0, 4) + "-" + c.Substring(4) : c;
    }

    static void Estrela(Graphics g, float cx, float cy, float r)
    {
        PointF[] p = new PointF[10];
        for (int i = 0; i < 10; i++)
        {
            double a = -Math.PI / 2 + i * Math.PI / 5;
            float rr = (i % 2 == 0) ? r : r * 0.42f;
            p[i] = new PointF(cx + (float)(Math.Cos(a) * rr), cy + (float)(Math.Sin(a) * rr));
        }
        g.FillPolygon(Brushes.Black, p);
    }

    // Texto centralizado que quebra linha dentro da largura; devolve a altura usada.
    static float Texto(Graphics g, string t, Font f, float y, float largura)
    {
        if (string.IsNullOrEmpty(t)) return 0;
        using (StringFormat sf = new StringFormat())
        {
            sf.Alignment = StringAlignment.Center;
            SizeF tam = g.MeasureString(t, f, (int)largura, sf);
            g.DrawString(t, f, Brushes.Black, new RectangleF(0, y, largura, tam.Height + 2), sf);
            return tam.Height;
        }
    }

    // Desenha o cupom a partir de y = 0 e devolve a altura total usada.
    public static float Desenhar(Graphics g, float largura, DadosSenha d)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        float y = 6;

        for (int i = -2; i <= 2; i++) Estrela(g, largura / 2 + i * 15, y + 7, i == 0 ? 8 : 6);
        y += 20;
        using (Font f = new Font("Georgia", 15, FontStyle.Bold)) y += Texto(g, d.Loja, f, y, largura) + 2;
        using (Pen p = new Pen(Color.Black, 1.5f)) g.DrawLine(p, largura * 0.15f, y, largura * 0.85f, y);
        y += 7;
        using (Font f = new Font("Arial", 10.5f, FontStyle.Bold)) y += Texto(g, d.Titulo, f, y, largura) + 6;

        using (Font f = new Font("Arial", 8.5f, FontStyle.Bold)) y += Texto(g, "SUA SENHA", f, y, largura);
        // caixa da senha
        string cod = Formata(d.Codigo);
        using (Font f = new Font("Consolas", 24, FontStyle.Bold))
        {
            SizeF tam = g.MeasureString(cod, f);
            float bw = Math.Min(largura - 8, tam.Width + 18), bh = tam.Height + 8;
            float bx = (largura - bw) / 2;
            using (Pen p = new Pen(Color.Black, 2.5f)) g.DrawRectangle(p, bx, y + 2, bw, bh);
            g.DrawString(cod, f, Brushes.Black, (largura - tam.Width) / 2, y + 6);
            y += bh + 12;
        }

        // QR Code (módulos inteiros, sem suavização, para ficar nítido na térmica)
        if (d.Qr != null)
        {
            int n = d.Qr.GetLength(0);
            float lado = Math.Min(largura - 20, 150);
            float m = (float)Math.Floor(lado / n * 8) / 8;   // múltiplo de 1/8 de centésimo: bordas regulares
            if (m < 1.2f) m = lado / n;
            float tot = m * n, x0 = (largura - tot) / 2;
            SmoothingMode antes = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.None;
            g.FillRectangle(Brushes.White, x0 - 6, y - 2, tot + 12, tot + 12);
            for (int r = 0; r < n; r++)
                for (int c = 0; c < n; c++)
                    if (d.Qr[r, c]) g.FillRectangle(Brushes.Black, x0 + c * m, y + 4 + r * m, m + 0.35f, m + 0.35f);
            g.SmoothingMode = antes;
            y += tot + 14;
            using (Font f = new Font("Arial", 8.5f)) y += Texto(g, "Aponte a câmera do celular para o QR Code", f, y, largura) + 2;
            using (Font f = new Font("Arial", 8.5f)) y += Texto(g, "ou acesse o endereço abaixo e digite a senha:", f, y, largura) + 2;
        }
        else
        {
            using (Font f = new Font("Arial", 8.5f)) y += Texto(g, "Para participar, acesse o endereço abaixo e digite a senha:", f, y, largura) + 2;
        }
        using (Font f = new Font("Arial", 10.5f, FontStyle.Bold)) y += Texto(g, d.LinkCurto, f, y, largura) + 6;

        if (!string.IsNullOrEmpty(d.Prazo))
            using (Font f = new Font("Arial", 8.5f)) y += Texto(g, d.Prazo, f, y, largura) + 4;
        using (Pen p = new Pen(Color.Black, 1f)) { p.DashStyle = DashStyle.Dash; g.DrawLine(p, 6, y, largura - 6, y); }
        y += 5;
        using (Font f = new Font("Arial", 7.5f)) y += Texto(g, d.Rodape, f, y, largura) + 1;
        using (Font f = new Font("Arial", 8.5f, FontStyle.Bold)) y += Texto(g, d.Aviso, f, y, largura);
        return y + 40;   // folga para o corte
    }

    // Manda para a impressora. impressora vazia = padrão do Windows. larguraMm = área útil do papel.
    public static void Imprimir(string impressora, float larguraMm, float alturaMm, DadosSenha d)
    {
        PrintDocument pd = new PrintDocument();
        if (!string.IsNullOrEmpty(impressora)) pd.PrinterSettings.PrinterName = impressora;
        if (!pd.PrinterSettings.IsValid) throw new InvalidOperationException("Impressora não encontrada: " + impressora);
        pd.DocumentName = "Senha do sorteio " + d.Codigo;
        float largura = larguraMm / 25.4f * 100f;
        if (alturaMm > 0)
        {
            try { pd.DefaultPageSettings.PaperSize = new PaperSize("Senha", (int)Math.Round(largura + 20), (int)Math.Round(alturaMm / 25.4f * 100f)); }
            catch (Exception) { }
        }
        pd.PrintPage += delegate(object sender, PrintPageEventArgs e)
        {
            float util = largura;
            RectangleF area = e.PageSettings.PrintableArea;
            if (area.Width > 50 && area.Width < util) util = area.Width;
            Desenhar(e.Graphics, util, d);
            e.HasMorePages = false;
        };
        pd.Print();
    }
}
