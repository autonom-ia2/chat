# PRD — Agentes de IA: nova experiência (redesign completo)

| | |
|---|---|
| **Status** | Rascunho v9.1 — rodadas 1–8 aplicadas; atualizado com o #1063 (§0); causas raiz C1–C15 (rodadas 2–8) em `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md`; aguardando decisões da §4 |
| **Data** | 05/10/2026 |
| **Dono do produto** | Rodrigo (Hub2You / Autonom.ia) |
| **Repositório** | `autonom-ia2/chat` (fork do Chatwoot) |
| **Fonte da verdade visual** | Protótipo aprovado: `docs/agentes-ia-redesign/mockup/jornada.html` (código em `mockup/src/*.js`) — publicado em https://claude.ai/artifact/NdjZdAnt8uhTa4P2VziyGM (versão 5) |
| **Contexto** | `docs/agentes-ia-redesign/DIAGNOSTICO.md` · bugs já corrigidos no PR #1036 (Issue #1035) |

> **Regra de ouro deste PRD:** a entrega é o protótipo funcionando de verdade. Toda tela, estado, texto e diálogo do protótipo
> existe no produto, com dados reais da API. Divergência só é aceita quando listada em §6.4 (correções de acessibilidade) ou
> decidida na §4. "Parecido" não é "pronto".

---

## 0. Mudança em produção depois deste PRD — #1063 (exclusão lógica), 06/10/2026

