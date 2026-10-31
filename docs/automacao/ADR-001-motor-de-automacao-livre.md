# ADR-001 · Motor de automação livre

- **Estado:** aceito pelo Rodrigo em 30/10/2026. A implementação espera a jornada navegável aprovada (F0).
- **Épico:** #2414
- **Base lida:** `main` em `c941772080`, mais conferência só de leitura em produção nas duas stacks.

## 1. Contexto

### O que existe hoje

**Motor 1, regras de automação** (`automation_rules`, herdado do Chatwoot):
- ouve 5 eventos: conversa criada, atualizada, aberta, resolvida e mensagem criada (`app/listeners/automation_rule_listener.rb`);
- oferece 28 ações: 19 do Chatwoot, 8 do fork e 1 do Enterprise;
- a espera só existe antes do primeiro passo e fica presa à conversa (`automation_rule_pending_executions`);
- não há histórico visível ao cliente;
- duas telas usam esse motor:
  - a tela nova `routes/dashboard/automacoes/`, em que o Guia monta;
  - o modo manual `routes/dashboard/settings/automation/`, um formulário com lista escrita à mão em `constants.js`.

**Motor 2, automações de etapa do CRM** (`crm_stage_automations`):
- gatilhos "entrou" ou "saiu da etapa";
- 4 tipos de passo: retorno, responsável, mover e Decisor. O painel `CrmStageAutomationsPanel.vue` mostra 3;
- o atraso é um job solto, contado a partir da entrada.

**O que o Guia já sabe:**
- O catálogo do Guia (`lib/operator_guide/formatos-das-acoes.json`) é gerado do roteador e dos controllers: 676 ações de escrita em 64 recursos, 393 delas com formato completo.
- Ele executa pela `Autonomia::Guide::ChamadaInterna`, com o token da pessoa, então Pundit, caixas e conta valem.
- Já marca o que é "sem volta" e sabe desfazer.

**Eventos que existem e ninguém usa como gatilho:**
- `lib/events/types.rb`: troca de responsável e de time, `message.updated` (entregue, lida, falhou) e `contact.*`;
- do card: `crm.card.created/moved/won/lost/archived`, que só saem quando a conta assina um webhook (`app/services/crm/webhooks/emitter.rb`).

