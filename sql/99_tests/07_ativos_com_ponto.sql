-- Todo colaborador ativo deve ter marcações de ponto no período.
SELECT id_colaborador, nome
FROM {{marts}}.mart_absenteismo_colaborador
WHERE dias_previstos = 0
