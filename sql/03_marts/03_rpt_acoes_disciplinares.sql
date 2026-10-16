-- rpt_acoes_disciplinares: o que vai para a planilha dos gestores.
-- Uma linha por colaborador ativo, com os mesmos nomes de coluna da planilha.
-- Fica separado do mart para que uma mudança lá não altere a planilha sem querer.
CREATE OR REPLACE TABLE {{marts}}.rpt_acoes_disciplinares AS
SELECT
  id_colaborador                AS ID_Colaborador,
  nome                          AS Nome,
  departamento                  AS Departamento,
  id_gestor                     AS Gestor,
  total_faltas_injustificadas   AS Total_Faltas_Injustificadas,
  total_dsr_perdido             AS Total_DSR_Perdido,
  acao_disciplinar_recomendada  AS Acao_Disciplinar_Recomendada,
  motivo_acao                   AS Motivo_Acao,
  desconto_total                AS Desconto_Total
FROM {{marts}}.mart_absenteismo_colaborador;
