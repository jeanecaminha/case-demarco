-- fct_ponto_diario: uma linha por colaborador por dia. Alimenta os gráficos
-- por dia e por semana do painel.
--
-- O custo do DSR é da semana, mas aqui o grão é o dia. Para não contar o DSR
-- duas vezes, ele fica só na 1ª falta da semana; assim a soma em qualquer recorte
-- bate com o total do mart_absenteismo_colaborador (teste 05).
CREATE OR REPLACE TABLE {{marts}}.fct_ponto_diario AS
WITH com_semana AS (
  SELECT
    p.*,
    s.valor_diaria_dsr,
    s.fl_perdeu_dsr,
    ROW_NUMBER() OVER (
      PARTITION BY p.id_colaborador, p.semana_inicio, p.fl_falta_injustificada
      ORDER BY p.data_registro
    ) AS ordem_no_grupo_semana
  FROM {{staging}}.int_ponto_diario AS p
  JOIN {{staging}}.int_semanas_dsr AS s
    ON s.id_colaborador = p.id_colaborador
   AND s.semana_inicio  = p.semana_inicio
)
SELECT
  id_colaborador,
  nome,
  departamento,
  cargo,
  id_gestor,
  COALESCE(nome_gestor, 'Sem gestor ativo')                   AS nome_gestor,
  data_registro,
  semana_inicio,
  DATE_TRUNC(data_registro, MONTH)                            AS mes_referencia,
  dia_semana_num,
  dia_semana,
  -- "1 Seg" ... "7 Dom": com o número na frente o gráfico ordena certo
  CONCAT(CAST(dia_semana_num AS STRING), ' ', SUBSTR(dia_semana, 1, 3)) AS dia_semana_ordem,
  dia_semana IN ('Segunda', 'Sexta')                          AS fl_segunda_ou_sexta,
  status_dia,
  codigo_abono,
  jornada_esperada_horas,
  horas_trabalhadas,
  minutos_deficit,
  fl_falta_injustificada,
  fl_falta_adjacente_descanso,
  fl_abono_requer_validacao,
  fl_falta_injustificada AND ordem_no_grupo_semana = 1        AS fl_gerou_perda_dsr,
  -- contadores 0/1 para o painel só precisar somar
  CASE WHEN fl_falta_injustificada THEN 1 ELSE 0 END          AS qtd_faltas_injustificadas,
  CASE WHEN fl_falta_injustificada AND dia_semana IN ('Segunda', 'Sexta') THEN 1 ELSE 0 END AS qtd_faltas_segunda_ou_sexta,
  CASE WHEN fl_falta_injustificada AND ordem_no_grupo_semana = 1 THEN 1 ELSE 0 END AS qtd_dsr_perdido,
  CASE WHEN status_dia = 'ATRASO_SAIDA_ANTECIPADA' THEN 1 ELSE 0 END AS qtd_atrasos,
  CASE WHEN fl_falta_injustificada AND dia_semana = 'Segunda' THEN 1 ELSE 0 END AS qtd_faltas_segunda,
  CASE WHEN fl_falta_injustificada AND dia_semana = 'Sexta' THEN 1 ELSE 0 END   AS qtd_faltas_sexta,
  CASE WHEN fl_falta_adjacente_descanso THEN 1 ELSE 0 END     AS qtd_faltas_adjacentes_descanso,
  horas_falta_integral,
  horas_atraso_saida,
  horas_falta_integral + horas_atraso_saida                   AS horas_injustificadas,
  valor_hora,
  ROUND(horas_falta_integral * valor_hora, 4)                 AS custo_faltas,
  ROUND(horas_atraso_saida * valor_hora, 4)                   AS custo_atrasos,
  CASE WHEN fl_falta_injustificada AND ordem_no_grupo_semana = 1
       THEN valor_diaria_dsr ELSE 0 END                       AS custo_dsr_perdido,
  ROUND((horas_falta_integral + horas_atraso_saida) * valor_hora, 4)
    + CASE WHEN fl_falta_injustificada AND ordem_no_grupo_semana = 1
           THEN valor_diaria_dsr ELSE 0 END                   AS custo_total
FROM com_semana;