### O problema
Cada motor e cada tela têm a sua própria lista do que dá para fazer, escrita à mão. Por isso a Automação fica sempre atrás do Guia. O modo manual também fica atrás do que o Guia cria: uma regra com passo do Decisor quebrava o formulário (#2413).

### O objetivo (Rodrigo)
- Construir qualquer coisa com as ações e as IAs da plataforma.
- O Guia e o manual fazem igual e nunca defasam.
- O card do CRM faz muito mais.
- As IAs do CRM não são tocadas.

## 2. Decisão

Um **motor novo, pequeno, do fork**, `Autonomia::Automacao`, em arquivos próprios. O upstream recebe só prepends com spec.

### 2.1 Passos
- **Ações do catálogo do Guia**, liberadas por **allowlist** em `lib/operator_guide/automacao-recursos.yml`:
  - cada um dos 64 recursos é marcado "passo" ou "fora", com o motivo;
  - "fora" é o padrão;
  - ação com formato incompleto fica fora.
  - O passo chama `Autonomia::Guide::Acoes#conferir!`/`#executar`, que passam pela conferência de formato e pela `ChamadaInterna`.
- **Passos nativos**, para o que o catálogo não faz bem:
  - esperar e esperar até, com prazo e caminho "se vencer";
  - se e parar;
  - mensagem ao cliente: sai como "Automação";
  - avisar a equipe;
  - Decisor com N caminhos mais "nenhuma se aplica";
  - IA de texto, extração e resumo pela chave da conta;
  - criar retorno, com "atraso = vencimento", o que mantém o comportamento das automações de etapa atuais.
- **Sempre fora:** usuários, funções, integrações, webhooks, tokens, conta, faturamento, segurança e as rotas de IA do CRM.

### 2.2 Catálogo único
- `rake autonomia:guia:automacao` gera `lib/operator_guide/automacao-passos.json` a partir de três fontes: os passos nativos, as ações liberadas e a chave i18n da frase de cada passo.
- O Guia (ferramenta `automacao_montar`) e o editor manual (`GET automacoes/passos` + um renderizador por nó do esquema) leem o mesmo arquivo.
- O spec de CI falha quando:
  - o arquivo está fora de dia;
  - um recurso não está classificado;
  - um passo não tem frase em pt_BR;
  - um nó do esquema não tem renderizador nem a marca "só leitura";
  - uma receita não valida.
- Passo sem frase aparece como "Ação avançada" e nunca some.

### 2.3 Dados (uma migration, sozinha na fila)
- `autonomia_automacoes`: conta, nome, ativa (padrão `false`), origem (guia, manual, receita ou conversão), versão ativa, quem ligou.
- `autonomia_automacao_versoes`:
  - receita em jsonb, validada por JSON Schema;
  - digest e autor;
  - **imutável**: salvar cria a próxima versão.
- `autonomia_automacao_execucoes`:
  - alvo polimórfico (conversa, card ou contato), versão, chave do gatilho, cursor, `due_at`, estado, cadeia e profundidade;
  - índice único por automação, alvo e chave do gatilho.
- `autonomia_automacao_registros`: uma linha por passo, com resultado, motivo (chave i18n) e ids. Retenção de 30 dias.

Variáveis são valores estruturados (`{"$valor":"card.valor"}`), não Liquid. O editor mostra cada uma como chip. Variável vazia pula o passo com motivo.

### 2.4 Execução
1. **Escuta:** prepend no despacho assíncrono, com um gate barato: "há automação ligada para esse gatilho nesta conta?" (cache por conta).
2. **Partida:**
   - acha o alvo e as pontes: card, conversa principal, contato;
   - confere filtros, Spam, "não repetir por N dias" (quando o cliente escolhe), acesso de quem ligou e profundidade.
3. **Avançar:** do cursor até uma espera, um Decisor ou o fim, gravando um registro por passo.
4. **Varredura:**
   - a cada minuto, com trava atômica em lote, acorda quem espera;
   - antes de seguir, reconfere versão, se está ligada, se o alvo existe e a meta de saída.
5. **Tempo** (de hora em hora): "parado há X dias na etapa", "N dias antes do campo de data" e, depois, recorrente no fuso da conta.
6. **Erros:**
   - 4xx falha sem repetir;
   - 5xx ou timeout tenta 3 vezes;
   - preso há mais de 15 minutos vira "interrompido" e nunca é repetido.

### 2.5 Card do CRM
- O emissor de eventos do card passa a sair também quando há automação assinante. O payload ganha a origem da cadeia.
- `crm.card.updated` vai só para quem assina automação.
- O painel da etapa e o do card abrem o mesmo editor:
  - "Automações desta etapa": as antigas com o selo "jeito antigo" e as novas;
  - "Automações deste cartão": execuções em andamento, histórico e "Parar para este cartão".
- Caminhos que hoje não disparam "entrou na etapa" (arquivamento em massa, `skip_automations`) continuam sem disparar, e a tela diz isso.

## 3. Segurança e regras (decididas pelo Rodrigo em 30/10/2026)

| # | Tema | Decisão |
|---|---|---|
| D1 | Identidade | Age como **quem ligou**, reconferido a cada execução. Quando a pessoa perde o acesso, a automação pausa e alguém usa "Assumir e religar". |
| D2/D4 | Quem monta | `automation_manage` monta e liga, no Guia e no manual. Gatilho ou passo de funil exige também `crm_manage_pipelines` (EE). |
| D3 | O que vira passo | Allowlist por recurso, "fora" como padrão, o CI cobra a classificação. |
| D5 | Caixas | Quem não é admin só automatiza as caixas de que é membro. O resto é pulado com motivo. |
| D6 | Cascata | Automações diferentes encadeiam até a profundidade 3, contada nos três motores. Nunca a si mesma. É proteção contra laço infinito por defeito, não limite de uso. |
| D7 | Desfazer | A execução não entra no desfazer do Guia. O histórico é a trilha. Desligar sempre funciona. |
| D8 | IA na chave do cliente | Sem teto de uso (regra de 31/10, abaixo). O custo fica visível no passo e no histórico. |
| D9 | Autor da mensagem | Dentro da plataforma, a mensagem fica marcada como enviada pela "Automação", nunca por uma pessoa. O cliente recebe uma mensagem normal da empresa, sem "Automação" no texto. |
| D10 | Edição com gente no meio | Por padrão, quem está no meio termina na versão antiga. Passo sem volta alterado pede OK de novo. |
| D11 | Flags | Uma por fase (motor/ações, card, IA, editor), nascendo ligadas no piloto 1, 16 e 18. O bit é dado pela Orquestração Deploy. |
| D12 | Motores antigos | A conversão é obrigatória, conta a conta, com OK. O antigo é desligado, nunca apagado. Depois de um prazo, fecha a criação nova nos motores antigos (a API é preservada). |

**Também:**
- O anti-loop vive numa cadeia própria do fork, fora do `Current`, para sobreviver aos `Current.reset`. Os motores ignoram o que o outro fez.
- **Sem freio no uso (Rodrigo, 31/10/2026):** o cliente paga e usa quanto quiser. Nenhum teto de mensagens por conversa, de execuções por hora ou de chamadas de IA. Ficam só as proteções contra defeito: anti-loop (D6), Spam e falha que não se repete.
- Passo sem volta leva selo na tela e confirmação ao ligar.

## 4. Alternativas consideradas

- **Evoluir `automation_rules`:** muda uma tabela viva e o motor upstream que o Chatwoot também está mudando. Os passos nativos continuariam sem identidade. Média 6,8.
- **Motor de fluxos completo:** até 3 níveis de ramo e versões. É o mais seguro de construir, mas pesado para o leigo, e usa denylist. Média 7,3. Dele vieram as versões imutáveis, os valores estruturados e os tetos.
- **Escolhida, "Leigo primeiro":** motor mínimo, allowlist, receitas e Guia como construtor. Média 7,7.

## 5. Fases

| Fase | Entrega | Migration |
|---|---|---|
| F0 | Este ADR + jornada navegável em tela real, com 3 exemplos, aprovada pelo Rodrigo | não |
| F1 | Anti-loop em cadeia própria, `executed_by` preservado na `ChamadaInterna`, profundidade comum, porteiro do Guia por `automation_manage` (PR de auth), upsert de card pelo Mover | não |
| F2 | As 4 tabelas | sim |
| F3 | Motor + passos esperar/se/parar + passo de ação do catálogo + allowlist + CI + anti-loop + Spam | não |
| F4 | Passos mensagem e avisar | não |
| F5 | Catálogo de passos, editor gerado, lista única, ensaio, histórico, ferramenta do Guia, receitas, Guia e Central | não |
| F6 | Gatilhos de card, tempo, retorno, painéis da etapa e do card, receitas por pacote | não |
| F7 | IA como passo (Decisor com N caminhos, extrator, texto, resumo, custo visível), com eval com orçamento | não |
| F8 | Recorrente, falha de entrega, troca de responsável e de time, reunião, webhook de saída | não |
| F9 | Conversor dos motores antigos | não (escrita por script com backup) |

## 6. Riscos

1. A perda de `executed_by` na `ChamadaInterna` ainda não foi testada. A F1 começa por um spec ponta a ponta.
2. Abrir o emissor do card aumenta o volume da fila `critical`. Medir no piloto.
3. Três motores mais as IAs do CRM convivendo trazem risco de mensagem dupla. As proteções são a profundidade comum, o histórico que mostra quem mandou cada mensagem e a conversão com prazo. Não há teto de envio: o cliente decide quanto usa.
4. "Quem ligou" pode parar uma automação em silêncio. O aviso vai pelo canal de avisos do Guia, com desligamento automático no 2º erro.
5. Uma classificação errada no yml libera ação perigosa. Por isso "fora" é o padrão e a revisão é recurso a recurso.
6. Enviar modelo de WhatsApp fora do follow-up ainda não foi confirmado. A saída alternativa é criar o retorno com envio automático, um caminho já validado.
7. O Chatwoot v4.19 mexe no motor de automação upstream. Arquivos próprios e prepends com spec.