O PR #1063 (Roberto, `4d79f25612`) trocou a exclusão de agente por **exclusão lógica**: `autonomia_agents.deleted_at` +
`deleted_by_id`, `autonomia_agent_inboxes.deleted_at`, escopo `kept`, serviço `Autonomia::Agents::SoftDelete` com registro em
`Audited` (comment "Logical deletion"), e o reaper passou a **arquivar** (`reason: 'stale_draft'`) em vez de destruir. Excluir
continua devolvendo as conversas para a equipe (`sync_mirror!(operating: false)` → `release_bot_conversations!`, #1036) e
remove o `AgentBotInbox` vivo; o vínculo e os materiais ficam guardados para recuperação. O que isso muda aqui:

- **Textos de excluir** (§6.4, CA-AJU-11, CA-LISTA-10): "são apagados… não dá para desfazer" deixou de ser verdade → D34.
- **BE-14:** a limpeza **arquiva** o rascunho vazio (sai da lista; fica no banco).
- **BE-22** perde o objetivo (excluir não apaga mais `knowledge_entries`) → fora desta entrega.
- **BE-01, BE-02, BE-08, BE-11, BE-25** e toda consulta nova usam só agentes e vínculos `kept`; material de agente arquivado
  não aparece em "Usar material de outro agente".
- **Validação (§11.7):** exclusão e limpeza agora deixam prova no banco (`deleted_at`, `deleted_by_id`, linha de auditoria);
  "id sumido" vira "id arquivado", explicado pelo próprio registro. Todas as consultas filtram `deleted_at IS NULL`.
- **NR-13** passa a incluir `spec/services/autonomia/agents/soft_delete_spec.rb` e
  `spec/requests/api/v1/accounts/autonomia/agents/soft_delete_spec.rb`.
- **Fila:** desde 07/10 a sessão Automação junta até 7 PRs sem migration por lote. O §14 pede lote de um PR só para os PRs
  deste projeto (rollback de um degrau) → conflito registrado em D35, para o Rodrigo decidir.

## 1. Resumo

A área **Agentes de IA** é a única do painel que não passou pelo redesign "premium e simples" (Automações #982, Campanhas
#990, Primeiros passos, Central). Ela destoa no visual (título de 16 px, roxo no lugar do azul da marca, botões menores que
44 px, vazio genérico do Chatwoot), tem uma jornada de criação com decisões técnicas logo de cara ("Externo/Interno",
"Com base/Sem base"), etapas escondidas, teste depois de ligar, e um painel sem ações básicas (ligar rascunho, excluir,
renomear).

Este projeto reconstrói a área inteira — lista, criação em 4 etapas (Escolha → Conte → Teste → Ligue), painel do agente com
5 abas (+ Ferramentas para admin da plataforma), conexão de WhatsApp por código, e as peças dentro da conversa (ajudante da
equipe e "resposta errada") — exatamente como no protótipo, mais o backend que o protótipo exige.

**Para quem:** dono e equipe de corretoras e pequenas empresas que usam o Chat2You (Hub2You **e** Autonom.ia). Critério de
linguagem: uma pessoa com pouca familiaridade com tecnologia ("QI 70") consegue criar, testar, ligar e ajustar um agente
sozinha.

## 2. Objetivos e como medir

| # | Objetivo | Medida de sucesso |
|---|---|---|
| O1 | Qualquer pessoa cria e liga um agente sem ajuda | Teste moderado com 3 pessoas leigas: as 3 chegam a "Pronto" sem pedir ajuda; tempo mediano ≤ 8 min com material, ≤ 5 min sem |
| O2 | Nenhum agente vai ao ar **pela tela nova** sem ser testado (escopo: D23) | Ligar da tela nova recusa agente sem teste válido da instrução atual (§6.6, D15, D23, CA-LIG-12); T14b em produção |
| O3 | Visual idêntico ao padrão Chat2You | Aceite visual CA-VISUAL-01..05 (§11.6) aprovado pelo Rodrigo |
| O4 | Zero regressão nos agentes em produção (Clara, Lia, contas Autonomia) | NR-01..NR-15 verdes; validação pós-deploy (§11.7) com invariantes ok e diferenças de estado decididas nas duas stacks; tester (§11.8) 100% no plano de cada PR |
| O5 | Nada promete o que o sistema não faz | Todo controle da tela tem efeito real comprovado por teste (ver §4 D1 e §7) |
| O6 | Painel completo | Ligar rascunho, pausar, excluir, renomear, trocar canal, ensinar, voltar versão — todos pelo painel |

## 3. Fora do escopo

- Tela de **Conexões da Cotação (AGGER)** — continua no módulo Cotação; daqui só há link.
- **Especialistas** (subagentes da Lia) com tela própria — só leitura dos ramos em "O que sabe".
- Apagar o código antigo — acontece num PR separado **depois** do aceite final e de 2 semanas com a flag ligada (§10, F10).
- Cobrança/medição de cotações (`ToolRun`) — não muda.
- Novos canais além dos que o Chatwoot já conecta.

---

## 4. Decisões que o Rodrigo precisa tomar (bloqueiam partes específicas)

Cada decisão tem recomendação. O que **não** depende dela pode começar já.

| # | Decisão | Opções | Recomendação | Bloqueia |
|---|---|---|---|---|
| **D1** | **O agente em produção ignora o "limite de certeza" e a regra "Quando passa para a equipe".** Em produção o Operate chama o Answerer com `trust_instruction: true` (`operate/responder.rb:331`), que nunca aplica portão de sistema (`answerer.rb:124,134-150`); o limite só vale no Testar e no Guia (`answerer.rb:649`). `handoff_strategy` é salvo e **nenhum código lê** (`agent.rb:125-128`). Hoje esses controles são decorativos e o Testar mostra um comportamento diferente do real. | **(a)** Testar passa a usar o mesmo caminho da produção; tira-se a régua de certeza; "Quando passa" vira texto da instrução (o modelo decide, como já decide hoje). **(b)** O Operate passa a aplicar limite e estratégia de verdade (muda o comportamento da Clara e da Lia no ar). **(c)** Esconder os dois controles até decidir. | **(a)** — honesto, sem mudar o que está no ar. A régua sai do protótipo; "Quando passa para a equipe" continua, gravando a regra no texto que o modelo lê (`PromptBuilder`), com spec provando o efeito. | Ajustes › "Quando passa para a equipe"; legenda da aba Testar (BE-12, F7) |
| **D2** | "Para quem vai" (pessoa / time) | (a) Implementar `HandoffRouter` (BE-06); (b) adiar e esconder | **(a)** com padrão "Quem estiver livre" = comportamento atual | BE-06, F7 |
| **D3** | Flag para alternar tela nova/antiga | (1) ENV global; (2) ENV mestra + atributo por conta; (3) sem flag | **(2)** — liga primeiro na Hub2you (conta 16) | F0 |
| **D4** | Azul-marinho `#0D2344` sem token (4 arquivos já usam `bg-[#0D2344]`) | (a) seguir o precedente arbitrário; (b) criar token `n-navy` em `theme/colors.js` | **(b)** e migrar os 4 usos no mesmo PR F0 | F0 |
| **D5** | Sugestão "Vi o link X. Usar como material?" | (a) o Construtor (modelo) devolve `suggested_links[]` no estado da conversa; (b) sem a sugestão, só "Colar um link" | **(a)** — regra do Rodrigo proíbe detectar por texto/regex no front | BE-09, F2 |
| **D6** | Texto "Fica guardado até você terminar ou excluir" × limpeza automática de 48 h (rascunho sem instrução e sem material que tem conversa) | (a) poupar rascunho com ao menos 1 resposta do usuário na conversa; (b) mudar o texto para "Guardado por 2 dias" | **(a)** | BE-14, F1 |
| **D7** | Conectar WhatsApp novo pelo fluxo do agente | O backend de caixa WAHA exige `phone` (`waha_inboxes_controller.rb:18,99`), aceita só celular do Brasil (55 + DDD + 9 dígitos, `inbox_provisioner.rb:11,44`) e grava o token de quem conecta (`waha_inboxes_controller.rb:102-104`). (a) pedir o número na tela e liberar a quem é administrador; (b) só administrador | **(a)**: campo "Número do WhatsApp" (55 + DDD + número) antes do código, permissão = administrador da conta, aviso "Esta conexão usa o seu acesso. Se você sair da conta, ela para."; `invalid_phone` vira mensagem pt-BR | BE-13, F6 |
| **D8** | Quem só pode ver pode usar a aba Testar? (hoje `POST test` aceita `autonomia_view`, `playground_controller.rb:29`) | sim / não | **sim** (como hoje) | — |
| **D9** | Ordem de merge com o lote de Campanhas (#993, ainda fora da `main`), que tem `JourneyStepper`, `JourneySwitch`, `useModalFocus`, `localeTag` | (a) F0 extrai esses 4 para `components-next/`/`helper/` e #993 importa no rebase; (b) esperar #993 | **(a)** | F0 |
| **D10** | Converter os tons antigos gravados em inglês (`friendly`, `professional`, `neutral`, `playful`) para a frase em português. **Muda o texto que o modelo lê ao vivo** (`prompt_builder.rb:242-246`) | (a) UPDATE por psql com foto antes (Q14) e 🟢, excluindo `insurance_quote` e agentes de sistema; (b) só a tela pré-seleciona | **(a)**, depois do deploy de F7, seguido do núcleo do §11.8 e do "teste responde" de cada agente ativo alterado, contra a foto Q14; volta = UPDATE pela foto || F9 |
| **D11** | Etapa "Parou em …" | (a) a lista e o "Continuar" seguem os estados de §6.6 (mecanismo no desenho técnico do B2); (b) a lista diz só "Falta terminar" | **(a)** (BE-08) | F1 |
| **D12** | **Problema em produção hoje:** `GET analytics/conversations` e `GET faq_suggestions` exigem só `autonomia_view` e devolvem dados de conversas de qualquer caixa (contato, atendente, última mensagem; pergunta e resposta de conversas reais) — `analytics_controller.rb:15-33`, `faq_suggestions_controller.rb:9-16` | (a) filtrar as conversas com `Conversations::PermissionFilterService` (a mesma regra que o repo usa para ver conversas, com a extensão Enterprise de funções personalizadas) e exigir `autonomia_manage` em `faq_suggestions`; (b) exigir `autonomia_manage` nos dois | **(a)**, no B1 (BE-25) | B1, F4, F5 |
| **D13** | Onde ficam as edições do Agente de Cotação. `insurance/*` exige `insurance_*` + flag de Cotação (`insurance/base_controller.rb:1-12`) | (a) rota sob `autonomia/agents/:id/quote_choices` (permissões de agentes); (b) exigir as duas permissões e esconder sem `insurance_manage` | **(a)** (BE-17) | B5, F5, F7 |
| **D14** | Números do agente interno (ajudante): uso do ajudante não gera evento | (a) sem números nesta entrega, com texto explicando; (b) criar evento de uso do copiloto | **(a)** | F1, F4 |
| **D15** | Garantir O2 ("ninguém liga sem testar"): rascunho "Pronto para ligar" vai direto para Ligue | (a) `publish` exige teste válido da instrução atual (BE-08) → 422 `missing_test`; vale para o ajudante interno (D26); escopo dos outros caminhos em D23; (b) só medir | **(a)** | B3, F3 |
| **D16** | "Usar material de outro agente" | (a) atalho de 1 clique do protótipo ("Usar o PDF que a Clara já usa") quando há exatamente 1 material pronto em outro agente; com 2+, diálogo com a lista; (b) só a lista | **(a)** | F2 |
| **D17** | Testar executa ferramentas de verdade (HTTP, inclusive POST com segredo) e é liberado a quem só vê (D8) | (a) quem só vê não executa ferramenta com método diferente de GET no teste **e no "sugerir resposta"** (`POST suggest`, também liberado a quem só vê); cotação nunca é feita no teste; o chat do ajudante dentro da conversa segue a regra própria; (b) aceitar o risco | **(a)** (BE-12) | B4b |
| **D18** | **Campos sem efeito hoje** (§6.5): Primeira mensagem (`greeting`), Perguntas para puxar conversa (`starter_questions`) e Quando não souber responder (`fallback_message`) — nenhum chega ao cliente no atendimento real | (a) Primeira mensagem e Quando não souber passam a entrar no texto que o modelo lê (BE-30, PR isolado, muda o prompt ao vivo de quem tem os campos preenchidos — foto Q15 e lista ao Rodrigo); Perguntas iniciais saem da tela; (b) os três saem da tela | **(a)** | B4b, F3, F7 |
| **D19** | Renomear não muda como o agente se apresenta (o nome vive na instrução) | (a) o texto do modelo ganha "Seu nome é {nome}." **só** quando o nome mudou depois da última instrução gerada (byte a byte igual nos demais, BE-29); (b) renomear avisa "Para ela se apresentar com o nome novo, use Mudar conversando" | **(a)** | B4b, F7 |
| **D20** | Mídias "Para enviar": o atendimento não envia os arquivos ao cliente | (a) aba sai nesta entrega (o upload continua no Construtor só como referência que o Construtor cita); (b) criar o envio de anexo pelo agente (escopo novo) | **(a)**; (b) vira Issue própria | F2, F5 |
| **D21** | Ajustes de operação por agente que o BE-19 fecha no PATCH (`voice_reply`, `voice_instructions`, `humanize_delivery`, `operate_media`, `operate_reactions`, `test_allowlist_phones`, `silence_tokens`, `native_tool_slugs`, `debounce_seconds`, `async_tools`, `async_poll_intervals`, `async_deadline_seconds`) — hoje só por esse PATCH | (a) tela no Super Admin "Ajustes de operação do agente" com lista fechada, registro de quem mudou e spec (BE-31); (b) só por psql com 🟢 e foto, comando no runbook | **(a)** | B1 |
| **D22** | "Mudar conversando" sobrescreve nome, saudação, tom, perguntas e até a instrução manual | (a) só em modo guiado (422 `manual_mode` no manual; botão desabilitado com explicação) e a retomada só pode mudar instrução, resumo, andaime e regra de passagem — nome, saudação, "quando não souber" e tom editados à mão ficam; (b) avisar no diálogo o que será trocado | **(a)** (BE-05) | B3, F7 |
| **D29** | Nome e Primeira mensagem eram editados no Ligue, **depois** do teste — o agente ia ao ar com cumprimento não testado | (a) "Como se apresenta" (Nome, Primeira mensagem) fica no **topo do Teste**, editável; mudar e testar de novo é imediato; o Ligue só mostra os dois no resumo; (b) mudar no Ligue invalida o teste | **(a)** | F3 |
| **D30** | Criar já ativo sem instrução (create da API/Guia com `status`/`enabled`) | (a) o BE-04 vale também no create → 422 `missing_instruction`; com instrução e sem teste continua como hoje (D23); (b) como hoje | **(a)** | B3 |
| **D31** | O funil do CRM (`Crm::Ai::HandoffExecutor`) passa conversas com o seletor dele, fora dos 3 pontos do BE-06 | (a) continua como hoje: "Para quem vai" do agente não se aplica ao funil; o evento do funil não leva alvo e fica fora do invariante I5; (b) o funil passa a respeitar o alvo do agente | **(a)** | B5 | Nota de passagem privada não chega ao cliente (BE-24); "Uma pessoa" e "Um time" atribuem conforme o BE-06, e o roteador nunca atribui fora do time — numa caixa de teste **sem** funil do CRM com IA (o funil pode atribuir depois, D31) |
| **D32** | De onde vem o gênero dos textos da tela ({a}, {ela}) | (a) de `config.voice` (feminina/masculina), que o Construtor já grava pela conversa; editável em "Foto e nome" como "Tratar por: ela / ele"; vale para todo tipo, inclusive o ajudante (sem masculino fixo); renomear não muda sozinho; nunca deduzido do texto do nome; (b) masculino neutro sempre | **(a)** | F1–F7 |
| **D33** | "Nunca" prometia passar quando a IA cai, e o atendimento não faz isso (falha de IA = silêncio, salvo a cotação assíncrona da Lia) | (a) tirar a promessa: "Nunca" passa só quando o cliente pede ou fora do horário/público; texto "Não oferece uma pessoa. Ainda passa quando o cliente pede."; (b) criar passagem por falha de IA para todas as opções (mudança ao vivo nova) | **(a)**; (b) vira Issue | B4b, F7 |
| **D34** | Texto de excluir depois do #1063 (exclusão lógica: some da lista, para de atender, materiais e vínculos guardados) | (a) externo "{A} {nome} sai da lista e para de atender. As conversas com {ela} vão para a equipe."; ajudante "O {nome} sai da lista e some do painel das conversas."; rascunho "O rascunho sai da lista."; sem "não dá para desfazer" (a recuperação existe no banco, sem tela nesta entrega); (b) criar tela de recuperação | **(a)**; (b) vira Issue | F1, F7 |
| **D35** | Lote de um PR só (§14) × fila da Automação com até 7 PRs por lote (07/10) | (a) PRs do caminho ao vivo (B1, B4b, B5, B6b) pedem vaga "sozinho por rollback"; os demais entram no lote de 7, e para eles a volta é por revert com OK (nunca rollback automático, §11.7 "lote misto"); (b) todos entram no lote de 7 | **(a)** | B1–F9 |
| **D23** | Até onde vale "ninguém liga sem testar" (O2). Hoje também ligam: tela antiga (PATCH), Guia, API e a criação da Lia pela Cotação | (a) só o fluxo novo exige teste (Ligar da tela nova e `publish`); tela antiga, Guia, API e Cotação continuam como hoje enquanto a flag existir; com o F10 (fim da tela antiga) a regra passa a valer em toda transição para "atendendo"; (b) toda transição exige teste já agora, com exceções | **(a)** | B3 |
| **D24** | O que acontece depois de ir ao ar | (a) a invalidação do teste só vale **antes** de ir ao ar (E3/E4); agente no ar ou pausado (E5/E6) continua como está quando a instrução muda (por material novo, pergunta aprovada, Mudar conversando, texto manual, voltar versão); religar um pausado pelo interruptor só exige instrução; (b) exigir novo teste | **(a)** | B2, B3 |
| **D25** | Voltar do modo manual para o guiado | (a) confirma ("O texto que você escreveu deixa de valer e {ela} volta para a última versão montada pela conversa."); restaura a última versão guiada guardada (BE-23) com o seu andaime; sem versão guiada guardada, a opção não aparece; o texto da pessoa fica nas versões; (b) não permitir voltar | **(a)** | B4, F7 |
| **D26** | Testar do ajudante da equipe (interno) | (a) o Testar do ajudante usa o caminho do ajudante dentro da conversa, com uma conversa de exemplo (do i18n) como contexto; sem faixa "passaria para a equipe"; esse teste conta para ligar; (b) ajudante liga sem teste | **(a)** | B4b, F3 |
| **D27** | No teste, ferramentas que gravam em outro sistema (método ≠ GET) rodam de verdade para quem edita | (a) avisar na tela do teste "Ferramentas que gravam em outro sistema rodam de verdade no teste." quando o agente tiver alguma; tester só roda T07/T08 com Clara sem ferramenta não-GET (conferido antes); (b) não rodar ≠ GET para ninguém no teste | **(a)** | B4b, F3, F5 |
| **D28** | De onde vêm as perguntas sugeridas do Teste | (a) exemplos genéricos por trabalho escolhido, no i18n (sem nicho); (b) nenhuma sugestão | **(a)** | F3 |

---

## 5. Princípios de experiência (valem em toda tela)

1. **Uma tela, uma tarefa, um botão principal.** Ações secundárias como contorno ou link.
2. **Língua do usuário.** Proibido na tela: "instrução", "prompt", "base de conhecimento" como jargão, "inbox", "handoff",
   "threshold", "webhook", "payload", inglês, CAIXA ALTA, "IA" dentro das telas (o nome do módulo no menu continua
   "Agentes de IA"). Gênero dos textos vem de "Tratar por: ela / ele" (D32), nunca deduzido do nome.
3. **Mostrar antes de fazer.** Teste vem antes de ligar. Pausar, tirar canal, excluir e voltar versão explicam o que acontece
   com as conversas antes de confirmar.
4. **Começar pronto.** Modelos com perguntas certas; respostas sugeridas tocáveis; primeira mensagem já escrita.
5. **Estados completos.** Toda tela/aba tem carregando (esqueleto), erro com "Tentar de novo", vazio que ensina, sucesso.
6. **Só o que existe.** Canais: só os conectados e livres; ocupados aparecem desabilitados com quem ocupa.
7. **Acessível e no celular.** Alvo ≥ 44 px, teclado completo, foco preso em diálogo/gaveta, leitor de tela, tema escuro,
   400 px sem rolagem lateral.
8. **Nada decorativo.** Todo controle grava algo que muda o comportamento real (ver D1).
9. **Construção aditiva.** Arquivos novos do fork, toque mínimo em arquivos do Chatwoot, sem coluna nova em tabela upstream,
   flag para voltar à tela antiga.

---

## 6. Experiência — tela por tela (como no protótipo)

Cada tela abaixo referencia a função do protótipo que a define (`mockup/src/<arquivo>.js`). Textos são os do protótipo,
salvo correções desta seção. Critérios de aceite detalhados: §11.

### 6.1 Seus agentes (`screens-list.js` · `viewLista`, `agentCard`, `viewVazio`)

- **Cabeçalho:** H1 "Seus agentes" (30/36 px, bold), subtítulo "Eles respondem seus clientes e chamam alguém da equipe quando
  precisam.", botão primário "Criar agente" (só quem pode editar).
- **Resumo:** contadores "N atendendo", "N pausados", "N para terminar" (este só se > 0).
- **Cartão de agente:** avatar (foto ou letra com cor), nome, selos ("Agente de Cotação", "Ajuda a equipe", "Clientes e
  equipe"), situação (Atendendo / Pausado / Pronto para ligar / Falta terminar) e uma linha de contexto:
  - externo com canal: nome do 1º canal + "e mais N"; sem canal: aviso âmbar "Sem canal: ninguém fala com ela";
  - interno: "Aparece ao lado das conversas da equipe";
  - números: "Esta semana: N respostas · passou N para a equipe"; sem semana: "Nada esta semana · N respostas em 30 dias";
    nada: "Ainda sem conversas" (BE-01);
  - rascunho: "Parou em "{Conte|Teste}". Fica guardado até você terminar ou excluir." (E2–E3 de §6.6; rascunho vazio em E1:
    "Guardado por N dias", N do prazo configurado; BE-08, BE-14, D6, D11).
- **Ações do cartão:** interruptor Atendendo/Pausado (só ligados/pausados, só quem edita; pausar confirma); "Abrir"; rascunho:
  "Continuar" ou "Escolher onde atende"/"Ligar"; menu "⋯" com "Excluir rascunho" (só rascunho).
- **Aviso fixo:** "Pausou um agente? As conversas que estavam com ele vão para a equipe na hora…" (já verdade após #1036).
- **Estados:** carregando (esqueleto), erro ("Não deu para carregar seus agentes" + "Tentar de novo"), vazio (herói
  azul-marinho + 3 modelos), "só pode ver" (sem botões de escrita + linha com cadeado).
- **Menu lateral:** um item só, "Agentes de IA" (some "Meus agentes" e "Construtor de agentes"), com a flag ligada.

### 6.2 Criar — estrutura comum (`screens-build.js`)

- Barra de etapas com 4 itens **Escolha · Conte · Teste · Ligue**, número = telas, `aria-current="step"`, ✓ nas anteriores.
- "Sair e continuar depois" (a partir do Conte, E1+) guarda o rascunho e volta para a lista ("Guardado. Continue quando
  quiser."). Na Escolha (E0) o botão é **"Voltar"**, sem aviso: ainda não existe nada guardado.
- Retomar pelo "Continuar" leva à etapa onde parou (BE-08).

**6.2.1 Escolha (`viewEscolha`).** "O que o agente vai fazer?" · 6 cartões (Tirar dúvidas, Qualificar contatos, Receber e
encaminhar, Acompanhar depois da venda, Marcar horários, Trazer cliente de volta) + 2 em linha (Ajudar minha equipe = agente
interno; Outro trabalho = `custom`). Clicar **marca**; "Continuar" avança. Sem perguntas "Externo/Interno" nem "Com/Sem
base" (padrão externo e com material opcional). **Ajudante depende do painel da equipe:** quando a instalação não tem o
painel do ajudante dentro da conversa (copiloto desligado no ambiente), "Ajudar minha equipe" não aparece, e em Ajustes
"A equipe"/"Os dois" ficam desabilitados com "Esta conta ainda não tem o ajudante dentro das conversas." (a API diz se o
painel existe; BE-32).

**6.2.2 Conte (`viewConte`).** Duas colunas:
- **Conversa com o Construtor:** uma pergunta por vez — negócio, público, quando chama a equipe, **nome** (BE-07); o que já
  foi respondido vem do backend em `knows` (BE-26), mesmo quando a pessoa responde fora de ordem. Resposta
  sugerida como chip; campo que cresce; Enter envia; anexar foto/print (até 4, 5 MB) ou arquivo (vira material); sugestão de
  link vinda do modelo (D5); estados "Pensando", "Erro ao enviar", "Não salvou", "Demorando", "Ainda respondendo" (BE-15) e "Muitas mensagens" (429 do
  BE-20: "Você mandou muitas mensagens seguidas. Espere um minuto e tente de novo.", campo desabilitado por 60 s).
- **"O que {a} {nome} já sabe":** 4 itens com ✓ (de `knows`, BE-26), barra 0–4, e **Materiais** (só para aprender), cada
  material com seu estado (Enviando, Lendo, Não deu para ler + motivo + "Enviar de novo", Precisa de outro
  arquivo, Ainda não conferido, Não é sobre o seu negócio, Pronto com nota — estado vindo do backend, BE-27), contador "N de
  30 materiais", "Colar um link", "Usar o PDF que a Clara já usa" / "Usar material de outro agente" (D16, BE-02). Sem a aba
  "Para enviar" (D20); barra "Base de conhecimento N%". Arquivo com falha **não** trava o avanço. Botão "Testar {a} {nome}" libera com as 4
  respostas.
- Depois das 4 respostas o campo **continua** disponível ("Quer mudar ou acrescentar algo? Escreva aqui.") e cada mensagem
  segue para o Construtor, que atualiza o que o agente sabe — é para lá que "Quero mudar algo" (Teste) leva.
- Interno ("Ajudar minha equipe"): gênero por D32; roteiro próprio (No que ajuda · Quem usa · O que ele evita · Nome), textos pelo gênero escolhido.

**6.2.3 Teste (`viewTeste`, `testPhone`).** "Teste antes de ligar" · no topo, **"Como se apresenta"** (Nome e Primeira
mensagem, "É uma sugestão. Mude como quiser.", D29) — a edição é salva no agente na hora (PATCH); mudar **recomeça a conversa de teste** (a anterior some), com o aviso "Você
mudou como {ela} se apresenta. O teste recomeçou: faça uma pergunta."; só conta como teste válido uma resposta dada depois da
mudança, e a primeira dessa conversa já traz o cumprimento novo; "Sair e continuar depois" guarda os dois · simulação de celular "{nome} · Teste · só você vê",
perguntas sugeridas (exemplos por trabalho escolhido, do i18n, D28), resposta chegando em partes, "Certeza N%", "Material usado (n)", faixa âmbar "Aqui ela passaria para a
equipe. {motivo}", "Limpar conversa", anexo só de foto ("Anexar foto", até 4, 5 MB). Lateral "Ficou bom?": "Está bom,
continuar" (libera após **1 teste válido**: uma resposta concluída, §6.6) e "Quero mudar algo". Dica: "Abaixo de cada resposta aparece a certeza dela. Quando ela
decide chamar alguém da equipe, aparece em amarelo, com o motivo." Estados "Pensando" (o teste é assíncrono: 202 + consulta),
"Demorando" (passou de `REQUEST_TIMEOUT`, 180 s, sem resposta: "Está demorando mais que o normal.", continua esperando, com "Tentar de novo"; o pedido expira no TTL de 30 min e vira "Não respondeu"), "Ainda
montando", "Não respondeu" e "Muitas mensagens" (429: "Você testou muitas vezes seguidas. Espere um minuto."). Teste
invalidado por material (§6.6): "{A} {nome} aprendeu um material novo. Teste de novo antes de ligar." Com ferramenta que grava
em outro sistema: "Ferramentas que gravam em outro sistema rodam de verdade no teste." (D27). Para quem só vê, ferramenta que
não rodou por permissão: "Neste teste, {ela} não usou {ferramenta}: só quem edita testa essa consulta." (D17). O aviso de D27 só aparece para quem edita. O teste usa o **mesmo caminho da produção** (D1-a, BE-12); no Agente de Cotação aparece
"No teste a cotação não é feita de verdade" quando o resultado traz `skipped_tools` (BE-12) — nunca deduzido do texto.
**Ajudante da equipe (interno, D26):** o Testar usa o caminho do ajudante dentro da conversa, com uma conversa de exemplo
(i18n) como contexto; para quem só vê, vale D17; título "Teste como ele ajudaria numa conversa"; sem a faixa "passaria para a equipe"; esse teste
conta para ligar.

**6.2.4 Ligue (`viewLigue`).** "Confira e escolha onde {a} {nome} atende":
- **Onde atende:** canais livres (radio), 1 só já vem marcado; "Conectar um WhatsApp novo" (só administrador; quem edita sem
  ser administrador lê "Peça a quem administra a conta para conectar um WhatsApp."); "Canais ocupados (n)"
  desabilitados com "Já tem a Clara atendendo aqui. Cada canal tem um agente." (BE-11).
- **Como se apresenta:** só no resumo (Nome e Primeira mensagem, com "Mudar" que volta ao Teste — D29). **Sem** "Perguntas
  para puxar conversa" (D18).
- **Quando atende:** Sempre / No horário comercial / Fora do horário comercial; se o canal escolhido não tem horário
  configurado, aviso "Este canal não tem horário definido: {ela} vai responder sempre." com link para o horário da caixa (BE-11).
- **Resumo** em frase + material pronto/base N% · "Ligar {a} {nome}" (atômico, BE-03, BE-04) · "Deixar desligada por
  enquanto" (vira "Pronto para ligar").
- Estados: "Nenhum canal livre", "Falhou ao ligar" ("Nada mudou: ela continua desligada.").
- Interno: sem canal; "Onde a equipe encontra"; botão "Ligar o {nome}".

**6.2.5 Pronto (`viewPronto`).** Faixa verde "A {nome} está atendendo no {canal}." / "O {nome} já aparece para a equipe." +
cartões "Ver como está indo", "Voltar para seus agentes", e (interno) "Ver numa conversa" — abre a lista de conversas da
pessoa com o aviso "Abra uma conversa: o {nome} aparece no painel ao lado."; quem não vê nenhuma caixa não vê o cartão.

### 6.3 Painel do agente (`screens-panel.js`)

- **Cabeçalho:** "← Seus agentes", avatar 64 px, nome + situação, resumo (`human_card`), interruptor ou "Continuar montagem"
  / "Ligar". Agente de Cotação: aviso "A forma de cotar da {nome} é mantida pela Hub2You. Você escolhe nome, horário, jeito
  de cotar e para quem ela responde. Conexão com as seguradoras fica em Cotação."
- **Abas** (nesta ordem): Como está indo · Testar · O que sabe · Onde atende · Ajustes · Ferramentas.
  - Só pode ver: só "Como está indo" e "Testar". Interno: sem "Onde atende". Ferramentas: só admin da plataforma e nunca no
    Agente de Cotação. Aba proibida pela URL cai em "Como está indo". Aba padrão = "Como está indo".

**Como está indo (`tabResumo`).** Agente interno (D14): "O {nome} ajuda a equipe dentro das conversas. Os números de uso
ainda não aparecem aqui." + "Ver numa conversa" (mesmo destino do Pronto). Demais: 7/30 dias; 5 números (conversas atendidas, respostas enviadas, % que passaram para a equipe
(N), certeza média, % que usaram seus materiais); alerta do servidor (`insight`) com "Ensinar"; "Resultado das conversas" com
5 botões que abrem gaveta com a lista real (máx. 50, "mostrando as 50 mais recentes"; só conversas de caixas que a pessoa
pode ver, D12); gráfico "Dia a dia"; "Por que passou
para a equipe" com rótulos pt-BR para **todos** os códigos de `ALLOWED_REASONS` (`low_confidence`, `ai_unavailable`, `human_requested`, `escolhas_incompletas`,
`missing_knowledge`, `policy`, `audience`, `schedule`, `other`). Estados: carregando, erro, vazio da semana com "Ver 30
dias", vazio total com "Testar".

**Testar (`tabTestar`).** Mesma simulação da criação, legenda "Como ler o teste" com: "Certeza — Quanto {ela} confia na
resposta. Quem decide passar para a equipe é a regra de 'Quando passa para a equipe'."; "Material usado — Mostra de qual
material veio a resposta."; "Amarelo — Aqui a conversa iria para a equipe, e o motivo." e "Ensinar algo que faltou" (quem edita).

**O que sabe (`tabSabe`).** Materiais (só "Para aprender"; a aba "Para enviar" sai, D20), todos os estados (BE-27),
"Adicionar material" (link / arquivo), confirmação para tirar, limite 30 (contador e aviso, igual à criação), barra
da base; "Perguntas que a equipe respondeu" com liga/desliga, Aprovar / Mudar e aprovar / Ignorar e "Da conversa #N".
Agente de Cotação: só "O que a Lia cota" (ramos).

**Onde atende (`tabOnde`).** Canais conectados com "Tirar deste canal" (confirma; conversas vão para a equipe); "Colocar em
outro canal" (só livres; rascunho e pausado desabilitados com "Ligue {a} {nome} para colocar em outro canal." —
o backend recusa `agent_not_active`); aviso "não está em nenhum canal"; erro de conexão com a
mensagem específica do servidor (BE-10); "Conectar um WhatsApp novo" (só administrador, mesma regra do Ligue).

**Ajustes (`tabAjustes`).** Seções, cada uma com seu "Salvar". Num rascunho já testado, salvar algo que muda o texto do
modelo mostra "Salvo. Teste {a} {nome} de novo antes de ligar." (§6.6):
1. Foto e nome (trocar/tirar foto; nome — sincroniza o bot da conversa, BE-16, e o modo de se apresentar, D19).
2. O que faz — resumo + "Mudar conversando" (retoma a conversa da criação; só no modo guiado, D22, BE-05; no manual o botão
   fica desabilitado com "Para mudar conversando, volte ao modo guiado."; sem versão guiada guardada, "Este agente foi escrito à
   mão. Para mudar, edite as instruções." e o interruptor de modo fica travado em manual) + "Escrever as instruções eu mesmo" (confirma;
   contador de 50.000). **Voltar ao modo guiado** (D25): só aparece quando existe versão guiada guardada; confirma "O texto
   que você escreveu deixa de valer e {ela} volta para a última versão montada pela conversa."; restaura essa versão com o seu
   andaime; o texto da pessoa fica em Versões.
3. Onde atua — Clientes / A equipe / Os dois (recusa "A equipe" com canal: "Tire a Clara dos canais antes.", BE-10).
4. Como fala — Primeira mensagem e Quando não souber responder (efeito real por D18), Jeito de falar (Amigável, Profissional,
   Neutro, Descontraído, Do meu jeito + texto; grava a frase em português, D10).
5. Quando passa para a equipe — Quando estiver em dúvida ("Chama a equipe quando não tem segurança na resposta.") /
   Sempre oferecer uma pessoa / Nunca (efeito real, D1; sem régua de percentual) + Para quem
   vai: Quem estiver livre / Uma pessoa / Um time (escolha por `ChoiceSelect`, D2, BE-06).
   Convivência com "Quando não souber responder" (o que o cliente recebe quando o agente não sabe):

   | Opção | O agente não sabe a resposta | Por iniciativa própria |
   |---|---|---|
   | Quando estiver em dúvida (padrão) | diz a frase de "Quando não souber" e passa para a equipe | passa quando não tem segurança |
   | Sempre oferecer uma pessoa | diz a frase e passa | oferece falar com uma pessoa |
   | Nunca | diz a frase e **não** passa | nunca oferece pessoa |

   "Nunca" tem exceções que continuam passando: o cliente pede uma pessoa, ou fora do horário ou do público (texto da opção:
   "Não oferece uma pessoa. Ainda passa quando o cliente pede." — D33).
   Sem frase de "Quando não souber", vale o comportamento de hoje. O resumo do Ligue reflete a opção gravada.
6. Para quem responde — Todo mundo / Só alguns clientes (condições, grupos e/ou, contato desconhecido).
7. Quando atende — 3 opções, com o aviso de canal sem horário (BE-11). Com vários canais, o aviso lista os canais sem horário,
   cada um com o link para o horário da sua caixa ("Estes canais não têm horário definido: {ela} responde sempre neles.").
8. Versões anteriores — "Cada mudança nas instruções fica guardada." Lista (Atual + "Voltar para esta" com confirmação)
   ou vazio; rótulos: Edição manual, Material novo entrou, Versão restaurada, Mudança conversando, Antes de escrever eu
   mesmo; autor ou "Automático" (BE-23).
9. Pausar/Ligar e Excluir (texto do que acontece com conversas e materiais). Rascunho (E1–E4): no lugar de Pausar/Ligar,
   "Continuar montagem", que leva à etapa que falta (mesmo destino do "Continuar" da lista: E1/E2 → Conte, E3 → Teste, E4 →
   Ligue, E2m → Ajustes › O que faz). Ajudante interno: "O {nome} some do painel das
   conversas até você ligar de novo." (pausar) e "O {nome} some do painel das conversas. Os materiais dele são apagados."
   (excluir) — ele não atende conversa.
**Ajudante interno:** não mostra "Quando passa para a equipe", "Para quem vai", "Para quem responde" nem "Quando atende"
(nenhum tem leitor no ajudante: `operate.rb:45` corta o interno e o copiloto não lê essas chaves), nem a Primeira mensagem
(no Teste, no Ligue e em Como fala). No `both`, um aviso acima das seções de atendimento: "As seções abaixo valem só quando {ela} atende clientes. No
painel da equipe, isto não se aplica." No ajudante, um aviso no lugar delas: "O {nome} só ajuda a equipe dentro das
conversas. Horário, público e passagem para a equipe não se aplicam a ele."
Agente de Cotação: Foto e nome, **Jeito de cotar** (Consultivo/Objetivo; "Quando {a} {nome} explica a cobertura…"), **Horário
que {ela} informa ao cliente** (texto, BE-17), Para quem vai (só a parte de pessoa/time; as três opções de "Quando passa" não
aparecem — não têm efeito na Lia), Para quem responde, Quando atende, Pausar/Excluir. Não mostra O que faz, Como fala, Onde
atua, Versões, Ferramentas.

**Ferramentas (`tabFerramentas`, só admin da plataforma).** Lista (nome, Ligada/Desligada, identificador · método, quando
usar; Testar / Mudar / Excluir com confirmação no próprio app — sem `window.confirm`), "Nova ferramenta" em diálogo (nome,
identificador, quando usar, método GET/POST, endereço, corpo JSON, cabeçalhos com "segredo" mascarado, informações que pede
ao cliente, ligada), resultado do teste em bloco, limite 10, "Começar pelo modelo de consulta de estoque".

### 6.4 Outras telas e diálogos (`screens-extra.js`, `main.js`)

- **Conectar um WhatsApp** (`viewConectar`): número (D7) → código QR, passos "Como ler", dica "Use um número da empresa";
  estados Esperando leitura / Conectando / Conectado ("Escolher o agente", volta à origem) / Não conectou ("Gerar outro
  código").
- **Dentro da conversa** (`viewConversa`): painel do ajudante da equipe (resumo, "Sugerir resposta", "Resumir de novo",
  pergunta livre; vazio com "Criar ajudante") e "Marcar resposta como errada" (5 motivos como opções, "Qual seria a resposta
  certa?", botão libera após escolher). O que for marcado aparece na gaveta "Respostas marcadas como erradas" com motivo,
  resposta sugerida e "Ensinar" (BE-28).
- **Conectar um WhatsApp:** também os estados "Verificando", "Sessão desligada" (texto próprio + "Reconectar") e o tempo
  restante do código (60 s no primeiro, 20 s nos seguintes), reaproveitando `ConnectionPage.vue`/`wahaQrWindow.js`.
- **Gaveta "Resultado das conversas"** (`openDrill`): lista real, foco preso, Esc fecha.
- **Textos de excluir (D34, depois do #1063):** externo "{A} {nome} sai da lista e para de atender. As conversas com {ela}
  vão para a equipe."; ajudante "O {nome} sai da lista e some do painel das conversas."; rascunho "O rascunho sai da
  lista."
- **Diálogos de confirmação:** pausar, excluir agente/rascunho, tirar material, tirar canal, escrever instruções, voltar ao
  modo guiado (D25), voltar versão, excluir ferramenta, mudar conversando, adicionar material, mudar e aprovar pergunta.

**Não implementar (só do protótipo):** faixa "Protótipo", "Todas as telas", "Ver como", "Ver esta tela como", selo "Novo",
texto "Respostas do teste são exemplos", botões "Simular arquivo com problema" e "Adicionar foto de exemplo", linha "Dados reais
da conta, até 05/10", a frase da gaveta "No produto aparecem as conversas reais… para não expor clientes." (a frase "Algumas conversas são de
caixas que você não vê." **fica**, CA-RES-05), a
página "Dentro de uma conversa" como página própria (no produto são peças da tela de conversa), toasts de demonstração ("No
produto…", "Material de exemplo.", "Enviando de novo.") e o sufixo "(exemplo)" do resultado da ferramenta.

**Correções obrigatórias sobre o protótipo (acessibilidade):**
- Opções de escolha única usam `role="radio"` + `aria-checked` (o protótipo usa `aria-pressed` em alguns chips).
- Abas com setas do teclado, `aria-controls` e `role="tabpanel"`.
- A gaveta prende o foco e fecha com Esc.
- "pick" vira `ChoiceSelect`.
- Régua de certeza sai (D1-a). Se D1-b: rótulo + `aria-valuetext` em %.
- Gráfico com `role="img"` e texto alternativo com os totais.

**Correções de texto sobre o protótipo (o protótipo prometia algo que o sistema não faz):**
- Material `needs_review`: "Ainda não conferido" (âmbar) + "Lido, mas a conferência não terminou. {Ela} ainda não usa este
  material." + "Enviar de novo" — o agente **não** usa material nesse estado (`retriever.rb:113-115`).
- Legendas e textos com percentual de certeza saem (D1-a) — textos novos em §6.2.3, §6.3 Testar e Ajustes.
- "Toda mudança fica guardada" → "Cada mudança nas instruções fica guardada." (só instruções têm versão, BE-23).
- Aviso da Lia: "jeito de falar" → "jeito de cotar".
- Certeza média nula: "Sem dados" (o protótipo mostra 0%).
- Anexo no teste: "Anexar foto" (o teste aceita só imagem).
- Conte: campo continua depois das 4 respostas.
- Cartão do agente interno sem "Ainda sem uso" (o uso não é medido, D14).
- Sem "Parou em Escolha" (o rascunho nasce depois da Escolha, §6.6); na Escolha, "Voltar" no lugar de "Sair e continuar
  depois".
- Voltar ao modo guiado pede confirmação (o protótipo volta direto, D25).
- Testar do ajudante sem a faixa "passaria para a equipe" (D26).
- Aviso da Lia no Testar: aparece só quando o resultado traz `skipped_tools`, com o texto curto "No teste a cotação não é
  feita de verdade." (o protótipo mostra fixo e mais longo).
- Resumo do Ligue: uma frase por opção de "Quando passa" (o protótipo mostra só a do padrão).
- Sem "Perguntas para puxar conversa" e sem a aba "Para enviar" (D18, D20).
- "Quando passa para a equipe" não aparece no Agente de Cotação (sem efeito nele); "Jeito de cotar" usa {nome}.
- Botão "Conectar um WhatsApp novo" só para administrador.
- Nota de passagem dentro da conversa ("A {nome} passou esta conversa para a equipe: {motivo}.") é nova (BE-24).

### 6.5 Matriz controle → leitor → efeito (CA-GERAL-14)

Uma linha por controle do protótipo. "Leitor" é quem usa o valor **durante o atendimento** (verificado no código em 05/10; cada PR reconfere as linhas das telas que entrega na `origin/main` do dia — o #1036 deslocou algumas referências).
Controle sem leitor só entra com decisão. Cada PR de front confere as linhas das telas que entrega; a lente de produto de toda
revisão confere a matriz inteira.

| Controle (tela) | Grava | Leitor em atendimento | Efeito hoje | Decisão nesta entrega |
|---|---|---|---|---|
| Situação Atendendo/Pausado (lista, painel) | `status`, `enabled` | `operate.rb:44` | Responde ou não; pausar devolve conversas (#1036) | Mantém |
| Nome (Teste, Ajustes) | `name` | **nenhum** no texto do modelo (`prompt_builder.rb` não usa `agent.name`; o nome vive na instrução); bot espelho com o nome da conexão | Renomear não muda como o agente se apresenta | **D19** (BE-29) + BE-16 |
| Foto (Ajustes) | avatar | bot espelho (BE-16) | Hoje não chega às conversas | BE-16 |
| Primeira mensagem (Teste, Ajustes) | `greeting` | **nenhum** | Nenhum | **D18**; escondida no ajudante interno (sem leitor) |
| Perguntas para puxar conversa (Ligue) | `starter_questions` | **nenhum** | Nenhum | **D18** — saem da tela |
| Quando não souber responder (Ajustes) | `fallback_message` | `prompt_builder.rb:261` (só cita que existe) e `answerer.rb:618-625` no caminho com portão — que é o do copiloto: no ajudante interno, quando o portão segura a resposta, a frase vira o que o ajudante mostra à equipe | No atendimento ao cliente, nenhum; no ajudante, sim | **D18**; no ajudante fica visível com o rótulo "Quando não souber, o ajudante mostra à equipe" |
| Jeito de falar (Ajustes) | `tone` | `prompt_builder.rb:242-246` | Entra cru no texto do modelo | Mantém (+ D10) |
| Quando passa para a equipe (Ajustes) | `config.handoff_strategy` | **nenhum** | Nenhum | **D1** (BE-12); oculto no Agente de Cotação |
| Régua de certeza (Ajustes, legenda do Testar) | `config.confidence_threshold` | só caminho com portão (`answerer.rb:649`) | Nenhum no atendimento real | **Sai** (D1-a) |
| Para quem vai (Ajustes) | `config.handoff_target_*` | **nenhum** | Nenhum | **D2** (BE-06) |
| Para quem responde (Ajustes) | `config.audience`, `audience_unknown_contact` | `operate/engagement_gate.rb` | Filtra quem o agente atende | Mantém |
| Quando atende (Ligue, Ajustes) | `config.response_window` | `operate/engagement_gate.rb:39-47` | Caixa **sem horário** = sempre | Mantém + aviso quando a caixa não tem horário (BE-11) |
| Onde atua (Ajustes) | `actuation` | `operate.rb:45` (interno não atende), copiloto | Externo/ajudante/os dois | Mantém |
| O que faz / Mudar conversando (Ajustes) | instrução via Construtor | `prompt_builder.rb` (instrução) | Muda o atendimento | Mantém, só em modo guiado (**D22**, BE-05) |
| Escrever as instruções eu mesmo (Ajustes) | `mode`, `instruction` | `prompt_builder.rb` | Muda o atendimento | Mantém |
| Materiais "Para aprender" | `sources` (kind knowledge) | `retriever.rb:80-131` — exclui `needs_resend`/`needs_review`; "fora do negócio" só quando resta material no escopo; `review_status` nulo entra | Responde com o material | Mantém; estado e "usa ou não" vêm do backend pela mesma regra (BE-27) |
| Materiais "Para enviar" (mídias) | `sources` (kind media) | **nenhum** no atendimento (só o Construtor cita a lista, `builder.rb:1459`) | O cliente nunca recebe o arquivo | **D20** — aba sai nesta entrega |
| Perguntas que a equipe respondeu (O que sabe) | `config.faq_suggestions` + aprovações | `faq/conversation_listener.rb`, `faq/knowledge_writer.rb` | Gera sugestões; aprovadas viram material | Mantém |
| Canais (Ligue, Onde atende) | `agent_inboxes` | `operate.rb` | Onde atende | Mantém |
| Jeito de cotar (Lia) | `config.agente_de_cotacao` | `quote_agent/builder.rb` | Muda o texto da Lia | BE-17 |
| Horário que a Lia informa (Lia) | `config.agente_de_cotacao.horario` | `quote_agent/builder.rb:292-293` | Texto dito ao cliente | BE-17 (campo próprio) |
| Marcar resposta como errada (conversa) | `Captain::MessageReport` | só contagem `wrong_replies` | Motivo e resposta certa ninguém lê | BE-28 (mostrar na gaveta) |
| Controles de atendimento no ajudante interno (Quando passa, Para quem vai, Para quem responde, Quando atende) | `config.*` | **nenhum** no ajudante (`operate.rb:45`; `copilot.rb:23` não lê) | Nenhum | Escondidos no interno (§6.3) |
| Testar (criação e painel) | — (leitura) | mesmo caminho do atendimento (BE-12), **exceto** público e horário, que não se aplicam no teste; ajudante interno = caminho do copiloto (D26) | Mostra o comportamento real da resposta | BE-12; a tela avisa "No teste, horário e público não são aplicados." |
| Escolha do trabalho (Criar) | `agent_type` (rascunho) | Construtor (roteiro/esqueleto, `builder.rb`); no atendimento, só o Agente de Cotação usa o tipo | Muda as perguntas da criação | Mantém |
| Ferramentas (só admin da plataforma) | `autonomia_agent_tools` (ligada, quando usar, método) | catálogo do Answerer (`answerer.rb`, `tools/bound.rb`) — no atendimento e no teste | O agente consulta sistemas de fora | Mantém; D17 |
| Voltar para esta versão (Ajustes) | instrução | `prompt_builder.rb` | Troca a instrução no atendimento | Mantém; BE-23 |

### 6.6 Máquina de estados da criação (comportamento)

Fonte da verdade para rotas (§8), BE-03/BE-08/BE-14 e CA-LISTA/CA-CRIAR. Define **o que acontece**; o mecanismo exato (onde
cada marca é gravada, qual sinal o front manda) é decidido no desenho técnico do B2/B3 (§7.0), cobrindo os casos de §7.2.

| # | Estado | Como se chega | Lista mostra | "Continuar" leva a |
|---|---|---|---|---|
| E0 | Escolhendo | "Criar agente" (nada no servidor) | — | — |
| E1 | Começando | "Continuar" na Escolha; o rascunho passa a existir (com id) **antes** de abrir o Conte | "Falta terminar · Parou em Conte · Guardado por N dias" (sem nenhuma resposta e sem material) | Conte |
| E1x | Começo falhou | a abertura falhou antes de existir rascunho | — (fica na Escolha com "Não deu para começar." + "Tentar de novo") | — |
| E2 | Conversando | ≥ 1 resposta ou ≥ 1 material | "Falta terminar · Parou em Conte · Fica guardado até você terminar ou excluir" | Conte |
| E3 | Pronto para testar | a pessoa toca "Testar {a} {nome}" (com as 4 respostas) e a instrução é **gerada sem nenhuma pergunta a mais** e **sem travar** por material com falha ou pendente | "Falta terminar · Parou em Teste" | Teste |
| E4 | Testado | um teste feito **por quem edita** terminou sobre a instrução **atual** | "Pronto para ligar" | Ligue |
| E5 | No ar | "Ligar" | "Atendendo" | Abrir |
| E6 | Pausado | interruptor | "Pausado" | Abrir |

**Quem muda o estado ou a instrução (todos os atores):**

| Ator | O que faz | Em E1–E4 (antes de ir ao ar) | Em E5/E6 (no ar ou pausado) |
|---|---|---|---|
| Pessoa na tela nova | responde no Conte, testa, Mudar conversando, escreve à mão, volta versão, pausa/religa | segue §6.6; mudar a instrução invalida o teste | continua no estado; religar só exige instrução (D24) |
| Sistema (reescrita automática quando um material termina de ser lido; pergunta da equipe aprovada) | reescreve a instrução sozinho | invalida o teste **e a tela diz por quê**: "{A} {nome} aprendeu um material novo. Teste de novo antes de ligar." | continua no estado (D24) |
| Tela antiga (contas sem a flag) | liga por PATCH, como hoje | sem exigir teste (D23) | como hoje |
| Guia da Plataforma e API | criam e ligam por POST/PATCH | sem exigir teste enquanto a flag existir (D23); ligar sem instrução é recusado também no create (BE-04, D30) | como hoje |
| Cotação (criação da Lia) | cria o Agente de Cotação já ativo | — | como hoje |

**Regras:**
- **Ligar pela tela nova** (E4→E5) exige instrução **e** teste válido da instrução atual. Recusas, nesta ordem: sem instrução;
  sem teste válido. A tela leva ao passo que falta. Outros caminhos: tabela acima (D23).
- **Religar um pausado** (E6→E5) pelo interruptor só exige instrução (D24) — inclusive legado sem teste registrado e a Lia.
- A lista **nunca** mostra "Falta terminar" para agente que já esteve no ar.
- **Antes de ir ao ar**, toda mudança depois do teste que altera **o que o agente responde ou por onde responde** —
  o texto que o modelo lê, os materiais que ele consulta (pôr ou tirar) ou a atuação ("Onde atua") — **invalida o teste**:
  volta a E3, a conversa de teste recomeça e a tela mostra o motivo. Exemplos (não é lista fechada): instrução por Conte,
  Mudar conversando, material que reescreve, texto manual, voltar versão; Nome, Primeira mensagem, "Quando não souber", Jeito
  de falar, "Quando passa"; tirar material; trocar Clientes/A equipe/Os dois. **Depois de ir ao ar**, nada disso muda o
  estado (D24).
- **Teste válido** é uma resposta **concluída**, por quem edita, na **conversa de teste atual**. Toda mudança que invalida o
  teste (pessoa no Teste, no Conte ou em Ajustes; material que reescreve) **recomeça a conversa de teste**: a tela limpa a
  conversa e mostra o motivo. Dentro da conversa atual, qualquer turno vale (a 1ª pergunta deu erro e a 2ª respondeu →
  válido). Erro, "Não respondeu", "Demorando" sem resposta, pedido expirado, 429 ou "Ainda montando" não contam. Resposta em
  que uma ferramenta não rodou (`skipped_tools`) conta — a tela avisa (D17, D27). "Está bom, continuar" só libera depois de um
  teste válido.
- **Campo editado à mão** (Nome e Primeira mensagem no Teste; campos de Ajustes) fica protegido: o fechamento seguinte do
  Construtor, na criação ou na retomada, não o troca, salvo quando a própria pessoa pede a troca na conversa (o modelo decide
  e devolve o campo pedido; sem regex sobre o texto).
- **Renomear invalida o teste em todo modo** (guiado ou manual): é decisão de produto — o nome aparece para o cliente no
  espelho e no cumprimento —, mesmo onde não entra no texto do modelo (manual).
- **Legado e rascunhos sem conversa do Construtor** (criados pela API, pelo Guia): com instrução → E3; guiado sem instrução e
  sem material → E1 (o que a lista diz e o que a limpeza faz são coerentes). **Manual sem instrução** → E2m: lista "Falta
  terminar · Falta escrever as instruções" (sem prazo: a limpeza só apaga guiado); "Continuar" leva a Ajustes › O que faz.
  Todo rascunho, com ou sem conversa, consegue chegar a E5 pela tela nova.
- **Limpeza (BE-14):** só apaga rascunho em E1 (sem nenhuma resposta, sem instrução e sem nenhum material) parado há 48 h.
  Qualquer resposta, instrução ou material (de qualquer idade) protege o rascunho. O prazo mostrado ("Guardado por N dias")
  vem do valor configurado da limpeza, exposto pela API.
- "Parou em Escolha" não existe (o rascunho nasce ao sair da Escolha) — divergência registrada em §6.4.
- A lista mostra o estado de cada agente sem carregar as conversas do Construtor inteiras (uma consulta para N agentes).

### 6.7 Matriz de variantes (passo 7 do §10.3)

Toda regra ou decisão é conferida contra estas dimensões. A célula é "vale", "não se aplica (motivo)" ou uma decisão.

| Regra | Externo guiado | Externo manual | Ajudante interno | Os dois | Cotação (Lia) | Sistema (Guia) |
|---|---|---|---|---|---|---|
| Teste para ligar pela tela nova (D15, D23) | vale | vale | vale (caminho do copiloto, D26) | vale | não se aplica (nasce ativa pela Cotação) | não aparece |
| Invalidação antes de ir ao ar (§6.6) | vale | vale (texto manual salvo) | vale | vale | não se aplica | — |
| Depois de ir ao ar não muda estado (D24) | vale | vale | vale | vale | vale | — |
| Não ligar sem instrução (BE-04, D30) — publish, PATCH, create | vale | vale | vale | vale | vale (instrução mantida) | — |
| "Quando passa" no texto do modelo (BE-12) | vale | vale | **não** (escondido) | só parte externa | **não** | **não** |
| Para quem vai / Para quem responde / Quando atende | vale | vale | **não** (escondido) | só parte externa | vale (só alvo, público, horário) | — |
| Primeira mensagem e "quando não souber" (BE-30) | vale | vale | Primeira mensagem escondida; "quando não souber" já tem leitor no copiloto (sem mudança) | parte externa | **não** | **não** |
| Nome no texto do modelo (BE-29) | vale | não (fica no texto da pessoa) | vale | vale | pelo BE-17 | **não** |
| Retomada "Mudar conversando" (BE-05) | vale | recusa `manual_mode` | vale | vale | recusa `instrucao_mantida` | — |
| D17 (só ver não roda ≠ GET) | vale | vale | vale | vale | cotação nunca roda | — |

Portas de entrada conferidas para cada regra: tela nova, tela antiga, Guia, API, Cotação, jobs (limpeza, reescrita por
material) e o **funil do CRM** (`Crm::Ai::HandoffExecutor`, que passa conversa com o seletor próprio dele: "Para quem
vai" do agente não se aplica a ele, D31). As exceções estão na tabela de atores de §6.6.

---

## 7. Requisitos de backend

### 7.0 Altitude (o que o PRD fixa e o que o PR decide)

Cada BE abaixo fixa **comportamento e invariantes**. Onde aparece um mecanismo (nome de chave, flag, endpoint), ele é
**sugestão**: o desenho técnico definitivo é escrito no PR, em `docs/agentes-ia-redesign/design/<PR>.md`, com o código aberto
(conferido na `origin/main` do dia), specs primeiro, e revisado pelo protocolo §10.3. O PR só é aceito quando **cada caso
obrigatório** do BE em §7.2 tem spec. Motivo: causa raiz C7 em `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md`.

### 7.1 Requisitos

Nenhum exige migration. Toda mudança é aditiva; endpoints antigos continuam para as telas antigas. Toda recusa nova sai com
`{ error, code }` estável (o Guia da Plataforma executa ações de agentes e precisa do `code`). Toda mudança de controller,
params ou GET regenera `bundle exec rails autonomia:guia:formatos` e roda `spec/services/autonomia/guide`.

| ID | Requisito | Detalhe técnico | Risco prod | Esforço |
|---|---|---|---|---|
| **BE-00** | Flag do redesign por conta (D3) | `Autonomia::Agents::Config.redesign_enabled?(account)` = ENV `AUTONOMIA_AGENTS_REDESIGN` + `internal_attributes['autonomia_agents_redesign']`; exposto em `_account.json.jbuilder` como `autonomia_agents_redesign_enabled`; helpers `enable_redesign_for!`/`disable_redesign_for!` (só specs e ambiente local); botão no Super Admin `SuperAdmin::AccountsController#toggle_agents_redesign` (rota + botão na tela da conta, mesmo padrão de `toggle_insurance`) — é por ele que se liga/desliga em produção, sem console. Endpoints novos **não** dependem da flag. | Zero | P |
| **BE-01** | Números e canais na lista sem N+1 | Service `Autonomia::Agents::ListStats` com **uma** consulta agregada em `autonomia_agent_events` (índice `idx_autonomia_events_agent_created`), janela **idêntica** ao Analytics (`(dias-1).days.ago.beginning_of_day`) e `HANDOFF_TYPES`; `index` entrega `stats: {week:{replies,handoffs}, month:{replies,handoffs}}` e `channels: [{inbox_id,name,channel_type}]` (`includes(agent_inboxes: :inbox)`). | Baixo | P |
| **BE-02** | Usar material de outro agente | `GET agents/:agent_id/sources/reusable` (só `knowledge` aceitos de outros agentes da conta; exclui agentes de sistema e a fonte de FAQ) e `POST agents/:agent_id/sources/copy {source_id}` (origem resolvida pela conta → 404 cross-tenant; limite 30; anexa a mesma blob; enfileira `IngestJob`; `metadata.copied_from_source_id`). | Baixo | M |
| **BE-03** | Ligar atômico | `POST agents/:id/publish {inbox_id?, agent:{config:{response_window}}}` (sem `name` e `greeting`: são editados no Teste por PATCH, D29; `name`/`greeting` no corpo → 422 `publish_field_not_allowed`) → `Autonomia::Agents::Publisher` numa transação: pré-condição BE-04 → atributos → `enabled+active` (dispara `sync_mirror_bots` do #1036) → `InboxConnector` se `inbox_id`; erro = rollback + 422 `{error, code}`; `RecordNotUnique` → `inbox_already_connected`; ordem das recusas: `missing_instruction` antes de `missing_test` (sem teste válido da instrução atual, §6.6, D15). Interno: `inbox_id` proibido. `missing_test` só no `publish` (escopo D23): PATCH `status`/`enabled`, create, Guia, tela antiga e Cotação continuam como hoje; religar pausado pelo PATCH só exige instrução (D24). | Baixo (aditivo) | M |
| **BE-04** | Não ligar sem instrução | Guarda em controller/service (não no model): na transição para "atendendo" (`publish`, PATCH **e create** com `status`/`enabled` ativos, D30) exige `instrucao_do_sistema.present?` → 422 `missing_instruction` (en + pt_BR). Atualiza `external_agent_lifecycle_spec.rb:32-40`. | Baixo (só a transição) | P |
| **BE-05** | Retomar a conversa da criação ("Mudar conversando") | `GET agents/:id/build_thread` (última thread do agente, jbuilder de `build_threads/show`), **exige `autonomia_manage`** (before_action própria; a conversa tem mensagens e imagens do dono); só em `mode=guided` (manual → 422 `manual_mode`, D22); zerar `force_close` ao retomar; ao fechar uma retomada, o `apply_builder_config!` só pode mudar `instruction`, `human_card`, `scaffold`, `handoff_rule` e `config.guardrails` (os "Limites duros" que o modelo lê, `prompt_builder.rb:248-252`) — `config.voice` só é gravada na criação; `name`, `greeting`, `fallback_message`, `tone`, `starter_questions` e `agent_type` ficam como estão; manter recusa `InstrucaoMantida`. **Invariante:** a instrução gerada nunca aparece na API (NR-10). Spec: só-ver → 401; outra conta → 404; manual → 422; retomada não muda campos editados à mão. | Baixo | P |
| **BE-06** | Para quem vai (D2) | Config `handoff_target_type ∈ any|member|team` + `handoff_target_id`; validação: `member` precisa ser membro da **caixa da conversa** (ou administrador) — senão cai em `any` com log `alvo_invalido`; `team` precisa ser time da conta,; o funil do CRM (`Crm::Ai::HandoffExecutor`) **não muda** (D31: spec de não-regressão — conversa passada pelo funil continua com o seletor do CRM, sem alvo no evento, mesmo com o agente em "Um time"); a devolução de conversas ao pausar, excluir ou tirar canal (`AgentInbox#release_bot_conversations!`, #1036) também não segue "Para quem vai" e não gera nota (não é passagem decidida pela IA), como hoje; `handoff_target_type` entra no slice do `_agent.json.jbuilder` e na lista do BE-19; corrigir o comentário de `agent.rb:125-127` (`Operate::HANDOFF_STRATEGIES` não existe); `Operate::HandoffRouter` chamado antes do `bot_handoff!` nos **três** pontos que liberam a conversa: `Responder#handoff_if_signaled`, `Responder#skip_for_humans` e `AvisoAoAtendente#escalar` (spec para os três): `member` → `Conversations::AssignmentService`; `team` → `update!(team:)` e a pessoa é escolhida pela distribuição automática da caixa, só entre membros do time (sem distribuição ligada ou sem ninguém disponível, a conversa fica com o time e sem responsável, como hoje sem time — o roteador nunca atribui gente de fora; o funil do CRM pode atribuir depois, D31); alvo inválido → `any` + log `[autonomia][handoff] alvo_invalido`. O evento `handed_off` registra o alvo atribuído pelo roteador (pessoa ou time), para a Q17 olhar a atribuição da passagem e não o responsável atual. Alvo válido = `inbox.assignable_agents` (membros + administradores, `inbox.rb:185-187`). Padrão `any` = comportamento atual. | **Médio** (caminho ao vivo) | M |
| **BE-07** | Construtor pergunta o nome | Roteiro do Construtor inclui o nome como última pergunta; o rascunho deixa de nascer "Novo agente" para sempre (`builder.rb:1401` vira provisório até a resposta). | Baixo | P |
| **BE-08** | Estados do rascunho (D11, §6.6) | A API expõe, para cada agente, o estado de §6.6 (E1–E6), a etapa de "Continuar" e, quando o teste foi invalidado, o **motivo** (`test_invalidated_by`: pessoa ou material novo), sem carregar as conversas do Construtor inteiras na lista. Teste válido = a regra única da §6.6 (resposta concluída, por quem edita, na conversa de teste atual, que recomeça a cada mudança que invalida); antes de ir ao ar, mudar a instrução por qualquer caminho invalida; depois de ir ao ar, não (D24). Vale também para rascunho sem conversa do Construtor. | Baixo | M |
| **BE-09** | Sugestão de link pelo modelo (D5) | `BUILDER_SCHEMA` (estrito) ganha `suggested_links: {type:'array', items:{type:'string'}}` em `properties` **e** em `required`; a instrução-mãe diz quando preencher (lista vazia = não se aplica); `state_for` grava; `build_threads/show.json.jbuilder` expõe `suggested_links`. O front só mostra o que veio. | Baixo | P |
| **BE-10** | Mensagens pt-BR com `code` | `render_unprocessable(message, code:)` passa a aceitar `code`. Recebem `code` estável: `instrucao_mantida`, `missing_instruction`, `missing_test`, `publish_field_not_allowed`, `copilot_unavailable`, `no_guided_version`, `internal_with_channels` (chave nova en+pt_BR), `config_key_not_allowed`, cada `connect_errors.*` (`agent_internal_not_connectable`, `agent_not_active`, `inbox_has_webhook_bot`, `inbox_already_connected`, `not_connected`) e os erros de `waha_inboxes#create` (`invalid_phone`, `integration_not_configured`, `remote_setup_failed`, `account_token_missing`) — neste endpoint o `error` continua trazendo o código, como hoje, para a tela antiga, e o `code` é acrescentado (a tela nova traduz pelo `code`). Mensagem em `error`, código em `code`. | Zero | P |
| **BE-11** | Quem ocupa o canal e se ele tem horário | `channels#index` ganha `occupied_inboxes: [{id,name,channel_type, occupied_by:{kind:'agent'|'other_bot', agent_id?, agent_name?}}]` (só agentes da conta; bot externo sem nome) e, em cada caixa (livre, ocupada ou conectada), `has_schedule` (true quando há agenda de atendimento do CRM ou horário comercial ligado — mesma regra de `engagement_gate.rb`). Remover leitura de `inbox.occupied` no front. | Baixo | P |
| **BE-12** | Testar igual à produção (D1-a) | `Playground` usa `trust_instruction: true` e `rodadas_do_turno(agent)` e **nunca** `delivery` (ferramenta assíncrona/cotação devolve recusa nomeada no teste; spec: zero `ToolRun` e zero job assíncrono); com quem só vê, ferramenta HTTP com método ≠ GET não executa (D17). "Passaria para a equipe" sai do `should_handoff` do modelo. `handoff_strategy` passa a ser lido pelo `PromptBuilder` como regra no texto do modelo — **vale também no Operate**: `nil` e `low_confidence` geram `instructions` **byte a byte iguais** aos de hoje (spec compara antes/depois para Clara, Lia e Guia); `insurance_quote`, agentes de sistema e o ajudante `internal` não recebem o bloco (byte a byte iguais, spec); no `both`, o bloco vale só no Operate, não no copiloto. **Todo** valor que não seja `always_ask`/`never` (nil, `low_confidence`, `none`, desconhecido) gera texto byte a byte igual, com spec por valor. Antes do merge: Q13 e lista ao Rodrigo dos ativos com qualquer valor diferente de nil/`low_confidence`, que decide por agente. O motivo de passagem do Testar passa por `EventLogger.curate_code` (mesma lista do Analytics, incluindo `escolhas_incompletas`). Ajudante interno (D26): o Testar roda `Agents::Copilot#suggest` com a mesma entrada que o `ConversationChat` montaria (aviso de segurança + transcrição da conversa de exemplo + pedido), aceitando rascunho; nunca devolve faixa de passagem; a resposta fixa de falta (`NO_ANSWER_TEXT`) não conta como teste válido; para quem só vê vale D17. Lia: o Testar tem um **teto de tempo próprio**, abaixo do TTL do pedido (30 min) e descontado o fechamento — a única diferença de propósito para a produção, porque com `rodadas_do_turno` o orçamento real dela passa de 2 h; a cotação é recusada como `not_in_test`. `InteractiveOperation#playground_result` passa `pode_editar: @account_user.permission_granted?('autonomia_manage')` ao Playground, que repassa ao Answerer (D17). O resultado do teste ganha `skipped_tools: [{slug, name, code}]` com `code` ∈ `not_in_test` (cotação/assíncrona) ou `viewer_not_allowed` (D17), e `writes_external: true` quando o agente tem ferramenta ligada com método ≠ GET **e quem testa edita** (aviso D27; para quem só vê vem `false`). Sobe no **B4b** (lote de um PR só), com a cobertura B4b do §11.8. Atualizar Central 11.10. | **Médio** (muda o prompt ao vivo de quem tem `always_ask`/`never`) | P |
| **BE-13** | Criar caixa WhatsApp pelo fluxo do agente (D7) | Reusar `waha_inboxes` com `phone` (55 + DDD + número) vindo da tela; permissão = administrador; erros com `code` (BE-10); volta com `?from=`, que só aceita rotas de agentes da própria conta (Ligue, Onde atende); qualquer outro valor volta para "Seus agentes". | Baixo | M |
| **BE-14** | Limpeza só do rascunho vazio (D6) | Desde o #1063 a limpeza **arquiva** (exclusão lógica, `reason: 'stale_draft'`), não destrói. Hoje (#1036) ela já poupa rascunho com instrução ou material; o BE-14 acrescenta que **uma resposta do usuário** também protege. O job de limpeza só apaga rascunho guiado desligado parado há 48 h **sem** instrução, **sem** nenhum material (de qualquer idade) e **sem** nenhuma resposta do usuário em qualquer conversa do Construtor. A API expõe o prazo configurado (`AUTONOMIA_DRAFT_REAP_HOURS`) para a tela dizer "Guardado por N dias". Rascunho criado pela API/Guia sem instrução e sem material é E1 (a lista diz o prazo). | Baixo | P |
| **BE-15** | Janela de geração presa (B6) | `STALE_PROCESSING_AFTER = REQUEST_TIMEOUT * (MAX_RETRIES + 1) + 1.minute` (~10 min). Front: "Demorando" vira "Ainda respondendo" dentro da janela (reenviar dá 409). | Baixo | P |
| **BE-16** | Nome e foto no bot da conversa | `after_update` sincroniza `name`/avatar do `AgentBot` espelho dos `agent_inboxes`. | Baixo | P |
| **BE-17** | Agente de Cotação editável pelo painel (D13) | `PATCH autonomia/agents/:id/quote_choices {name?, behavior?, horario?}` (`horario` = o texto que a Lia diz ao cliente, campo "Horário que ela informa ao cliente"; não confundir com `response_window`) no escopo de agentes (`agents_scope`, `autonomia_manage`), só para `insurance_quote`: lê as **quatro** escolhas salvas em `config['agente_de_cotacao']`, sobrepõe as enviadas e chama o método público novo `QuoteAgent::Builder#atualizar_escolhas!(agent, escolhas)`, que reusa as validações privadas atuais e grava `name` + as quatro chaves numa transação. PATCH genérico com `name` no agente de cotação → delega para o mesmo método. `_agent.json.jbuilder` expõe, só quando `instrucao_mantida?`, `instrucao_mantida`, `quote_choices` e `quote_branches` (os ramos de `insurance/quote_agent#show`) — a aba O que sabe da Lia não chama `insurance/*`. Spec de função personalizada nas combinações `autonomia_*` × `insurance_*`; spec que o texto montado da Lia reflete a escolha nova. Corrige: Lia renomeada continuava se apresentando como Lia. | **Médio** (prompt da Lia) | M |
| **BE-18** | ~~Perguntas iniciais validadas~~ | **Fora** (D18: o campo sai da tela). | — | — |
| **BE-19** | Segurança: config aberta (N3 + B9) | `config` no create **e** no PATCH aceita só a lista fechada: `handoff_strategy`, `handoff_target_type`, `handoff_target_id`, `confidence_threshold` (enquanto a tela antiga existir), `audience`, `audience_unknown_contact`, `response_window`, `faq_suggestions`. Qualquer outra chave (inclusive `native_tool_slugs`, `voice_reply`, `voice_instructions`, `humanize_delivery`, `operate_media`, `operate_reactions`, `test_allowlist_phones`, `silence_tokens`, `guardrails`, `model`, `temperature`, `max_turns`, `with_knowledge`, `system_key`, `guide_*`, `PROTECTED_CONFIG_KEYS`) → 422 `config_key_not_allowed` com a `key` (nunca descarte silencioso), também para SuperAdmin pelo PATCH genérico. Seed do Guia e `QuoteAgent::Builder` gravam pelo model e não são afetados. Chaves de `PROTECTED_CONFIG_KEYS` (hoje descartadas em silêncio) também passam a 422. Mudança real de spec: em `external_agent_lifecycle_spec.rb:170-209` os dois exemplos (que mandam `with_knowledge` e `agente_de_cotacao`) passam a afirmar 422 `config_key_not_allowed` com a `key` e `config` relido igual; um exemplo novo prova que `response_window` sozinho mescla e preserva as chaves calculadas (mudança justificada no PR). Ajustes de operação saem do PATCH e vão para o Super Admin (D21, BE-31). Regerar `autonomia:guia:formatos` (`config` deixa de ser `objeto_livre`). Antes e depois do deploy: Q12 (todas as chaves fora da lista gravadas hoje); limpar só com 🟢 e foto; volta da limpeza = `config = config || <foto>` por agente. | Baixo | P |
| **BE-20** | Limite de chamadas (B7) | Throttles novos em `rack_attack.rb` para `build_threads` (create/messages/retry), `agents/:id/test`, `suggest` e `sources/copy`, com chave `account_id` do caminho + hash do cabeçalho de token (o throttle não enxerga o usuário), limites por ENV. O responder global de 429 **não** muda (`error.code == 'rate_limited'`); o front traduz pelo código para frase pt-BR. Spec liga `Rack::Attack.enabled = true` no próprio teste (fora de produção ele fica desligado). | Baixo | P |
| **BE-21** | Threads só para quem edita (B10) | `BuildThreadsController` exige `autonomia_manage` também no GET. | Baixo | P |
| **BE-22** | ~~Exclusão rápida~~ | **Fora** desde o #1063: excluir é lógico e não apaga `knowledge_entries`. | — | — |
| **BE-23** | Versões cobrem o que a tela promete | (1) Concluir "Mudar conversando" grava `record_instruction_version!(reason: 'builder', created_by:)`; (2) passar de guiado para manual grava antes a versão guiada atual (`reason: 'before_manual'`); (3) `instruction_versions` expõe `reason` e `created_by_name` **nulo** quando não há autor (hoje vem fixo "Autonom.ia"); rótulos pt-BR no front, autor nulo = "Automático"; (4) voltar do manual para o guiado (D25) restaura a última versão guiada guardada com o seu andaime, numa transação, e grava versão `rollback`; (5) "Voltar para esta" numa versão escrita à mão leva o agente a `mode=manual`, com o andaime manual e o texto visível — nunca fica guiado com o texto da pessoa escondido; só conta como "versão guiada guardada" a que tem o andaime gravado junto (versões gravadas depois deste deploy); agente que já estava em manual antes, ou só tem versões `kb_refresh`, não tem a opção de voltar → 422 `no_guided_version`. **Invariante NR-10:** o texto só sai para versões de autoria do usuário (`manual_edit` e `rollback` de versão manual); `builder`, `before_manual` e `kb_refresh` mostram só data, motivo e autor, mesmo com o agente em manual; restaurar uma versão guiada volta o agente para `mode=guided` (nunca cola o texto no manual). Spec em `agent_config_exposure_spec`. Agente de Cotação não tem versões. | Baixo | P |
| **BE-24** | Nota privada de passagem para a equipe | Nos 3 pontos de passagem (BE-06), postar nota **privada** (sender AgentBot, `content_attributes.autonomia_nota_passagem`, idempotente por episódio): "{A\|O} {nome} passou esta conversa para a equipe: {motivo pt-BR do código curado por `EventLogger.curate_code`}."; quando houver `NotaDoEncaminhamento` (recusas de ferramenta), as duas viram uma só. Spec: 1 nota por passagem, 0 na resposta normal, nada vai ao cliente. | **Médio** (caminho ao vivo) | P |
| **BE-25** | Conversas só para quem pode vê-las (D12) | `analytics/conversations`: `outcome_scope` filtrado por `Conversations::PermissionFilterService.new(scope, Current.user, Current.account).perform` (a extensão Enterprise entra por `prepend_mod_with`; o número agregado do resultado não muda). `faq_suggestions#index` exige `autonomia_manage`. Specs em `spec/enterprise`: função só `autonomia_view` sem `conversation_*` → lista vazia; com `conversation_participating_manage` → só as suas; administrador → todas. Corrige exposição existente hoje. | Baixo | P |
| **BE-26** | O que o agente já sabe (Conte) | O estado da conversa do Construtor diz quais dos 4 itens do roteiro (negócio, público, quando chama a equipe, nome; no ajudante: no que ajuda, quem usa, o que evita, nome) já foram respondidos, mesmo fora de ordem; tocar "Testar" com os 4 gera a instrução sem nenhuma pergunta a mais (sem "posso criar sem base?") e sem travar por material pendente ou com falha. O front só lê o que vem da API. | Baixo | M |
| **BE-27** | Estado do material para a tela | A API diz, por material, o estado de tela e se o agente **usa** o material, calculado pela **mesma regra** do retriever (inclusive a salvaguarda: quando todos os aceitos são "fora do negócio", o retriever usa todos). Estados: enviando, lendo, não deu para ler, precisa de outro arquivo, ainda não conferido, fora do negócio e não usado, fora do negócio mas usado (aviso), pronto. | Baixo | P |
| **BE-28** | O que foi marcado como resposta errada | Na gaveta "Respostas marcadas como erradas", cada conversa lista suas marcações (motivo, resposta sugerida, mensagem, data), montado no controller do fork sem mudar o serializer upstream. | Baixo | P |
| **BE-29** | Nome novo no modo de se apresentar (D19) | Depois de renomear, o agente se apresenta com o nome novo. Nenhum agente que **não** foi renomeado depois desta entrega tem o texto do modelo alterado (byte a byte), incluindo Clara, Lia e Guia; Agente de Cotação e agentes de sistema ficam fora (a Lia recebe o nome pelo BE-17); modo manual: o nome fica no texto que a pessoa escreve. | **Médio** | P |
| **BE-30** | Primeira mensagem e "quando não souber" com efeito (D18) | A primeira resposta de uma conversa nova segue a Primeira mensagem; quando o agente não sabe, a resposta é a frase de "Quando não souber" e o que acontece depois segue a tabela de §6.3 Ajustes item 5 (spec por opção com modelo simulado: o texto que o modelo recebe contém a frase como resposta para esse caso e a regra da opção). Vale no atendimento e no Testar. O caminho do copiloto (ajudante interno, Testar do ajudante pela D26 e a parte de equipe do `both`) recebe texto **byte a byte igual ao de hoje**, mesmo com os campos preenchidos. Agente de Cotação e agentes de sistema ficam fora (byte a byte iguais mesmo com os campos preenchidos). Entra no B4b (lote de um PR só); antes do merge, Q15 e lista ao Rodrigo de quem muda (o Construtor preenche esses campos, então a Clara muda de propósito). | **Médio** | P |
| **BE-31** | Ajustes de operação no Super Admin (D21) | Só SuperAdmin muda, por agente, a lista fechada `voice_reply`, `voice_instructions`, `humanize_delivery`, `operate_media`, `operate_reactions`, `test_allowlist_phones`, `silence_tokens`, `native_tool_slugs`, `debounce_seconds`, `async_tools`, `async_poll_intervals`, `async_deadline_seconds` (a mesma da D21); agentes de sistema não aparecem na tela e, no Agente de Cotação, `native_tool_slugs` não é oferecida (vale a lista do deploy) — recusa sem linha no registro; o registro guarda só as chaves do BE-31, com telefone mascarado, nunca `instruction`/`scaffold` (o model `Agent` não passa a ser auditado por inteiro), e aparece no Registro de atividades da conta; cada mudança registrada no `Enterprise::AuditLog` (sem migration). `voice` fica fora: o Construtor grava na criação, pelo nome (`builder.rb:1021`); renomear não muda a voz (fora do escopo, Issue própria). | Baixo | M |
| **BE-32** | Ajudante só onde existe o painel | A API diz se a instalação/conta tem o ajudante dentro da conversa (o painel aparece **e** o chat consegue responder: `conversation_copilot_controller.rb:52-55` — CRM, flag da Autonomia e `CRM_COPILOT_ENABLED` — **e** `conversation_chat.rb:43` — `Crm::Ai::Config.enabled?`, que exige `CRM_AI_ENABLED`); com ele desligado, criar ou mudar para `internal`/`both` → 422 `copilot_unavailable`. Conferir o valor nas duas stacks antes do F2. | Zero | P |

### 7.2 Casos obrigatórios por requisito

Cada caso vira spec no PR do BE. Entre colchetes, o achado de revisão de onde veio (`docs/agentes-ia-redesign/revisoes/`).

- **BE-03 / BE-08 / D15 (ligar e estados):** ligar com instrução e sem teste → recusa e leva ao Teste; sem instrução → recusa
  antes; testar → mudar a instrução (Conte, Mudar conversando, material que reescreve, texto manual salvo, voltar versão) →
  ligar = recusa [R3-19/36/47, R4-04]; teste com erro, sem resposta, expirado, 429 ou "Ainda montando" não leva a E4 [R4-03/18/36];
  teste com material "Lendo" → material fica pronto e reescreve → estado volta a E3 com `test_invalidated_by` = material [R4-15/36];
  agente no ar cuja instrução muda (material, pergunta aprovada, Mudar conversando, texto manual) continua E5 [R4-02/13/26/35];
  pausado legado sem teste, e a Lia, religam pelo interruptor [R4-02/26/35]; PATCH `status=active` em rascunho sem teste e o
  create com `status` ativo continuam como hoje, e a tela antiga com a flag desligada liga como hoje (D23, NR-05) [R4-01/27]; teste por
  quem só vê não conta; rascunho sem conversa do Construtor (API, Guia, manual) testa e liga [R3-08/20/59]; rascunho legado com
  e sem instrução [R2-13]; a lista de N agentes sai numa consulta sem carregar mensagens [R3-48]; uma regra só nas três peças
  (estado, `publish`, tela) [R3-01/12/46].
- **D25 (manual → guiado):** volta restaura a versão guiada e o andaime dela; nunca deixa o agente sem instrução; o texto manual
  fica em Versões e nunca fica escondido valendo no atendimento; sem versão guiada → recusa [R4-05/17/28/40].
- **D26 (ajudante):** o resultado do Testar do ajudante é igual à saída do `ConversationChat` (o que o painel da conversa
  mostraria) para a mesma entrada; resposta vazia do modelo não conta como teste válido e a tela mostra o mesmo texto do
  painel [R8-15], exceto pelas ferramentas puladas por D17 para quem só vê; num rascunho também funciona [R5-21/32]; nunca há faixa de passagem;
  o teste do ajudante conta para ligar [R4-09/14/38]. **BE-32:** com o copiloto desligado, `internal`/`both` são recusados [R4-37].
- **BE-12 / D27 (ferramentas no teste):** `skipped_tools` distingue cotação de permissão; `writes_external` bate com as
  ferramentas ligadas [R4-19/30]. "Nunca": pedido do cliente por pessoa e porta de horário/público ainda passam (D33)
  [R4-29, R8-08].
- **Teste válido (§6.6):** na conversa de teste atual, turno 1 com erro e turno 2 com resposta → E4; resposta dada antes da
  mudança não leva a E4; material que invalida recomeça a conversa; `publish` com `name`/`greeting` → 422 [R6-01/02,
  R7-03/26].
- **Campo editado à mão:** editar a Primeira mensagem no Teste → "Quero mudar algo" → mandar mensagem no Conte → a Primeira
  mensagem continua a da pessoa; "muda o nome para Bia" no Conte → renomeia [R7-08].
- **Devolução ao pausar/excluir/tirar canal:** não segue "Para quem vai" e não gera nota [R7-11].
- **BE-23 legado:** agente manual de antes do deploy, com versão `kb_refresh` e sem andaime → sem opção de voltar [R6-12].
- **BE-12 Lia:** teste com rodadas máximas e modelo simulado lento termina antes do TTL [R6-13].
- **BE-06 time:** time sem distribuição automática → fica com o time, sem responsável, sem gente de fora [R6-09/19].
- **D29 / §6.6:** mudar Nome, Primeira mensagem, "Quando não souber", Jeito de falar ou "Quando passa" depois do teste e
  antes de ir ao ar → `missing_test` [R5-01].
- **BE-04 / D30:** create com `status` ativo e sem instrução, pela API e pelo Guia → 422 `missing_instruction`; com
  instrução e sem teste → como hoje [R5-15/28].
- **E2m:** rascunho manual sem instrução — lista sem prazo, "Continuar" leva a Ajustes, a limpeza não apaga [R5-17].
- **BE-05:** um limite novo pedido no "Mudar conversando" aparece em `guardrails` e no texto do modelo [R5-16].
- **BE-12 (ajudante):** `internal` com qualquer `handoff_strategy` → texto byte a byte igual; `both` → bloco só no Operate [R5-02].
- **BE-06:** alvo administrador fora da caixa é válido e o evento registra o alvo [R5-04/18/23/35].
- **BE-13:** `from` fora da lista volta para "Seus agentes" (inclusive `javascript:` e endereço externo) [R4-33].
- **BE-14:** rascunho criado pela API/Guia sem instrução e sem conversa é E1, e a lista mostra o prazo configurado [R4-39/46].
- **E1 / BE-03 (abertura):** abertura que falha antes de existir rascunho mostra erro com "Tentar de novo" e não deixa o front
  esperando [R3-18/42/49]; o rascunho existe antes de abrir o Conte, mesmo sem material [R2-48].
- **BE-26 (fechar a instrução):** 4 respostas + "Testar" → instrução gerada, sem a pergunta "posso criar sem base?", com
  material pendente, com material `needs_resend` e sem material [R3-02/13/45]; respostas fora de ordem marcam o item certo [R2-47].
- **BE-14 (limpeza):** poupa com instrução; com material de qualquer idade (inclusive só material, sem resposta); com 1 resposta;
  apaga só o vazio [R3-17/29, R2-22].
- **BE-05 / D22 (Mudar conversando):** a guarda de modo manual fica no ponto de escrita (aplicar o resultado do Construtor em
  agente manual não acontece; abrir/continuar conversa de agente manual é recusado) [R3-31]; a restrição de campos vale só para a
  retomada pelo painel — na criação, "muda o nome para Bia" ainda renomeia [R3-50]; a instrução gerada nunca aparece na API.
- **Escrever as instruções eu mesmo:** o agente nunca fica sem instrução: o modo manual só é gravado junto com a instrução nova; o
  campo abre vazio (a instrução gerada não aparece) [R3-16].
- **BE-23 (versões):** a exibição do texto decide pela **origem** da versão (guiada ou escrita pela pessoa), não pelo motivo;
  restaurar versão guiada devolve também o andaime original; rollback de versão guiada seguido de modo manual não expõe texto
  [R3-51, R2-02/32]; autor nulo aparece como "Automático" [R2-41/60].
- **BE-12 (Testar = atendimento):** sem saudação dupla e sem balão fixo que o cliente não recebe — o primeiro turno do Testar e
  do atendimento recebem o mesmo texto [R3-07/22]; motivo curado igual ao do evento [R2-12/53]; `none` e valores desconhecidos
  byte a byte iguais [R2-21]; "Quando passa" tem precedência definida sobre a regra de passagem gerada e sobre a ordem genérica de
  passar quando inseguro — "Nunca" e "Sempre oferecer" provados com modelo simulado [R3-23]; no Testar, público e horário não se
  aplicam e a tela avisa [R3-21]; ferramenta com método ≠ GET não roda para quem só vê, também no **sugerir resposta** (D17)
  [R3-32, R2-19/52]; cotação nunca é feita no teste e a tela sabe disso por um campo da API [R2-38].
- **BE-27 (materiais):** a tela diz "não usa" ⇔ o retriever não usa, inclusive quando todos são fora do negócio, fonte sem revisão
  (legado) e fonte em revisão [R3-04/14/37/52, R2-35].
- **BE-29 (nome):** Clara, Lia, Guia e um agente manual sem renomear → texto igual byte a byte; renomear → o nome novo aparece
  [R3-03/15/30/44].
- **BE-30 (primeira mensagem / quando não souber):** Lia, um ajudante interno e um `both` (no copiloto) com os campos
  preenchidos → texto igual [R7-01]; Q10 compara esses campos
  [R3-35].
- **BE-19 / Q12:** chaves gravadas pelo Construtor e pelo model (`voice`, `builder_active_thread_id`, e qualquer chave nova
  deste projeto) não contam como desvio [R3-34/56]; os valores para a volta da limpeza ficam fora do repositório (podem ter
  telefone) [R3-33]; NR-05 e BE-19 com o mesmo texto [R3-40/53].
- **BE-06 (para quem vai):** "Uma pessoa" só oferece quem é membro de todas as caixas do agente, ou avisa onde cai em "quem
  estiver livre" [R3-28]; os 3 pontos de passagem [R2-55/56].
- **BE-24 (nota de passagem):** no caminho em que já existe nota de aviso, fica 1 nota só [R3-54].
- **BE-25 / BE-28 (gaveta):** o cabeçalho usa a contagem da lista que a pessoa pode ver e avisa quando há conversas ocultas;
  "Respostas marcadas como erradas" mostra cada marcação (motivo, resposta sugerida, conversa), sem mudar o serializer upstream
  [R3-25/55].
- **BE-10 / WhatsApp:** `account_token_missing` com frase pt-BR; a tela antiga de criar caixa WhatsApp continua recebendo o código
  como hoje (compatibilidade) [R3-06/11/43/58].
- **BE-31:** registro em `Enterprise::AuditLog`, sem migration [R3-41/58].

**Prioridade de segurança:** BE-19 (ferramenta nativa e outras chaves ligadas pelo PATCH) e BE-25 (conversas de outras caixas
visíveis a quem só vê agentes) são falhas reais em produção hoje, independentes do redesign; entram no **primeiro** PR de
backend (B1).

---

## 8. Arquitetura de frontend

- **Pasta nova:** `app/javascript/dashboard/routes/dashboard/autonomia/agentes/{pages,components,composables}/`. A pasta antiga
  não é tocada enquanto a flag existir.
- **Padrões:** Vue 3 `<script setup>`, `components-next` (Button, Dialog, Switch, RadioCard, TabBar, ChoiceSelect, Avatar,
  Icon), **só Tailwind** com tokens `n-*` (+ `n-navy`, D4). Nada de CSS próprio, `<style>` ou `style=""` — exceção única:
  `:style="{ width: pct + '%' }"` em barras e gráfico. Sem `<select>` nativo.
- **Kit** (`agentes/components/kit/`): `AgentAvatar`, `AgentStatusPill`, `AgentSwitch` (sobre `LabeledSwitch`), `AgentSteps`
  (sobre `StepsBar`), `KnowledgeMeter`, `ConfidenceBar`, `MaterialItem` (8 estados de BE-27), `NoticeBanner`, `RadioCardGroup`,
  `SegmentedToggle`, `ConfirmDialog`. Gaveta = `components-next/side-panel/SidePanel.vue` **existente**, que passa a usar
  `useModalFocus` para prender o foco (alteração no próprio componente, com spec) — nada de segundo SidePanel.
- **Extraídos do #993 para lugar comum (D9):** `components-next/stepper/StepsBar.vue`, `components-next/switch/LabeledSwitch.vue`,
  `dashboard/composables/useModalFocus.js`, `dashboard/helper/localeTag.js`.
- **Mapa tela → componente → API:** ver tabela do Apêndice A.
- **Rotas** (mantêm os 3 nomes atuais para não quebrar Guia, trilha e Central):

  | Nome | Caminho | Permissão |
  |---|---|---|
  | `autonomia_agents_index` | `agents` | ver |
  | `autonomia_agents_builder` | `agents/new` (Escolha) | editar |
  | `autonomia_agent_build` (nova) | `agents/:agentId/build/:step(tell\|test\|live)` | editar |
  | `autonomia_agent_ready` (nova) | `agents/:agentId/ready` | editar |
  | `autonomia_agent_panel` | `agents/:agentId/:tab(performance\|test\|knowledge\|channels\|tune\|tools\|publish)?` — padrão `performance`; `publish` redireciona para `build/live`; inclui `tools` no regex (hoje falta) | ver |
  | `autonomia_agents_connect_whatsapp` (nova) | `agents/connect-whatsapp?from=` | administrador (D7) |

  Toda rota usa `ensureAutonomiaEnabled` com `await contaDaRota(to)`; as mantidas renderizam a página nova ou antiga pela
  flag (`AgentsIndexEntry.vue` etc.); as novas redirecionam para a equivalente antiga com a flag desligada.
- **Menu lateral** (`Sidebar.vue`, toque mínimo, F1): item único "Agentes de IA" com `activeOn` = `autonomia_agents_index`,
  `autonomia_agents_builder`, `autonomia_agent_build`, `autonomia_agent_ready`, `autonomia_agent_panel`,
  `autonomia_agents_connect_whatsapp`; com a flag desligada, os filhos atuais.
- **Teste assíncrono:** `POST agents/:id/test` responde 202 com `poll_url`; o front consulta `ai_requests/:id` e mostra
  "Pensando" enquanto `pending` (padrão já usado por `pollAiRequest`).
- **Permissões:** `useCanManage('autonomia_manage')`; admin da plataforma = `currentUser.type === 'SuperAdmin'`.
- **i18n:** namespace `AGENTS.V2.*` dentro de `agents.json` (catálogo do fork, en + pt_BR no mesmo PR, `pnpm i18n:fork:check`).
  Datas/números com `toLocaleTag(locale)` (`pt_BR` → `pt-BR`).
- **Armadilhas conhecidas:** CSS global do dashboard (`h1` escuro → `!text-white` no herói; `p mb-2` → `mb-0`; `ul` com
  bolinha → `list-none p-0 m-0`; `button` com padding → sobrescrever em cartões-botão; `label block`); `watch(agentId)` nas
  páginas do painel (reuso de componente); `$t` devolve a chave nos specs → `withFullI18n()`; destaque do Guia acha o botão
  pelo texto (`guideHighlightRegistry.js:37` "Criar agente com IA" → atualizar); arquivos upstream (`Sidebar.vue`,
  `MessageContextMenu.vue`, `Dashboard.vue`) com toque mínimo; **proibido** decidir por texto/regex o que o usuário escreveu
  (sugestão de link vem do backend, D5).
- **Guia da Plataforma:** cada rota nova com bloco ou `cobre:` em `lib/operator_guide/porques.md`; reescrever os 8 blocos
  atuais da área (textos da tela antiga) no PR que liga a flag; `pnpm guia:build && pnpm guia:check`.
- **Central de Ajuda:** reescrever capítulo 11 (11.01–11.11), 00.08, 01.01, 18.06/09/10/11 com evidências novas
  (`node scripts/central-de-ajuda/conferir.mjs`); cada rota nova com artigo/`me_leve_ate_la` ou `mapa.fora`.

---

## 9. Segurança e não-regressão

- **Falha encontrada (N3):** quem tem `autonomia_manage` grava `config.native_tool_slugs` pelo PATCH e liga ferramenta
  nativa, contornando a aba Ferramentas (só SuperAdmin). Correção: BE-19, primeiro PR de backend.
- **Isolamento entre contas:** todo endpoint novo resolve recursos pela conta (`agents_scope`, `Current.account`) e tem spec
  cross-tenant (BE-01, BE-02, BE-03, BE-05, BE-06, BE-11, BE-17).
- **Comportamentos que não podem mudar** (specs atuais passam sem alteração; mudança justificada no PR):

| # | Comportamento | Specs |
|---|---|---|
| NR-01 | Responder/passar para a equipe; reconfere elegibilidade; público e horário | `operate/responder*_spec`, `engagement_gate_spec`, `reply_job_filas_spec`, `evento_job_spec` |
| NR-02 | Só opera com `enabled && active` + flag da conta | `journeys/operate_eligibility_spec.rb` |
| NR-03 | Isolamento no operar e nos vínculos | `operate_tenancy_spec.rb`, `agent_inbox_spec.rb` |
| NR-04 | Conexão recusa ocupado, interno, rascunho, bot de outro sistema; aceita `both` | `journeys/channel_connection_spec.rb`, `inbox_connector_spec` |
| NR-05 | Ciclo ativo → pausado → ativo, troca de modo, exclusão limpa espelho | `journeys/external_agent_lifecycle_spec.rb` (linha 33 muda com BE-04; nos exemplos das linhas 170-209, os que mandam `with_knowledge`/`agente_de_cotacao` passam a afirmar 422 `config_key_not_allowed` com a `key` e `config` igual, e um exemplo novo prova que `response_window` mescla preservando as chaves calculadas — BE-19) |
| NR-06 | Agente de Cotação (instrução mantida, ramos, voz) | `insurance/quote_agent_spec.rb`, `insurance/quote_agent/*`, `tools/native/insurance_quote_*`, `responder_rodadas_da_lia_spec` |
| NR-07 | Copiloto (seletor, isolamento, flags) | `copilot_access_spec`, `conversation_copilot_visibility_spec`, `copilot/*` |
| NR-08 | Construtor (isolamento de conversa e imagem, retry) | `builder_thread_tenancy_spec`, `builder_image_tenancy_spec`, `build_threads_spec`, `builder_spec` |
| NR-09 | Conhecimento (ingestão, revisor, limite, URL segura) | `journeys/knowledge_sources_spec.rb`, `knowledge/*_spec` |
| NR-10 | Exposição de config (sem instrução no guiado, sem `scaffold`) | `agent_config_exposure_spec.rb` |
| NR-11 | Ativação do interno | `internal_agent_activation_spec.rb` |
| NR-12 | Analytics | `agents/analytics_spec.rb`, `services/.../analytics_spec` |
| NR-13 | Limpeza só de rascunho vazio; pausar/excluir devolvem conversas (#1036) | `reap_stale_drafts_job_spec`, `agent_operating_sync_spec` |
| NR-14 | Guia e Central em dia | `pnpm guia:check`, `pnpm central:check`, `autonomia:guia:formatos:check` |
| NR-15 | Rotas e permissões do front | `autonomia.routes.spec.js` |

---

## 10. Plano de entrega

### 10.1 PRs e ordem

**Todo PR deste projeto sobe em lote de um PR só** (§14). Backend e frontend em PRs separados (um PR de backend que toca `config/routes.rb` liga o gate de lint de e-mail da CI
para todo o front do mesmo PR). Cada PR de front depende só dos BE listados.

| PR | Escopo | Depende de | Telas do protótipo |
|---|---|---|---|
| **B1** | BE-19 + BE-25 + BE-31 (segurança; BE-31 dá o caminho controlado para o que o BE-19 fecha), BE-10, BE-21, BE-15, BE-20, **BE-14** (limpeza só do vazio, antes de qualquer tela prometer guardar); **lote de um PR só** (§14) | — | — |
| **B2** | BE-00 (flag), BE-01 (lista), BE-08 (estado/etapa), BE-11 (ocupados + horário), BE-16 (nome no bot), BE-27 (estado do material), BE-28, BE-32 (ajudante só onde existe o painel) | B1 | — |
| **B3** | BE-03 + BE-04 (ligar atômico + guardas), BE-07 (nome perguntado), BE-09 (links sugeridos), BE-26 (o que já sabe), BE-05 (retomar conversa) | B1, **B2** (BE-08) | — |
| **B4** | BE-02 (material de outro agente), BE-23 (versões) | B1 | — |
| **B4b** | BE-12 + BE-29 + BE-30 — tudo o que muda o texto do modelo ao vivo, num **lote de um PR só** (Q13 e Q15 antes; cobertura B4b do §11.8 depois) | B1 | — |
| **B5** | BE-06 (para quem vai) + BE-24 (nota de passagem) — caminho ao vivo, **lote de um PR só** (cobertura B5 do §11.8 depois) | B1 | — |
| **B6a** | BE-13 (WhatsApp novo) | B1 | — |
| **B6b** | BE-17 (Agente de Cotação), **lote de um PR só** (cobertura B6b do §11.8 depois) | B1 | — |
| **F0** | Flag no front, kit, extração do #993 (D9), token `n-navy` (D4), namespace i18n, entradas nova/antiga, `tools` no regex, specs de rota, `@axe-core/playwright` + helper `expectNoSeriousA11y(page)`, `tests/playwright/agents.config.ts` (loopback) e `agents-prod.config.ts` (só leitura, para T23) | B2 (BE-00) | — |
| **F1** | Lista + vazio + menu de item único + destaque do Guia | F0, B2 | 6.1 |
| **F2** | Escolha + Conte (+ rota `build`, bloco no Guia) | F0, B3, B4 (BE-02) | 6.2.1–6.2.2 |
| **F3** | Teste + Ligue + Pronto (+ rota `ready`, Guia) | F2, B3, B4b, **F6** (rota de conexão usada no Ligue) | 6.2.3–6.2.5 |
| **F4** | Casca do painel + Como está indo + gaveta | F0 | 6.3 |
| **F5** | Testar + O que sabe (materiais, perguntas da equipe, ramos da cotação) | F4, B2 (BE-27), B4, B4b, B6b (`quote_branches`) | 6.3 |
| **F6** | Onde atende + Conectar WhatsApp (+ rota, Guia) | F4, B2 (BE-11), B6a (BE-13) | 6.3, 6.4 |
| **F7** | Ajustes completos + Ferramentas | F4, B3 (BE-05), B4 (BE-23), B4b (BE-12/29/30), B5 (BE-06), B6b (BE-17) | 6.3 |
| **F8** | Dentro da conversa: visual do ajudante, "resposta errada" e nota de passagem (toque mínimo em upstream) | F0, **B5** (BE-24) | 6.4 |
| **F9** | Reescrita do Guia (8 blocos) e da Central (cap. 11, 00.08, 01.01, 18.x); ligar a flag na conta 16 pelo **Super Admin** (BE-00); UPDATE de tons D10 por psql com 🟢 | F1–F8 | — |
| **F10** | Remover código antigo (só após aceite final + 2 semanas com a flag ligada sem incidente) | aceite | — |

Cada PR: Issue filha da épica, worktree em `/Users/rodrigosilva/dev/worktrees/chat2you/<issue>-<slug>`, `Refs #<épica>`,
entrada no Project Autonom.ia Dev (Projeto Hub2You, Tipo, Prioridade, Risco, Próxima ação, Ambiente), fila de merge
coordenada pela sessão **Automação** (avisar antes, mandar "ok, SHA" depois da validação).

### 10.2 Orquestração dinâmica (como cada PR é executado)

Cada PR roda como um workflow de agentes, com o agente principal no comando entre as fases:

1. **Entender** — leitores em paralelo (backend tocado, front tocado, specs e Guia/Central afetados) devolvem o mapa exato
   de arquivos e o que pode quebrar. O principal confere a parte crítica no código antes de seguir.
2. **Desenho técnico** — `docs/agentes-ia-redesign/design/<PR>.md` com o código aberto na `origin/main` do dia: mecanismo de cada BE
   do PR, invariantes tocados, uma spec planejada por caso obrigatório de §7.2 e, nos PRs que mudam produção, o **plano de
   validação** (§11.7/§11.8, a partir de `validacao-producao-base.md`, com as pendências do escopo resolvidas). Revisado (rodada 1; rodada 2 com achado → para e
   causa raiz) antes de escrever código.
3. **Implementar** — um implementador por fatia independente, cada um na sua worktree (`isolation: worktree`) quando mexem
   em arquivos diferentes; fatias que tocam o mesmo arquivo vão em série. Teste primeiro (spec vermelha → código → verde).
4. **Validar local** — o principal roda e **lê** a saída inteira: `rspec` da área (`spec/{requests,models,services,jobs}/**/autonomia/**`, `spec/enterprise/**/*autonomia*`,
   `spec/enterprise/requests/api/v1/accounts/custom_role_module_access_spec.rb`, `spec/controllers/super_admin/accounts_controller_spec.rb`
   e a spec do `rack_attack`),
   `pnpm test` dos specs da tela, `pnpm eslint` sem nenhum aviso, rubocop, `pnpm i18n:fork:check`, `pnpm guia:check`,
   `pnpm central:check`, `autonomia:guia:formatos:check` quando a API mudar, build do front. Teste e commit nunca no mesmo
   comando; ferramenta que reescreve código (`rubocop -a`, `eslint --fix`) é seguida de `git diff` lido e testes de novo.
5. **Conferir visual** (PRs de front) — capturas protótipo × implementação (§11.6); ninguém entrega tela sem olhar a captura.
6. **Revisão** — protocolo de §10.3, com os 5 passos de método abaixo já feitos pelo principal antes de chamar os revisores.
7. **Testes de aceite** — os CA da tela (§11) marcados um a um no PR, com evidência (spec, captura ou passo manual).
8. **Merge e deploy** — com OK do Rodrigo, pela fila; validação pós-deploy (§11.7) e tester (§11.8) nos PRs que mudam
   comportamento em produção.

### 10.3 Protocolo de revisão (regra do Rodrigo)

- **Rodada 1:** revisores independentes, em paralelo, cada um com uma lente:
  - **produto/UX** — compara com o protótipo e os CA da tela (texto, estados, permissões, celular, tema escuro);
  - **técnica** — correção, padrões do repo, construção aditiva, Enterprise, i18n, Guia/Central;
  - **segurança e produção** — isolamento entre contas, permissões, agentes no ar, Agente de Cotação, dados pessoais;
  - **testes** — o teste prova o critério? falha sem a correção?
  Cada achado é verificado (reproduzido ou provado no código) antes de virar correção. O principal corrige e roda a
  validação local de novo.
- **Rodada 2:** os mesmos revisores sobre o resultado corrigido.
  - **Sem achados → segue** para testes de aceite e merge.
  - **Com achados → PARA.** Antes de corrigir, o principal encontra a **causa raiz** de cada achado — por que a rodada 1 e a
    validação não pegaram, ou por que a correção introduziu o problema (requisito ambíguo, padrão do repo ignorado, teste
    fraco, falta de contexto do implementador) — e registra em `docs/audit/<data>-agentes-<pr>-causa-raiz.md` com: achado,
    causa raiz, correção da causa (não só do sintoma), o que muda no processo para não repetir. Só depois corrige, roda a
    validação local e manda para **nova revisão**, e continua.
- Achado de severidade **crítica** (segurança, perda de dado, agente no ar quebrado) em qualquer rodada bloqueia o PR até a
  causa raiz estar registrada.
- **Passos de método obrigatórios antes de cada rodada** (vieram da causa raiz da rodada 2 deste PRD,
  `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md`):
  1. **Matriz controle → leitor → efeito** (§6.5) conferida para cada controle tocado: leitor em `arquivo:linha` ou decisão.
  2. **Invariantes** de §9 (instrução oculta, permissão de conversa, isolamento entre contas, agentes no ar, Agente de Cotação)
     conferidos para cada mudança, com a prova citada no PR.
  3. **Máquina de estados** (§6.6) atualizada antes de mexer em rota, estado ou tela de fluxo.
  4. **Tester** com Tipo (leitura/escrita 🟢) e Alvo por linha; valores (status HTTP, tempos) lidos do código.
  5. **Passe de consistência** com lista fixa: cada identificador criado ou alterado (D, BE, CA, Q, T, nome de campo) é
     procurado em todo o documento e no código/specs, e conferido nestes lugares: cabeçalho (status, versão do protótipo), §2,
     linha do §10.1 do PR que entrega, cobertura por PR do §11.8, §12, §13, §14 e Apêndice A.
  6. **Validação de produção** (C10): toda Q, regra de aborto, T e volta responde por escrito: (a) volume real lido por psql;
     (b) caminho do código até o efeito observado; (c) a evidência sobrevive ao blue-green?; (d) o que dispara em falso com uso
     legítimo e o que deixa passar com defeito. Invariante violado ou cenário que falhou dispara a classificação (§11.7,
     C15); diferença de estado vai para decisão.
  7. **Matriz de variantes** (C11, §6.7): toda regra ou decisão nova conferida por tipo de agente × modo × porta de entrada ×
     campos que mudam o texto do modelo.
- CI verde não é revisão. Revisão não substitui o teste de aceite.

---

## 11. Critérios de aceite (termos de aceite por tela)

Formato: cada critério é verificado por **V** (Vitest), **R** (RSpec), **P** (Playwright/captura) ou **M** (inspeção
manual). Um critério só conta como atendido com evidência anexada ao PR.

### 11.1 Gerais (todas as telas)

- **CA-GERAL-01 (V/P)** Nenhum `<select>` nativo; escolhas com `ChoiceSelect` (teclado do padrão *select-only combobox*).
- **CA-GERAL-02 (P)** Todo botão, link, aba, interruptor, opção e chip tem altura e largura ≥ 44 px.
- **CA-GERAL-03 (P)** A 400 px, `scrollWidth ≤ 400` em todas as telas e estados (abas podem rolar dentro do próprio
  contêiner). Menu lateral some abaixo de 860 px; margem lateral 16 px abaixo de 640 px.
- **CA-GERAL-04 (P/M)** Claro e escuro com contraste ≥ 4,5:1 (`expectNoSeriousA11y(page)` com `@axe-core/playwright`, F0, sem
  violação *serious/critical*). Só Tailwind e tokens;
  destaque `n-brand`, nunca `n-iris`.
- **CA-GERAL-05 (V)** Nenhum texto fixo no template; chaves em en e pt_BR; `pnpm i18n:fork:check` passa.
- **CA-GERAL-06 (M)** Textos iguais aos do protótipo, frases curtas, sem jargão nem CAIXA ALTA; gênero acompanha o nome.
- **CA-GERAL-07 (V)** Diálogos: `role="dialog"`, `aria-modal`, `aria-labelledby`; Tab/Shift+Tab presos; Esc e clique fora
  fecham; o foco volta ao gatilho. Nenhum `window.confirm`/`alert`.
- **CA-GERAL-08 (V)** Avisos `role="status"`; erros `role="alert"`; conversas `aria-live="polite"`.
- **CA-GERAL-09 (V)** Ícones decorativos `aria-hidden`; botão só de ícone com `aria-label` que nomeia o alvo.
- **CA-GERAL-10 (V/R)** Permissões: só ver não vê nenhum botão de escrita nem as abas O que sabe / Onde atende / Ajustes, e o
  backend recusa com **401** (padrão do repo para `Pundit::NotAuthorizedError`) toda escrita, exceto `POST agents/:id/test`,
  `POST agents/:id/suggest` (D8), `POST agents/message_reports` e o chat do ajudante dentro da conversa (regra própria: qualquer
  membro que vê a conversa); quem edita faz tudo menos Ferramentas; Ferramentas só SuperAdmin (401 para os demais).
- **CA-GERAL-11 (R)** Com `Config.enabled?` desligado, a API de agentes devolve 404 e o menu não aparece.
- **CA-GERAL-12 (V/R/P)** Flag do redesign (BE-00): desligada → as rotas resolvem os componentes antigos (spec de rota), as
  specs atuais das telas antigas passam sem alteração e há capturas das telas antigas antes/depois do F0 sem diferença; ligada →
  telas novas; ligar/desligar numa conta (botão do Super Admin) não muda `autonomia_agents_redesign_enabled` de outra (R).
- **CA-GERAL-13 (M)** Correções de acessibilidade sobre o protótipo (§6.4) aplicadas.
- **CA-GERAL-14 (V/R)** Todo controle tem efeito real: cada linha da matriz §6.5 tem o leitor provado por spec (grava → o
  atendimento ou o Testar muda) ou a decisão aplicada (controle removido).

### 11.2 Seus agentes

- **CA-LISTA-01 (V)** Título, subtítulo, "Criar agente" (só quem edita), contadores "N atendendo" (E5), "N pausados" (E6) e
  "N para terminar" (E1–E4), este só se > 0.
- **CA-LISTA-02 (V/R)** Situação por agente a partir do estado de §6.6 (BE-08): E1–E3 → "Falta terminar" (âmbar); E4 → "Pronto
  para ligar" (azul); E5 → "Atendendo"; E6 → "Pausado". (R) Spec por estado, para rascunho sem conversa do Construtor e para
  legado; antes de ir ao ar, mudar a instrução depois do teste volta a "Falta terminar · Parou em Teste" com o motivo; agente
  no ar ou pausado cuja instrução muda continua "Atendendo"/"Pausado" (D24).
- **CA-LISTA-03 (V)** Selos: `insurance_quote` → "Agente de Cotação"; `internal` → "Ajuda a equipe"; `both` → "Clientes e
  equipe".
- **CA-LISTA-04 (V/R)** Linha de contexto: interno → "Aparece ao lado das conversas da equipe"; externo sem canal → aviso
  âmbar; com canal → nome do 1º canal + "e mais N" (de `channels[]`, BE-01); E4 → "Falta escolher onde atende" (interno:
  "Falta ligar para a equipe usar"); E3 invalidado por material → "{A} {nome} aprendeu um material novo. Teste de novo antes de
  ligar."; E3 invalidado por mudança da pessoa → "Parou em Teste · Algo mudou depois do teste."
- **CA-LISTA-05 (V/R)** "Esta semana: N respostas · passou N para a equipe" / "Nada esta semana · N respostas em 30 dias" /
  "Ainda sem conversas", de `stats` (BE-01). Os números batem com os da aba Como está indo para o mesmo período (R: spec
  compara `ListStats` com `Analytics`). Uma única consulta para N agentes (R: spec conta queries). Agente interno: sem linha de
  números (D14).
- **CA-LISTA-06 (V/R)** Rascunho: "Parou em "{Conte|Teste}". Fica guardado até você terminar ou excluir." (E2–E3); E1:
  "Guardado por N dias" com N do prazo configurado (BE-14 apaga esse caso, spec R); legado com instrução sem etapa = "Parou em
  Teste"; rascunho da API/Guia guiado sem instrução e sem material = E1; manual sem instrução = "Falta escrever as instruções", sem
  prazo (E2m).
- **CA-LISTA-07 (V)** Ações: E1–E3 → "Continuar" (leva à etapa de §6.6 — legado com instrução vai ao Teste); E4 → "Escolher
  onde atende" (ou "Ligar" se interno); E5/E6 → "Abrir" + interruptor.
- **CA-LISTA-08 (V/R)** Interruptor `role="switch"`, `aria-checked`, `aria-label="Atendendo: {nome}"`; pausar abre "Pausar {a}
  {nome}?" com o texto das conversas (ajudante interno: "O {nome} some do painel das conversas até você ligar de novo.");
  confirmar grava `status=paused` + `enabled` coerentes e mostra "{nome} pausad{a}. As conversas foram para a equipe." (interno:
  "{nome} pausado."); ligar não pede confirmação e só exige instrução (D24) — (R) Clara e Lia, sem teste registrado, religam.
- **CA-LISTA-09 (R)** Depois de pausar, as conversas com o bot voltam para a equipe e conversa nova nasce sem bot (#1036).
- **CA-LISTA-10 (V)** Menu "⋯" (`aria-haspopup="menu"`, `aria-expanded`) só em rascunho e para quem edita, com "Excluir
  rascunho" (confirma); Esc fecha.
- **CA-LISTA-11 (V)** Aviso fixo sobre pausa presente.
- **CA-LISTA-12 (V)** Carregando: esqueleto com `aria-busy="true"` e texto para leitor de tela; sem spinner solto.
- **CA-LISTA-13 (V)** Erro: `role="alert"`, "Não deu para carregar seus agentes" / "Pode ser a internet. Seus agentes
  continuam atendendo normalmente." e "Tentar de novo" que recarrega.
- **CA-LISTA-14 (V)** Vazio: herói azul-marinho, "Criar meu primeiro agente", "Comece por um destes" com 3 modelos; clicar num
  modelo abre a Escolha com ele marcado. Só ver: texto "Ainda não há agentes nesta conta…" sem botões.
- **CA-LISTA-15 (V)** Rascunho (E1–E4) para quem só vê: "Abrir", que leva ao painel com Como está indo e Testar (D8); sem
  Continuar nem Ligar. Só ver: sem criar, sem interruptor, sem menu; linha com cadeado "Você pode ver e testar os agentes. Para
  criar ou mudar, peça a quem administra a conta."
- **CA-LISTA-16 (R)** Agentes de sistema (Guia) nunca aparecem.
- **CA-LISTA-17 (M)** Menu lateral com um item "Agentes de IA" (flag ligada).

### 11.3 Criar

- **CA-CRIAR-01 (V)** `<ol aria-label="Etapas">` com Escolha · Conte · Teste · Ligue; atual com `aria-current="step"`;
  anteriores com ✓.
- **CA-CRIAR-02 (V/R)** A partir do Conte (E1+), "Sair e continuar depois" guarda (inclusive Nome e Primeira mensagem do
  Teste), volta à lista, toast "Guardado. Continue quando quiser." e a lista mostra o estado da §6.6 (E1–E3: "Falta terminar ·
  Parou em …"; sair do Teste depois de teste válido, ou do Ligue: E4 "Pronto para ligar"); na Escolha o botão é "Voltar",
  sem toast e sem rascunho; a limpeza não apaga rascunho com resposta do usuário, instrução ou material (BE-14, #1036).
- **CA-CRIAR-03 (R/M)** Rotas novas no Guia (`porques.md`), `pnpm guia:check` e `central:check` verdes.
- **Escolha**
  - **CA-ESC-01 (V)** Título; 6 cartões com ícone em quadrado colorido (`size-14 rounded-2xl`), descrição e exemplo; 2 em
    linha (Ajudar minha equipe, Outro trabalho).
  - **CA-ESC-02 (V)** Clicar marca (`aria-checked`) e mostra "Escolhido: {modelo}"; "Continuar" desabilitado sem escolha.
  - **CA-ESC-03 (V/R)** Sem perguntas Externo/Interno e Com/Sem base; "Ajudar minha equipe" cria `actuation=internal`; os
    demais `external`.
  - **CA-ESC-04 (R)** Rascunho nasce com o `agent_type` do modelo (`custom` para "Outro trabalho"; "Ajudar minha equipe" =
    `support` + `actuation=internal`; nunca `insurance_quote`).
  - **CA-ESC-05 (V)** Teclado: Tab pelos 8 cartões, Enter/Espaço marca, foco visível.
  - **CA-ESC-06 (V/R)** Sem o painel do ajudante na instalação (BE-32), "Ajudar minha equipe" não aparece e a API recusa
    `internal`/`both` com `copilot_unavailable`.
- **Conte**
  - **CA-CON-01 (V)** Título ("Conte sobre o seu negócio" / interno "Conte como ele vai ajudar"); 2 colunas → 1 abaixo de
    980 px.
  - **CA-CON-02 (V/R)** Uma pergunta por vez; **o nome é perguntado** e o agente nunca fica "Novo agente" depois da resposta
    (BE-07). Entrar no Conte: o front espera `agent_id` no polling da abertura e só então navega para `build/tell` (§6.6 E1).
  - **CA-CON-03 (V)** Resposta sugerida em chip; tocar envia.
  - **CA-CON-04 (V)** Campo com rótulo para leitor de tela, cresce, Enter envia, Shift+Enter quebra; anexar com
    `aria-label`; até 4 imagens de 5 MB (5ª → "Até 4 imagens por mensagem."); miniatura removível.
  - **CA-CON-05 (V/R)** Painel "já sabe": 4 itens ✓/"Ainda não" lidos de `knows` (BE-26; resposta fora de ordem também marca),
    barra `aria-valuenow` 0–4, "N de 4 respostas" / "Pronto para testar".
  - **CA-CON-06 (V)** Materiais (sem aba "Para enviar", D20), área de soltar com formatos, "N de 30 materiais · N prontos"; no
    limite o adicionar desabilita com aviso.
  - **CA-CON-07 (V/R)** Estados de material vindos da API (BE-27), um texto por estado: "Enviando" · "Lendo" · "Não deu para ler" +
    motivo + "Enviar de novo" · "Precisa de outro arquivo" · "Ainda não conferido" + "Lido, mas a conferência não terminou. {Ela}
    ainda não usa este material." + "Enviar de novo" · "Não é sobre o seu negócio. {Ela} não usa este material." · "Parece não
    ser sobre o seu negócio. Enquanto não houver outro material, {ela} ainda usa este." · "Pronto" (+ "Nota N de 10 · {rótulo} ·
    certeza {nível}. {resumo}" quando houver revisão). O front não deduz estado. (R) A tela diz "não usa" ⇔ o retriever não usa
    (casos de §7.2). Falha não trava o avanço.
  - **CA-CON-08 (V)** Tirar material pede confirmação nos dois lugares (criação e painel).
  - **CA-CON-09 (V/R)** Com exatamente 1 material pronto em outro agente: atalho "Usar {o material} que {a} {Agente} já usa"
    (texto do protótipo, D16), copia com 1 clique; com 2+: "Usar material de outro agente" abre diálogo com itens "{nome} · de
    {Agente}" e "Usar"; vazio "Nenhum outro agente tem material pronto." (BE-02); de outra conta → 404.
  - **CA-CON-10 (V/R)** Sugestão de link aparece só quando o Construtor devolveu `suggested_links` (BE-09); "Usar" cria o
    material; "Agora não" some.
  - **CA-CON-11 (V)** "Testar {a} {nome}" desabilitado até as 4 respostas.
  - **CA-CON-12 (V)** Pensando: três pontos com `aria-label="Pensando"` enquanto `processing`.
  - **CA-CON-13 (V)** Erro ao enviar: `role="alert"` + "Tentar de novo" que reenvia o mesmo texto sem perdê-lo.
  - **CA-CON-14 (V/R)** Não salvou (422 com `error_fields`): mensagem com o campo em pt-BR + "Tentar de novo".
  - **CA-CON-15 (V/R)** Ainda respondendo: campo e enviar desabilitados; reenviar dentro da janela não duplica geração (409);
    a janela é ≥ pior caso da chamada (BE-15).
  - **CA-CON-16 (V)** Interno: roteiro próprio; gênero por D32 (spec V com um ajudante "Ana" tratado por ela e um agente
    "Isabel" tratado por ela — nunca pela última letra).
  - **CA-CON-17 (V/R)** Demorando: só depois de `STALE_PROCESSING_AFTER` (BE-15) com a mensagem ainda em `processing`; banner
    `role="status"` "Está demorando mais que o normal. Envie sua mensagem de novo."; "Enviar de novo" chama `retry` com o mesmo
    texto e não duplica a geração. Antes da janela vale CA-CON-15.
  - **CA-CON-19 (V/R)** Muitas mensagens (429 `rate_limited`, BE-20): banner `role="status"` "Você mandou muitas mensagens
    seguidas. Espere um minuto e tente de novo.", campo e enviar desabilitados por 60 s; o texto digitado não se perde.
  - **CA-CON-18 (V)** Com as 4 respostas dadas, o campo continua habilitado ("Quer mudar ou acrescentar algo? Escreva aqui.") e
    a mensagem chega ao Construtor.
- **Teste**
  - **CA-TES-01 (V)** Título e "Nada disso vai para clientes de verdade."; com `writes_external` (D27), aviso "Ferramentas que
    gravam em outro sistema rodam de verdade no teste."
  - **CA-TES-02 (V/R)** Celular "{nome} · Teste · só você vê", aviso "No teste, horário e público não são aplicados." (no
    ajudante, no lugar dele, a conversa de exemplo — D26), a primeira resposta segue a Primeira mensagem (D18), perguntas sugeridas somem ao usar, "Limpar conversa"
    após a 1ª; `POST agents/:id/test` aceita rascunho e responde 202 + `poll_url` — o front consulta `ai_requests/:id` e mostra
    "Pensando" enquanto `pending`; perguntas sugeridas vêm do i18n pelo trabalho escolhido (D28), nunca de um negócio fixo; partes da resposta em sequência quando `humanized`; anexo só de imagem ("Anexar foto", até
    4, 5 MB, em `images`).
  - **CA-TES-03 (V)** Abaixo da última parte: "Certeza" com barra (verde ≥ 70, âmbar 40–69, vermelha < 40) e
    `confidence×100`%; "Material usado (n)" expansível; quando `handoff.should`, faixa âmbar "Aqui {ela} passaria para a
    equipe. {motivo em pt-BR}" — motivo vindo já curado do backend (BE-12), rótulo para cada código de `ALLOWED_REASONS` e para
    nulo ("Sem motivo informado"). Nenhum texto da tela cita percentual de corte (D1-a). Agente de Cotação: com `skipped_tools`,
    aviso "No teste a cotação não é feita de verdade" (V/R).
  - **CA-TES-04 (R)** O Testar usa o mesmo caminho da produção (BE-12), em agente sem ferramenta assíncrona: com o modelo
    simulado devolvendo `confidence: 0.2` e `should_handoff: false`, o Playground devolve `handoff.should=false`, igual ao
    Responder com o mesmo agente e entrada (a spec **falha no código de hoje**, que aplica o portão de certeza no teste);
    segundo caso `should_handoff: true` → os dois `true`, e o motivo curado do Playground é igual ao `handoff_reason` do evento
    gravado pelo Responder. Agente de Cotação: no teste, zero `ToolRun` e zero job assíncrono.
  - **CA-TES-05 (V)** "Está bom, continuar" só depois de 1 teste válido (resposta concluída; erro, "Não respondeu",
    "Demorando" e 429 não liberam); "Quero mudar algo" volta ao Conte sem perder nada.
  - **CA-TES-06 (V)** "Ainda montando" com `has_instruction=false`; "Não respondeu" com `error`/5xx + "Tentar de novo" com a
    mesma pergunta; "Demorando" depois de `REQUEST_TIMEOUT` (180 s) sem resultado, continuando a esperar até o TTL de 30 min (texto de §6.2.3 + "Tentar de novo"); 429 → "Você testou
    muitas vezes seguidas. Espere um minuto."
  - **CA-TES-07 (R)** Teste não cria `autonomia_agent_events`, não envia nada a canal, não muda `status`.
  - **CA-TES-08 (V/R)** Ajudante interno (D26): o resultado bate com o do copiloto para a mesma entrada; sem faixa de passagem;
    o teste conta para ligar; para quem só vê, sem o aviso de D27 e com as ferramentas ≠ GET puladas.
- **Ligue**
  - **CA-LIG-01 (V)** Título e subtítulo (externo/interno).
  - **CA-LIG-02 (V/R)** Canais livres em `role="radiogroup"`; "Canais ocupados (n)" desabilitados com quem ocupa (BE-11);
    bot de outro sistema aparece como "Já tem outro robô neste canal".
  - **CA-LIG-03 (V)** 1 canal livre → já marcado.
  - **CA-LIG-04 (V)** O Ligue mostra Nome e Primeira mensagem só no resumo, com "Mudar" que volta ao Teste (D29).
  - **CA-TES-09 (V/R)** "Como se apresenta" no topo do Teste: Nome e Primeira mensagem editáveis, salvos por PATCH; a
    Primeira mensagem muda a primeira resposta no Testar e no atendimento (BE-30, spec R); mudar recomeça a conversa de teste
    com o aviso de §6.2.3, e a primeira resposta nova contém o cumprimento novo; sem perguntas para puxar conversa (D18); no
    ajudante interno, sem Primeira mensagem.
  - **CA-LIG-05 (V/R)** "Quando atende" com 3 opções (só externo) → `config.response_window`; canal com `has_schedule=false`
    mostra "Este canal não tem horário definido: {ela} vai responder sempre." com link (BE-11; spec R do caso sem horário).
  - **CA-LIG-06 (V)** Resumo em frase, com a parte de passagem por opção gravada: dúvida → "Quando não souber, passa a
    conversa para a equipe."; sempre oferecer → "Oferece falar com uma pessoa."; nunca → "Não oferece uma pessoa; passa
    quando o cliente pede."; "N material pronto · base N%" ou "Sem material: responde só com o que você contou."; "Ligar"
    desabilitado sem canal (externo).
  - **CA-LIG-07 (R)** Ligar é atômico (BE-03): se a conexão falha, o agente continua rascunho e nada foi gravado; sem
    instrução → 422 `missing_instruction` (BE-04).
  - **CA-LIG-08 (V)** Falhou ao ligar: `role="alert"` com o motivo do servidor e "Nada mudou: {ela} continua desligad{a}." +
    "Tentar de novo".
  - **CA-LIG-09 (V)** Sem canal livre: texto + "Conectar um WhatsApp novo" para administrador; quem edita sem ser administrador
    lê "Peça a quem administra a conta para conectar um WhatsApp." (sem botão).
  - **CA-LIG-10 (V)** "Deixar desligad{a} por enquanto" grava e volta com "Pronto para ligar" + toast.
  - **CA-LIG-11 (V/R)** Interno: sem canal, "Onde a equipe encontra", liga sem escolher canal (o teste válido continua
    exigido, D26); backend recusa canal em interno.
  - **CA-LIG-12 (R/V)** Ligar pela tela nova sem instrução → recusado (vem primeiro); com instrução e sem teste válido da
    instrução atual → recusado; a tela leva ao passo que falta ("Teste {a} {nome} antes de ligar.", ou com o motivo do material
    novo); os casos obrigatórios de §7.2 (BE-03/BE-08, D23, D24) têm spec.
  - **CA-PRO-01 (V)** Pronto: `role="status"` com a frase certa e os cartões; interno com "Ver numa conversa" → lista de
    conversas com o aviso "Abra uma conversa: o {nome} aparece no painel ao lado."; sem caixa visível, o cartão não aparece.

### 11.4 Painel do agente

- **CA-PAINEL-01 (V)** "← Seus agentes", avatar 64 px, nome + situação, resumo; interruptor ou "Continuar montagem"/"Ligar".
- **CA-PAINEL-02 (V)** Abas na ordem certa; só ver → Como está indo + Testar; interno sem Onde atende; Ferramentas só
  SuperAdmin e nunca no Agente de Cotação; aba proibida pela URL → Como está indo; abas com setas do teclado e `tabpanel`.
- **CA-PAINEL-03 (V)** Agente de Cotação: aviso "A forma de cotar da {nome} é mantida pela Hub2You. Você escolhe nome,
  horário, jeito de cotar e para quem ela responde. Conexão com as seguradoras fica em Cotação." com link para Cotação.
- **Como está indo**
  - **CA-RES-01 (V)** 7/30 dias → `analytics?range=7d|30d`.
  - **CA-RES-02 (V)** 5 números de `analytics` (`conversations_handled`, `replies_sent`, `handoff_rate×100`% (`handoff_count`),
    `avg_confidence×100`%, `knowledge_answer_rate×100`%); valor nulo mostra "Sem dados" (nunca "—" solto).
  - **CA-RES-03 (V)** Alerta só quando `insight` vem do servidor (`high_handoff`/`low_knowledge`); "Ensinar" → O que sabe; o
    front não recalcula. No Agente de Cotação: sem "Ensinar", sem "Ensinar algo que faltou" no Testar, sem o alerta
    `low_knowledge` e sem o número "% que usaram seus materiais" (ela não tem material).
  - **CA-RES-04 (V/R)** 5 resultados de `outcomes`; clicar abre a gaveta com `analytics/conversations` (≤ 50, `has_more` →
    "Mostrando as 50 mais recentes"). (R, `spec/enterprise`) Função só `autonomia_view` sem `conversation_*` → 0 conversas; com
    `conversation_participating_manage` → só as suas; com `conversation_manage` → as das caixas de que é membro; administrador →
    todas (BE-25). Em "Respostas marcadas como erradas", cada item mostra motivo, resposta sugerida e "Ensinar" (BE-28).
  - **CA-RES-05 (V)** Gaveta: `role="dialog"`, título e "N conversas · últimos X dias" com N = conversas que a pessoa pode ver;
    quando há conversas ocultas, "Algumas conversas são de caixas que você não vê."; itens com contato, canal e "Abrir"; foco
    preso, Esc fecha; vazio "Nenhuma conversa com esse resultado no período."
  - **CA-RES-06 (V)** Dia a dia: `role="img"` com texto dos totais; uma barra por dia (7 ou 30, sem buraco), legenda, datas
    dd/mm nas pontas.
  - **CA-RES-07 (V)** Motivos (até 5) com rótulo pt-BR para todos os códigos; vazio "Nenhuma conversa foi para a equipe neste
    período."
  - **CA-RES-08 (V)** Carregando (esqueleto), erro (`role="alert"` + "Tentar de novo"), vazio da semana ("Ver 30 dias"),
    vazio total ("Testar"); agente interno: "O {nome} ajuda a equipe dentro das conversas. Os números de uso ainda não aparecem
    aqui." + "Ver numa conversa" (D14; destino de CA-PRO-01).
- **Testar**
  - **CA-PTES-01 (V)** Mesma simulação da criação (CA-TES-02/03), **sem** balão fixo de saudação (a primeira resposta do agente traz o cumprimento, como no atendimento); legenda "Certeza — Quanto {ela} confia na resposta. Quem decide passar para a equipe é a regra de 'Quando passa para a equipe'." (no Agente de Cotação e no ajudante interno, só "Quanto {ela} confia na resposta."; no interno, sem a linha "Amarelo"); aviso "No teste, horário e público não são aplicados."; sem percentual de corte (D1-a); "Ensinar algo que faltou" só para quem edita.
  - **CA-PTES-02 (V)** Avisos de montagem não terminada e de erro. Agente de Cotação: a legenda "Certeza" não cita "Quando passa
    para a equipe" (não existe para ela).
  - **CA-PTES-03 (R)** Quem só vê consegue testar (D8) e o teste dela não conta como teste válido (§6.6).
  - **CA-PTES-04 (V/R)** D17: com ferramenta POST ligada, teste feito por quem só vê → zero requisições HTTP (stub) e
    `skipped_tools` com `viewer_not_allowed`; a tela mostra "Neste teste, {ela} não usou {ferramenta}: só quem edita testa essa
    consulta." (V); por quem edita → a chamada sai e a tela mostra o aviso de D27; ferramenta GET sai nos dois casos.
- **O que sabe**
  - **CA-SAB-01 (V)** Só materiais para aprender (D20), barra da base (`knowledge_confidence`), estados de CA-CON-07, "N de 30
    materiais".
  - **CA-SAB-02 (V)** Spec com um material em cada estado (texto, cor, ação); "Enviar de novo" chama `resync`.
  - **CA-SAB-03 (V)** Vazio.
  - **CA-SAB-04 (V/R)** Limite de 30 com aviso e botão desabilitado; backend recusa o 31º material.
  - **CA-SAB-05 (V)** "Adicionar material": Um link / Um arquivo; `type=url` com rótulo;
    "PDF, Word, Excel, TXT, MD ou JSON · até 25 MB"; aviso de Word/Excel.
  - **CA-SAB-06 (V/R)** Perguntas da equipe: interruptor ↔ `config.faq_suggestions`; Aprovar / Mudar e aprovar / Ignorar;
    "Da conversa #N"; textos de desligado e vazio; `GET faq_suggestions` com só `autonomia_view` → 401 (BE-25).
  - **CA-SAB-07 (V/R)** Agente de Cotação: só os ramos de `quote_branches` do próprio agente (BE-17; sem chamar `insurance/*`);
    sem materiais nem perguntas; função com `autonomia_view` e sem `insurance_view` vê os ramos.
- **Onde atende**
  - **CA-OND-01 (V/R)** Conectados com "Tirar deste canal" → confirmação ("as conversas vão para a equipe") → `DELETE
    channels/:inbox_id`; as conversas com o bot voltam para a equipe.
  - **CA-OND-02 (V)** "Colocar em outro canal" (só livres) → `POST channels`; rascunho e pausado: "Ligue {a} {nome} para
    colocar em outro canal." + desabilitado.
  - **CA-OND-03 (V)** Aviso de sem canal.
  - **CA-OND-04 (V/R)** Falha de conexão mostra a mensagem pt-BR do servidor (pelo `code`, BE-10) e nada muda.
  - **CA-OND-05 (V)** "Conectar um WhatsApp novo" (só administrador; demais leem o texto de CA-LIG-09) → tela de conexão com
    volta à origem.
- **Ajustes**
  - **CA-AJU-01 (V/R)** Foto (trocar/tirar) e nome; "Salvar" por seção; toast "Salvo."; o nome novo aparece nas conversas
    (BE-16) e é o nome com que o agente se apresenta (BE-29, spec R).
  - **CA-AJU-02 (V/R)** Sem versão guiada guardada: "Este agente foi escrito à mão. Para mudar, edite as instruções." e o
    interruptor de modo travado. "Mudar conversando" retoma a conversa da criação (BE-05, só quem edita, só modo guiado — no manual o
    botão fica desabilitado com explicação e a API devolve 422 `manual_mode`); "Concluir" grava versão `builder` (BE-23) e não
    muda nome, primeira mensagem, "quando não souber" nem jeito de falar (spec R, D22).
  - **CA-AJU-03 (V/R)** "Escrever as instruções eu mesmo": confirmação; o campo abre **vazio** (a instrução gerada nunca aparece); o modo manual só é gravado junto com o texto novo (o agente nunca fica sem instrução); a versão guiada é guardada antes (BE-23); contador de 50.000; aviso âmbar. Voltar ao guiado (D25): só com versão guiada guardada; confirma com o texto de §6.3; restaura a versão e o andaime; o texto manual fica em Versões (spec R).
  - **CA-AJU-04 (V/R)** Onde atua (Clientes / A equipe / Os dois); "A equipe" com canal → "Tire {a} {nome} dos canais antes."
    em pt-BR (BE-10); sem o painel do ajudante (BE-32), "A equipe" e "Os dois" desabilitados com "Esta conta ainda não tem o
    ajudante dentro das conversas." e o PATCH recebe 422 `copilot_unavailable`; ajudante interno não mostra os controles de
    atendimento (§6.3, V).
  - **CA-AJU-05 (V/R)** Como fala (no ajudante interno: sem Primeira mensagem e com o rótulo "Quando não souber, o ajudante
    mostra à equipe"): Primeira mensagem e Quando não souber, com o efeito da tabela de §6.3 item 5 provado por spec
    por opção (BE-30); Jeito de falar (4 opções gravam a frase em português; "Do meu jeito" grava o texto livre ≤ 1.000; ao abrir,
    pré-seleciona a opção cujo texto bate).
  - **CA-AJU-06 (R)** Quando passa para a equipe: "Sempre oferecer" e "Nunca" mudam o texto que o modelo recebe, com spec por
    opção (BE-12/D1); "Quando estiver em dúvida" e todo valor fora de `always_ask`/`never` (nil, `low_confidence`, `none`,
    desconhecido) geram `instructions` byte a byte iguais aos de hoje (Clara, Lia, Guia), e o ajudante `internal` também, com qualquer valor; com "Nunca", pedido do cliente por
    pessoa e porta de horário/público ainda passam (D33). Não aparece no Agente de Cotação.
  - **CA-AJU-07 (V/R)** Para quem vai: Quem estiver livre (padrão, igual hoje) / Uma pessoa (a lista mostra só quem é membro de todas as caixas do agente) / Um
    time, com `ChoiceSelect`; ao passar, nos 3 pontos de passagem, a conversa vai para quem foi escolhido; alvo inválido ou fora
    da caixa cai em "Quem estiver livre"; com time escolhido, nas 3 portas do BE-06 ninguém de fora do time é atribuído; o funil
    do CRM e a devolução ao pausar/excluir continuam como hoje (spec de não-regressão, D31).
  - **CA-AJU-08 (V/R)** Para quem responde: Todo mundo / Só alguns clientes (condições, grupos e/ou, contato desconhecido);
    specs atuais de público passam.
  - **CA-AJU-09 (V)** Quando atende: 3 opções + aviso de canal sem horário (como CA-LIG-05); com vários canais, lista só os
    sem horário, cada um com seu link.
  - **CA-AJU-10 (V/R)** Versões: "Cada mudança nas instruções fica guardada."; lista com "Atual" e "Voltar para esta"
    (confirma, `restore`); rótulos pt-BR por `reason` e autor ou "Automático" (BE-23); versão de origem guiada nunca mostra texto
    e, restaurada, volta o agente ao modo guiado (spec R — invariante NR-10); vazio; não aparece no Agente de Cotação.
  - **CA-AJU-11 (V/R)** Rascunho: "Continuar montagem" no lugar de Pausar/Ligar, com o destino por estado de §6.3 item 9 (V
    por estado); ajudante interno: o aviso de §6.3 no lugar das seções de atendimento; num rascunho testado, salvar algo que muda o
    texto do modelo mostra "Salvo. Teste {a} {nome} de novo antes de ligar."; `both`: um aviso "As seções abaixo valem só quando {ela}
    atende clientes. No painel da equipe, isto não se aplica." Pausar/Ligar e Excluir com textos sobre conversas e materiais (ajudante interno: textos de §6.3 item 9);
    excluir confirma, apaga, volta para a lista com toast; conversas voltam para a equipe.
  - **CA-AJU-12 (V/R)** Agente de Cotação: Foto e nome, Jeito de cotar (Consultivo/Objetivo, texto com {nome}), Horário que
    {ela} informa ao cliente (`quote_choices.horario`), Para quem vai (sem as 3 opções de estratégia), Para quem responde, Quando
    atende (`response_window`, só abre/fecha a porta), Pausar/Excluir; renomear e trocar o jeito de cotar mudam o texto que a Lia recebe (BE-17, spec R);
    editar instrução → 422 `instrucao_mantida`; função `autonomia_manage` sem `insurance_manage` consegue editar (D13).
- **Ferramentas**
  - **CA-FER-01 (V/R)** Aviso de acesso; lista (nome, Ligada/Desligada, identificador · método, quando usar; Testar / Mudar /
    Excluir); limite 10; identificador começa com letra, depois letras, números e `_`, até 64 (`tool.rb` `SLUG_FORMAT`), erro "O
    identificador começa com uma letra e usa só letras, números e _."; não SuperAdmin → 401.
  - **CA-FER-02 (V)** Segredo nunca volta legível; resultado do teste em bloco que quebra linha; zero texto fora do i18n;
    excluir confirma no app.
  - **CA-FER-03 (R)** `PATCH`/`create` com `config.native_tool_slugs` (ou qualquer chave fora da lista do BE-19) → 422
    `config_key_not_allowed` com a `key`, e o `config` relido é igual ao de antes.

### 11.5 Outras telas

- **CA-CONECTAR-01 (V/R)** Número do WhatsApp (D7) → código QR (`role="img"` + `aria-label`), passos, dica; só
  administrador; erros do passo do número por `code` (BE-10): `invalid_phone`, `integration_not_configured`,
  `remote_setup_failed`, `account_token_missing`, cada um com frase pt-BR.
- **CA-CONECTAR-02 (V)** Estados Esperando leitura (com tempo restante do código: 60 s no primeiro, 20 s nos seguintes) /
  Verificando / Conectando / Conectado ("Escolher o agente" volta à origem) / Não conectou ("O código venceu… Gerar outro
  código" → `reconnect`) / Sessão desligada (texto próprio + "Reconectar") — mesmo mapeamento de `ConnectionPage.vue`.
- **CA-CONVERSA-01 (V/R)** Ajudante da equipe no painel da conversa (agente `internal|both` ativo), resumo, "Sugerir
  resposta", "Resumir de novo", pergunta livre; vazio com "Criar ajudante" só para quem edita; isolamento entre contas.
- **CA-CONVERSA-02 (V/R)** "Marcar resposta como errada" no menu da mensagem do agente; 5 motivos (`role="radio"`), "Qual
  seria a resposta certa?"; botão libera após escolher; `POST agents/message_reports`; o número aparece em "Respostas
  marcadas como erradas".
- **CA-CONVERSA-03 (V/R)** Nota **privada** de passagem "{A|O} {nome} passou esta conversa para a equipe: {motivo}." (BE-24):
  spec conta 1 nota por passagem e 0 na resposta normal; nada é enviado ao cliente.

### 11.5b Backend sem tela

- **CA-BE-01 (R)** BE-19: para cada chave fora da lista, `create` e `update` respondem 422 `config_key_not_allowed`; SuperAdmin
  pelo PATCH genérico também.
- **CA-BE-02 (R)** BE-20: acima do limite em `build_threads`, `test`, `suggest` e `sources/copy` → 429 `rate_limited` (spec com
  `Rack::Attack.enabled = true`); o front mostra a frase pt-BR.
- **CA-BE-03 (R)** BE-21/BE-05: `GET build_threads/:id` e `GET agents/:id/build_thread` com só `autonomia_view` → 401.
- **CA-BE-04 (R)** ~~BE-22~~ fora desde o #1063; no lugar: excluir pela tela nova usa a exclusão lógica do #1063
  (`deleted_at`, auditoria) e devolve as conversas (spec existente `soft_delete_spec`).
- **CA-BE-05 (R)** BE-16: renomear o agente muda o nome do bot nas caixas conectadas; trocar e tirar a foto mudam o avatar do espelho (o gatilho cobre os dois caminhos do endpoint de avatar).
- **CA-BE-06 (R)** Todo endpoint novo tem spec cross-tenant (outra conta → 404).
- **CA-BE-07 (R)** BE-31: só SuperAdmin muda os ajustes de operação; cada mudança fica registrada com quem e quando.
- **CA-BE-08 (R)** BE-26: `knows` reflete respostas fora de ordem (spec com modelo simulado).
- **CA-BE-09 (R)** BE-29/BE-30: Clara, Lia, Guia, um agente manual sem renomear, e o copiloto de um ajudante interno e de um
  `both` com Primeira mensagem e "quando não souber" preenchidos → `instructions` byte a byte iguais; Lia com Primeira mensagem e "quando não souber" preenchidos → igual; renomear → nome novo aparece.

### 11.6 Aceite visual (protótipo × implementação)

- Capturas por Playwright local (`tests/playwright/tests/agents/visual.spec.ts` + `agents.config.ts`, novos; só loopback,
  `locale pt-BR`, `America/Sao_Paulo`), conta local semeada com dados equivalentes (Clara externa com 1 PDF aceito; Lia
  `insurance_quote`; 4 caixas, 2 ocupadas); erro/carregando/vazio por `page.route`.
- Para cada tela × estado da lista abaixo: {1440, 400} × {claro, escuro}, mesmo nome dos dois lados
  (`<tela>@<estado>.<largura>.<tema>.png`). Lista (fonte: `MAP` e `stateBar` do protótipo + estados novos do PRD):
  lista (normal, carregando, erro, vazio, só ver) · escolha · conte (normal, pensando, erro, recusado, demorando, ainda
  respondendo, muitas mensagens, depois das 4 respostas) · teste (normal, apresentação mudada, ainda montando, não respondeu, demorando, muitas mensagens, invalidado por material, ferramenta que grava,
  cotação, ajudante) · escolha sem ajudante · escolha (não deu para começar) · ligue
  (normal, sem canal livre, falhou, canal sem horário, sem teste, quem edita sem ser admin) · pronto (externo, interno) · painel Clara: como está indo
  (dados, carregando, erro, sem conversas), testar (normal, montagem não terminou, não respondeu, ferramenta pulada para quem só vê), o que sabe (como está, todos os
  estados, vazio, limite), onde atende (como está, sem canal, falhou, quem edita sem ser admin, pausado), ajustes (como está, com versões, sem ajudante, ajudante interno, os dois, sem versão guiada, rascunho testado,
  modo manual, voltar ao guiado, vários canais sem horário), ferramentas (admin da plataforma) · Lia: como está indo, testar, o que cota, ajustes · ajudante interno: cartão,
  como está indo · conectar (número, número inválido, esperando leitura, verificando, conectando, conectado, falhou, sessão
  desligada) · conversa (ajudante, vazio do ajudante, resposta errada, nota interna de passagem) · gaveta de resultados (com
  itens, vazia, respostas erradas).
  Estados sem referência no protótipo (marcados "novo") são aprovados pelo Rodrigo na página lado a lado.
- **CA-VISUAL-01** Todas as capturas dos dois lados anexadas ao PR (página lado a lado).
- **CA-VISUAL-02** Nenhuma captura em branco ou cortada, conferida antes de enviar.
- **CA-VISUAL-03** Contrato estrutural 100%: mesmos títulos na mesma ordem, um botão primário por tela, mesma ordem de seções
  e abas, mesmos textos de estado, `scrollWidth ≤ largura`, controles ≥ 44 px, axe sem *serious/critical*.
- **CA-VISUAL-04** Toda divergência listada como intencional (§6.4 ou §4) ou corrigida.
- **CA-VISUAL-05** Aprovação explícita do Rodrigo na página lado a lado.

### 11.7 Validação em produção — contrato

O PRD fixa **o que** a validação garante. As consultas e os cenários concretos são escritos no **plano de validação de cada
PR** (`design/<PR>.md`), com o código do PR aberto, o volume do dia lido por psql e o workflow de deploy vigente. O ponto de
partida e as pendências obrigatórias estão em `validacao-producao-base.md` (causa raiz C13). O plano passa pelo protocolo
§10.3, com as respostas 6(a–d) por escrito para cada consulta e cenário. Os códigos Q1–Q17, T01–T31 e P0–P5 citados neste
PRD apontam para as linhas de `validacao-producao-base.md`.

**Como se mede:**
- Só leitura: SSM `AWS-RunShellScript` → `docker exec chatwoot-web psql "$DATABASE_URL"` com `BEGIN TRANSACTION READ ONLY`.
  **Nunca** `rails runner`/`rails console`. Nenhuma saída traz nome, telefone ou mensagem de cliente, só ids e contagens.
  Ler `docs/processo-de-release.md` antes.
- **Foto** do estado dos agentes tirada logo antes do merge e salva **fora** da instância. A janela de toda comparação começa
  no horário da foto.
- **Evidência só do banco.** No blue-green, a instância antiga é terminada e leva o log do container.
- **Duas stacks** (hub2you e autonomia), sempre.

**Invariantes.** Todo invariante olha só o que **mudou depois da foto**. O que já estava assim na foto é Estado (C14):
legado e estado antigo nunca disparam volta.

| # | Invariante (violação → classificação, regra abaixo) | (a) volume real | (b) caminho no código | (c) evidência no banco | (d) falso positivo / deixa passar |
|---|---|---|---|---|---|
| I1 | Nenhum vínculo agente↔caixa entre contas diferentes | 0 na foto de 05/10 | `agent_inboxes` × `inboxes.account_id` | linha do vínculo | Falso: nenhum uso legítimo cria. Deixa passar: nada |
| I2 | Pausa feita **depois da foto** devolve as conversas: nenhuma conversa `pending` ou `open` daquele agente fica com o espelho dele como `assignee_agent_bot` | Pausas por dia: poucas (medir no plano) | `release_bot_conversations!` (#1036) | `updated_at` do agente + conversa com o espelho | Falso: conversa resolvida ou adiada com o espelho é o esperado e não conta; marcada como pendente por atendente sem o espelho no comando não conta. Deixa passar: pausa anterior à foto (Estado) |
| I3 | Para cada **vínculo** criado, religado ou pausado **depois da foto**: agente que atende → espelho ativo; agente que não atende → espelho inativo | Poucos por deploy | `sync_mirror_bots` / `sync_mirror!` (#1036) | `agent_bot_inboxes` + `updated_at` do agente/vínculo | Falso: o ajudante não tem vínculo; caixa em que o administrador trocou o bot (`agent_bot` ≠ espelho) vira Estado. Deixa passar: espelho errado de antes da foto (Estado; ver "Antes do B1") |
| I4 | Conversa do Construtor que começou a processar **depois da troca de tráfego** não fica presa além da janela do BE-15 | Medir no plano | `BuildThread#build_stale?` | `updated_at` + status | Falso: thread abandonada antes, ou morta junto com o worker na troca de instância → Estado. Deixa passar: nada na janela |
| I5 | Passagem com alvo registrado pelo roteador (BE-06), criada depois da troca de tráfego, só atribui a quem **estava**, na hora da passagem, em `inbox.assignable_agents`; "Um time" só a time da mesma conta | 0 hoje (o alvo nasce no B5) | `Operate::HandoffRouter` | evento `handed_off` com alvo + filiação na data | Falso: evento sem alvo (funil, instância antiga, D31); membro que saiu da caixa depois → Estado; medido antes da limpeza do tester. Deixa passar: reatribuição manual posterior (não é a IA); atribuição posterior do funil (D31) |
| I6 | Agente com `updated_at` depois da foto não ganha chave de `config` fora de: chaves que ele já tinha na foto; lista do BE-19; chaves gravadas pelo Construtor e pelo model (`guardrails`, `voice`, `with_knowledge`, `topic_map`, `knowledge_*`, `builder_active_thread_id`, `agente_de_cotacao` e as chaves novas deste projeto, declaradas no PR que as cria; `system_key`, `guide_*` e `hidden_from_hub` só em agente que já tinha `system_key` na foto ou que o Seed do Guia criou; `native_tool_slugs` também quando gravada pelo Seed ou pelo `QuoteAgent::Builder` na criação); chaves do BE-31 com linha no `AuditLog` | Medir na foto do B1 | PATCH (BE-19), Construtor, Super Admin (BE-31) | chaves de `config` + `AuditLog` | Falso: escrita legítima do model fora da lista → a lista é corrigida, sem voltar; agente novo criado pelo Seed ou pela Cotação, com as chaves do nascimento. Deixa passar: chave proibida gravada por outro caminho fora da lista (a prova de que o PATCH recusa fica no tester do B1) |

**Antes do B1** (uma vez, só leitura, nas duas stacks): contar agentes que não atendem com espelho ativo e conversas presas
neles, sobra de antes do #1036, que só sincroniza na transição. Se houver algum, a correção vai para decisão com 🟢 e foto
(inativar o espelho e devolver as conversas pelo caminho do #1036).

**Consequência de uma falha** (invariante violado, ou cenário do núcleo ou da cobertura que falhou), C15. Nada volta por regra
mecânica. A falha dispara a **classificação**, feita na hora pelo tester/sessão com a coluna (d), o cenário repetido uma
vez e outro agente sem mudança do lote como controle:
- **Defeito do lote** → volta pré-aprovada do §14 **na hora**, sem 🟢 novo (regra 3 do Rodrigo), e aviso.
- **Não é do lote** (estado legítimo, provedor de IA fora — o agente de controle também falha —, ação de pessoa) → registra e
  lista ao Rodrigo; não volta.
- **Dúvida** → volta (o lado seguro).
- **Lote misto** (veio junto com PR de outra sessão, apesar da regra do §14) → **nunca** volta sozinho: parar, avisar o
  Rodrigo e a sessão Automação; volta por revert com OK.
- **Mudança que não é deploy** (UPDATE da D10, limpeza da Q12, flag pelo Super Admin): a volta é a dela, nunca o
  `action=rollback` — UPDATE de restauração pela foto (a foto é o backup; pré-aprovado pela regra 3) ou desligar a flag no
  Super Admin.

**Estado** (diferença não explicada pelo banco → **lista por id ao Rodrigo**, que decide antes do "ok, SHA"; nunca volta
automática, porque o cliente muda estado de propósito): retrato dos agentes, rascunhos com instrução, Agente de Cotação
(escolhas, saudação, nome do espelho), chaves de `config`, "Quando passa" dos ativos, saudação e "quando não souber" dos ativos.

**Listas ao Rodrigo antes do merge** (decisões que o PR não toma sozinho): chaves de `config` que o B1 fecha (com os valores
fora do repositório, no local do runbook); ativos com `always_ask`/`never` (B4b); ativos com saudação ou "quando não souber"
preenchidos (B4b); tons gravados em inglês (D10).

**Comportamento ao vivo** (responde, passa, para quem vai, primeira mensagem, "Nunca") **não** se mede por estatística de
produção: o volume é baixo (05/10: Clara com 3 conversas em 7 dias; Lia com 29 em 30 dias). Ele se prova no tester (§11.8).

### 11.8 Tester em produção — contrato (`chat2you-agentes-refactor-tester`)

**Regras do Rodrigo** (valem sem exceção):
- listar os testes antes de rodar, cada um com o motivo;
- afirmação dura; tempo-limite é **falha**; zero "passou" por omissão;
- 18+ cenários na entrega final, com conversação, capabilities, fora do escopo, borda e isolamento entre contas;
- evidência por cenário: HTTP, latência, ids, eventos antes/depois e captura. Campo que não existe é registrado como "não
  disponível", nunca inventado;
- todo cenário que escreve tem 🟢 e é desfeito no fim; sem o pré-requisito, o cenário fica BLOQUEADO, nunca "passou".

**Exigências de desenho** (cada plano de PR cumpre):
- Prazo de espera lido do código do dia, por tipo de agente. O teto do pedido de teste é o TTL do `InteractiveRequest`. A
  Lia tem o orçamento próprio de rodadas.
- Afirmar que **algo não aconteceu** exige uma janela de observação fixa, registrada.
- Cenário com mensagem real começa em conversa **sem responsável** e com a distribuição automática da caixa de teste
  desligada, ou com contato novo. O plano confere isso antes de mandar a mensagem.
- Agente, caixa, usuário só-ver e conta B de teste são criados para o teste, com 🟢, e apagados no fim. A Clara e a Lia só
  recebem leitura, salvo `POST test`, que não muda status nem cria evento, e pode gravar a marca de teste válido do BE-08
  (declarada no PR) — essa marca não conta como diferença de Estado nem como chave nova no I6. Agente de cliente fora da
  Clara e do agente da conta 2 é testado como usuário **só-ver** (ferramentas que gravam ficam puladas, D17), com conta e
  usuário definidos com 🟢.
- Antes de testar a Clara (ou o agente da conta 2), confirmar por psql que ela não tem ferramenta ligada que grava em
  outro sistema (D27).

**Núcleo** que roda depois de **todo** deploy que muda comportamento, nas duas stacks:
- os invariantes I1–I6;
- isolamento entre contas: lista da própria conta sem nada de outra; id de outra conta pelo caminho da própria → 404;
  caminho de uma conta da qual o usuário não é membro → 401;
- teste responde (Clara, Lia e o agente ativo da conta 2). Se um deles tem ferramenta que grava em outro sistema (D27),
  usa outro agente ativo da mesma stack sem ela; sem nenhum, o item fica **dispensado por decisão do Rodrigo**, registrado, e
  não conta como BLOQUEADO na §12;
- efeito colateral final, depois de apagar o que o teste criou.

**Cobertura obrigatória por PR** (soma ao núcleo; o plano do PR escreve os cenários):

| PR | O que precisa ser provado em produção |
|---|---|
| B1 | Chave fora da lista recusada e `config` igual (BE-19); quem só vê agentes não vê conversas de outras caixas nem perguntas da equipe (BE-25); mudar uma chave do BE-31 no agente de teste pelo Super Admin deixa linha no `AuditLog` e não mexe em outro agente; os limites do BE-20 (ENV) comportam a sequência do tester e o uso do Guia, conferido antes; BE-14 só por leitura: nenhum rascunho com resposta sumiu entre a foto e o primeiro ciclo do cron (por id; se nenhum era elegível pela idade, registra — a regra fica provada pela spec, e o "ok, SHA" não espera 48 h) |
| B2 | Lista com estado, números e canais (BE-01/08/11); renomear o agente de teste renomeia o espelho (BE-16); ligar e desligar a tela nova numa conta de teste não mexe em outra (BE-00) |
| B3 | Ligar atômico (BE-03); recusas `missing_instruction` e `missing_test` (BE-04, D15); pausar devolve a conversa; religar sem novo teste (D24); excluir limpa o espelho; o Construtor pergunta o nome (BE-07) |
| B4 | Copiar material de outra conta → 404 (BE-02); versão guiada nunca mostra texto (BE-23, NR-10) |
| B4b | Primeira mensagem e "quando não souber" chegam ao cliente (BE-30); "Nunca" não passa por iniciativa própria e passa quando o cliente pede (BE-12); o agente de teste renomeado se apresenta com o nome novo numa conversa nova (BE-29); a Lia termina o teste dentro do teto, sem cotar |
| B5 | Nota de passagem privada não chega ao cliente (BE-24); "Uma pessoa" e "Um time" atribuem conforme o BE-06 e nunca fora do time |
| B6a | Número inválido recusado sem criar caixa (BE-13) |
| B6b | Lia exposta com as escolhas iguais à foto e sem instrução (BE-17) |
| D10 (F9) | Depois do UPDATE de tons: núcleo, mais "teste responde" de cada agente ativo alterado, contra a foto Q14 — como usuário só-ver, com a conferência da D27 por agente (com ferramenta que grava: dispensado e registrado) |
| F1+ | Telas de quem só vê, em 1440 e 400 px, claro e escuro, sem nenhum clique em botão de escrita |

---

## 12. Termos de aceite da entrega final

A entrega final do projeto só é aceita quando **todos** os itens abaixo estiverem marcados, com evidência linkada:

**Escopo e fidelidade**
- [ ] Todas as telas, estados e diálogos de §6 implementados e com a flag ligada na conta 16.
- [ ] Matriz §6.5 sem nenhuma linha "nenhum leitor" sem decisão aplicada; máquina de estados §6.6 coberta por spec.
- [ ] CA-GERAL, CA-LISTA, CA-CRIAR (ESC/CON/TES/LIG/PRO), CA-PAINEL (RES/PTES/SAB/OND/AJU/FER), CA-CONECTAR, CA-CONVERSA, CA-BE:
      100% atendidos, cada um com evidência (spec, captura ou passo manual) no PR que o entregou.
- [ ] CA-VISUAL-01..05 aprovados; página lado a lado protótipo × produto aprovada pelo Rodrigo.
- [ ] Decisões D1–D35 registradas com a opção escolhida e implementadas conforme decidido.
- [ ] Nenhum controle decorativo (CA-GERAL-14).

**Qualidade**
- [ ] Cada PR passou pelo protocolo de revisão (§10.3); todo achado da rodada 2 tem registro de causa raiz em `docs/audit/`.
- [ ] Falhas de segurança fechadas e provadas: BE-19 (chaves de config pelo PATCH) e BE-25 (conversas de outras caixas), com
      Q12 tratada com 🟢.
- [ ] CI verde em todos os PRs (RSpec, Vitest, trava, central, fork-i18n) e, localmente, ESLint sem aviso, Rubocop limpo,
      `guia:check`, `central:check`, `autonomia:guia:formatos:check`.
- [ ] Cobertura de linhas ≥ 80% nos arquivos novos do front (`pnpm test:coverage` filtrado em `routes/dashboard/autonomia/agentes/**`)
      e specs para todo endpoint/serviço novo (incluindo cross-tenant).
- [ ] Specs NR-01..NR-15 passando sem alteração (ou alteração justificada no PR).
- [ ] Teste moderado com 3 pessoas leigas (O1) registrado.

**Produção**
- [ ] Cada deploy com plano de volta escrito antes, foto de antes fora da instância, validação §11.7 nas duas stacks (invariantes ok, diferenças de estado decididas) e
      "ok, SHA" na fila.
- [ ] Tester: plano de validação de cada PR (núcleo + cobertura do §11.8) 100% (afirmação dura), com os pré-requisitos criados e apagados com 🟢, com evidência, depois do último deploy; nenhum
      cenário BLOQUEADO na entrega final.
- [ ] Nenhum incidente com Clara, Lia ou agentes das contas Autonomia durante o projeto.
- [ ] UPDATE de tom (D10) executado com 🟢 e foto (Q14), se escolhido.

**Documentação e rastreabilidade**
- [ ] Guia da Plataforma (8 blocos + rotas novas) e Central de Ajuda (cap. 11, 00.08, 01.01, 18.x) reescritos e conferidos.
- [ ] Épica e Issues no Project Autonom.ia Dev com todos os campos; cada PR linkado (`Refs #épica`).
- [ ] Plano de remoção do código antigo (F10) aberto como Issue, com data.
- [ ] Checklist final de entrega (regra 8) publicado na épica.

## 13. Riscos

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| Mudança no caminho de resposta ao vivo (BE-06, BE-12, BE-17, BE-24, BE-29, BE-30) afeta Clara/Lia | Média | Alto | Padrões que reproduzem o comportamento atual; specs NR; invariantes da §11.7; tester com o núcleo e a cobertura de cada PR (§11.8); lote de um PR só com rollback de um degrau (§14) |
| Guia/Central ficam descrevendo a tela antiga | Alta | Médio | F9 obrigatório antes do aceite; enquanto houver contas nas duas versões, blocos descrevem as duas |
| Conflito com o lote de Campanhas (#993) | Média | Médio | D9: extrair peças comuns no F0 e avisar a sessão Campanhas |
| Gate de lint de e-mail bloqueia PR por aviso antigo em arquivo tocado | Alta | Baixo | Backend e front separados; rodar o recibo local antes do push |
| Promessa de comportamento que o backend não faz (como hoje com a régua) | Média | Alto | CA-GERAL-14 + revisão de produto em toda rodada |
| Fila de deploy congestionada (2 stacks, ~30 min cada) | Alta | Baixo | Agrupar PRs pequenos de backend; coordenar com a Automação |

## 14. Volta (rollback)

- **Telas:** Super Admin → Conta → desligar "Tela nova de Agentes" (BE-00) — volta no próximo carregamento da página, sem
  deploy e sem console (ETA ~2 min). Plano B, com 🟢: psql via SSM com foto antes —
  `UPDATE accounts SET internal_attributes = internal_attributes - 'autonomia_agents_redesign' WHERE id = 16;`. Nunca
  `rails runner`/console.
- **Volta padrão de um deploy** (`docs/processo-de-release.md`, regra 9): `workflow_dispatch` com `action=rollback` nos
  dois workflows de deploy. Ele religa a instância anterior, que fica parada com a tag, sem build. Só volta **um
  degrau** e desfaz o **lote inteiro**. Por isso, **todo PR deste projeto que vai para produção** (B1–B6b e os de front) sobe num **lote de um PR
  só**: o rollback desfaz só ele. Isso deixa o trem de release mais lento; é o preço da volta automática segura. Vale enquanto não houver outro lote por cima, e a regra 4 garante isso até o
  "ok, SHA". Com outro lote por cima, a volta é um lote novo com `git revert`, que espera os "ok" das outras sessões.
  O tempo de cada caminho é medido e registrado no primeiro uso. **Lote de um PR só na prática:** combinar com a sessão
  Automação que a fila de merge esteja vazia do `gh pr merge` até o deploy (a fila junta até 2 PRs por rodada) e conferir no
  `git log` da `main` que o push tem só esse PR; se veio junto com outro, a volta é por revert em lote novo.
- **O que volta junto:** nenhum dado migrado (sem migration). D10: UPDATE de volta pela foto de Q14. Limpeza da Q12:
  `UPDATE autonomia_agents SET config = config || <foto> WHERE id = <id>` por agente, com 🟢.
- **Limpeza de rascunhos (BE-14, no B1):** voltar o B1 devolve a limpeza do #1036, que poupa instrução e material mas apaga
  o rascunho que só tem respostas — justamente o que a tela promete guardar ("Fica guardado até você terminar"). A volta do
  B1 **não pode** apagar esse rascunho. Mudar o parâmetro no SSM não basta: a instância religada pelo rollback continua com o
  `.env` do primeiro boot. O plano do B1 escreve o passo exato e pré-aprovado para o aborto automático (por exemplo, tirar o
  cron da limpeza na instância religada antes de reiniciar o worker, ou voltar por revert mantendo o BE-14), com spec do
  passo; depois de uma volta real, conferir por psql antes e depois do primeiro ciclo do cron que nenhum rascunho com
  resposta sumiu.

---

## Apêndice A — Tela → componente → API

| Tela | Componente novo | Reaproveita | API | PR |
|---|---|---|---|---|
| Seus agentes | `AgentsListPage`, `AgentRow`, `AgentsSummaryChips` | lógica de `AgentCard.vue`; padrão `AutomacoesPage`/`AutomacaoLinha` | `GET agents` (+ `stats`, `channels`, `state`), `PATCH`, `DELETE` | F1 |
| Vazio | `AgentsEmptyHero`, `AgentModelCard` | padrão `AutomacaoHeroi`/`AutomacaoModelos` | — | F1 |
| Escolha | `AgentBuildChoosePage`, `AgentModelCard`, `AgentSteps` | tipos de `AgentTypePicker`; `StepsBar` | `POST build_threads` | F2 |
| Conte | `AgentBuildTellPage`, `BuildKnowsPanel`, `BuildMaterialsPanel` | `BuilderChat`, `ChatBubble`, `ChatComposer`, `MaterialDropzone`, `useFileDrop` | `build_threads/:id/messages|retry`, `builder_images`, `sources`, `sources/reusable|copy` | F2 |
| Teste | `AgentTestPhone`, `TestAnswerMeta` | `PanelTest`, `ChatBubble` | `POST agents/:id/test`, `PATCH agents/:id` (`name`, `greeting`, D29) | F3 |
| Ligue | `AgentBuildGoLivePage`, `ChannelRadioList`, `GoLiveSummary` | `BuilderReview` (lógica) | `GET channels` (+ `occupied_inboxes`), `POST agents/:id/publish` | F3 |
| Pronto | `AgentReadyPage` | `AgentModelCard` | — | F3 |
| Painel (casca) | `AgentPanelShell` | regras de `AgentPanelPage`, `TabBar` | `GET/PATCH agents/:id` | F4 |
| Como está indo | `PanelHowItsGoing`, `StatTiles`, `OutcomeButtons`, `DailyBars`, `HandoffReasons`, `OutcomeConversationsDrawer` | `PanelPerformance`, `PerformanceOutcomes`, `PerformanceConversationsPanel` | `analytics`, `analytics/conversations` | F4 |
| Testar | `AgentTestPhone`, `TestLegend` | `PanelTest` | `POST test` | F5 |
| O que sabe | `PanelKnows`, `AddMaterialDialog`, `FaqReviewList`, `QuoteBranchesList` | `PanelKnowledge`, `SourceAddDialog`, `FaqSuggestionsSection` | `sources`, `faq_suggestions`, `quote_branches` do agente (BE-17) | F5 |
| Onde atende | `PanelWhereServes` | `PanelChannels` | `channels` | F6 |
| Conectar WhatsApp | `ConnectWhatsappPage`, `QrPanel` | `InviteConnectionPage`, `wahaQrWindow` | `waha_inboxes` | F6 |
| Ajustes | `PanelSettings` + `SettingsPhotoName`, `SettingsWhatItDoes` (+`ReconverseDialog`), `SettingsActuation`, `SettingsVoice`, `SettingsHandoff`, `SettingsAudience`, `SettingsWindow`, `SettingsVersions`, `SettingsDangerZone`, `SettingsQuoteStyle` | `PanelTune`, `AgentAudienceForm`, `AgentScheduleForm` | `PATCH agents/:id`, avatar, `instruction_versions`, `agents/:id/build_thread`, `PATCH agents/:id/quote_choices` | F7 |
| Ferramentas | `PanelToolsV2`, `ToolDialog`, `ToolRow` | lógica de `PanelTools` | `tools` | F7 |
| Conversa: ajudante | visual de `AutonomiaCopilotContainer` | o próprio | `copilot` | F8 |
| Conversa: resposta errada | visual de `ReportAgentMessageDialog` | o próprio, `MessageContextMenu` | `agents/message_reports` | F8 |
| Diálogos | `ConfirmDialog` sobre `Dialog` | `components-next/dialog/Dialog.vue` | — | F1–F7 |

---

## 15. Registro de revisão do PRD

| Rodada | Revisores | Achados | Resultado |
|---|---|---|---|
| 1 (05/10) | produto/UX, técnica, segurança/produção, testes — cada achado com prova em `arquivo:linha` | 60 (16 altos, 29 médios, 15 baixos; ~12 repetidos entre lentes) | Todos aplicados nesta v2. Principais: material "não conferido" não é usado pelo agente; teste é assíncrono (202); recusa do repo é 401; BE-12 muda o prompt ao vivo (Médio, PR próprio, Q13); BE-19 vira lista fechada com 422; nova falha BE-25 (conversas de outras caixas); Cotação em rota de agentes (D13); volta pelo Super Admin, sem console; foto fora da instância e nas duas stacks; versões, nota de passagem e etapas que a tela prometia (BE-23, BE-24, BE-08) |
| 2 (05/10) | mesmas lentes, conferindo também as correções da rodada 1 | 63 (16 altos, 32 médios, 15 baixos) | **Parou.** Causa raiz em `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md`: 5 causas de método (C1 controle decorativo sem rastrear o leitor; C2 correção sem conferir invariantes; C3 fluxo sem máquina de estados; C4 tester sem regra por linha; C5 sem passe de consistência). Corrigida a causa (§6.5 matriz, §6.6 máquina de estados, §10.3 cinco passos, §11.8 com Tipo/Alvo) e depois os 63 achados, mais 3 que só a matriz achou (mídias "Para enviar", renomear, perguntas iniciais). D18–D22 e BE-26–BE-31 novos |
| 3 (05/10) | mesmas lentes, conferindo matriz §6.5, máquina de estados §6.6 e correções da v3 | 59 (17 altos, 25 médios, 17 baixos) | **Parou de novo.** Série 60 → 63 → 59 sem convergir. Causa raiz (mesmo arquivo de audit): C6 os 5 passos aplicados só ao que o revisor apontou, não aos mecanismos novos que eu criei; C7 altitude errada — o PRD fixava mecanismo interno que só estabiliza com código e teste. Correção da causa: §7.0 (o PRD fixa comportamento, invariantes e casos obrigatórios; o desenho técnico vai para `design/<PR>.md` no PR, com specs), §6.6 reescrita em comportamento, §7.2 com todos os casos técnicos das rodadas 2–3 (IDs `R2-*`/`R3-*`, arquivos em `revisoes/`). Achados de comportamento aplicados direto (Testar sem balão fixo e com aviso de horário/público; manual nunca sem instrução; D17 no "sugerir"; Q10/Q12a/Q12b/Q15; tester com sequência P1a→P1b e P5; matriz com Escolha, Ferramentas e Voltar versão) |
| 4 (05/10) | mesmas lentes, na altitude nova (comportamento e aceite; mecanismo vira caso obrigatório) | 46 (9 altos, 28 médios, 9 baixos; ~10 repetidos entre lentes) | **Parou.** Convergência 59 → 46, altos 17 → 9. Causa raiz no mesmo audit: C8 a máquina de estados tinha só a pessoa como ator (o sistema reescreve a instrução, a tela antiga, o Guia, a API e a Cotação ligam por outros caminhos) e não cobria o depois de ir ao ar; C9 edição por linha deixou sobras nos CA. Correção da causa: tabela de atores em §6.6 e `item_replace` (troca o item inteiro). Decisões novas D23–D28 (escopo do O2, depois de ir ao ar, voltar ao guiado, Testar do ajudante, ferramentas que gravam, perguntas sugeridas); BE-32; Q16/Q17 e evidência por id; tester com P0, T14b, T25, T26 e tempo-limite de 12 min |
| 5 (05/10) | mesmas lentes | 43 (3 altos, 24 médios, 16 baixos) | **Parou.** 21 achados nos mecanismos de produção criados na rodada 4 e 12 em regras novas não cruzadas com as variantes. Causa raiz (mesmo audit): C10 validação de produção desenhada sem volume real, código até o fim, processo de release e fonte da evidência; C11 regra nova não cruzada com tipo × modo × porta × campos do modelo; C12 passe de consistência de memória. Correção da causa: passos 6 e 7 no §10.3, lista fixa no passo 5, §6.7 matriz de variantes, §11.7 com só invariante abortando sozinho, §11.8 com "Vale a partir de" e pacote por deploy. D29–D30 novos |
| 6 (05/10) | mesmas lentes | 27 (5 altos, 16 médios, 6 baixos) | **Parou.** 17 achados (4 altos) de novo na validação de produção. Causa raiz C13: a §11.7/§11.8 estava na altitude de mecanismo (a C7 que eu tinha corrigido só para os BE). Correção da causa: o PRD fixa o contrato (invariantes I1–I6, princípios, núcleo, cobertura por PR); consultas e cenários vão para o plano de cada PR, com `validacao-producao-base.md` como ponto de partida e 15 pendências obrigatórias. Comportamento corrigido: D29 recomeça a conversa de teste; `publish` sem nome e saudação; ajudante sem Primeira mensagem e com o leitor real de "quando não souber"; textos de motivo; andaime do legado; teto do teste da Lia; reaper já corrigido pelo #1036; volta do B1; lote de um PR só na prática; D31 (funil do CRM) |
| 7 (05/10) | mesmas lentes | 28 (0 altos, 18 médios, 10 baixos) | **Parou.** Primeiro sem alto. Causa raiz C14: passos 5–7 executados de cabeça, sem registro (a D31 não foi procurada no BE-06; I2/I3/I6 sem a resposta 6d). Correção da causa: §15.1 registro de conferência obrigatório; respostas 6(a–d) escritas ao lado de cada invariante; todo invariante olha só o que mudou depois da foto. Comportamento: teste válido com regra única (mudança recomeça a conversa); campo editado à mão protegido do Construtor; renomear invalida em todo modo; BE-30 fora do copiloto; devolução ao pausar sem "Para quem vai"; todo PR em lote de um PR só; consequência de falha do tester; prova do BE-14 por leitura; cobertura de BE-29, BE-31, BE-20 e D10 |
| 8 (05/10) | mesmas lentes | 28 (0 altos, 14 médios, 14 baixos) | **Parou.** Zero altos pela 2ª vez; 12 achados na volta automática. Causa raiz C15: volta por regra mecânica exige prever todo estado legítimo (conjunto aberto). Correção da causa: falha dispara classificação (defeito do lote → volta na hora, sem 🟢; não é do lote → lista; dúvida → volta). C11 de novo: invalidação por lista → regra pelo efeito ("o que responde ou por onde responde"). D32 (gênero por "Tratar por"), D33 ("Nunca" sem promessa de passar quando a IA cai); restaurar versão manual; chaves `async_*`; WAHA compatível; avatar; registro do BE-31; Lia sem "Ensinar"; textos de excluir; rascunho para quem só vê |
| 9 | mesmas lentes | — | pendente |

### 15.1 Registro de conferência da rodada 7 (passos 5, 6 e 7 do §10.3)

| Item criado ou alterado | Passo 5 — onde aparece (conferido) | Passo 6 (a–d) | Passo 7 — variantes |
|---|---|---|---|
| D31 (funil do CRM não muda) | D31, BE-06, CA-AJU-07, §6.7, I5, cobertura B5 | (d) escrito em I5 | funil = porta própria; "não se aplica" |
| Teste válido (regra única) | §6.6, BE-08 (referência à §6.6), §6.2.3, CA-TES-05, CA-TES-09, §7.2 | — | todos os tipos; ajudante pelo copiloto (D26) |
| Campo editado à mão protegido | §6.6, §7.2, BE-05 (retomada) | — | guiado; manual não tem Construtor |
| Renomear invalida em todo modo | §6.6, §6.7 (Nome), §7.2 | — | guiado e manual; cotação pelo BE-17 |
| BE-30 fora do copiloto | BE-30, §6.7, §7.2, CA-BE-09 | — | interno, `both` (parte de equipe), D26 |
| Devolução ao pausar/excluir | BE-06, §7.2, BE-24 (3 portas) | — | todos os externos |
| I1–I6 reescritos | §11.7 (tabela com a–d), núcleo | escrito na tabela | ajudante sem vínculo (I3); cotação (I6 `agente_de_cotacao`) |
| Antes do B1 (legado de espelho) | §11.7 | (a) medir; (d) só leitura | todos |
| Lote de um PR só para todo PR | §14, §10.1 (topo e B1), §11.7, §10.3 passo 6 | (d) lote misto → sem volta automática | — |
| Cobertura B1/B4b/D10 | §11.8, D10 (F9), §10.1 | prova do BE-14 por leitura | — |

### 15.1b Registro de conferência da rodada 8

| Item | Passo 5 — onde aparece | Passo 6 (a–d) | Passo 7 — variantes |
|---|---|---|---|
| Classificação no lugar da volta mecânica (C15) | §11.7 consequência, §10.3 passo 6, cabeçalho dos invariantes, §14 (volta pré-aprovada) | (d) é guia de julgamento; controle = outro agente | deploy × não-deploy (D10, Q12, flag) × lote misto |
| Invalidação pelo efeito | §6.6, BE-08 (aponta para §6.6), §7.2 | — | inclui atuação (externo↔interno↔os dois) e tirar material |
| D32 gênero | D32, §5 princípio 2, §6.2.2, CA-CON-16 | — | todos os tipos, inclusive o ajudante |
| D33 "Nunca" | D33, §6.3 item 5, CA-AJU-06, §7.2 | — | não se aplica à Lia (sem "Quando passa") |
| I2, I4, I5, I6 ajustados | §11.7 tabela | (d) atualizado | seed do Guia, cotação, membro removido |
| BE-31 lista = D21 | D21, BE-31, I6 | — | sistema fora; Lia sem `native_tool_slugs` |
