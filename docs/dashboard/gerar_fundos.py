"""Gera os fundos de design das páginas do dashboard (Looker Studio).

Técnica: o layout (cabeçalho, cartões, títulos, legendas fixas) é desenhado em
HTML/CSS e renderizado como PNG no tamanho exato do canvas. No Looker Studio, a
imagem fica atrás de tudo e os gráficos, com fundo transparente, são posicionados
sobre os cartões nas mesmas coordenadas definidas aqui.

Uso:  python docs/dashboard/gerar_fundos.py
Saída: docs/dashboard/fundo_<pagina>.png (renderizado em 2x para telas retina)
"""
from __future__ import annotations

import subprocess
from pathlib import Path

PASTA = Path(__file__).resolve().parent
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
LARGURA = 1440

# Paleta (dataviz: 3 primeiras cores categóricas validadas para daltonismo, todos os pares)
COR = {
    "plano": "#F3F4F6", "cartao": "#FFFFFF", "navy": "#0F1B2D", "tinta": "#0F1B2D",
    "tinta2": "#4B5563", "muda": "#6B7280", "borda": "rgba(15,27,45,0.08)",
    "faltas": "#2a78d6", "atrasos": "#1baf7a", "dsr": "#eb6834",
    "critico": "#d03b3b", "serio": "#ec835a", "alerta": "#fab219", "neutro": "#9CA3AF",
}

CSS = f"""
@import url('https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700;900&display=swap');
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ width: {LARGURA}px; background: {COR['plano']}; font-family: 'Roboto', sans-serif;  /* mesma fonte do tema do Data Studio */
       color: {COR['tinta']}; position: relative; -webkit-font-smoothing: antialiased; }}
.header {{ position: absolute; left: 0; top: 0; width: {LARGURA}px; height: 112px; background: {COR['navy']};
          overflow: hidden; }}
.header::before {{ content: ''; position: absolute; inset: 0;
   background-image: linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px),
                     linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px);
   background-size: 28px 28px; }}
.header::after {{ content: ''; position: absolute; right: -120px; top: -160px; width: 520px; height: 420px;
   background: radial-gradient(closest-side, rgba(42,120,214,0.45), transparent); }}
.header .barra {{ position: absolute; left: 0; bottom: 0; height: 3px; width: 100%;
   background: linear-gradient(90deg, {COR['faltas']} 0 33%, {COR['atrasos']} 33% 66%, {COR['dsr']} 66% 100%); }}
.eyebrow {{ position: absolute; left: 40px; top: 24px; font-size: 11px; font-weight: 600; letter-spacing: .14em;
           color: #8FB8EE; text-transform: uppercase; z-index: 1; }}
.titulo {{ position: absolute; left: 40px; top: 42px; font-size: 28px; font-weight: 800; color: #fff;
          letter-spacing: -0.02em; z-index: 1; }}
.subtitulo {{ position: absolute; left: 40px; top: 80px; font-size: 13px; color: #AEB8C6; z-index: 1; }}
.periodo {{ position: absolute; right: 40px; top: 24px; font-size: 11px; font-weight: 600; letter-spacing: .08em;
           color: #DCE6F3; background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.14);
           padding: 5px 10px; border-radius: 999px; z-index: 1; text-transform: uppercase; }}
.card {{ position: absolute; background: {COR['cartao']}; border-radius: 16px; border: 1px solid {COR['borda']};
        box-shadow: 0 1px 2px rgba(15,27,45,0.04), 0 8px 24px rgba(15,27,45,0.05); }}
.card.hero {{ background: {COR['navy']}; border-color: {COR['navy']}; }}
.card h3 {{ position: absolute; left: 24px; top: 20px; font-size: 15px; font-weight: 700; letter-spacing: -0.01em; }}
.card p.sub {{ position: absolute; left: 24px; top: 42px; font-size: 12px; color: {COR['muda']}; }}
.kpi .rotulo {{ position: absolute; left: 20px; top: 18px; font-size: 11px; font-weight: 700; letter-spacing: .1em;
               text-transform: uppercase; color: {COR['muda']}; display: flex; align-items: center; gap: 8px; }}
.kpi.hero .rotulo {{ color: #8FB8EE; }}
.kpi .legenda {{ position: absolute; left: 20px; bottom: 16px; font-size: 12px; color: {COR['muda']}; }}
.kpi.hero .legenda {{ color: #AEB8C6; }}
.ponto {{ width: 8px; height: 8px; border-radius: 50%; display: inline-block; }}
.acento {{ position: absolute; left: 0; top: 16px; bottom: 16px; width: 4px; border-radius: 0 4px 4px 0; }}
.linha-comp {{ position: absolute; left: 24px; right: 24px; height: 72px; border-top: 1px solid {COR['borda']};
              display: flex; align-items: center; gap: 10px; font-size: 13px; color: {COR['tinta2']}; font-weight: 500; }}
.linha-comp .sw {{ width: 12px; height: 12px; border-radius: 3px; }}
.nota {{ position: absolute; font-size: 12px; color: {COR['muda']}; }}
"""


