# #641 · Intenção de fechar do Construtor sem regex

## Onde estava

`Autonomia::Agents::Builder` (o Construtor, meta-agente que cria e ajusta agentes) lia a última fala do
dono com `CLOSE_INTENT_PATTERNS` e `CLOSE_INTENT_NEGATION` em `close_intent?`. Regra do Rodrigo de
20/09/2026: regex não interpreta fala de pessoa.

Alcance real: só o Construtor. O único chamador de produção é `Builder::SubmitJob`, disparado pelo
`BuildThreadsController`. A conversa dos agentes em operação (Lia, especialistas de auto, residencial e
empresarial) não passa por aqui. `InstructionRefresher` reusa `MOTHER_INSTRUCTION`, que não mudou, com
schema próprio.

## Os quatro usos e o efeito de cada um

| Uso | Quando | Efeito quando dava verdadeiro |
|---|---|---|
| `closing_phase?` | antes da chamada | escolhia `BUILDER_REASONING_EFFORT_FINAL` em vez de `COLLECT` |
| `force_close?` | depois do parse | virava um `needs_more_info=true` teimoso em `false` (fecha o agente) |
| `force_materials_gate!` | depois do parse | não reabria a entrevista por material `needs_resend` |
| `unanswered_question` | no fechamento | escrevia no `human_card` a pergunta que ficou aberta |

## Decisão

Campo novo `user_asked_to_close` no `BUILDER_SCHEMA` (strict, obrigatório): a leitura do modelo sobre
a última fala. `false` é a saída "não se aplica"; ausente conta como `false`. Sem ferramenta nova e sem
chamada extra: o modelo já responde o turno, só passa a declarar o que entendeu. É um campo separado de
`needs_more_info`, então o portão continua cobrindo o modelo que entende a ordem mas hesita em fechar.

`closing_phase?` deixou de olhar a intenção, porque ela só existe depois da chamada. Sem efeito hoje:
`COLLECT` e `FINAL` são os dois `'medium'`.

## Validação

- Base `origin/main` (c80b86d39b): `spec/services/autonomia spec/requests/api/v1/accounts/autonomia
  spec/jobs/autonomia` com 3161 exemplos e 1 falha (`quote_agent_spec.rb:68`, conhecida, corrigida na #716).
- Depois: 3168 exemplos e a mesma falha, nenhuma nova. `builder_spec.rb`: 24 exemplos, 0 falhas.
- Mutação: sete quebras no código, cada uma reprovada por pelo menos um spec, e o código restaurado
  (md5 conferido).
- Avaliação paga (`builder_close_intent_eval_spec.rb`, `AUTONOMIA_EVAL_PAGO=1`), com o modelo e o input
  reais do Construtor: 11 falas (5 ordens de fechar, inclusive em inglês; 4 que não são ordem, inclusive
  negação e "não tenho material"; 2 pedidos de ajuste com "pode criar"), todas lidas certo.
