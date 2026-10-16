-- stg_ponto: uma linha por linha do arquivo de ponto.
-- As duplicatas ficam e são só contadas; a escolha de qual vale é no int_ponto_diario.
--
-- O que tem de sujo no ponto:
--   - código de abono escrito diferente ("ATESTADO MEDICO" x "ATESTADO_MEDICO")
--   - o mesmo dia repetido para a mesma pessoa, às vezes com horas diferentes
--   - horas trabalhadas negativas
CREATE OR REPLACE TABLE {{staging}}.stg_ponto AS
WITH tipado AS (
  SELECT
    UPPER(TRIM(id_colaborador))                                    AS id_colaborador,
    SAFE_CAST(SUBSTR(TRIM(data_registro), 1, 10) AS DATE)          AS data_registro,
    SAFE_CAST(REPLACE(jornada_esperada_horas, ',', '.') AS FLOAT64) AS jornada_esperada_horas,
    SAFE_CAST(REPLACE(horas_trabalhadas, ',', '.') AS FLOAT64)     AS horas_trabalhadas,
    SAFE_CAST(SAFE_CAST(flag_dsr AS FLOAT64) AS INT64)             AS flag_dsr,
    NULLIF(TRIM(codigo_abono), '')                                 AS codigo_abono_original,
    -- maiúsculo, sem acento e com _ no lugar de espaço ou hífen
    NULLIF(
      REGEXP_REPLACE(UPPER(TRIM(REPLACE(REPLACE(codigo_abono, 'É', 'E'), 'é', 'e'))), r'[\s\-]+', '_'),
      ''
    )                                                              AS codigo_abono,
    _arquivo_origem,
    SAFE_CAST(_linha_origem AS INT64)                              AS linha_origem
  FROM {{raw}}.espelho_ponto
  WHERE id_colaborador IS NOT NULL
)
SELECT
  *,
  COUNT(*) OVER (PARTITION BY id_colaborador, data_registro) AS qtd_registros_mesmo_dia,
  COUNT(DISTINCT horas_trabalhadas) OVER (PARTITION BY id_colaborador, data_registro) AS qtd_versoes_horas_mesmo_dia
FROM tipado;
