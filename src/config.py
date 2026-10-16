"""Parâmetros do pipeline.

Tudo pode ser sobrescrito por variável de ambiente ou pelo arquivo .env,
assim o mesmo código roda local e na nuvem.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

RAIZ_PROJETO = Path(__file__).resolve().parent.parent
PASTA_SQL = RAIZ_PROJETO / "sql"
PASTA_DADOS_BRUTOS = RAIZ_PROJETO / "data" / "raw"
PASTA_SAIDA = RAIZ_PROJETO / "data" / "processed"
PASTA_BACKUP = RAIZ_PROJETO / "data" / "backups"


def _carregar_dotenv(caminho: Path) -> None:
    # Leitor simples de .env (CHAVE=valor), para não depender de mais uma lib.
    # O que já estiver definido no ambiente tem prioridade.
    if not caminho.exists():
        return
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        os.environ.setdefault(chave.strip(), valor.strip().strip('"').strip("'"))


_carregar_dotenv(RAIZ_PROJETO / ".env")


# tabela na raw -> prefixo do arquivo. Aceita .csv (formato citado no briefing)
# ou .xlsx (formato que recebemos).
FONTES_BRUTAS = {
    "base_colaboradores": "base_colaboradores",
    "escalas": "escalas",
    "espelho_ponto": "espelho_ponto",
}

# Colunas da planilha dos gestores. O pipeline só escreve nas CALCULADAS;
# as MANUAIS são dos gestores e nunca são tocadas.
COLUNA_CHAVE_PLANILHA = "ID_Colaborador"
COLUNAS_IDENTIFICACAO = ["ID_Colaborador", "Nome", "Departamento", "Gestor"]
COLUNAS_CALCULADAS = [
    "Total_Faltas_Injustificadas",
    "Total_DSR_Perdido",
    "Acao_Disciplinar_Recomendada",
    "Data_Ultimo_Processamento",
]
COLUNAS_MANUAIS = ["Data_Conversa_1on1", "Advertencia_Aplicada_SN", "Observacoes_Gestor"]


@dataclass(frozen=True)
class Config:
    # período de apuração do case: jun a ago/2025
    periodo_inicio: str = field(default_factory=lambda: os.getenv("PERIODO_INICIO", "2025-06-01"))
    periodo_fim: str = field(default_factory=lambda: os.getenv("PERIODO_FIM", "2025-08-31"))

    # CLT art. 58 §1º: até 10 min por dia não se desconta
    tolerancia_minutos: int = field(default_factory=lambda: int(os.getenv("TOLERANCIA_MINUTOS", "10")))
    # salário mínimo 2025; abaixo disso o salário do cadastro é considerado inválido
    salario_minimo: float = field(default_factory=lambda: float(os.getenv("SALARIO_MINIMO", "1518")))

    # BigQuery
    gcp_project: str | None = field(default_factory=lambda: os.getenv("GCP_PROJECT_ID"))
    bq_location: str = field(default_factory=lambda: os.getenv("BQ_LOCATION", "US"))
    dataset_raw: str = field(default_factory=lambda: os.getenv("BQ_DATASET_RAW", "rh_raw"))
    dataset_staging: str = field(default_factory=lambda: os.getenv("BQ_DATASET_STAGING", "rh_staging"))
    dataset_marts: str = field(default_factory=lambda: os.getenv("BQ_DATASET_MARTS", "rh_marts"))

    # Google Sheets
    gsheets_spreadsheet_id: str | None = field(default_factory=lambda: os.getenv("GSHEETS_SPREADSHEET_ID"))
    gsheets_worksheet: str | None = field(default_factory=lambda: os.getenv("GSHEETS_WORKSHEET") or None)

    # modo local (DuckDB + planilha .xlsx)
    duckdb_path: Path = field(
        default_factory=lambda: Path(os.getenv("DUCKDB_PATH", str(RAIZ_PROJETO / "data" / "warehouse.duckdb")))
    )
    planilha_gestores_local: Path = field(
        default_factory=lambda: Path(
            os.getenv("PLANILHA_GESTORES_LOCAL", str(PASTA_DADOS_BRUTOS / "template_acoes_disciplinares.xlsx"))
        )
    )

    @property
    def datasets(self) -> dict[str, str]:
        return {"raw": self.dataset_raw, "staging": self.dataset_staging, "marts": self.dataset_marts}