def header(titulo: str, subtitulo: str) -> str:
    return f"""
<div class="header">
  <div class="eyebrow">Gente &amp; Gestão · Controle de absenteísmo</div>
  <div class="titulo">{titulo}</div>
  <div class="subtitulo">{subtitulo}</div>
  <div class="periodo">Jun – Ago / 2025</div>
  <div class="barra"></div>
</div>"""


def card(x, y, w, h, titulo="", sub="", extra="", classe="") -> str:
    t = f"<h3>{titulo}</h3>" if titulo else ""
    s = f'<p class="sub">{sub}</p>' if sub else ""
    return f'<div class="card {classe}" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">{t}{s}{extra}</div>'


def kpi(x, y, w, rotulo, legenda, cor=None, hero=False, acento=None) -> str:
    ponto = f'<span class="ponto" style="background:{cor}"></span>' if cor else ""
    barra = f'<div class="acento" style="background:{acento}"></div>' if acento else ""
    classe = "kpi hero" if hero else "kpi"
    extra = f'{barra}<div class="rotulo">{ponto}{rotulo}</div><div class="legenda">{legenda}</div>'
    return card(x, y, w, 132, extra=extra, classe=classe)


def pagina(altura: int, corpo: str) -> str:
    return (f'<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><style>{CSS}'
            f'body{{height:{altura}px}}</style></head><body>{corpo}</body></html>')


def kpis(rotulos, y=136):
    """Distribui n cartões KPI entre x=40 e x=1400 com 20px de espaçamento."""
    n = len(rotulos)
    w = (1360 - 20 * (n - 1)) // n
    return "".join(kpi(40 + i * (w + 20), y, w, **r) for i, r in enumerate(rotulos))


