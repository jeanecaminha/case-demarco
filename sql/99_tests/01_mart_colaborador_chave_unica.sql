-- Cada colaborador deve aparecer uma única vez no mart (chave do Reverse ETL).
SELECT id_colaborador, COUNT(*) AS qtd
FROM {{marts}}.mart_absenteismo_colaborador
GROUP BY id_colaborador
HAVING COUNT(*) > 1
