-- mart_absenteismo_colaborador: uma linha por colaborador ativo no período.
-- Fonte do painel e do Reverse ETL.
--
-- Fórmulas do financeiro, como estão no briefing:
--   valor hora    = salário mensal / divisor
--   diária do DSR = valor hora * (jornada semanal / 6)
--   desconto      = horas faltadas injustificadas * valor hora + DSRs perdidos * diária do DSR
--
-- Régua da Política de Consequências (vale a primeira que bater):
--   4+ faltas ou 2+ DSRs perdidos em semanas seguidas -> Suspensão (1 a 3 dias)
--   2 a 3 faltas                                      -> Advertência Escrita
--   1 falta                                           -> Alinhamento em 1-on-1
--   0 faltas                                          -> Sem ação requerida
CREATE OR REPLACE TABLE {{marts}}.mart_absenteismo_colaborador AS
WITH dias AS (
  SELECT
    id_colaborador,
    COUNTIF(jornada_esperada_horas > 0)                  AS dias_previstos,
    SUM(jornada_esperada_horas)                          AS horas_previstas,
    COUNTIF(status_dia = 'FALTA_INJUSTIFICADA')          AS total_faltas_injustificadas,
    COUNTIF(status_dia = 'AUSENCIA_ABONADA')             AS total_ausencias_abonadas,
    COUNTIF(status_dia = 'ATRASO_SAIDA_ANTECIPADA')      AS total_dias_atraso_saida,
    COUNTIF(status_dia = 'REGISTRO_INVALIDO')            AS total_registros_invalidos,
    COUNTIF(fl_falta_injustificada AND dia_semana IN ('Segunda', 'Sexta')) AS faltas_segunda_ou_sexta,
    COUNTIF(fl_falta_adjacente_descanso)                 AS faltas_adjacentes_descanso,
    SUM(horas_falta_integral)                            AS horas_falta_integral,
    SUM(horas_atraso_saida)                              AS horas_atraso_saida
  FROM {{staging}}.int_ponto_diario
  GROUP BY id_colaborador
),

semanas AS (
  SELECT
    id_colaborador,
    COUNTIF(fl_perdeu_dsr)                   AS total_dsr_perdido,
    MAX(tamanho_sequencia_dsr_perdido)       AS maior_sequencia_dsr_perdido,
    MAX(valor_diaria_dsr)                    AS valor_diaria_dsr
  FROM {{staging}}.int_semanas_dsr
  GROUP BY id_colaborador
),

consolidado AS (
  SELECT
    c.id_colaborador,
    c.nome,
    c.cargo,
    c.departamento,
    c.id_gestor,
    COALESCE(c.nome_gestor, 'Sem gestor ativo')                      AS nome_gestor,
    c.status_gestor,
    c.id_escala,
    c.fl_escala_inferida,
    c.salario_mensal,
    c.origem_salario,
    c.divisor_folha,
    c.jornada_semanal_horas,
    ROUND(c.salario_mensal / c.divisor_folha, 4)                     AS valor_hora,
    ROUND((c.salario_mensal / c.divisor_folha) * (c.jornada_semanal_horas / 6), 4) AS valor_diaria_dsr,
    COALESCE(d.dias_previstos, 0)                                    AS dias_previstos,
    COALESCE(d.horas_previstas, 0)                                   AS horas_previstas,
    COALESCE(d.total_faltas_injustificadas, 0)                       AS total_faltas_injustificadas,
    COALESCE(d.total_ausencias_abonadas, 0)                          AS total_ausencias_abonadas,
    COALESCE(d.total_dias_atraso_saida, 0)                           AS total_dias_atraso_saida,
    COALESCE(d.total_registros_invalidos, 0)                         AS total_registros_invalidos,
    COALESCE(d.faltas_segunda_ou_sexta, 0)                           AS faltas_segunda_ou_sexta,
    COALESCE(d.faltas_adjacentes_descanso, 0)                        AS faltas_adjacentes_descanso,
    COALESCE(d.horas_falta_integral, 0)                              AS horas_falta_integral,
    COALESCE(d.horas_atraso_saida, 0)                                AS horas_atraso_saida,
    COALESCE(s.total_dsr_perdido, 0)                                 AS total_dsr_perdido,
    COALESCE(s.maior_sequencia_dsr_perdido, 0)                       AS maior_sequencia_dsr_perdido
  FROM {{staging}}.int_colaboradores AS c
  LEFT JOIN dias    AS d USING (id_colaborador)
  LEFT JOIN semanas AS s USING (id_colaborador)
  WHERE c.fl_ativo_no_periodo
),

