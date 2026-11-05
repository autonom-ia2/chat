# F9 · Converter os motores antigos para a Automação livre (#2568, épico #2414)

Desenho de 05/11/2026, começado em paralelo às fases F6 a F8 a pedido do Rodrigo (+50% de velocidade sem perder qualidade). Ainda não aprovado. Nesta fase não há código de produção e nenhuma escrita em lugar nenhum.

- **Aceite:** F9.1 a F9.5 (`docs/automacao/termos-de-aceite-F1-F9.md`).
- **Decisão de base:** ADR-001, D12. A conversão é obrigatória, feita conta a conta, com o OK do Rodrigo. O antigo é desligado e nunca apagado. Depois de um prazo, fecha a criação de regra nova nos motores antigos.
- **Gerador do relatório (F9.1):** `Autonomia::Automacao::Conversao::Relatorio` e o rake `autonomia:automacao:conversao:relatorio[conta]`. Só leem. Ver a seção 3.

## 1. O que existe em produção (leitura agregada de 05/11)

A leitura foi feita pela Orquestração Deploy, só leitura (`BEGIN TRANSACTION READ ONLY` … `ROLLBACK`), nas duas stacks. Ela trouxe só ids de conta, contagens e chaves técnicas. Nenhum nome, texto ou valor.

**Stack hub2you: 34 regras em 3 contas, 27 delas ligadas. Nenhuma automação de etapa.**

| Conta | Regras | Ligadas | Molde | Autor conhecido (audit) |
|---|---|---|---|---|
| 17 | 26 | 26 | conversa criada + caixa igual a X → atribuir à pessoa | 0 de 26 |
| 6 | 7 | 0 | conversa atualizada + atributo personalizado da conversa igual a X → pôr etiqueta | 7 de 7 |
| 16 (piloto) | 1 | 1 | mensagem criada + caixa + assunto do e-mail contém + tipo da mensagem → criar card + perguntar ao Decisor | 1 de 1 |

Nas duas stacks:
- nenhuma regra tem espera (`execution_delay`);
- não há execução pendente em `automation_rule_pending_executions`;
- o motor novo tem 1 automação, manual e desligada.

**Stack autonomia: 12 automações de etapa em 2 contas, todas "entrou na etapa", ligadas e com autor. Nenhuma regra.**

| Conta (ids da stack autonomia) | Automações | Passos |
|---|---|---|
| A | 11 | 24 retornos, 23 deles com atraso |
| B | 1 | 1 troca de responsável |

**Conclusão:** o universo real é pequeno. São 34 regras e 12 automações de etapa.
- As 26 regras da conta 17 convertem hoje, sem falta nenhuma.
- As outras 8 regras e as 12 automações de etapa esperam peças das fases F6, F7 e "F9.0" (seção 4).

Este doc não junta o número da conta com nome de atributo, texto ou valor, porque o repo é público.

## 2. O mapa: do antigo para o novo

Uma regra antiga vira **uma** automação. As peças se traduzem assim:
- o evento vira o gatilho;
- as condições viram o filtro do gatilho;
- cada ação vira um passo, na mesma ordem.

Uma automação de etapa também vira uma automação, com um passo para cada passo dela.

A automação nova nasce com:
- `origem: 'conversao'`;
- o mesmo nome;
- a versão 1 com a receita;
- `ativa: false` até a troca (seção 5).

O mapa vive em `app/services/autonomia/automacao/conversao/mapa.rb`. O relatório e o conversor leem dele, para nunca dizerem coisas diferentes.

### 2.1 Gatilhos

| Antigo | Novo | Hoje |
|---|---|---|
| `conversation_created` | `conversa.criada` | na main |
| `conversation_opened` | `conversa.aberta` | na main |
| `conversation_resolved` | `conversa.resolvida` | na main |
| `message_created` | `mensagem.criada` | na main |
| `conversation_updated` | — | **falta**: gatilho "conversa atualizada", com o que mudou (proposta para o PR2d da F6) |
| etapa `on_enter` | `card.entrou_na_etapa` + `etapa_id` | #2554 (F6) |
| etapa `on_exit` | `card.saiu_da_etapa` + `etapa_id` | #2554 (F6) |

**Ressalva da etapa:** o `card.entrou_na_etapa` novo também dispara quando o card **nasce** na etapa. O antigo não dispara, porque o `Crm::Cards::Creator` não chama o `Runner`.
- Converter direto mudaria o comportamento.
- Saída proposta: um parâmetro do gatilho, "só quando o card é movido", na F6, usado pela conversão.
- Pergunta à sessão F6, P4 abaixo.

