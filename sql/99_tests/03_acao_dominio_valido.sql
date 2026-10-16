-- A ação recomendada deve ser exatamente um dos valores da Política de Consequências.
SELECT id_colaborador, acao_disciplinar_recomendada
FROM {{marts}}.mart_absenteismo_colaborador
WHERE acao_disciplinar_recomendada NOT IN (
  'Sem ação requerida',
  'Alinhamento em 1-on-1',
  'Advertência Escrita',
  'Suspensão Disciplinar (1 a 3 dias)'
)
