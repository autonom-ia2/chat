# Revisão normal — desenho técnico B2

**Data:** 07/10/2026  
**Branch/worktree:** `docs/agentes-ia-prd` / `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Baseline de código:** `6242e31695fd1c6b8b088f2fcb819c027fc5083c`  
**Escopo:** `docs/agentes-ia-redesign/design/B2.md`, PRD §6.6, §7.2 e §10.1  
**Estado:** achados para correção; desenho ainda não aprovado para implementação.

## Método e limite

Esta é a revisão normal independente, com lentes técnica e de segurança. As afirmações de código abaixo
foram conferidas no baseline fixo com `git show <SHA>:<arquivo>`; o checkout atual está sujo e não foi
usado como fonte de comportamento. Não rodei RSpec, serviço do M2, banco, produção ou eval. Não houve
alteração no desenho B2, no produto ou no PRD nesta revisão.

O protótipo e o aceite de telas reais continuam sendo gates de produto. Este arquivo não é aprovação
visual nem aprovação de release.

## Achados

### B2-TEC-01 — digest não cobre os leitores de operação nem o scaffold oculto (P1)

**Evidência.** O contrato do `TestDigest` em `design/B2.md:209-243` lista instrução, campos da pessoa,
tipo e digest de material, mas não define o efeito no teste/invalidação para os controles de operação do
BE-31 nem para o `scaffold`. O PRD exige invalidar antes de ir ao ar toda mudança que altere o que o
agente responde ou por onde responde (`PRD.md:446-451`), e lista os doze controles do BE-31 em
`PRD.md:544`.

No baseline, isso já é comportamento executável:

- `prompt_builder.rb:98-111` concatena `scaffold` no prompt enviado ao modelo;
- `agent.rb:174-180` faz `with_knowledge=false` pular o retrieval, e `agent.rb:210-215` entrega
  `native_tool_slugs` ao catálogo;
- `tools/registry.rb:68-75` decide as ferramentas efetivamente disponíveis;
- `responder.rb:97-100` usa `silence_tokens`, `responder.rb:224-260` usa voz e instruções de voz,
  `responder.rb:292-315` usa a entrega humanizada e `responder.rb:398-403` usa `operate_media`;
- `config.rb:218-241,251-277` lê debounce, entrega humanizada, mídia e reações; `async_config.rb:90-125`
  lê a configuração das ferramentas assíncronas; `operate.rb:53-67` lê a lista de telefones de teste.

Portanto, um teste pode ficar marcado como E4 com o digest atual e chegar ao atendimento com retrieval,
ferramentas, silêncio, mídia, voz, allowlist ou entrega diferentes. O mesmo vale para uma mudança de
`scaffold` feita por uma geração legada: o `apply_builder_config!` mescla `config` e grava os atributos
ocultos (`agent.rb:217-243,321-329`), enquanto `refresh_instruction!` e o token de refresh escrevem por
caminhos próprios (`agent.rb:246-274`). Dizer que `AgentStateStore` é o único escritor do namespace
privado não fecha esses escritores legados.

**Correção exigida antes de implementar.** Fechar uma matriz campo → leitor → efeito → escritor → regra
de invalidação, incluindo os doze campos do BE-31 e `with_knowledge`, `scaffold` e demais campos que o
runtime realmente lê. A matriz deve dizer quais controles entram no hash e quais têm outra prova de
paridade Teste/live; nenhum campo pode ficar como “não entra” sem justificativa e caso de teste. Para o
`scaffold`, usar versão/hash não reversível, sem expor o texto oculto. Definir também como a leitura
detecta alterações feitas pelos escritores legados e como fica D24 depois de E5/E6. O conjunto mínimo de
specs deve cobrir mudança de knowledge, ferramenta, silêncio e ao menos um controle de entrega, além de
uma gravação legada que não passe pelo `AgentStateStore`.

### B2-TEC-02 — avatar aparece como invalidador e como exceção ao mesmo tempo (P1)

`design/B2.md:238-240` diz que `AgentsController#update/avatar` chama `invalidate!`; o traçado de
`design/B2.md:480-489` repete `PATCH/avatar` junto de `invalidate!(person)`. Porém `design/B2.md:357-359`
diz que a foto sozinha não invalida o digest, porque só atualiza a identidade do espelho. O PRD confirma
que avatar tem apenas leitor de espelho (`PRD.md:388-390`) e que a invalidação pré-live é para mudanças
de resposta/rota (`PRD.md:446-451`).

