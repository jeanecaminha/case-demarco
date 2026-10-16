-- O custo somado no fato diário deve reconciliar com o mart por colaborador (tolerância de arredondamento).
SELECT m.id_colaborador, m.desconto_total, f.custo_total
FROM {{marts}}.mart_absenteismo_colaborador AS m
LEFT JOIN (
  SELECT id_colaborador, SUM(custo_total) AS custo_total
  FROM {{marts}}.fct_ponto_diario
  GROUP BY id_colaborador
) AS f USING (id_colaborador)
WHERE ABS(m.desconto_total - COALESCE(f.custo_total, 0)) > 0.05
