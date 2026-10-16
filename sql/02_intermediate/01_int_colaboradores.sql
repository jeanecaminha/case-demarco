-- int_colaboradores: uma linha por colaborador, com os buracos do cadastro resolvidos.
--   ID duplicado     -> fica o primeiro registro do arquivo (P3)
--   escala em branco -> deduzida pela jornada diária no ponto (P4)
--   salário inválido -> mediana do cargo; se não houver, do departamento (P5)
--   gestor inválido  -> só marcado; não invento hierarquia (P6)
CREATE OR REPLACE TABLE {{staging}}.int_colaboradores AS
WITH colaboradores AS (
  SELECT *
  FROM {{staging}}.stg_colaboradores
  WHERE ordem_registro_id = 1
),

-- jornada diária mais comum de cada um no ponto, fora os dias de folga
jornada_predominante AS (
  SELECT id_colaborador, jornada_esperada_horas
  FROM (
    SELECT
      id_colaborador,
      jornada_esperada_horas,
      ROW_NUMBER() OVER (PARTITION BY id_colaborador ORDER BY COUNT(*) DESC, jornada_esperada_horas DESC) AS rn
    FROM {{staging}}.stg_ponto
    WHERE jornada_esperada_horas > 0
    GROUP BY id_colaborador, jornada_esperada_horas
  )
  WHERE rn = 1
),

escala_inferida AS (
  SELECT j.id_colaborador, e.id_escala
  FROM jornada_predominante AS j
  JOIN {{staging}}.stg_escalas AS e
    ON ROUND(e.horas_diarias, 2) = ROUND(j.jornada_esperada_horas, 2)
),

com_escala AS (
  SELECT
    c.*,
    COALESCE(c.id_escala_cadastro, ei.id_escala) AS id_escala,
    c.id_escala_cadastro IS NULL AND ei.id_escala IS NOT NULL AS fl_escala_inferida,
    c.data_admissao <= DATE '{{periodo_fim}}'
      AND (c.data_desligamento IS NULL OR c.data_desligamento >= DATE '{{periodo_inicio}}') AS fl_ativo_no_periodo
  FROM colaboradores AS c
  LEFT JOIN escala_inferida AS ei USING (id_colaborador)
),

-- mediana só com salários válidos de quem estava ativo no período
mediana_cargo AS (
  SELECT DISTINCT cargo, PERCENTILE_CONT(salario_mensal, 0.5) OVER (PARTITION BY cargo) AS mediana_salario_cargo
  FROM com_escala
  WHERE salario_mensal IS NOT NULL AND fl_ativo_no_periodo
),

mediana_departamento AS (
  SELECT DISTINCT departamento, PERCENTILE_CONT(salario_mensal, 0.5) OVER (PARTITION BY departamento) AS mediana_salario_departamento
  FROM com_escala
  WHERE salario_mensal IS NOT NULL AND fl_ativo_no_periodo
)

SELECT
  c.id_colaborador,
  c.nome,
  c.cargo,
  c.departamento,
  c.id_escala,
  c.fl_escala_inferida,
  e.descricao               AS descricao_escala,
  e.divisor_folha,
  e.jornada_semanal_horas,
  c.salario_original,
  c.status_salario,
  c.salario_mensal          AS salario_mensal_informado,
  -- O +0.000001 é de propósito: a mediana do Analista de TI dá 5268,155 exato, e em
  -- ponto flutuante o ROUND caía às vezes para ,15 e às vezes para ,16.
  ROUND(COALESCE(c.salario_mensal, mc.mediana_salario_cargo, md.mediana_salario_departamento) + 0.000001, 2) AS salario_mensal,
  CASE
    WHEN c.salario_mensal IS NOT NULL         THEN 'INFORMADO'
    WHEN mc.mediana_salario_cargo IS NOT NULL THEN 'IMPUTADO_MEDIANA_CARGO'
    WHEN md.mediana_salario_departamento IS NOT NULL THEN 'IMPUTADO_MEDIANA_DEPARTAMENTO'
    ELSE 'SEM_SALARIO'
  END                       AS origem_salario,
  c.data_admissao,
  c.data_desligamento,
  c.fl_ativo_no_periodo,
  c.id_gestor,
  -- Nome (ID) porque tem homônimo: dois "Thiago Pereira", EMP_001 e EMP_051.
  -- Gestor desligado fica NULL para não aparecer com custo no painel.
  CASE
    WHEN g.id_colaborador IS NOT NULL
         AND (g.data_desligamento IS NULL OR g.data_desligamento >= DATE '{{periodo_inicio}}')
      THEN CONCAT(g.nome, ' (', g.id_colaborador, ')')
  END                       AS nome_gestor,
  CASE
    WHEN c.id_gestor IS NULL                    THEN 'NAO_INFORMADO'
    WHEN g.id_colaborador IS NULL               THEN 'INEXISTENTE_NO_CADASTRO'
    WHEN g.data_desligamento IS NOT NULL
         AND g.data_desligamento < DATE '{{periodo_inicio}}' THEN 'GESTOR_DESLIGADO'
    ELSE 'OK'
  END                       AS status_gestor,
  c.qtd_registros_mesmo_id > 1 AS fl_id_duplicado_na_origem
FROM com_escala AS c
LEFT JOIN {{staging}}.stg_escalas AS e      ON e.id_escala = c.id_escala
LEFT JOIN mediana_cargo AS mc               ON mc.cargo = c.cargo
LEFT JOIN mediana_departamento AS md        ON md.departamento = c.departamento
LEFT JOIN colaboradores AS g                ON g.id_colaborador = c.id_gestor;