**Correção exigida antes de implementar.** Separar o contrato por campo: nome invalida `person` e sincroniza
o espelho; avatar atualiza somente o espelho e preserva E4/E5/E6 e o `tested_digest`; PATCH com nome e foto
invalida uma vez por nome. A lista de escritores e o traçado de entrada devem usar essa mesma regra. Os
casos de upload, remoção e alteração de ambos precisam afirmar explicitamente a situação antes e depois.

### B2-TEC-03 — paridade de material não fecha a exclusão de mídia (P1)

O desenho afirma em `design/B2.md:361-410` que `MaterialProjection` é a mesma decisão do Retriever, mas
não fixa `kind` como parte da projeção, do snapshot ou de `uses`. A distinção é obrigatória no baseline:
`source.rb:59-69` separa `knowledge` de `media`, `source.rb:162-169` marca mídia pronta sem revisão e
declara que ela nunca entra no retrieval, e `retriever.rb:79-85` consulta `knowledge_entries.ready`.
O PRD também diz que mídia não tem leitor e sai desta aba (`PRD.md:402-404`).

Sem essa condição explícita, uma implementação pode aplicar a tabela de status/revisão a uma mídia pronta
ou incluí-la no digest de materiais e no contador da tela, embora ela não seja material de conhecimento.
A linha de legado sem `review_status` em `design/B2.md:394-395` aumenta a ambiguidade, porque mídias
legadas também podem ter revisão nula.

**Correção exigida antes de implementar.** Fixar no contrato que a projeção e o snapshot de conhecimento
operam somente sobre `kind=knowledge`, e definir o payload para `kind=media` (exclusão da projeção ou
estado separado sem `uses`, conforme o endpoint de compatibilidade). Provar uma fonte de mídia pronta,
uma fonte de conhecimento pronta e a mistura das duas: a mídia não pode virar “Pronto”, usada, contada ou
entregue como conhecimento.

### B2-TEC-04 — a promessa de uma consulta na lista só cobre eventos (P1)

O resultado do B2 promete lista sem N+1 (`design/B2.md:20-25`). O único caso correspondente em
`design/B2.md:503-505` captura uma agregação de eventos. Contudo, o `StateResolver` também precisa ler
estado de `BuildThread` (`design/B2.md:202-205`), e o baseline mantém `Agent has_many :build_threads`
(`agent.rb:55-63`) com estado JSONB (`build_thread.rb:45-64`). O desenho não diz como obter a última thread
e os campos necessários para N agentes, nem como a projeção de material/estado evita uma consulta por
agente.

**Correção exigida antes de implementar.** Descrever a estratégia de leitura em lote/preload para a última
thread e para qualquer relação usada por `StateResolver`, separando-a da agregação de `AgentEvent`. Fixar
um orçamento de consultas para a requisição completa da lista e um caso com N agentes misturando E1–E4,
thread sem agente, materiais provisórios e snapshots completos. A prova deve capturar queries de todo o
`GET`, não somente da contagem de eventos.

### B2-TEC-05 — ator, permissão e leitura de resultado assíncrono estão incompletos (P1)

`design/B2.md:196-198` diz que somente o editor satisfaz o teste, mas permite POST de quem só vê; em
`design/B2.md:261-265` menciona checagem no pedido e no digest, sem definir revogação, troca de papel ou
quem pode consultar a conclusão. O baseline torna o ponto concreto: `defer_interactive_ai.rb:4-10` salva
`account_user_id`; `interactive_request.rb:6-12` persiste esse ator no Redis; o job reautoriza na execução
(`interactive_job.rb:10-21`); e o polling exige a mesma conta, o mesmo `account_user_id` e o mesmo token
(`ai_requests_controller.rb:1-8`). A autorização atual do teste é `autonomia_view`
(`interactive_operation.rb:105-109`), não `autonomia_manage`.

