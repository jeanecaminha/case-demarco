-- Revalida a régua de forma independente da query que a calcula.
SELECT id_colaborador, total_faltas_injustificadas, maior_sequencia_dsr_perdido, acao_disciplinar_recomendada
FROM {{marts}}.mart_absenteismo_colaborador
WHERE (total_faltas_injustificadas >= 4 AND acao_disciplinar_recomendada != 'Suspensão Disciplinar (1 a 3 dias)')
   OR (maior_sequencia_dsr_perdido >= 2 AND acao_disciplinar_recomendada != 'Suspensão Disciplinar (1 a 3 dias)')
   OR (total_faltas_injustificadas = 0 AND acao_disciplinar_recomendada != 'Sem ação requerida')
   OR (total_dsr_perdido > total_faltas_injustificadas)