### 2.2 Condições

No antigo, o `query_operator` de cada condição a liga à próxima, e o filtro vira SQL na ordem em que as condições estão. Assim o AND pesa mais que o OR: `a AND b OR c` é `(a e b) ou c`.
- A conversão corta a lista no OR: `alguma[todas[a, b], c]`.
- Uma condição com vários valores, como "caixa igual a [1, 2]", vale qualquer um deles: `alguma[igual 1, igual 2]`.
- Com "diferente", vale para todos: `todas[...]`.

| Chave antiga | Caminho novo |
|---|---|
| `inbox_id`, `status`, `priority`, `assignee_id`, `team_id` | `conversa.caixa_id`, `.status`, `.prioridade`, `.responsavel_id`, `.time_id` |
| `labels` | `conversa.etiquetas` (lista: igual vira `contem`) |
| `email`, `phone_number` | `contato.email`, `contato.telefone` |
| `message_type` (incoming/outgoing) | `mensagem.tipo` (recebida/enviada), só no gatilho `mensagem.criada` |
| `private_note` | `mensagem.privada`, só no gatilho `mensagem.criada` |
| `crm_pipeline_id`, `crm_stage_id`, `crm_card_status` | `card.funil_id`, `card.etapa_id`, `card.status` |
| atributo personalizado da conversa ou do contato | `conversa.atributos.<chave>`, `contato.atributos.<chave>` |
| `mail_subject`, `content`, `city`, `company_name`, `country_code`, `browser_language`, `conversation_language`, `referer` | **falta**: o motor novo não tem esses valores |
| `sla_policy_id` (EE) | **falta**, sem fase |

| Operador antigo | Novo |
|---|---|
| `equal_to` / `not_equal_to` | `igual` / `diferente` (em lista: `contem` / `nao_contem`) |
| `is_present` / `is_not_present` | `preenchido` / `vazio` |
| `contains` / `does_not_contain` em texto | **falta** (ver a nota abaixo) |
| `starts_with` | **falta** |
| `attribute_changed` (de → para) | **falta**: precisa dos valores do evento (`evento.*`, PR2d da F6) |

**Nota:** o `contem` novo pergunta se um item está na lista. O `contains` antigo pergunta se um pedaço está no texto. Os dois parecem iguais e não são. O conversor nunca troca um pelo outro. A regra fica com a falta `operador_texto`.

### 2.3 Ações das regras