calculado AS (
  SELECT
    *,
    horas_falta_integral + horas_atraso_saida                        AS horas_faltadas_injustificadas,
    ROUND(horas_falta_integral * valor_hora, 2)                      AS custo_faltas,
    ROUND(horas_atraso_saida * valor_hora, 2)                        AS custo_atrasos,
    ROUND(total_dsr_perdido * valor_diaria_dsr, 2)                   AS custo_dsr,
    ROUND((horas_falta_integral + horas_atraso_saida) * valor_hora
          + total_dsr_perdido * valor_diaria_dsr, 2)                 AS desconto_total,
    CASE
      WHEN total_faltas_injustificadas >= 4 OR maior_sequencia_dsr_perdido >= 2 THEN 3
      WHEN total_faltas_injustificadas >= 2 THEN 2
      WHEN total_faltas_injustificadas = 1  THEN 1
      ELSE 0
    END                                                              AS nivel_acao
  FROM consolidado
)

SELECT
  *,
  CASE nivel_acao
    WHEN 3 THEN 'Suspensão Disciplinar (1 a 3 dias)'
    WHEN 2 THEN 'Advertência Escrita'
    WHEN 1 THEN 'Alinhamento em 1-on-1'
    ELSE 'Sem ação requerida'
  END                                                                AS acao_disciplinar_recomendada,
  CASE WHEN nivel_acao > 0 THEN 1 ELSE 0 END                         AS qtd_com_acao_requerida,
  CASE WHEN nivel_acao = 3 THEN 1 ELSE 0 END                         AS qtd_suspensao,
  CASE WHEN nivel_acao = 2 THEN 1 ELSE 0 END                         AS qtd_advertencia,
  CASE WHEN nivel_acao = 1 THEN 1 ELSE 0 END                         AS qtd_alinhamento,
  CASE WHEN nivel_acao = 0 THEN 1 ELSE 0 END                         AS qtd_sem_acao,
  CONCAT(nome, ' (', id_colaborador, ')')                            AS colaborador,
  CASE WHEN origem_salario != 'INFORMADO' OR fl_escala_inferida
       THEN '⚠ Estimado' ELSE '' END                                 AS alerta_dado_estimado,
  CASE
    WHEN total_faltas_injustificadas = 0 THEN 'Nenhuma falta injustificada no período'
    ELSE CONCAT(
      CAST(total_faltas_injustificadas AS STRING), ' falta(s) injustificada(s)',
      CASE WHEN maior_sequencia_dsr_perdido >= 2
           THEN CONCAT('; ', CAST(maior_sequencia_dsr_perdido AS STRING), ' DSRs perdidos em semanas consecutivas')
           ELSE '' END
    )
  END                                                                AS motivo_acao,
  ROUND(SAFE_DIVIDE(horas_falta_integral + horas_atraso_saida, horas_previstas) * 100, 2) AS taxa_absenteismo_injustificado_pct,
  origem_salario != 'INFORMADO' OR fl_escala_inferida                AS fl_calculo_com_dado_estimado,
  DATE '{{periodo_inicio}}'                                          AS periodo_inicio,
  DATE '{{periodo_fim}}'                                             AS periodo_fim,
  '{{data_processamento}}'                                           AS data_processamento
FROM calculado;
