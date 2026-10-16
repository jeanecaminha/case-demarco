"""Pipeline de absenteísmo, DSR e ações disciplinares.

Uso:
    python pipeline.py --alvo local                 # DuckDB + planilha .xlsx local
    python pipeline.py --alvo bigquery              # BigQuery + Google Sheets
    python pipeline.py --alvo bigquery --etapas extrair,transformar,testar
    python pipeline.py --alvo bigquery --etapas reverse_etl --simular

Etapas, nesta ordem:
    extrair      arquivos brutos -> camada raw
    transformar  SQL de staging, intermediate e marts
    testar       sql/99_tests; se algum falhar, para aqui
    exportar     marts em CSV (data/processed), para conferência
    reverse_etl  atualiza a planilha dos gestores sem tocar nas colunas manuais
"""
from __future__ import annotations

import argparse
import logging
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

from src.config import PASTA_SAIDA, Config
from src.extract import extrair_fontes
from src.transform import executar_modelos, executar_testes, variaveis_sql
from src.warehouse import criar_warehouse

ETAPAS = ["extrair", "transformar", "testar", "exportar", "reverse_etl"]
TABELAS_EXPORTADAS = [
    "mart_absenteismo_colaborador",
    "fct_ponto_diario",
    "mart_qualidade_dados",
    "rpt_acoes_disciplinares",
]

log = logging.getLogger("pipeline")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pipeline de absenteísmo, DSR e ações disciplinares")
    parser.add_argument("--alvo", choices=["local", "bigquery"], default="local")
    parser.add_argument("--etapas", default=",".join(ETAPAS), help="Lista separada por vírgula")
    parser.add_argument("--simular", action="store_true", help="Reverse ETL sem gravar (dry-run)")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    etapas = [e.strip() for e in args.etapas.split(",") if e.strip()]
    desconhecidas = set(etapas) - set(ETAPAS)
    if desconhecidas:
        parser.error(f"Etapas desconhecidas: {sorted(desconhecidas)}")

    config = Config()
    data_processamento = datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%Y-%m-%d %H:%M")
    wh = criar_warehouse(args.alvo, config)
    wh.preparar()
    variaveis = variaveis_sql(wh, config, data_processamento)
    log.info("Alvo=%s | Período=%s a %s | Etapas=%s", args.alvo, config.periodo_inicio, config.periodo_fim, etapas)

    if "extrair" in etapas:
        for tabela, df in extrair_fontes().items():
            wh.carregar_dataframe(df, "raw", tabela)

    if "transformar" in etapas:
        executar_modelos(wh, variaveis)

    if "testar" in etapas:
        executar_testes(wh, variaveis)

    if "exportar" in etapas:
        PASTA_SAIDA.mkdir(parents=True, exist_ok=True)
        for tabela in TABELAS_EXPORTADAS:
            df = wh.consultar(f"SELECT * FROM {variaveis['marts']}.{tabela}")
            destino = PASTA_SAIDA / f"{tabela}.csv"
            df.to_csv(destino, index=False, encoding="utf-8-sig")
            log.info("Exportado %s (%d linhas)", destino.name, len(df))

    if "reverse_etl" in etapas:
        from src.reverse_etl import executar_reverse_etl

        recomendacoes = wh.consultar(f"SELECT * FROM {variaveis['marts']}.rpt_acoes_disciplinares")
        executar_reverse_etl(args.alvo, config, recomendacoes, data_processamento, simular=args.simular)

    log.info("Pipeline concluído.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
