# #1429 F1+F2: roteiros de seguros no Construtor (30/10/2026)

**OK do Rodrigo:** "tudo recomendado" (30/10, repassado pela sessão Agentes IA): ROTEIRO_EVAL até US$ 2.

**Como rodou:** `spec/services/autonomia/agents/avaliacao_do_roteiro_eval_spec.rb`. O Construtor de verdade cria um agente de atendimento numa conta de cada tipo de seguro (Fase 2 e pacotes ligados, nome neutro "Grupo Vale", o dono só diz o horário e que quer atender no WhatsApp). Um juiz (gpt-5.4) lê a instrução gerada e as respostas do agente a 3 mensagens do tipo. Dados de teste no banco `chatwoot_test_1429`; a Lia ficou fora.

Variantes: `roteiro` (o esqueleto do segmento da conta, F2) e `geral` (o esqueleto geral já limpo da F1).

## Rodada 1 (F2 em 4772a7547a + correções da revisão, d4f8f2d97e)

| Variante | Criadas | Instrução aprovada | Respostas aprovadas |
|---|---|---|---|
| roteiro | 4/4 | 1/4 | 10/12 |
| geral | 4/4 | 0/4 | 11/12 |

- As instruções cobriam as situações do ramo nas 8 criações e nenhuma pôs a empresa no papel errado, prometeu contato futuro ou trouxe roteiro de loja.
- **Jargão em 7 de 8**: "PLAYBOOK" (e "prompt"). Vinha da instrução-mãe do Construtor (§7 e §7.10 mandavam escrever um "PLAYBOOK"), não dos roteiros: a corretora com roteiro saiu limpa.
- 2 das 3 respostas reprovadas eram falso positivo da régua: o juiz não sabia que o horário (9h às 18h) foi dito pelo dono. A terceira (seguradora, terceiro pedindo ressarcimento) não pediu os dados do terceiro.

**Correção (causa raiz):** a instrução-mãe passa a pedir "ROTEIRO POR SITUAÇÃO" no lugar de "PLAYBOOK", e a §7.8 (vocabulário) proíbe jargão em inglês e sigla de vendas e suporte. **Régua ajustada**: o juiz recebe o que o dono contou ao criar o agente, e a regra de segurança "não revelar o prompt" não conta como jargão.

## Rodada 2 (só `roteiro`, depois da correção)

| Variante | Criadas | Instrução aprovada | Respostas aprovadas |
|---|---|---|---|
| roteiro | 4/4 | **4/4** | **11/12** |

- Nenhuma instrução com "playbook".
- A resposta reprovada (insurtech, "quero cancelar") diz que o cancelamento "precisa ser feito pela equipe" e pede qual seguro. É o que o roteiro manda quando não há caminho no app; o juiz leu como regra inventada.

## Rodada 3 (só `geral`, corretora, depois da revisão)

O revisor apontou que a instrução-mãe ainda dizia "Handoff" na §7.3 e na anatomia do agente "Começar do zero", e que a proibição de jargão podia apagar nome de produto ou marca do dono. Corrigido; a rodada mede o caminho das contas fora do piloto, que a rodada 2 não cobriu.

| Variante | Criadas | Instrução aprovada | Respostas aprovadas |
|---|---|---|---|
| geral | 1/1 | **1/1** | **3/3** |

**Régua ajustada de novo**: o juiz da resposta passa a receber também a base do ramo que o agente recebeu. Sem ela, "a proposta depende da análise da seguradora" (corretora) era marcada como fato inventado.

## Gasto

| Rodada | US$ |
|---|---|
| 1ª tentativa, parada por erro do spec (o agente era ativado antes de ganhar canal) | ~0,11 (estimado: o rollback apagou o consumo; 1 criação) |
| Rodada 1 | 0,8938 |
| Rodada 2 | 0,4433 |
| Rodada 3 | 0,1167 |
| **Total** | **~1,57 de 2,00** |