| Ação antiga | Passo novo | Hoje |
|---|---|---|
| `assign_agent [id]` / `assign_team [id]` | ação `POST conversations/:conversation_id/assignments` (`assignee_id` / `team_id`) | na main |
| `remove_assigned_agent` / `remove_assigned_team`, `assign_* ['nil']` | a mesma rota, com o valor vazio | na main, com ressalva: conferir na F9.2 que a rota tira o responsável |
| `assign_agent ['last_responding_agent']` | — | falta, F9.0 |
| `add_label` / `remove_label` | ação `PATCH …/labels/alterar` (`por` / `tirar`) | na main |
| `change_status`, `resolve`, `open`, `pending_conversation` | ação `POST conversations/:id/toggle_status` | na main |
| `snooze` | `toggle_status` com `snoozed` | ressalva: o antigo adia até a próxima mensagem; o novo aceita prazo |
| `change_priority` | ação `POST conversations/:id/toggle_priority` | na main |
| `send_message` (texto puro) | passo `mensagem` | na main (F4, flag `automacao_mensagens`) |
| `send_message` com variável Liquid (`{{…}}`) | passo `mensagem` com valores estruturados | o conversor monta à mão de quem revisa, nunca adivinha |
| `add_private_note` | — | falta, F9.0 |
| `send_email_to_team` | — | falta: o `avisar` novo avisa pelo canal de avisos, não manda e-mail |
| `send_webhook_event` | passo webhook | F8 (#2499, PR4) |
| `crm_create_card`, `crm_move_card_stage`, `crm_mark_card_won/lost`, `crm_assign_card_owner` | passos de card | F6, PR2a' |
| `perguntar_ao_decisor [decisor, chave]` | passo `decidir`, com a pergunta e os caminhos copiados do Decisor salvo | F7 (#2500) |
| `mute`, `send_email_transcript`, `send_attachment`, `disable/enable_crm_ai_followup`, `add_sla` | — | sem equivalente nem fase; nenhuma conta usa hoje |
| `execution_delay` (espera por episódio) | `esperar` + `se` | falta, F9.0; nenhuma regra usa hoje |

### 2.4 Passos das automações de etapa

| Passo antigo | Novo | Fase |
|---|---|---|
| `create_follow_up` (atraso = vencimento) | ação `POST crm/follow_ups`, com o vencimento = agora + atraso (P3 da F6) | F6 |
| `assign_owner` (`owner_id`) | passo de card "responsável" | F6, PR2a' |
| `assign_owner` (`use_card_owner`) | — | falta, F9.0 |
| `move_stage` | passo de card "mover" | F6, PR2a' |
| `perguntar_ao_decisor` | `decidir` | F7 |
| atraso de passo que não é retorno | `esperar` antes do passo | na main, com ressalva: o job antigo não reconfere se a automação segue ligada, e o novo reconfere |

## 3. O relatório de conversão (F9.1)

`Autonomia::Automacao::Conversao::Relatorio.new(conta)` lê as regras e as automações de etapa da conta e devolve um `Resultado` para cada uma:
- a receita proposta;
- as faltas, cada uma com a fase;
- as ressalvas;
- se a antiga está ligada;
- se o autor é conhecido.

O `resumo` dá o "estas N viram estas N":
- antigas, ligadas e convertíveis agora;
- sem autor conhecido;
- faltas por fase.

**Uma antiga só é convertível sem falta nenhuma.** Uma regra pela metade quebraria o F9.2.

```
bundle exec rails "autonomia:automacao:conversao:relatorio[<conta>]"
```

O relatório não roda em produção, porque lá o acesso é só por psql. Os números reais saem da leitura agregada da seção 1. Na F9.3, o mesmo relatório aparece na tela da conversão, dentro do produto.

**Rodada no banco de teste** (`chatwoot_test_2568`, com `db:seed` e os moldes da seção 1, sem dado real): 34 antigas, 27 ligadas, 26 convertíveis agora.

```json
{ "antigas": 34, "ligadas": 27, "convertiveis_agora": 26,
  "faltas_por_fase": { "F6 (#2554)": 1, "F6 (P3: POST crm/follow_ups)": 1, "F6 PR2a'": 1, "F6 PR2d (proposta F9)": 7 } }
```

O spec (`spec/services/autonomia/automacao/conversao/relatorio_spec.rb`, 9 exemplos) confere quatro coisas:
- a receita do molde da conta 17 passa no esquema **e** na conferência do motor (`Receita#problemas`). Isso pegou um defeito do primeiro rascunho: faltava o `caminho` da ação;
- o relatório não grava nada;
- o agrupamento do AND e do OR está certo;
- o `contem` de texto nunca é traduzido.

## 4. O que falta e onde entra

Só entra o que uma conta de verdade usa (YAGNI). O resto fica "sem equivalente" e a regra continua no motor antigo até alguém precisar.

| Falta | Quem usa hoje | Fase |
|---|---|---|
| gatilho "conversa atualizada" + "o atributo mudou" | conta 6 (7 regras, desligadas) | PR2d da F6 (proposta) |
| gatilhos e passos de card, retorno | conta 16 e as 12 de etapa | F6 (#2554, PR2a') |
| `decidir` a partir de um Decisor salvo | conta 16 | F7 |
| assunto do e-mail como valor + "contém texto" | conta 16 | **F9.0**: o caminho `conversa.assunto_do_email` e um operador `contem_texto`, separado do `contem` de lista |
| "só quando o card é movido" | as 12 de etapa | F6 (P4) |
| último atendente que respondeu, nota privada, espera por episódio, `use_card_owner`, demais valores | ninguém | sem fase, até alguém pedir |

**F9.0** é um PR pequeno, só com os dois itens que a conta 16 pede. Ele entra depois do PR2a' da F6.

## 5. A troca de uma conta: desligar sem apagar, com backup

**Pergunta P1 ao Rodrigo (recomendação: sim).** Uma migration pequena, sozinha na fila, com a tabela `autonomia_automacao_conversoes`. Colunas:
- `account_id`;
- `antiga_tipo` e `antiga_id` (`AutomationRule` ou `Crm::StageAutomation`);
- `automacao_id`;
- `estado_antes` (jsonb, a linha antiga inteira);
- `convertida_por_id`, `convertida_em`, `revertida_em`;
- índice único em (`antiga_tipo`, `antiga_id`) enquanto não revertida.

O ADR-001 disse "F9 sem migration". Sem essa tabela, porém, o par antigo↔novo só existiria num arquivo de backup no servidor. Aí a trava da seção 7 e a reversão em minutos (seção 6) não teriam onde olhar enquanto o sistema roda.

**A troca é uma ação dentro do produto**, porque produção não aceita `rails runner`. Uma tela "Converter regras antigas" (F9.3) mostra o relatório da conta. O botão "Converter" vale só para:
- quem é administrador da conta;
- conta que já tem o OK do Rodrigo registrado na Issue.

**Passos, nesta ordem:**
1. **Backup antes.** A Orquestração Deploy tira a cópia das linhas da conta por psql, só leitura: `automation_rules`, `crm_stage_automations` e `crm_stage_automation_steps`. O arquivo fica com permissão 0600 em `/tmp/chat_f9_<conta>_<timestamp>.json` no host, como na regra 3 do Rodrigo. Além disso, a tabela guarda o `estado_antes` de cada antiga.
2. **Recusa** a conta que tenha espera armada (`automation_rule_pending_executions` aberta) ou passo de etapa com atraso na fila, ou que tenha alguma antiga com falta. Hoje nenhuma conta tem espera nem passo atrasado na fila.
3. **Numa transação só, por conta:**
   - trava as antigas (`FOR UPDATE`);
   - cria cada automação nova (versão 1, `ativa: false`);
   - grava a linha da conversão;
   - desliga a antiga (`active`/`enabled` = false), sem apagar nada;
   - liga a nova (`ativa: true`, `ligada_por`, seção 9).
4. **Limpa o cache** do gate "há automação ligada para esse gatilho nesta conta".

**Por que uma transação só resolve o F9.3 (nenhuma mensagem dupla):** os dois motores leem "ligada" na hora de processar o evento, não na hora em que ele foi enfileirado.
- Um evento processado antes do commit vê a antiga ligada e a nova desligada. Roda só a antiga.
- Um evento processado depois do commit vê o contrário. Roda só a nova.
- Nunca há janela com as duas ligadas, nem com as duas desligadas.

## 6. Reverter uma conta em minutos (F9.4)

O botão "Reverter conversão", no mesmo lugar, faz numa transação:
- `Definicao#desligar!` em cada nova, o que também para as execuções abertas;
- a antiga volta ao `estado_antes`;
- grava `revertida_em`.

A automação nova não é apagada: fica desligada, com o histórico.

**Plano B, se a tela estiver fora:** a mesma troca por psql, pela Orquestração Deploy, com os ids da tabela de conversões:
- desligar as novas (`ativa = false`) e fechar as execuções abertas, como o `desligar!` faz;
- religar as antigas.

O comando exato vai no runbook do PR da F9.2, escrito antes da primeira conta. Tempo estimado: menos de 5 minutos. É o rollback pré-aprovado da regra 3. Ainda assim, é escrita em produção, e por isso exige o OK do Rodrigo antes de virar runbook.

## 7. Antigo e novo nunca ligados juntos para a mesma coisa (F9.3)

Três travas, todas pela tabela de conversões:
1. **Ligar a nova** (`Definicao#recusa_para_ligar`) recusa com `antiga_ligada` se a antiga do par está ligada.
2. **Religar a antiga** pela API, pela tela ou pelo Guia: um prepend em `AutomationRule` e em `Crm::StageAutomation` recusa `active`/`enabled` = true enquanto houver conversão vigente. A mensagem diz "esta regra virou a automação X; reverta a conversão".
3. **Fila da etapa:** o `Crm::StageAutomationStepJob` não reconfere o `enabled`, então um passo atrasado já na fila rodaria depois da troca. A F9.2 faz o job reconferir, e a troca recusa conta com passo na fila (seção 5).

A cadeia comum (D6) já impede que as duas, cada uma num motor, se disparem em laço.

## 8. Um mês de comportamento igual (F9.2)

**Antes de ligar:** o ensaio histórico da F5 roda cada automação nova sobre os últimos 30 dias da conta. Ele compara o que ela faria com o que a antiga fez (atribuições, etiquetas, retornos). Diferença sem explicação bloqueia a troca.

**Durante 30 dias depois da troca:** uma leitura agregada semanal, por psql e só leitura, pela Orquestração. Para cada par:

| Medida | Antes (30 dias da antiga) | Depois (motor novo) |
|---|---|---|
| Disparos | conversas ou cards que atendiam ao filtro | execuções iniciadas |
| Efeito | atribuições, etiquetas e retornos criados | registros com sucesso por passo |
| Erros | — | execuções com erro, pausadas (`ligada_por` sem acesso) ou interrompidas |
| Duplas | — | conversas com mensagem de automação e de regra no mesmo minuto (tem de ser 0) |

- Os registros do motor novo ficam 30 dias (ADR 2.3). A leitura semanal cabe na janela.
- Divergência sem explicação, ou qualquer dupla: reverter a conta (seção 6) e abrir Issue.
- O mês só fecha com as quatro semanas limpas.

## 9. Quem vira `ligada_por` (parecer da sessão Funções personalizadas)

A regra antiga roda como "sistema", com todo o acesso. A nova roda como quem ligou (D1):
- reconferido a cada execução;
- quem não é admin só automatiza as caixas de que é membro (D5);
- passo de funil pede a chave de funis.

Opções:
- **a) Quem aperta "Converter"** (recomendada). É sempre o usuário logado, administrador da conta, como no "Assumir e religar" (F3.7). O autor do audit, quando existe, aparece só como informação. É a mesma regra que já vale para religar, e o admin tem todas as caixas.
- **b) O autor da regra** pelo audit do EE. Não serve: a conta 17 não tem autor em nenhuma das 26 regras, e quem criou pode ter perdido o acesso ou nem ser admin.
- **c) Um usuário "sistema".** Quebra o D1 e o histórico deixa de dizer quem.

