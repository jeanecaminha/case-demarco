-- Todo colaborador ativo precisa de salário, divisor e jornada para que o custo seja calculável.
SELECT id_colaborador, salario_mensal, divisor_folha, jornada_semanal_horas
FROM {{marts}}.mart_absenteismo_colaborador
WHERE salario_mensal IS NULL OR divisor_folha IS NULL OR jornada_semanal_horas IS NULL
