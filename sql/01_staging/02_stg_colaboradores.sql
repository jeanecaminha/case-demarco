-- stg_colaboradores: uma linha por linha do arquivo.
-- Duplicatas de ID continuam aqui, só marcadas; quem escolhe o registro
-- que vale é o int_colaboradores.
--
-- O que tem de sujo no cadastro:
--   - salário escrito de vários jeitos: "R$ 2.721,03", "R$5614", "2301,08",
--     "2589.9", "5.036" (= 5036), "A combinar", vazio
--   - data em 2021-05-12 00:00:00 e em 23/08/2021
--   - escala e gestor em branco
--   - acento quebrado ("OperaÃ§Ãµes"), já consertado no extract.py
CREATE OR REPLACE TABLE {{staging}}.stg_colaboradores AS
WITH fonte AS (
  SELECT
    UPPER(TRIM(id_colaborador))                         AS id_colaborador,
    TRIM(nome)                                          AS nome,
    TRIM(cargo)                                         AS cargo,
    TRIM(departamento)                                  AS departamento,
    salario_mensal                                      AS salario_original,
    -- só dígitos, ponto e vírgula; o resto ("R$", espaço, texto) sai
    REGEXP_REPLACE(COALESCE(salario_mensal, ''), r'[^0-9,.]', '') AS salario_digitos,
    NULLIF(UPPER(TRIM(id_escala)), '')                  AS id_escala_cadastro,
    TRIM(data_admissao)                                 AS data_admissao_original,
    TRIM(data_desligamento)                             AS data_desligamento_original,
    NULLIF(UPPER(TRIM(id_gestor)), '')                  AS id_gestor,
    _colunas_encoding_reparado                          AS colunas_encoding_reparado,
    _arquivo_origem,
    SAFE_CAST(_linha_origem AS INT64)                   AS linha_origem
  FROM {{raw}}.base_colaboradores
  WHERE id_colaborador IS NOT NULL
),

salario_convertido AS (
  SELECT
    *,
    SAFE_CAST(
      CASE
        WHEN salario_digitos = '' THEN NULL
        -- tem vírgula: formato brasileiro (ponto = milhar, vírgula = decimal)
        WHEN STRPOS(salario_digitos, ',') > 0
          THEN REPLACE(REPLACE(salario_digitos, '.', ''), ',', '.')
        -- ponto seguido de exatamente 3 dígitos é milhar: "5.036" = 5036, não 5,036
        WHEN REGEXP_CONTAINS(salario_digitos, r'^\d{1,3}(\.\d{3})+$')
          THEN REPLACE(salario_digitos, '.', '')
        -- sobra ponto decimal ("2589.9") ou número inteiro
        ELSE salario_digitos
      END AS FLOAT64
    ) AS salario_numerico
  FROM fonte
)

SELECT
  id_colaborador,
  nome,
  cargo,
  departamento,
  salario_original,
  CASE WHEN salario_numerico >= {{salario_minimo}} THEN ROUND(salario_numerico, 2) END AS salario_mensal,
  CASE
    WHEN salario_original IS NULL                 THEN 'AUSENTE'
    WHEN salario_numerico IS NULL                 THEN 'NAO_NUMERICO'
    WHEN salario_numerico < {{salario_minimo}}    THEN 'ABAIXO_DO_SALARIO_MINIMO'
    ELSE 'OK'
  END AS status_salario,
  id_escala_cadastro,
  CASE
    WHEN REGEXP_CONTAINS(data_admissao_original, r'^\d{4}-\d{2}-\d{2}')
      THEN SAFE_CAST(SUBSTR(data_admissao_original, 1, 10) AS DATE)
    WHEN REGEXP_CONTAINS(data_admissao_original, r'^\d{2}/\d{2}/\d{4}$')
      THEN SAFE_CAST(CONCAT(SUBSTR(data_admissao_original, 7, 4), '-',
                            SUBSTR(data_admissao_original, 4, 2), '-',
                            SUBSTR(data_admissao_original, 1, 2)) AS DATE)
  END AS data_admissao,
  CASE
    WHEN REGEXP_CONTAINS(data_desligamento_original, r'^\d{4}-\d{2}-\d{2}')
      THEN SAFE_CAST(SUBSTR(data_desligamento_original, 1, 10) AS DATE)
    WHEN REGEXP_CONTAINS(data_desligamento_original, r'^\d{2}/\d{2}/\d{4}$')
      THEN SAFE_CAST(CONCAT(SUBSTR(data_desligamento_original, 7, 4), '-',
                            SUBSTR(data_desligamento_original, 4, 2), '-',
                            SUBSTR(data_desligamento_original, 1, 2)) AS DATE)
  END AS data_desligamento,
  data_admissao_original,
  id_gestor,
  COUNT(*) OVER (PARTITION BY id_colaborador)                             AS qtd_registros_mesmo_id,
  -- ID duplicado: vale o primeiro registro do arquivo (premissa P3 do README)
  ROW_NUMBER() OVER (PARTITION BY id_colaborador ORDER BY linha_origem)   AS ordem_registro_id,
  colunas_encoding_reparado,
  _arquivo_origem,
  linha_origem
FROM salario_convertido;
