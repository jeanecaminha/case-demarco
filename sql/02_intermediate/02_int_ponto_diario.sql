-- int_ponto_diario: uma linha por colaborador por dia, só dentro do período
-- e do vínculo. É aqui que cada dia ganha um status.
--
--   DESCANSO                 folga pela escala, sem horas
--   TRABALHO_EM_DESCANSO     folga com horas (hora extra, fica fora do desconto)
--   REGISTRO_INVALIDO        horas negativas ou vazias: não dá para afirmar falta (P8)
--   AUSENCIA_ABONADA         faltou horas mas tem código de abono
--   FALTA_INJUSTIFICADA      dia de trabalho, 0 horas, sem abono
--   ATRASO_SAIDA_ANTECIPADA  faltou mais que a tolerância, sem abono
--   PRESENTE                 cumpriu a jornada, ou faltou até {{tolerancia_minutos}} min
--
-- A ordem do CASE importa: o abono é testado antes da falta.
CREATE OR REPLACE TABLE {{staging}}.int_ponto_diario AS
WITH deduplicado AS (
  -- Dia duplicado: fica o registro com mais horas. Se a duplicata é erro de
  -- exportação, não faz sentido o colaborador pagar por isso.
  -- Se qualquer uma das versões tiver abono, o abono vale.
  SELECT
    id_colaborador,
    data_registro,
    jornada_esperada_horas,
    horas_trabalhadas,
    flag_dsr,
    MAX(codigo_abono) OVER (PARTITION BY id_colaborador, data_registro) AS codigo_abono,
    qtd_registros_mesmo_dia
  FROM {{staging}}.stg_ponto
  WHERE data_registro BETWEEN DATE '{{periodo_inicio}}' AND DATE '{{periodo_fim}}'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY id_colaborador, data_registro
    ORDER BY horas_trabalhadas DESC, linha_origem
  ) = 1
),

-- só dias em que a pessoa tinha vínculo; o resto (ex.: ponto depois do
-- desligamento) aparece no mart_qualidade_dados
vinculado AS (
  SELECT
    p.*,
    c.nome,
    c.departamento,
    c.cargo,
    c.id_gestor,
    c.nome_gestor,
    c.salario_mensal,
    c.divisor_folha,
    c.jornada_semanal_horas
  FROM deduplicado AS p
  JOIN {{staging}}.int_colaboradores AS c
    ON c.id_colaborador = p.id_colaborador
   AND p.data_registro >= c.data_admissao
   AND (c.data_desligamento IS NULL OR p.data_registro <= c.data_desligamento)
),

classificado AS (
  SELECT
    *,
    ROUND((jornada_esperada_horas - horas_trabalhadas) * 60, 1) AS minutos_deficit,
    CASE
      WHEN horas_trabalhadas IS NULL OR horas_trabalhadas < 0 OR jornada_esperada_horas IS NULL
        THEN 'REGISTRO_INVALIDO'
      WHEN jornada_esperada_horas = 0 AND horas_trabalhadas > 0 THEN 'TRABALHO_EM_DESCANSO'
      WHEN jornada_esperada_horas = 0                            THEN 'DESCANSO'
      WHEN codigo_abono IS NOT NULL AND horas_trabalhadas < jornada_esperada_horas
        THEN 'AUSENCIA_ABONADA'
      WHEN horas_trabalhadas = 0                                 THEN 'FALTA_INJUSTIFICADA'
      WHEN ROUND((jornada_esperada_horas - horas_trabalhadas) * 60, 1) > {{tolerancia_minutos}}
        THEN 'ATRASO_SAIDA_ANTECIPADA'
      ELSE 'PRESENTE'
    END AS status_dia
  FROM vinculado
)

SELECT
  id_colaborador,
  data_registro,
  DATE_TRUNC(data_registro, WEEK(MONDAY))                              AS semana_inicio,
  -- 1 = segunda ... 7 = domingo. Feito assim porque EXTRACT(DAYOFWEEK) muda entre BigQuery e DuckDB
  DATE_DIFF(data_registro, DATE_TRUNC(data_registro, WEEK(MONDAY)), DAY) + 1 AS dia_semana_num,
  CASE DATE_DIFF(data_registro, DATE_TRUNC(data_registro, WEEK(MONDAY)), DAY) + 1
    WHEN 1 THEN 'Segunda' WHEN 2 THEN 'Terça'  WHEN 3 THEN 'Quarta' WHEN 4 THEN 'Quinta'
    WHEN 5 THEN 'Sexta'   WHEN 6 THEN 'Sábado' WHEN 7 THEN 'Domingo'
  END                                                                  AS dia_semana,
  nome,
  departamento,
  cargo,
  id_gestor,
  nome_gestor,
  jornada_esperada_horas,
  horas_trabalhadas,
  flag_dsr,
  codigo_abono,
  qtd_registros_mesmo_dia,
  minutos_deficit,
  status_dia,
  status_dia = 'FALTA_INJUSTIFICADA'                                   AS fl_falta_injustificada,
  CASE WHEN status_dia = 'FALTA_INJUSTIFICADA' THEN jornada_esperada_horas ELSE 0 END AS horas_falta_integral,
  -- Súmula 366 do TST: passou da tolerância, desconta o atraso inteiro
  CASE WHEN status_dia = 'ATRASO_SAIDA_ANTECIPADA'
       THEN ROUND(jornada_esperada_horas - horas_trabalhadas, 2) ELSE 0 END AS horas_atraso_saida,
  -- "emenda": falta num dia vizinho à folga da própria escala
  status_dia = 'FALTA_INJUSTIFICADA' AND (
    LAG(jornada_esperada_horas)  OVER (PARTITION BY id_colaborador ORDER BY data_registro) = 0
    OR LEAD(jornada_esperada_horas) OVER (PARTITION BY id_colaborador ORDER BY data_registro) = 0
  )                                                                    AS fl_falta_adjacente_descanso,
  status_dia = 'AUSENCIA_ABONADA' AND codigo_abono = 'DECLARACAO_HORAS' AND horas_trabalhadas = 0
                                                                       AS fl_abono_requer_validacao,
  salario_mensal,
  divisor_folha,
  jornada_semanal_horas,
  ROUND(salario_mensal / divisor_folha, 4)                             AS valor_hora
FROM classificado;
