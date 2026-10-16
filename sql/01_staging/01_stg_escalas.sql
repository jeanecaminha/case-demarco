-- stg_escalas: uma linha por escala.
-- Tipa as colunas e tira a jornada semanal do contrato, que entra no cálculo
-- da diária do DSR (valor hora * jornada semanal / 6).
CREATE OR REPLACE TABLE {{staging}}.stg_escalas AS
SELECT
  UPPER(TRIM(id_escala))                                     AS id_escala,
  TRIM(descricao)                                            AS descricao,
  UPPER(REPLACE(dias_trabalho, ' ', ''))                     AS dias_trabalho,
  UPPER(REPLACE(dia_dsr, ' ', ''))                           AS dia_dsr,
  SAFE_CAST(REPLACE(horas_diarias, ',', '.') AS FLOAT64)     AS horas_diarias,
  SAFE_CAST(REPLACE(horas_sabado, ',', '.') AS FLOAT64)      AS horas_sabado,
  SAFE_CAST(REPLACE(divisor_folha, ',', '.') AS FLOAT64)     AS divisor_folha,
  -- Jornada semanal vem da descrição ("Jornada 44h semanais") e não da soma das
  -- horas diárias: a ESC_44H descreve seg-sex 8,8h + sáb 4,4h = 48,4h, o que bate
  -- de frente com o contrato de 44h e com o divisor 220. Fiquei com o contrato.
  -- A 12x36 não informa carga semanal; uso a média de 42h (alterna 36h e 48h).
  COALESCE(
    SAFE_CAST(REGEXP_EXTRACT(descricao, r'(\d+)h semanais') AS FLOAT64),
    CASE WHEN UPPER(id_escala) LIKE '%12X36%' THEN 42.0 END
  )                                                          AS jornada_semanal_horas,
  _colunas_encoding_reparado                                 AS colunas_encoding_reparado
FROM {{raw}}.escalas
WHERE id_escala IS NOT NULL;
