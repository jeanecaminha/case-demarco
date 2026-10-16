"""Roda os SQL de transformação e os testes de dados.

Os arquivos de sql/ rodam em ordem de pasta e de nome (01_staging, 02_intermediate,
03_marts). Cada teste em sql/99_tests procura um erro: se voltar alguma linha,
o pipeline para antes de mexer na planilha dos gestores.
"""
from __future__ import annotations

import logging
from pathlib import Path

from .config import PASTA_SQL, Config
from .warehouse import Warehouse, dividir_statements, renderizar_sql

log = logging.getLogger(__name__)

PASTA_TESTES = "99_tests"


def variaveis_sql(wh: Warehouse, config: Config, data_processamento: str) -> dict[str, str]:
    return {
        "raw": wh.referencia("raw"),
        "staging": wh.referencia("staging"),
        "marts": wh.referencia("marts"),
        "periodo_inicio": config.periodo_inicio,
        "periodo_fim": config.periodo_fim,
        "tolerancia_minutos": str(config.tolerancia_minutos),
        "salario_minimo": str(config.salario_minimo),
        "data_processamento": data_processamento,
    }


def _arquivos_modelo() -> list[Path]:
    return sorted(p for p in PASTA_SQL.glob("*/*.sql") if p.parent.name != PASTA_TESTES)


def _arquivos_teste() -> list[Path]:
    return sorted((PASTA_SQL / PASTA_TESTES).glob("*.sql"))


def executar_modelos(wh: Warehouse, variaveis: dict[str, str]) -> None:
    for arquivo in _arquivos_modelo():
        sql = renderizar_sql(arquivo.read_text(encoding="utf-8"), variaveis)
        for statement in dividir_statements(sql):
            wh.executar(statement)
        log.info("Modelo executado: %s", arquivo.relative_to(PASTA_SQL))


class FalhaQualidadeDados(Exception):
    pass


def executar_testes(wh: Warehouse, variaveis: dict[str, str]) -> None:
    # roda todos antes de falhar, para o log mostrar todos os problemas de uma vez
    falhas = []
    for arquivo in _arquivos_teste():
        sql = renderizar_sql(arquivo.read_text(encoding="utf-8"), variaveis)
        violacoes = wh.consultar(dividir_statements(sql)[0])
        if len(violacoes):
            falhas.append(f"{arquivo.name}: {len(violacoes)} violação(ões)\n{violacoes.head(10).to_string()}")
            log.error("Teste FALHOU: %s", arquivo.name)
        else:
            log.info("Teste OK: %s", arquivo.name)
    if falhas:
        raise FalhaQualidadeDados("\n\n".join(falhas))