**Correção exigida antes de implementar.** Escolher e documentar a regra em cada ponto: POST, execução,
gravação da conclusão e polling. Cobrir editor que perde `manage`, viewer que posta e conclui, permissão
revogada antes do polling, outro usuário autorizado na mesma conta, usuário removido e conta diferente.
Definir se o polling continua somente para o criador (compatível com o caminho atual) ou se há leitura por
outro membro, sem expor id ou conteúdo. O resultado não pode virar E4 por uma permissão que deixou de
ser válida, e a mensagem de erro/404 precisa seguir o isolamento existente.

### B2-TEC-06 — gaveta de respostas erradas mistura contagem de conversas com contagem de marcações (P1)

O contrato de `design/B2.md:412-444` promete uma linha por marcação, mas descreve filtrar primeiro uma
relação de conversas e depois consultar `Captain::MessageReport`. No baseline, `Analytics#outcomes` conta
reports (`analytics.rb:51-56`), enquanto `outcome_scope('wrong_replies')` devolve conversas distintas
(`analytics.rb:59-69,228-239`) e o controller limita/ordena essa relação de conversas antes de serializar
(`analytics_controller.rb:11-32`). `Captain::MessageReport` é uma linha por marcação, com
`conversation_id` e `message_id` (`enterprise/app/models/captain/message_report.rb:3-13`).

Assim, uma conversa com duas marcações pode contar uma vez, perder uma linha ou produzir `has_more`
incorreto. O desenho também não define se `total_count`, `hidden_count`, `count` e o limite 50 contam
conversas ou marcações, nem a ordenação quando há várias marcações na mesma conversa.

**Correção exigida antes de implementar.** Fixar `MessageReport` como unidade do payload (se esse continua
sendo o contrato), definir a consulta, ordem estável e limite de 51 antes da serialização, e aplicar a
permissão sem vazar texto/ids ocultos. Definir matematicamente as quatro contagens e `has_more`. Os casos
obrigatórios são: duas marcações na mesma conversa, duas mensagens na mesma conversa, marcação fora da
janela, mistura visível/oculta e nenhuma sugestão.

## Cobertura por BE

| BE | Resultado da revisão normal |
|---|---|
| BE-00 | Sem achado bloqueador nesta leitura; flag nova e desvio antiga/nova estão descritos em `design/B2.md:64-89`. |
| BE-01 | **B2-TEC-04**: o orçamento de queries da lista não cobre o resolver de estado. |
| BE-08 | **B2-TEC-01** e **B2-TEC-05**: digest não fecha leitores reais; ator e permissão assíncronos precisam de regra. |
| BE-11 | Sem achado novo nesta leitura; vínculo mantido e regra de horário estão delimitados em `design/B2.md:310-355`. |
| BE-16 | **B2-TEC-02**: avatar e nome têm regras conflitantes de invalidação. |
| BE-27 | **B2-TEC-03**: falta fechar `kind=knowledge`/mídia na projeção e no snapshot. |
| BE-28 | **B2-TEC-06**: payload de marcações e contagens ainda não têm unidade definida. |
| BE-32 | Sem achado novo nesta leitura; as quatro condições e o guard de create/PATCH estão coerentes em `design/B2.md:446-478`. |

## Gate para a próxima etapa

O desenho precisa receber as seis correções acima e passar por uma checagem independente. Se a checagem
encontrar erro novamente, a causa raiz deve ser registrada e a tarefa deve parar para retorno ao Rodrigo,
conforme a regra desta revisão. Depois disso ainda serão necessárias as specs vermelhas previstas em
`design/B2.md:496-525`, a validação do diff real e o gate de todas as telas reais e cenários de
`docs/agentes-ia-redesign/aceite-telas-reais.md` em ambiente local. A conclusão “sem migration” continua
dependente do diff e do CI do PR, como já registra `design/B2.md:41-43`.
