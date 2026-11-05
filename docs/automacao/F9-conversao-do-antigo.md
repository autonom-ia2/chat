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

**Ressalva da etapa (corrigida pelo Multifunnel, 05/11).** O antigo **não** segue uma regra única sobre o card que nasce: depende do caminho. O `card.entrou_na_etapa` novo dispara em toda criação e em todo movimento que grava a atividade, então converter direto mudaria o comportamento nos dois sentidos.

| Caminho | Antigo (`Runner`) | Novo hoje (#2554) |
|---|---|---|
| Card criado pela Automação livre (`CardNaEtapa:63`) | dispara | dispara |
| Card criado pelo prospecting (`CrmCardConverter:79`) | dispara | dispara |
| Card criado pela IA de assunto numa etapa escolhida (`Etapa.entrar`) | dispara, **exceto** na 1ª etapa (`etapa.rb:38`) | dispara |
| Card da chegada pelo `CardSyncer` (Creator na etapa padrão) | **não** dispara | dispara |
| Card criado pela tela do Kanban ou pela API (`cards_controller` → `Creator`) | **não** dispara | dispara |
| Mover com `skip_automations: true` (card do aviso ou da chegada levado a outro funil, #1638, #1711) | **não** dispara, por decisão registrada | dispara: o Mover grava a atividade `move` assim mesmo |
| Movimento comum pelo Mover | dispara | dispara |

O maior risco está nas linhas do "não dispara". As 23 automações de retorno com atraso dariam um retorno a todo card da chegada.

**P4, combinada com a sessão Gatilhos (F6) em 05/11.** Nada de parâmetro escondido que só a conversão usa. A atividade do card grava o fato, e o gatilho o expõe como valor que qualquer automação pode filtrar:
- **Quem chama passa o caminho.** O `Creator` e o `Mover` recebem o caminho explícito (`applier_etapa`, `card_na_etapa`, `crm_card_converter`, `ia_assunto`, `sync`, `tela`, `api`…). Nada é deduzido no emissor. Na IA de assunto, a decisão de rodar vem depois do `Creator`, fora da trava (`etapa.rb:38`, Multifunnel).
- **Critério num lugar só:** `Crm::Cards::RodaAutomacoesDeEtapa.para(caminho, etapa)`, com o "sim só fora da 1ª etapa" do `Applier`. O `Runner` e a atividade leem o mesmo método.
- **A atividade grava** `origem` (o fato: `pessoa`, `ia_assunto`, `prospeccao`, `automacao`, `integracao`, `sem_automacoes`) e `roda_automacoes_de_etapa` (o critério).
- **O gatilho expõe** `evento.origem` e `evento.roda_automacoes_de_etapa` como valores fechados, do mesmo jeito que o `conversa.iniciada_por`. A conversão de uma automação de etapa gera `card.entrou_na_etapa` (etapa X) + o filtro `evento.roda_automacoes_de_etapa = sim`. A tela explica o filtro, e ele serve a qualquer automação nova.
- **Specs:** um por caminho, incluindo a IA de assunto na 1ª etapa, que não dispara.
- **Onde entra:** no PR2d da F6. Se a F9.2 precisar antes, a sessão Gatilhos separa só "caminho + `RodaAutomacoesDeEtapa` + atividade + valor" num PR pequeno, que o Multifunnel revisa. A F9.2 só precisa disso para as 12 automações de etapa (stack autonomia). A conta 17 não depende disso.
- "Só quando o card é movido" não serve: quebraria os três caminhos de criação que disparam. "Sempre" também não: quebraria as exclusões.

**Idempotência:** o antigo dedupa pelo `TriggerToken` (`enter:<etapa>:<entered_stage_at>`, `exit:<etapa>:<card>:<exited_at>`). O novo usa a marca `tipo:atividade:<id>` (#2554): o retry da atividade ou do emissor reusa o mesmo id e não abre outra execução. O spec da F9.2 confere que o retry não duplica o retorno.

**on_exit:** as 12 automações de produção são todas `on_enter`. O `card.saiu_da_etapa` existe na F6.

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

**Nota sobre campo vazio (qualidade, 05/11):** no antigo, `not_equal_to` vira `NOT IN (...)` no SQL (`filter_service.rb:179`), e campo vazio (NULL) não casa. Por exemplo, "time diferente de 3" numa conversa sem time **não** dispara. O `diferente` novo trata o vazio como texto vazio e casa. Por isso, em campo de valor único, o conversor gera `todas[preenchido, diferente …]`. Nas etiquetas não, porque o antigo usa `NOT EXISTS` e a conversa sem etiqueta casa nos dois.

**Nota sobre `attribute_changed`:** ele é avaliado em Ruby, à parte do SQL, e se junta às outras condições por interseção e união de listas, não pela precedência do AND e do OR. Hoje é falta. Quando o PR2d da F6 trouxer os valores `evento.*`, o conversor precisa dessa outra regra de precedência.

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

O spec (`spec/services/autonomia/automacao/conversao/relatorio_spec.rb`, 10 exemplos) confere cinco coisas:
- a receita do molde da conta 17 passa no esquema **e** na conferência do motor (`Receita#problemas`). Isso pegou um defeito do primeiro rascunho: faltava o `caminho` da ação;
- o relatório não grava nada;
- o agrupamento do AND e do OR está certo;
- o `contem` de texto nunca é traduzido;
- o `diferente` de campo único vai junto com `preenchido`, como o `NOT IN` antigo.

## 4. O que falta e onde entra

Só entra o que uma conta de verdade usa (YAGNI). O resto fica "sem equivalente" e a regra continua no motor antigo até alguém precisar.

| Falta | Quem usa hoje | Fase |
|---|---|---|
| gatilho "conversa atualizada" + "o atributo mudou" | conta 6 (7 regras, desligadas) | PR2d da F6 (proposta) |
| gatilhos e passos de card, retorno | conta 16 e as 12 de etapa | F6 (#2554, PR2a') |
| `decidir` a partir de um Decisor salvo | conta 16 | F7 |
| assunto do e-mail como valor + "contém texto" | conta 16 | **F9.0**: o caminho `conversa.assunto_do_email` e um operador `contem_texto`, separado do `contem` de lista, com `include?` sobre o texto em minúsculas, sem regex (Automação, 05/11) |
| `evento.roda_automacoes_de_etapa` e `evento.origem` | as 12 de etapa | F6 PR2d (P4) |
| último atendente que respondeu, nota privada, espera por episódio, `use_card_owner`, demais valores | ninguém | sem fase, até alguém pedir |

**F9.0** é um PR pequeno, só com os dois itens que a conta 16 pede. Ele entra depois do PR2a' da F6.

## 5. A troca de uma conta: desligar sem apagar, com backup

**P1, decidida pelo Rodrigo em 05/11:** "pode criar tabela nova sem problemas... só cuide para ela ser o mais eficiente possível". Uma migration, sozinha na fila e com versão única, com uma tabela só.

`autonomia_automacao_conversoes`, o par e o backup:

| Coluna | Para quê |
|---|---|
| `account_id` | a conta; primeira coluna do índice único |
| `antigo_tipo`, `antigo_id` | a antiga (`AutomationRule` ou `Crm::StageAutomation`) |
| `definicao_id` | a automação nova |
| `estado_antes` (jsonb) | a linha antiga inteira, o backup que a reversão restaura |
| `created_at`, `updated_at` | `created_at` é o instante da conversão (o `convertida_em` das seções abaixo) |

- **Índice único** em (`account_id`, `antigo_tipo`, `antigo_id`). Ele é a própria trava: uma antiga tem no máximo uma conversão vigente. É também o índice que o motor antigo consulta ("esta regra foi convertida?").
- **Índice** em `definicao_id`, que é o que o motor novo consulta.
- Nada que dê para derivar. Quem converteu fica na Issue (o OK do Rodrigo) e no `ligada_por` da nova. A reversão apaga a linha (seção 6), então não há `revertida_em`.

**A reivindicação não precisa de tabela nova.** A tabela de execuções do motor novo já tem o índice único (`automacao_id`, `evento`). O antigo reivindica o fato gravando, para a automação do par, uma execução terminal num estado novo, `do_antigo`, com o mesmo `evento` (5.1). A mesma migration acrescenta `do_antigo` à lista do CHECK `chk_autonomia_automacao_execucoes_finalizada`. A execução fica 90 dias, bem mais que o retry máximo do Sidekiq.

A linha `do_antigo` é gravada como uma execução de verdade: `versao_id` = a versão ligada, e `alvo` e `chave_gatilho` reais, porque são NOT NULL. A F9.2 também põe `do_antigo` em `Execucao::ESTADOS` e `TERMINAIS`, além do CHECK.

**Quem lê execuções passa a ver essas linhas** (qualidade, 05/11). A F9.2 decide e cobre com spec cada leitor:

| Leitor | Tratamento proposto |
|---|---|
| `Historico` e `LivreHistorico.vue` (frase por estado) | mostra "feito pela regra antiga" (frase em en e pt_BR) |
| contagens da lista (`useCriadasPeloGuia.js`, `AutomacoesPage`) | não conta como execução da nova |
| custos da IA (#2571, `custos_da_automacao`) | fica fora: a linha não tem custo |
| `VarreduraJob` | não acorda: já nasce terminal (`finalizada_em` preenchida) |
| `Partida`, `Executor`, `Escuta` | a `Partida` recebe o conflito do índice e não abre outra; o `Executor` nunca vê a linha, porque ela é terminal |
| `LimparRegistrosJob` e a retenção de 90 dias | igual às outras |
| `ExclusaoDaConta` | apaga junto, igual às outras |

**A troca é uma ação dentro do produto**, porque produção não aceita `rails runner`. Uma tela "Converter regras antigas" (F9.3) mostra o relatório da conta. O botão "Converter" vale só para:
- o administrador da conta (parecer de Funções, seção 9);
- conta que já tem o OK do Rodrigo registrado na Issue.

### 5.1 Quem cuida de cada fato: o instante do fato, não o "ligada agora"

A primeira versão deste doc dizia que uma transação bastava, porque os dois motores leem "ligada" na hora de processar. A qualidade mostrou que não basta (05/11). Três furos:
- **Mesmo evento, dois listeners em série:** o `EventDispatcherJob` chama o `AutomationRuleListener`, que lê a regra ligada antes do commit. Depois o `AutomacaoListener` lê a nova ligada depois do commit. As duas rodam.
- **Mesmo movimento, dois caminhos:** o `Mover` chama o `Runner` na hora, antes do commit. A `Crm::Activity` do mesmo movimento vai pelo emissor ao `EventoDoCardJob`, que roda depois do commit. As duas rodam.
- **O inverso:** o evento enfileirado antes da troca chega ao antigo depois do commit (vê desligada). O novo já o tinha pulado, porque o gate ou o cache dizia "sem assinante". Nenhuma roda.

**A regra:** cada fato tem um dono, decidido pelo instante do fato contra o par na tabela de conversões.
- Fato com instante antes de `convertida_em` (o `created_at` da linha): só o antigo, mesmo que ele processe depois.
- Fato com instante em ou depois de `convertida_em`: só o novo.
- Sem linha (nunca convertida, ou revertida): só o antigo.

**O instante do fato:**
- `created_at` da mensagem, nos eventos de mensagem;
- `created_at` da `Crm::Activity`, nos de card;
- o instante do despacho do evento, nos eventos de conversa (o mesmo da marca `Gatilhos.marca_do_despacho`).

**Quem consulta o par:**
- o antigo: um prepend no `AutomationRuleListener` e no `Runner` decide pela tabela, e não pelo `active`/`enabled`, para as regras com conversão;
- o novo: a `Partida` recusa o fato anterior a `convertida_em`, com o motivo `antes_da_conversao`. Isso evita que a execução `do_antigo` e a do novo disputem o índice por um fato que é claramente do antigo.

**Por que a decisão não cruza a troca:** a decisão do antigo e a troca se serializam por um advisory lock da conta no Postgres.
- O antigo decide com o lock compartilhado.
- A troca pega o exclusivo e só então grava `convertida_em`.
- Assim, todo fato que o antigo decidiu "sem conversão" tem instante anterior a `convertida_em`, e o novo o recusa.
- Custo: um `pg_advisory_xact_lock_shared` por decisão, nas contas com regra antiga.

**O relógio: o instante decide quem pode; a reivindicação decide quem faz (qualidade, 05/11).** O `created_at` do fato vem do relógio do container que o criou, e o `convertida_em` vem do relógio de outro. Com um container 2 s adiantado, um fato anterior à troca ganha instante ≥ `convertida_em`. O antigo, que decidiu antes sob o lock, roda; o novo também. Medir não evita essa dupla.
- Por isso cada fato é **reivindicado** no índice único (`automacao_id`, `evento`) das execuções, com a automação do par:
  - o novo já grava a execução com esse `evento` (a marca do #2494);
  - o antigo grava uma execução terminal `do_antigo`, com o mesmo `evento`, antes de agir.
- Cada motor só executa se o `INSERT … ON CONFLICT DO NOTHING` dele devolver a linha.
- A dupla fica impossível por construção. O lock passa a ser só otimização.
- **A mesma marca nos dois motores:**
  - **um método só** monta a marca, `Gatilhos.marca(tipo, evento_ou_atividade)`. O listener novo, o listener antigo e o `Runner` chamam esse método, e nenhum deles a reimplementa. Duas montagens da mesma string divergiriam (registro errado, instante, prefixo), os dois motores rodariam, e a medida "Duplas" ficaria cega (qualidade, 05/11);
  - conversa: o tipo novo vem do mapa (`conversation_created` → `conversa.criada`) e o instante é o do despacho, que os dois listeners recebem do mesmo evento;
  - card: o id da `Crm::Activity`. O `Runner` roda depois do `log_move!`, então o id da atividade passa a ele;
  - spec: o mesmo evento passa pelos dois motores, e a string sai igual.
- **Quando o antigo grava `do_antigo`:** só quando vai agir, depois de conferir as condições. Assim a medida "Perdidas" fica certa, sem linha de ruído.
- A reivindicação vale enquanto houver conversão vigente, não só 30 dias: um evento de antes da troca pode chegar dias depois, num retry do Sidekiq.
- **O lock:** `pg_advisory_xact_lock_shared` só vale dentro de transação, e o `AutomationRuleListener` e o `Runner` não rodam numa. A F9.2 põe uma `transaction` curta em volta da decisão.

**Spec obrigatório da F9.2:**
- o commit da troca entre os dois listeners do mesmo evento dá exatamente 1 efeito;
- o commit da troca entre o `Runner` e o `EventoDoCardJob` do mesmo movimento dá exatamente 1 efeito;
- o evento enfileirado antes da troca e processado depois dá exatamente 1 efeito (o do antigo).
- com o relógio do fato adiantado (o `travel` no create), não há dupla.

### 5.2 Passos, nesta ordem

1. **Backup antes.** A Orquestração Deploy tira a cópia das linhas da conta por psql, só leitura: `automation_rules`, `crm_stage_automations` e `crm_stage_automation_steps`. O arquivo fica com permissão 0600 em `/tmp/chat_f9_<conta>_<timestamp>.json` no host, como na regra 3. A tabela guarda também o `estado_antes`.
2. **Recusa** a conta que tenha:
   - espera armada (`automation_rule_pending_executions` aberta);
   - passo de etapa com atraso na fila;
   - alguma antiga com falta no relatório.

   Hoje nenhuma conta tem espera nem passo atrasado na fila.
3. **Numa transação, com o lock exclusivo da conta:**
   - trava as antigas (`FOR UPDATE`);
   - cria cada automação nova (versão 1);
   - grava o par (o `created_at` é o `convertida_em`);
   - desliga a antiga (`active`/`enabled` = false), sem apagar nada;
   - liga a nova (`ativa: true`, `ligada_por`).
4. **O gate do emissor e o cache.** O gate ("há automação ligada para esse gatilho nesta conta") não pode negar depois de `convertida_em`. A chave do cache leva o `convertida_em` mais recente da conta, lido na mesma consulta do gate. A troca muda a chave na própria transação, e nenhum leitor repovoa o valor velho.
   - Limpar o cache depois do commit deixaria uma janela em que o novo perde o evento.

## 6. Reverter uma conta em minutos (F9.4)

O botão "Reverter conversão", no mesmo lugar, faz numa transação com o lock exclusivo da conta (o mesmo da 5.1), para que nenhum fato fique sem dono:
- `Definicao#desligar!` em cada nova, o que também para as execuções abertas;
- a antiga volta ao `estado_antes`;
- apaga a linha da conversão. A partir desse instante, os fatos voltam a ser do antigo, e a antiga pode ser convertida de novo depois;
- muda a chave do cache do gate, como na troca.

A automação nova não é apagada: fica desligada, com o histórico.

**O que sobra na reversão:** sem a linha, o antigo não reivindica mais. Um fato que o novo já executou e que chega atrasado ao antigo depois da reversão (um retry no meio) rodaria de novo. A janela é a do retry de um evento que cruza a reversão, e a reversão é um caso de emergência. Este risco fica aceito e escrito: guardar o par depois da reversão pediria uma coluna a mais, e a tabela é mínima por decisão do Rodrigo. Antes de reverter, a Orquestração confere as três filas do Sidekiq com evento da conta: retry, scheduled e enqueued. Com evento da conta em qualquer uma delas, a reversão espera ele sair. A `Definicao` não tem jsonb livre para guardar de onde veio (colunas: nome, ativa, origem, versao_ativa_id, ligada_por_id), e por isso a saída sem coluna nova não se aplica.

**Retorno em espera na reversão:** o `desligar!` para a execução nova que espera (por exemplo, um retorno com atraso), e o antigo não tem aquele fato. Esse retorno se perde. É emergência: a lista das execuções paradas fica no histórico, para refazer à mão.

**Plano B, se a tela estiver fora:** a mesma troca por psql, pela Orquestração Deploy, com os ids da tabela de conversões:
- desligar as novas (`ativa = false`) e fechar as execuções abertas, como o `desligar!` faz;
- religar as antigas pelo `estado_antes`;
- apagar as linhas da conversão.

O comando exato vai no runbook do PR da F9.2, escrito antes da primeira conta. Tempo estimado: menos de 5 minutos. É o rollback pré-aprovado da regra 3. Ainda assim, é escrita em produção, e por isso exige o OK do Rodrigo antes de virar runbook.

## 7. Antigo e novo nunca ligados juntos para a mesma coisa (F9.3)

**A trava de verdade é a 5.1:** a decisão de cada fato pela tabela de conversões, nos dois motores. Ela vale mesmo que alguém religue a antiga por um caminho que pula validação (`update_column`, `update_all`, psql), porque o listener antigo de uma regra convertida decide pelo par, não pelo `active`.

As travas abaixo são a frente do sistema (UX): dizem à pessoa o que aconteceu, em vez de deixar a regra ligada sem efeito.
1. **Ligar a nova** (`Definicao#recusa_para_ligar`) recusa com `antiga_ligada` se a antiga do par está ligada.
2. **Religar a antiga** pela API, pela tela ou pelo Guia é barrado por uma validação em `AutomationRule` e em `Crm::StageAutomation`, enquanto houver conversão vigente. A mensagem diz "esta regra virou a automação X; reverta a conversão". Pelo parecer de Funções:
   - só a **transição para ligada** é barrada. Apagar (`ExclusaoDaConta`) e editar mantendo desligada continuam;
   - o "Reverter conversão" religa porque apaga a linha da conversão antes, na mesma transação;
   - a recusa é 422 com frase em en e pt_BR, sem mudar a policy do EE;
   - validação nova no modelo pode mudar os formatos do Guia (lição do #1219): o PR regera `autonomia:guia:formatos`.
3. **Duplicar regra** (`POST automation_rules/:id/clone`) numa conta com conversão vigente: o clone nasce desligado e fora da tabela, com a frase "monte em Automações". Spec cobre o clone.
4. **Fila da etapa:** o `Crm::StageAutomationStepJob` não reconfere o `enabled`, então um passo atrasado já na fila rodaria depois da troca. A F9.2 faz o job reconferir o `enabled` **e** o dono do fato pela 5.1 (o instante do fato é o da execução da etapa). Além disso, a troca recusa conta com passo na fila.

A cadeia comum (D6) já impede que as duas, cada uma num motor, se disparem em laço.

## 8. Um mês de comportamento igual (F9.2)

**Antes de ligar:** o ensaio histórico da F5 roda cada automação nova sobre os últimos 30 dias da conta e compara com o que aconteceu de fato.
- Nas atribuições, compara o **responsável final** da conversa, não "atribuiu ou não". É o que o dono vê.
- Diferença sem explicação bloqueia a troca.

**Ressalvas de comportamento que o ensaio precisa cobrir** (qualidade, 05/11; vale para as 26 regras da conta 17):
- **Ordem:** a regra antiga atribui dentro do `EventDispatcherJob`, como "sistema". A nova atribui depois, num job a mais (`Partida`, depois `AvancarJob`). Contra a Atribuição e o auto-assign do fork, a ordem pode mudar quem fica no fim. A F9.2 tem um teste da corrida com a Atribuição ligada. Se o resultado final mudar, a conversão da conta espera a correção.
- **Quem aparece:** a atividade e a notificação da atribuição passam a dizer o nome do administrador que ligou, e não "Automação". O D9 marca só a mensagem. Pergunta ao Rodrigo: a atividade da atribuição também deve dizer "Automação"? (P7)

**Durante 30 dias depois da troca:** a reivindicação (5.1) deixa a prova nas execuções da automação do par: cada fato tem uma execução, `do_antigo` ou do novo, nunca as duas (índice único). A dupla é impossível por construção.

Uma leitura agregada semanal, por psql e só leitura, pela Orquestração:

| Medida | Como |
|---|---|
| Duplas | o mesmo `evento` com execução nos dois motores. É 0 pelo índice; a leitura confere |
| Perdidas | fatos que atendem ao filtro (por exemplo, conversas criadas na caixa X) sem execução nenhuma, `do_antigo` ou nova. Tem de ser 0 |
| Efeito | registros com sucesso por passo, contra o ensaio. Nas atribuições, o responsável final |
| Erros | execuções com erro, pausadas (`ligada_por` sem acesso) ou interrompidas |
| Relógio | execuções `do_antigo` com instante do fato a menos de 1 s do `convertida_em`. Mede a diferença entre os relógios |

- Divergência sem explicação, ou qualquer dupla ou perdida: reverter a conta (seção 6) e abrir Issue.
- O mês só fecha com as quatro semanas limpas. A reivindicação continua enquanto a conversão estiver vigente.

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

**Parecer de Funções (05/11, [comentário](https://github.com/autonom-ia2/chat/pull/2575#issuecomment-6655917227)): opção a) liberada, só para administrador.**
- O administrador basta: `permission_granted?` já dá `automation_manage` e `crm_manage_pipelines` (`StageAutomationPolicy#create?`). Um spec cobre isso.
- Função personalizada com `automation_manage` **não converte**. Com `ligada_por` sem ser admin, o D5 cortaria caixas em silêncio: a regra que rodava em todas passaria a rodar em menos, sem erro. O gate é `administrator?` explícito, com request spec de 403 para função com `automation_manage` + `crm_manage_pipelines`.

## 10. Fechar o motor antigo (P2, decidida pelo Rodrigo em 05/11)

Nas palavras do Rodrigo: "pode fechar o motor antigo... com prazer. Vamos colocar o novo motor para subir. Ninguém será prejudicado. Ainda não fiz o lançamento oficial." Não há prazo de 30 dias.

- **Por conta, junto com a conversão.** A conta com alguma linha em `autonomia_automacao_conversoes` não cria mais regra antiga nem automação de etapa: o `create` responde 422, com a frase "monte em Automações". O `update` só aceita desligar. O `index`, o `show` e o `destroy` seguem (D12: a API é preservada).
- **Conta sem nenhuma antiga** (quase todas): não há o que converter. Proposta: a criação antiga fecha para elas quando a F9.2 subir, porque ninguém usa e ninguém é prejudicado. Decisão da Automação.
- **Com a última conta convertida**, o motor antigo é desligado: o listener das regras e o `Runner` param de rodar. O código sai depois, num PR próprio.
- **Antes de fechar qualquer conta:** o Guia (`porteiro_da_automacao`, que hoje grava `POST automation_rules`) precisa montar no motor novo. Senão o Guia recebe 422 na conta convertida.
- As telas `settings/automation` e o painel antigo da etapa saem do menu da conta fechada. A lista única mostra tudo no motor novo (F9.5).

## 11. Ordem dos PRs da F9

1. **Este PR, só docs:** o desenho e a leitura agregada.
2. **F9.1, o relatório:** mapa, `Resultado`, `Condicoes`, `DaRegra`, `DaEtapa`, `Relatorio`, rake e spec. Só leitura, então entra cedo (Automação, 05/11), em PR próprio.
3. **F9.2, a troca:** a migration da tabela (P1) e do estado `do_antigo` no CHECK, o conversor, a divisão por instante com o advisory lock e a reivindicação (5.1), o gate versionado, a reversão, as travas da seção 7, o job da etapa reconferindo e o fechamento por conta (seção 10).
4. **F9.3, a tela:** "Converter regras antigas" e "Reverter", com o relatório.
5. **F9.0:** os dois itens da conta 16, depois da F6 PR2a' e da F7.
6. **F9.5, o fim do antigo:** desligar o motor antigo depois da última conta; o código sai num PR próprio.

**Primeira conta (P3, decidida pela Automação em 05/11):** o ensaio é na conta 1 (hub2you), com o molde da 17 montado à mão. A 17 só converte depois, com o OK do Rodrigo registrado na Issue. A escrita em produção é pela Orquestração Deploy, com aviso antes.

## 12. Perguntas abertas

- **P1:** decidida. Uma tabela, a mínima (seção 5). A reivindicação usa o índice das execuções.
- **P2:** decidida. O antigo fecha por conta, junto com a conversão (seção 10).
- **P3:** decidida. Ensaio na conta 1, a 17 depois.
- **P4:** combinada com a sessão Gatilhos em 05/11 (seção 2.1).
- **P5 (Funções):** respondida em 05/11. `ligada_por` = o administrador que aperta "Converter"; função personalizada não converte (seção 9).
- **P7 (Rodrigo):** a atividade e a notificação da atribuição feita por automação dizem "Automação" (como a mensagem, D9) ou o nome de quem ligou? (seção 8)
- **P6 (Multifunnel):** respondida em 05/11.
  - O respeito da IA do funil olha só `payload['by'] == 'automacao'` na última atividade de criar ou mover (`MovimentoDaAutomacao#respeitar?`, e o `sem_automacao` do FecharCard e do Evaluator). A `origem` não entra.
  - Condição: o passo convertido de mover ou criar passa pelo Mover/Creator com `automacao:`, ou pelo `cards_controller` com a `Cadeia.automacao_livre` ativa. Por outro caminho, a atividade sai sem `by` e a IA desfaz o movimento.
  - Spec da F9.2: card movido pelo passo convertido, a IA avalia dentro de 4 horas, e o card fica onde está.
  - O que a F6 precisa manter do `Runner`: o `CardGuard#move_allowed?` com pessoa no ator (o ator é quem ligou); a raiz comum da cadeia (`cadeia_nos_motores.rb`) contra o laço mover → entrou → mover; e a espera do Decisor (#858), se alguma conta usar. Nenhuma das 12 usa hoje.
  - O Multifunnel revisa o `by:'automacao'` no PR da F6 que tocar no Mover e no Creator. De acordo com o desenho no 1f6c60bd86.
