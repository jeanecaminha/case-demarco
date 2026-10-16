# Painel no Looker Studio

Link: https://datastudio.google.com/reporting/52f463dd-8798-4f54-a870-84cdcafe403c

O painel tem 4 páginas e segue a ordem das perguntas da diretoria: quanto custa, quando as faltas acontecem, quem precisa de ação e quanto dá para confiar nos números.

## Fontes

Conector do BigQuery, projeto `desafio-demarco`, dataset `rh_marts`, usando as credenciais da dona do relatório. Assim quem abre o painel não precisa de acesso ao projeto.

| Fonte | Usada nas páginas |
|---|---|
| `mart_absenteismo_colaborador` | 1 e 3 |
| `fct_ponto_diario` | 1 e 2 |
| `mart_qualidade_dados` | 4 |

As tabelas já chegam com contadores de 0 ou 1 (`qtd_faltas_injustificadas`, `qtd_suspensao`, `qtd_alta` etc.) e com rótulos prontos, como `colaborador` no formato "Nome (ID)" e `dia_semana_ordem` de "1 Seg" a "7 Dom". O painel só soma; as regras ficam no SQL.

Os únicos campos calculados no painel são dois percentuais, porque percentual não se soma linha a linha:

```
Taxa de absenteísmo injustificado = SUM(horas_faltadas_injustificadas) / SUM(horas_previstas)
% faltas em segunda ou sexta = SUM(qtd_faltas_segunda_ou_sexta) / SUM(qtd_faltas_injustificadas)
```

## Páginas

**1. Visão executiva.** Desconto total em destaque (R$ 11.083,27), faltas, DSRs perdidos, colaboradores com ação e taxa de absenteísmo. Abaixo: desconto por departamento separado em faltas, atrasos e DSR; desconto por gestor; evolução por semana; e quanto cada parte pesa no total.

**2. Padrão de emenda.** Responde à suspeita do briefing sobre segundas e sextas: 90% das faltas caem nesses dias. Tem faltas por dia da semana, um mapa de calor de departamento por dia, outro de semana por departamento e a lista de quem mais falta em segunda ou sexta.

**3. Ações disciplinares.** Quantas pessoas em cada nível da régua e a tabela por colaborador, ordenada pela gravidade da ação e pelo desconto. As suspensões aparecem em vermelho. A coluna "Dias c/ atraso" explica por que alguém sem faltas pode ter desconto: o atraso entra no custo, mas não na régua.

**4. Qualidade dos dados.** As 291 ocorrências separadas por severidade (20 alta, 21 média, 250 informativas), a contagem por tipo e o detalhe de cada uma, com o valor encontrado e o que foi feito.

Os filtros de Departamento e Gestor ficam no topo de todas as páginas.

## Escolhas de design

- O número que mais importa, o desconto total, fica sozinho num cartão escuro no topo.
- O custo aparece sempre dividido em faltas, atrasos e DSR, com as mesmas cores em todas as páginas. O DSR é 42% do desconto e era o item que os gestores não calculavam.
- Pessoas aparecem como "Nome (ID)", porque a base tem homônimos.
- A tabela de ações marca quando o custo usou salário ou escala estimados, para ninguém aplicar uma suspensão sem saber disso.
- Onde os nomes são longos (gestores, tipos de ocorrência), usei tabela com barra no lugar de gráfico de barras, para o nome aparecer inteiro.

## Visual

O fundo de cada página é uma imagem gerada por `docs/dashboard/gerar_fundos.py` (cabeçalho, cartões e títulos). Os gráficos do Looker Studio ficam por cima, com fundo transparente. Para mudar um título, edite o script, rode `python docs/dashboard/gerar_fundos.py` e troque a imagem da página.

Fonte Roboto. Cores fixas: faltas `#2a78d6`, atrasos `#1baf7a`, DSR `#eb6834`. Severidade alta em vermelho e média em âmbar.

## Compartilhamento

O relatório está aberto para qualquer pessoa com o link, só para visualização.
