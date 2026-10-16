"""Leitura dos arquivos brutos para a camada raw.

Tudo entra como texto. Salário "A combinar", data em dd/mm/aaaa ou hora negativa
não podem derrubar a carga; a limpeza e a tipagem ficam no SQL de staging.

A exceção é o encoding quebrado ("OperaÃ§Ãµes"), que é problema de leitura do
arquivo e não de conteúdo, então é resolvido aqui. As linhas reparadas ficam
marcadas em _colunas_encoding_reparado.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from .config import FONTES_BRUTAS, PASTA_DADOS_BRUTOS

log = logging.getLogger(__name__)

EXTENSOES_ACEITAS = (".csv", ".xlsx")


def localizar_arquivo(prefixo: str, pasta: Path = PASTA_DADOS_BRUTOS) -> Path:
    # se houver mais de um arquivo com o mesmo prefixo, usa o mais recente
    candidatos = [
        p for p in pasta.iterdir()
        if p.is_file() and p.name.lower().startswith(prefixo) and p.suffix.lower() in EXTENSOES_ACEITAS
    ]
    if not candidatos:
        raise FileNotFoundError(f"Nenhum arquivo '{prefixo}*' (.csv/.xlsx) encontrado em {pasta}")
    return max(candidatos, key=lambda p: p.stat().st_mtime)


def _ler_csv(caminho: Path) -> pd.DataFrame:
    # CSV de sistema legado: o encoding e o separador variam
    for encoding in ("utf-8-sig", "latin-1"):
        try:
            return pd.read_csv(caminho, dtype=str, sep=None, engine="python", encoding=encoding)
        except UnicodeDecodeError:
            continue
    raise ValueError(f"Não foi possível decodificar {caminho}")


MARCADORES_MOJIBAKE = ("Ã", "Â")


def reparar_mojibake(valor: object) -> object:
    """Desfaz texto UTF-8 que foi lido como Latin-1 ("OperaÃ§Ãµes" -> "Operações").

    Se a conversão não fechar, devolve o valor original. O caractere U+FFFD
    não tem conserto: a informação já se perdeu na origem.
    """
    if not isinstance(valor, str) or not any(m in valor for m in MARCADORES_MOJIBAKE):
        return valor
    for encoding in ("latin-1", "cp1252"):
        try:
            return valor.encode(encoding).decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
    return valor


def _reparar_encoding(df: pd.DataFrame) -> pd.DataFrame:
    reparado = df.apply(lambda col: col.map(reparar_mojibake))
    alterado = (reparado != df) & df.notna()
    df_out = reparado.copy()
    # guarda quais colunas de cada linha foram consertadas (vai para o mart de qualidade)
    df_out["_colunas_encoding_reparado"] = [
        ",".join(df.columns[linha]) or None for linha in alterado.to_numpy()
    ]
    return df_out


def ler_arquivo_bruto(caminho: Path) -> pd.DataFrame:
    if caminho.suffix.lower() == ".csv":
        df = _ler_csv(caminho)
    else:
        df = pd.read_excel(caminho, dtype=str)

    df.columns = [str(c).strip().lower() for c in df.columns]
    df = df.dropna(how="all")
    # string vazia e NaN viram NULL do mesmo jeito no banco
    df = df.apply(lambda col: col.str.strip()).replace({"": None})
    df = df.astype(object).where(df.notna(), None)
    df = _reparar_encoding(df)
    qtd_reparadas = df["_colunas_encoding_reparado"].notna().sum()
    if qtd_reparadas:
        log.warning("%s: encoding reparado em %d linha(s)", caminho.name, qtd_reparadas)

    # origem de cada linha, para conseguir voltar do painel até o arquivo
    df["_arquivo_origem"] = caminho.name
    df["_linha_origem"] = [str(i) for i in range(2, len(df) + 2)]  # linha 1 é o cabeçalho
    df["_carregado_em"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return df


def extrair_fontes(pasta: Path = PASTA_DADOS_BRUTOS) -> dict[str, pd.DataFrame]:
    tabelas = {}
    for tabela, prefixo in FONTES_BRUTAS.items():
        caminho = localizar_arquivo(prefixo, pasta)
        df = ler_arquivo_bruto(caminho)
        log.info("Extraído %s: %d linhas de %s", tabela, len(df), caminho.name)
        tabelas[tabela] = df
    return tabelas
