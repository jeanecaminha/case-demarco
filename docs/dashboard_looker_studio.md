# Dashboard no Looker Studio (Data Studio)

O painel responde, nesta ordem, às perguntas da diretoria: **quanto custa → onde está → quando acontece → quem precisa de ação → quanto confiar nos números**. Cada página responde a uma delas.

Relatório: **Absenteísmo e Custo de DSR — Case DeMarco** (4 páginas, canvas 1440 × 1160): https://datastudio.google.com/reporting/52f463dd-8798-4f54-a870-84cdcafe403c

## 1. Fontes de dados

Conector BigQuery, projeto `desafio-demarco`, dataset `rh_marts`, com as credenciais do proprietário:

| Fonte | Tabela | Usada em |
|---|---|---|
| `mart_absenteismo_colaborador` | `rh_marts.mart_absenteismo_colaborador` | Páginas 1 e 3 |
| `fct_ponto_diario` | `rh_marts.fct_ponto_diario` | Páginas 1 e 2 |
| `mart_qualidade_dados` | `rh_marts.mart_qualidade_dados` | Página 4 |

Os marts já trazem **contadores 0/1** (`qtd_faltas_injustificadas`, `qtd_suspensao`, `qtd_alta` etc.) e rótulos prontos (`colaborador` = `Nome (ID)`, `dia_semana_ordem` = `1 Seg`…`7 Dom`, `alerta_dado_estimado`). Assim, o BI só soma: a regra de negócio fica no SQL, versionada e testada.

Só dois campos calculados ficam no Looker, porque são razões e não podem ser somadas linha a linha:

```
-- fonte mart_absenteismo_colaborador (formato: percentual)
Taxa de absenteísmo injustificado = SUM(horas_faltadas_injustificadas) / SUM(horas_previstas)

-- fonte fct_ponto_diario (formato: percentual)
% faltas em segunda ou sexta = SUM(qtd_faltas_segunda_ou_sexta) / SUM(qtd_faltas_injustificadas)
```

Na fonte `mart_absenteismo_colaborador`, os campos exibidos foram renomeados (Colaborador, Departamento, Gestor, Ação recomendada, Faltas, DSRs perdidos, DSRs seguidos, Desconto, Dado estimado).

## 2. Visual

- **Fundo de cada página** é uma imagem gerada por [`dashboard/gerar_fundos.py`](dashboard/gerar_fundos.py): faixa de cabeçalho navy, cartões brancos com título e subtítulo, e o cartão de destaque escuro. Os gráficos nativos ficam por cima, com fundo transparente. Para mudar textos ou layout, edite o script e rode `python docs/dashboard/gerar_fundos.py` (requer Chrome); depois troque a imagem em cada página.
- Tema: fonte Roboto, fundo `#F3F4F6`. As cores dos componentes são fixas em todas as páginas: faltas `#2a78d6`, atrasos `#1baf7a`, DSR `#eb6834`.
- Severidade: ALTA em vermelho (`#9B1C1C` sobre `#FDECEC`), MÉDIA em âmbar (`#8A5A00` sobre `#FEF5E1`), INFO neutra.
- Controles **Departamento** e **Gestor** no cabeçalho de todas as páginas.

## 3. Páginas

### Página 1: Visão executiva (diretoria)

| Bloco | Componente |
|---|---|
| KPIs | **Desconto total** R$ 11.083,27 (cartão de destaque) · Faltas injustificadas 30 · DSRs perdidos 30 · Com ação disciplinar 10 · Taxa de absenteísmo 1,31% |
| Onde está o custo | Colunas empilhadas por departamento: faltas, atrasos e DSR perdido |
| Custo por gestor | Tabela com barra de desconto, faltas e quantidade de colaboradores com ação |
| Evolução semanal | Colunas empilhadas por `semana_inicio` (segunda a domingo), mesmos três componentes |
| Composição do desconto | Valores de faltas (R$ 5.437,54), atrasos (R$ 1.025,89) e DSR (R$ 4.619,79) |

### Página 2: Padrão de emenda de fim de semana

| Bloco | Componente |
|---|---|
| KPIs | % das faltas em segunda ou sexta **90%** · faltas na segunda 16 · faltas na sexta 11 · faltas coladas à folga 21 |
| Faltas por dia da semana | Colunas por `dia_semana_ordem` |
| Departamento × dia da semana | Tabela dinâmica com mapa de calor |
| Recorrência semana a semana | Tabela dinâmica `Semana de` (dd/MM) × departamento, com mapa de calor |
| Quem mais emenda | Tabela com barra: faltas em segunda ou sexta vs. faltas no total, por colaborador |

### Página 3: Ações disciplinares (BPs e gestores)

- KPIs por nível da régua: Suspensão 7 · Advertência escrita 2 · Alinhamento em 1-on-1 1 · Sem ação 30.
- Tabela de recomendações por colaborador, ordenada por `nivel_acao` desc e desconto desc: Colaborador, Departamento, Gestor, Ação recomendada, Dado estimado, Faltas, Dias c/ atraso, DSRs perdidos, DSRs seguidos, Desconto. Linhas de suspensão destacadas em vermelho.
- A coluna **Dias c/ atraso** explica por que quem tem 0 faltas pode ter desconto: atrasos e saídas antecipadas acima da tolerância de 10 min entram nas horas faltadas descontadas, mas não contam na régua disciplinar (que considera só faltas injustificadas).

### Página 4: Qualidade dos dados

- KPIs: 291 ocorrências tratadas · 20 de severidade ALTA · 21 MÉDIA · 250 informativas.
- **Ocorrências por tipo**: tabela com barra (`tipo_ocorrencia` × quantidade), com linhas coloridas por severidade.
- **Detalhe das ocorrências**: Severidade, Ocorrência, ID, Data, Valor encontrado, Tratamento aplicado e Qtd, ordenado por severidade. As linhas ALTA ficam destacadas.

## 4. Compartilhamento

**Compartilhar → Gerenciar acesso → Qualquer pessoa com o link pode ver**. As fontes usam as **credenciais do proprietário** (padrão do conector BigQuery), para que a banca não precise de acesso ao projeto GCP.

## 5. Decisões de usabilidade

- **Hierarquia**: os números absolutos ficam no topo e o detalhe por pessoa fica na página 3. A diretoria lê a página 1 em menos de 30 segundos.
- **Decomposição do custo** (faltas × atrasos × DSR): o DSR responde por cerca de 42% do desconto, e era justamente o item que os líderes não calculavam.
- **Gestor com ID** (`Nome (EMP_xxx)`): a base tem homônimos, e agrupar só pelo nome misturaria pessoas diferentes.
- **Sinal de dado estimado** na tabela de ações: um BP não deve aplicar uma suspensão sem saber que o salário usado no custo foi imputado.
- **Tabela com barra em vez de barras horizontais** quando os rótulos são longos (gestores, tipos de ocorrência): o rótulo aparece inteiro e o número fica ao lado da barra.