Com a opção a), quando o admin sai da conta, a automação pausa e alguém usa "Assumir e religar". Não há troca silenciosa.

## 10. Fechar a criação nova nos motores antigos

Quando todas as contas estiverem convertidas e com o mês limpo, uma flag `automacao_antigo_fechado` (bit dado pela Orquestração) fecha a criação. Prazo proposto: 30 dias depois da última conversão (P2).
- O `create` de `automation_rules` e de `stage_automations` responde 422, com a frase "monte em Automações".
- O `update` só aceita desligar. O `index`, o `show` e o `destroy` seguem, como D12 pede: a API é preservada.
- O Guia (`porteiro_da_automacao`, que hoje grava `POST automation_rules`) passa a montar só no motor novo **antes** de a flag ligar.
- As telas `settings/automation` e o painel antigo da etapa saem do menu. A lista única mostra tudo no motor novo (F9.5).

## 11. Ordem dos PRs da F9

1. **Este PR, só docs:** o desenho e a leitura agregada.
2. **F9.1, o relatório:** mapa, `Resultado`, `Condicoes`, `DaRegra`, `DaEtapa`, `Relatorio`, rake e spec. Só leitura. Está commitado localmente, sem push, até o desenho ser aprovado.
3. **F9.2, a troca:** migration da tabela (P1), conversor, reversão, as três travas e o job da etapa reconferindo `enabled`.
4. **F9.3, a tela:** "Converter regras antigas" e "Reverter", com o relatório.
5. **F9.0:** os dois itens da conta 16, depois da F6 PR2a' e da F7.
6. **F9.5, o fechamento:** a flag, o Guia no motor novo e a saída das telas.

**Primeira conta (P3):** a 17 converte hoje sem falta, mas é cliente real. A recomendação é ensaiar primeiro numa conta piloto com o mesmo molde, montado à mão, e só depois converter a 17, com o OK do Rodrigo.

## 12. Perguntas abertas

- **P1 (Rodrigo):** a migration da tabela de conversões. Recomendação: sim.
- **P2 (Rodrigo):** o prazo para fechar a criação nova. Recomendação: 30 dias depois da última conversão.
- **P3 (Rodrigo):** a ordem das contas. Recomendação: a piloto antes da 17.
- **P4 (sessão F6):** o parâmetro "só quando o card é movido" no `card.entrou_na_etapa`.
- **P5 (Funções):** `ligada_por` = quem aperta "Converter" (seção 9).
- **P6 (Multifunnel):** as automações de etapa convertidas passam a sair pela `Crm::Activity` e pelo emissor, não mais pelo `Runner`.
  - O que o `Runner` fazia e a F6 precisa manter: profundidade 3, o `CardGuard` do mover e a marca `automacao:{origem:'etapa'}` que a IA do funil respeita (#2428).
  - A marca passa a ser `origem: 'livre'`. A IA do funil continua respeitando?
