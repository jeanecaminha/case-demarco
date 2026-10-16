"""Testes da lógica de Reverse ETL: o histórico manual dos gestores nunca é tocado."""
import pandas as pd
import pytest

from src.reverse_etl import (
    fotografia_colunas_manuais,
    planejar_atualizacao,
    verificar_preservacao,
)
from src.extract import reparar_mojibake

CABECALHO = [
    "ID_Colaborador", "Nome", "Departamento", "Gestor",
    "Total_Faltas_Injustificadas", "Total_DSR_Perdido", "Acao_Disciplinar_Recomendada",
    "Data_Ultimo_Processamento", "Data_Conversa_1on1", "Advertencia_Aplicada_SN", "Observacoes_Gestor",
]
LINHAS = [
    ["EMP_001", "Ana", "Ops", "EMP_008", None, None, None, None, None, None, None],
    ["EMP_002", "Rafael", "Ops", "EMP_008", 9, 9, "valor antigo", None, "2025-06-10", "S", "Reincidente"],
    ["EMP_099", "Desligado", "Ops", "EMP_008", None, None, None, None, "2025-01-01", "N", "Histórico antigo"],
]
RECOMENDACOES = pd.DataFrame([
    {"ID_Colaborador": "EMP_001", "Nome": "Ana", "Departamento": "Ops", "Gestor": "EMP_008",
     "Total_Faltas_Injustificadas": 0, "Total_DSR_Perdido": 0, "Acao_Disciplinar_Recomendada": "Sem ação requerida"},
    {"ID_Colaborador": "emp_002 ", "Nome": "Rafael", "Departamento": "Ops", "Gestor": "EMP_008",
     "Total_Faltas_Injustificadas": 4, "Total_DSR_Perdido": 4,
     "Acao_Disciplinar_Recomendada": "Suspensão Disciplinar (1 a 3 dias)"},
    {"ID_Colaborador": "EMP_041", "Nome": "Novo", "Departamento": "TI", "Gestor": None,
     "Total_Faltas_Injustificadas": 1, "Total_DSR_Perdido": 1, "Acao_Disciplinar_Recomendada": "Alinhamento em 1-on-1"},
])


def _aplicar_em_memoria(linhas, plano):
    resultado = [list(l) for l in linhas]
    for a in plano.atualizacoes:
        resultado[a.linha - 2][a.coluna - 1] = a.valor
    return resultado + plano.novas_linhas


def test_escreve_somente_colunas_calculadas():
    plano = planejar_atualizacao(CABECALHO, LINHAS, RECOMENDACOES, "2025-09-01 06:00")
    colunas_escritas = {a.nome_coluna for a in plano.atualizacoes}
    assert colunas_escritas == {
        "Total_Faltas_Injustificadas", "Total_DSR_Perdido",
        "Acao_Disciplinar_Recomendada", "Data_Ultimo_Processamento",
    }


def test_colunas_manuais_preservadas_e_valores_corretos():
    plano = planejar_atualizacao(CABECALHO, LINHAS, RECOMENDACOES, "2025-09-01 06:00")
    depois = _aplicar_em_memoria(LINHAS, plano)
    verificar_preservacao(fotografia_colunas_manuais(CABECALHO, LINHAS), fotografia_colunas_manuais(CABECALHO, depois))
    assert depois[1][4:8] == [4, 4, "Suspensão Disciplinar (1 a 3 dias)", "2025-09-01 06:00"]
    assert depois[1][8:] == ["2025-06-10", "S", "Reincidente"]


def test_linha_sem_correspondencia_fica_intacta():
    plano = planejar_atualizacao(CABECALHO, LINHAS, RECOMENDACOES, "2025-09-01 06:00")
    assert plano.ids_sem_recomendacao == ["EMP_099"]
    assert all(a.id_colaborador != "EMP_099" for a in plano.atualizacoes)


def test_colaborador_novo_entra_com_colunas_manuais_vazias():
    plano = planejar_atualizacao(CABECALHO, LINHAS, RECOMENDACOES, "2025-09-01 06:00")
    assert len(plano.novas_linhas) == 1
    nova = plano.novas_linhas[0]
    assert nova[0] == "EMP_041" and nova[6] == "Alinhamento em 1-on-1"
    assert nova[8:] == ["", "", ""]


def test_colunas_localizadas_pelo_nome_mesmo_reordenadas():
    ordem = [10, 0, 6, 8, 1, 2, 3, 4, 5, 7, 9]
    cab = [CABECALHO[i] for i in ordem]
    linhas = [[l[i] for i in ordem] for l in LINHAS]
    plano = planejar_atualizacao(cab, linhas, RECOMENDACOES, "2025-09-01 06:00")
    depois = _aplicar_em_memoria(linhas, plano)
    verificar_preservacao(fotografia_colunas_manuais(cab, linhas), fotografia_colunas_manuais(cab, depois))
    assert depois[1][cab.index("Acao_Disciplinar_Recomendada")] == "Suspensão Disciplinar (1 a 3 dias)"


def test_planilha_sem_coluna_obrigatoria_aborta_sem_gravar():
    cabecalho = [c for c in CABECALHO if c != "Observacoes_Gestor"]
    with pytest.raises(ValueError):
        planejar_atualizacao(cabecalho, [l[:-1] for l in LINHAS], RECOMENDACOES, "2025-09-01 06:00")


def test_verificacao_detecta_historico_alterado():
    depois = [list(l) for l in LINHAS]
    depois[1][10] = "apagado"
    with pytest.raises(RuntimeError):
        verificar_preservacao(fotografia_colunas_manuais(CABECALHO, LINHAS), fotografia_colunas_manuais(CABECALHO, depois))


@pytest.mark.parametrize("entrada, esperado", [
    ("OperaÃ§Ãµes", "Operações"),
    ("LogÃ\xadstica", "Logística"),
    ("SÃ´nia Ferreira", "Sônia Ferreira"),
    ("Atendimento", "Atendimento"),
    ("Opera��es", "Opera��es"),  # caractere já perdido: não há como reparar
])
def test_reparo_de_encoding(entrada, esperado):
    assert reparar_mojibake(entrada) == esperado
