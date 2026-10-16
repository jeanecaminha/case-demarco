-- int_semanas_dsr: uma linha por colaborador por semana (segunda a domingo).
--
-- Lei 605/49, art. 6º: uma ou mais faltas injustificadas na semana = 1 DSR perdido.
-- Atraso não faz perder DSR (P9).
-- Também acha semanas seguidas com DSR perdido, porque 2 em sequência já é
-- suspensão pela política. Para isso uso gaps and islands (ver id_ilha).
CREATE OR REPLACE TABLE {{staging}}.int_semanas_dsr AS
WITH semanas AS (
  SELECT
    id_colaborador,
    semana_inicio,
    COUNTIF(fl_falta_injustificada)                AS faltas_injustificadas,
    COUNTIF(fl_falta_injustificada) > 0            AS fl_perdeu_dsr,
    MAX(valor_hora)                                AS valor_hora,
    MAX(jornada_semanal_horas)                     AS jornada_semanal_horas
  FROM {{staging}}.int_ponto_diario
  GROUP BY id_colaborador, semana_inicio
),

ilhas AS (
  SELECT
    *,
    -- nº da semana no calendário menos a posição dela entre as semanas com perda:
    -- semanas seguidas dão o mesmo número, e esse número vira a "ilha"
    CAST(DATE_DIFF(semana_inicio, DATE '2000-01-03', DAY) / 7 AS INT64)
      - ROW_NUMBER() OVER (PARTITION BY id_colaborador, fl_perdeu_dsr ORDER BY semana_inicio) AS id_ilha
  FROM semanas
)

SELECT
  id_colaborador,
  semana_inicio,
  faltas_injustificadas,
  fl_perdeu_dsr,
  CASE WHEN fl_perdeu_dsr
       THEN COUNT(*) OVER (PARTITION BY id_colaborador, fl_perdeu_dsr, id_ilha)
       ELSE 0
  END                                                         AS tamanho_sequencia_dsr_perdido,
  ROUND(valor_hora * (jornada_semanal_horas / 6), 4)          AS valor_diaria_dsr,
  CASE WHEN fl_perdeu_dsr
       THEN ROUND(valor_hora * (jornada_semanal_horas / 6), 2) ELSE 0
  END                                                         AS custo_dsr_perdido
FROM ilhas;
