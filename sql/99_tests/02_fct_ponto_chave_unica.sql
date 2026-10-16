-- O fato diário não pode ter mais de uma linha por colaborador e dia.
SELECT id_colaborador, data_registro, COUNT(*) AS qtd
FROM {{marts}}.fct_ponto_diario
GROUP BY id_colaborador, data_registro
HAVING COUNT(*) > 1
