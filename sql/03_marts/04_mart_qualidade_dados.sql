-- mart_qualidade_dados: uma linha por problema encontrado nos dados.
-- É a página "Qualidade dos dados" do painel: mostra o valor original e o que
-- foi feito com ele, para o RH saber quando um número depende de estimativa.
--
--   ALTA  mexe no custo ou na ação disciplinar; alguém precisa conferir
--   MEDIA resolvido por uma premissa documentada no README
--   INFO  só padronização, não muda resultado
CREATE OR REPLACE TABLE {{marts}}.mart_qualidade_dados AS
WITH ocorrencias AS (

-- 1. Salário ausente, não numérico ou abaixo do mínimo -> imputado
SELECT
  'base_colaboradores'                     AS fonte,
  id_colaborador,
  CAST(NULL AS DATE)                       AS data_referencia,
  'SALARIO_AUSENTE_OU_INVALIDO'            AS tipo_ocorrencia,
  CASE WHEN fl_ativo_no_periodo THEN 'ALTA' ELSE 'INFO' END AS severidade,
  COALESCE(salario_original, '(vazio)')    AS valor_original,
  CONCAT(origem_salario, ': R$ ', CAST(salario_mensal AS STRING)) AS tratamento_aplicado
FROM {{staging}}.int_colaboradores
WHERE status_salario != 'OK'

UNION ALL
-- 2. Salário em formato não padronizado (convertido com sucesso)
SELECT
  'base_colaboradores', id_colaborador, CAST(NULL AS DATE),
  'SALARIO_FORMATO_NAO_PADRAO', 'INFO',
  salario_original,
  CONCAT('Convertido para ', CAST(salario_mensal AS STRING))
FROM {{staging}}.stg_colaboradores
WHERE status_salario = 'OK'
  AND NOT REGEXP_CONTAINS(salario_original, r'^\d+(\.\d{1,2})?$')

UNION ALL
-- 3. ID de colaborador duplicado no cadastro
SELECT
  'base_colaboradores', id_colaborador, CAST(NULL AS DATE),
  'ID_DUPLICADO', 'ALTA',
  CONCAT(nome, ' | ', cargo, ' | linha ', CAST(linha_origem AS STRING)),
  'Registro descartado: mantido o 1º registro do arquivo (coerente com a planilha dos gestores)'
FROM {{staging}}.stg_colaboradores
WHERE ordem_registro_id > 1

UNION ALL
-- 4. Escala não informada -> inferida pelo ponto
SELECT
  'base_colaboradores', id_colaborador, CAST(NULL AS DATE),
  'ESCALA_AUSENTE', 'MEDIA',
  '(vazio)',
  CONCAT('Inferida pelo padrão de jornada do ponto: ', id_escala)
FROM {{staging}}.int_colaboradores
WHERE fl_escala_inferida

UNION ALL
-- 5. Gestor ausente ou desligado
SELECT
  'base_colaboradores', id_colaborador, CAST(NULL AS DATE),
  CONCAT('GESTOR_', REPLACE(status_gestor, 'GESTOR_', '')), 'MEDIA',
  COALESCE(id_gestor, '(vazio)'),
  'Mantido como está; agrupado como "Sem gestor ativo" no dashboard'
FROM {{staging}}.int_colaboradores
WHERE status_gestor != 'OK' AND fl_ativo_no_periodo

UNION ALL
-- 6. Data de admissão em formato brasileiro
SELECT
  'base_colaboradores', id_colaborador, CAST(NULL AS DATE),
  'DATA_FORMATO_DD_MM_AAAA', 'INFO',
  data_admissao_original,
  CONCAT('Convertida para ', CAST(data_admissao AS STRING))
FROM {{staging}}.stg_colaboradores
WHERE REGEXP_CONTAINS(data_admissao_original, r'^\d{2}/\d{2}/\d{4}$')

UNION ALL
-- 7. Texto com dupla codificação (mojibake) reparado na ingestão
SELECT
  'base_colaboradores', id_colaborador, CAST(NULL AS DATE),
  'ENCODING_REPARADO', 'INFO',
  colunas_encoding_reparado,
  'Texto UTF-8 decodificado como Latin-1 foi revertido na ingestão'
FROM {{staging}}.stg_colaboradores
WHERE colunas_encoding_reparado IS NOT NULL

UNION ALL
SELECT
  'escalas', id_escala, CAST(NULL AS DATE),
  'ENCODING_REPARADO', 'INFO',
  colunas_encoding_reparado,
  'Texto UTF-8 decodificado como Latin-1 foi revertido na ingestão'
FROM {{staging}}.stg_escalas
WHERE colunas_encoding_reparado IS NOT NULL

UNION ALL
-- 8. Registros de ponto duplicados (mesmo colaborador e dia)
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  CASE WHEN MAX(qtd_versoes_horas_mesmo_dia) > 1 THEN 'PONTO_DUPLICADO_CONFLITANTE' ELSE 'PONTO_DUPLICADO' END,
  CASE WHEN MAX(qtd_versoes_horas_mesmo_dia) > 1 THEN 'MEDIA' ELSE 'INFO' END,
  CONCAT('horas: ', STRING_AGG(CAST(horas_trabalhadas AS STRING), ' | ')),
  'Mantida 1 linha por dia; em conflito prevalece a de mais horas trabalhadas'
FROM {{staging}}.stg_ponto
WHERE qtd_registros_mesmo_dia > 1
GROUP BY id_colaborador, data_registro

UNION ALL
-- 9. Registros de ponto fora do vínculo (ex.: após desligamento) ou de ID inexistente
SELECT
  'espelho_ponto', p.id_colaborador, p.data_registro,
  'PONTO_FORA_DO_VINCULO', 'ALTA',
  CONCAT('horas: ', CAST(p.horas_trabalhadas AS STRING)),
  'Descartado: colaborador desligado/inexistente na data'
FROM {{staging}}.stg_ponto AS p
LEFT JOIN {{staging}}.int_ponto_diario AS d
  ON d.id_colaborador = p.id_colaborador AND d.data_registro = p.data_registro
WHERE d.id_colaborador IS NULL
  AND p.data_registro BETWEEN DATE '{{periodo_inicio}}' AND DATE '{{periodo_fim}}'

UNION ALL
-- 10. Horas trabalhadas inválidas (negativas)
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  'HORAS_INVALIDAS', 'ALTA',
  CAST(horas_trabalhadas AS STRING),
  'Dia não classificado como falta; requer validação do BP com o espelho original'
FROM {{staging}}.int_ponto_diario
WHERE status_dia = 'REGISTRO_INVALIDO'

UNION ALL
-- 11. Código de abono com grafia fora do padrão
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  'CODIGO_ABONO_NAO_PADRONIZADO', 'INFO',
  codigo_abono_original,
  CONCAT('Padronizado para ', codigo_abono)
FROM {{staging}}.stg_ponto
WHERE codigo_abono_original != codigo_abono

UNION ALL
-- 12. Declaração de horas cobrindo o dia inteiro (abono parcial usado como integral)
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  'ABONO_REQUER_VALIDACAO', 'ALTA',
  codigo_abono,
  'Tratado como abonado (benefício da dúvida); BP deve confirmar a cobertura da declaração'
FROM {{staging}}.int_ponto_diario
WHERE fl_abono_requer_validacao

UNION ALL
-- 13. flag_dsr = 1 em dia com jornada cumprida
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  'FLAG_DSR_INCONSISTENTE', 'INFO',
  CONCAT('flag_dsr=1 em ', dia_semana, ' com jornada de ', CAST(jornada_esperada_horas AS STRING), 'h'),
  'Ignorado: o DSR é derivado da semana (seg-dom), não do flag'
FROM {{staging}}.int_ponto_diario
WHERE flag_dsr = 1 AND jornada_esperada_horas > 0

UNION ALL
-- 14. Trabalho em dia de descanso (hora extra; fora do escopo de desconto)
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  'TRABALHO_EM_DIA_DE_DESCANSO', 'INFO',
  CONCAT(CAST(horas_trabalhadas AS STRING), 'h em ', dia_semana),
  'Sem impacto no desconto; sinalizado para gestão de horas extras'
FROM {{staging}}.int_ponto_diario
WHERE status_dia = 'TRABALHO_EM_DESCANSO'

UNION ALL
-- 15. Déficit pequeno absorvido pela tolerância da CLT
SELECT
  'espelho_ponto', id_colaborador, data_registro,
  'DEFICIT_DENTRO_DA_TOLERANCIA', 'INFO',
  CONCAT(CAST(minutos_deficit AS STRING), ' min'),
  'Não descontado (CLT art. 58 §1º: até {{tolerancia_minutos}} min/dia)'
FROM {{staging}}.int_ponto_diario
WHERE status_dia = 'PRESENTE' AND minutos_deficit > 0
)

SELECT
  *,
  -- para ordenar e contar no painel
  CASE severidade WHEN 'ALTA' THEN 1 WHEN 'MEDIA' THEN 2 ELSE 3 END AS ordem_severidade,
  CASE WHEN severidade = 'ALTA'  THEN 1 ELSE 0 END AS qtd_alta,
  CASE WHEN severidade = 'MEDIA' THEN 1 ELSE 0 END AS qtd_media,
  CASE WHEN severidade = 'INFO'  THEN 1 ELSE 0 END AS qtd_info
FROM ocorrencias;
