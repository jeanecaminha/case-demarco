"""Conexão com o banco: BigQuery (produção) ou DuckDB (local).

O SQL é escrito uma vez só, no dialeto do BigQuery. No modo local o sqlglot
traduz para DuckDB, então dá para testar tudo sem nuvem e as regras de negócio
continuam num lugar só.
"""
from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Protocol

import pandas as pd

from .config import Config

log = logging.getLogger(__name__)


class Warehouse(Protocol):
    def preparar(self) -> None: ...
    def referencia(self, camada: str) -> str: ...
    def carregar_dataframe(self, df: pd.DataFrame, camada: str, tabela: str) -> None: ...
    def executar(self, sql: str) -> None: ...
    def consultar(self, sql: str) -> pd.DataFrame: ...


def renderizar_sql(sql: str, variaveis: dict[str, str]) -> str:
    # troca {{ nome }} pelo valor; marcador sem valor é erro, não string vazia

    def substituir(m: re.Match) -> str:
        nome = m.group(1)
        if nome not in variaveis:
            raise KeyError(f"Variável de template não definida: {nome}")
        return str(variaveis[nome])

    return re.sub(r"\{\{\s*(\w+)\s*\}\}", substituir, sql)


def dividir_statements(sql: str) -> list[str]:
    # quebra o arquivo nos ';' de fim de linha (nenhum .sql do projeto tem ';' dentro de texto)
    sem_comentarios = re.sub(r"--[^\n]*", "", sql)
    return [s.strip() for s in re.split(r";\s*(?:\n|$)", sem_comentarios) if s.strip()]


class BigQueryWarehouse:
    def __init__(self, config: Config):
        from google.cloud import bigquery

        if not config.gcp_project:
            raise ValueError("Defina GCP_PROJECT_ID (variável de ambiente ou .env) para usar o BigQuery.")
        self._bq = bigquery
        self.config = config
        self.client = bigquery.Client(project=config.gcp_project, location=config.bq_location)

    def preparar(self) -> None:
        for dataset in self.config.datasets.values():
            ds = self._bq.Dataset(f"{self.config.gcp_project}.{dataset}")
            ds.location = self.config.bq_location
            self.client.create_dataset(ds, exists_ok=True)

    def referencia(self, camada: str) -> str:
        return f"`{self.config.gcp_project}`.{self.config.datasets[camada]}"

    def carregar_dataframe(self, df: pd.DataFrame, camada: str, tabela: str) -> None:
        destino = f"{self.config.gcp_project}.{self.config.datasets[camada]}.{tabela}"
        job_config = self._bq.LoadJobConfig(
            write_disposition=self._bq.WriteDisposition.WRITE_TRUNCATE,
            schema=[self._bq.SchemaField(c, "STRING") for c in df.columns],
        )
        self.client.load_table_from_dataframe(df, destino, job_config=job_config).result()
        log.info("Carregado %s (%d linhas)", destino, len(df))

    def executar(self, sql: str) -> None:
        self.client.query(sql).result()

    def consultar(self, sql: str) -> pd.DataFrame:
        linhas = [dict(r) for r in self.client.query(sql).result()]
        return pd.DataFrame(linhas)


class DuckDBWarehouse:
    def __init__(self, config: Config):
        import duckdb
        import sqlglot

        self._sqlglot = sqlglot
        self.config = config
        Path(config.duckdb_path).parent.mkdir(parents=True, exist_ok=True)
        self.con = duckdb.connect(str(config.duckdb_path))

    def preparar(self) -> None:
        for dataset in self.config.datasets.values():
            self.con.execute(f"CREATE SCHEMA IF NOT EXISTS {dataset}")

    def referencia(self, camada: str) -> str:
        return self.config.datasets[camada]

    def carregar_dataframe(self, df: pd.DataFrame, camada: str, tabela: str) -> None:
        destino = f"{self.config.datasets[camada]}.{tabela}"
        self.con.register("_df_carga", df.astype(object))
        self.con.execute(f"CREATE OR REPLACE TABLE {destino} AS SELECT * FROM _df_carga")
        self.con.unregister("_df_carga")
        log.info("Carregado %s (%d linhas)", destino, len(df))

    def _transpilar(self, sql: str) -> str:
        return ";\n".join(self._sqlglot.transpile(sql, read="bigquery", write="duckdb"))

    def executar(self, sql: str) -> None:
        self.con.execute(self._transpilar(sql))

    def consultar(self, sql: str) -> pd.DataFrame:
        return self.con.execute(self._transpilar(sql)).df()


def criar_warehouse(alvo: str, config: Config) -> Warehouse:
    if alvo == "bigquery":
        return BigQueryWarehouse(config)
    if alvo == "local":
        return DuckDBWarehouse(config)
    raise ValueError(f"Alvo desconhecido: {alvo}")