PAGINAS = {
    "1_visao_executiva": (1160, header("Visão executiva", "Quanto o absenteísmo custa, onde se concentra e como evolui")
        + kpis([
            dict(rotulo="Desconto total", legenda="Faltas + atrasos + DSRs perdidos", hero=True),
            dict(rotulo="Faltas injustificadas", legenda="Sem presença e sem abono", cor=COR["faltas"]),
            dict(rotulo="DSRs perdidos", legenda="Descanso remunerado descontado", cor=COR["dsr"]),
            dict(rotulo="Com ação disciplinar", legenda="Colaboradores com recomendação ativa", cor=COR["critico"]),
            dict(rotulo="Taxa de absenteísmo", legenda="Horas injustificadas ÷ horas previstas", cor=COR["neutro"]),
        ])
        + card(40, 292, 832, 400, "Onde está o custo", "Desconto por departamento, decomposto por componente")
        + card(896, 292, 504, 400, "Custo por gestor", "Gestor responsável pela condução das ações")
        + card(40, 716, 960, 380, "Evolução semanal", "Desconto por semana (segunda a domingo), por componente")
        + card(1024, 716, 376, 380, "Composição do desconto", "Quanto cada componente pesa no total",
               extra=f"""
               <div class="linha-comp" style="top:84px"><span class="sw" style="background:{COR['faltas']}"></span>Faltas integrais</div>
               <div class="linha-comp" style="top:156px"><span class="sw" style="background:{COR['atrasos']}"></span>Atrasos e saídas antecipadas</div>
               <div class="linha-comp" style="top:228px"><span class="sw" style="background:{COR['dsr']}"></span>DSRs perdidos</div>
               <div class="nota" style="left:24px;right:24px;top:316px;line-height:1.5">Cada semana com falta injustificada
               também perde o descanso semanal remunerado (DSR).</div>""")),

    "2_padrao_emenda": (1160, header("Padrão de emenda de fim de semana", "As faltas se concentram nos dias colados ao descanso?")
        + kpis([
            dict(rotulo="Faltas em seg. ou sex.", legenda="Participação no total de faltas injustificadas", hero=True),
            dict(rotulo="Faltas na segunda-feira", legenda="Dia seguinte ao descanso semanal", cor=COR["faltas"]),
            dict(rotulo="Faltas na sexta-feira", legenda="Dia anterior ao fim de semana", cor=COR["faltas"]),
            dict(rotulo="Faltas coladas à folga", legenda="Dia útil vizinho ao descanso da própria escala", cor=COR["dsr"]),
        ])
        + card(40, 292, 660, 400, "Faltas por dia da semana", "Faltas injustificadas no período")
        + card(724, 292, 676, 400, "Departamento × dia da semana", "Onde e quando as faltas se concentram")
        + card(40, 716, 832, 380, "Recorrência semana a semana", "Cada célula é uma semana × dia; quanto mais escuro, mais faltas")
        + card(896, 716, 504, 380, "Quem mais emenda", "Colaboradores com faltas em segunda ou sexta")),

    "3_acoes_disciplinares": (1160, header("Ações disciplinares", "Recomendação da Política de Consequências para cada colaborador")
        + kpis([
            dict(rotulo="Suspensão (1 a 3 dias)", legenda="4+ faltas ou 2+ DSRs perdidos seguidos", cor=COR["critico"], acento=COR["critico"]),
            dict(rotulo="Advertência escrita", legenda="2 a 3 faltas, sem DSRs consecutivos", cor=COR["serio"], acento=COR["serio"]),
            dict(rotulo="Alinhamento em 1-on-1", legenda="1 falta injustificada", cor=COR["alerta"], acento=COR["alerta"]),
            dict(rotulo="Sem ação requerida", legenda="Nenhuma falta injustificada", cor=COR["neutro"], acento=COR["neutro"]),
        ])
        + card(40, 292, 1360, 788, "Recomendações por colaborador",
               "Ordenado por gravidade e custo  ·  O desconto inclui atrasos acima de 10 min  ·  ⚠ Estimado: cálculo com salário ou escala estimados")),

    "4_qualidade_dados": (1160, header("Qualidade dos dados", "Ruídos encontrados nas fontes e como cada um foi tratado")
        + kpis([
            dict(rotulo="Ocorrências tratadas", legenda="Identificadas e tratadas na ingestão", hero=True),
            dict(rotulo="Severidade alta", legenda="Impactam o custo ou a ação disciplinar", cor=COR["critico"], acento=COR["critico"]),
            dict(rotulo="Severidade média", legenda="Tratadas por regra documentada", cor=COR["alerta"], acento=COR["alerta"]),
            dict(rotulo="Informativa", legenda="Padronização sem impacto no resultado", cor=COR["neutro"], acento=COR["neutro"]),
        ])
        + card(40, 292, 520, 788, "Ocorrências por tipo", "Quantidade, colorida por severidade")
        + card(584, 292, 816, 788, "Detalhe das ocorrências", "Valor original encontrado e tratamento aplicado")),
}


def main() -> None:
    for nome, (altura, corpo) in PAGINAS.items():
        html = PASTA / f"fundo_{nome}.html"
        png = PASTA / f"fundo_{nome}.png"
        html.write_text(pagina(altura, corpo), encoding="utf-8")
        subprocess.run([
            CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=2", f"--window-size={LARGURA},{altura}",
            "--virtual-time-budget=4000", f"--screenshot={png}", html.as_uri(),
        ], check=True, capture_output=True)
        print("gerado", png.name)


if __name__ == "__main__":
    main()
