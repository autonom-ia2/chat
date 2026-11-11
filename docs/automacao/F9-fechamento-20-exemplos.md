# Automação livre · teste de fechamento dos 20 exemplos (F9.6 a F9.8)

- **Épico:** #2414 · **Issue:** #2570 · **Base:** termos de aceite F1–F9 (31/10, commit `dcd9a9f5d4`, em [`termos-de-aceite-F1-F9.md`](termos-de-aceite-F1-F9.md)), main em `4bd7168c0f` (05/11).
- **Para que serve:** o épico só fecha quando os 20 exemplos dos termos rodam de ponta a ponta no ambiente de testes,
  montados como o dono montaria, com teste automático conferindo o resultado prometido. Este documento desenha esse
  teste e, antes dele, mostra **o que falta no motor para cada exemplo rodar**. A lista de lacunas (seção 5) é o
  produto principal agora: vira trabalho para as frentes.

## 1. Regras do teste

1. **Montado como o dono montaria.** A automação nasce pela API pública da tela (`POST /api/v1/accounts/:id/autonomia/automacoes`)
   e é ligada por `POST …/automacoes/:id/ligar`, com o usuário que o exemplo nomeia. Nada de `create(:autonomia_automacao)`
   nem de gravar a receita direto no banco: a receita passa pelo esquema, pela `Receita#problemas`, pela chave de funis
   e pelo "assumir e religar", como na tela.
2. **O mundo é real; só a borda é dublê.** Conta, caixas, contatos, conversas, cards, etiquetas e atributos são
   gravados no banco de teste. O gatilho chega pelo caminho de produção: a mensagem do cliente é gravada como o canal grava, o
   callback do modelo dispara o evento, e o despacho assíncrono o leva ao `AutomacaoListener`, um job por vez.
3. **Saídas externas no receptor de teste (F9.7).** Tudo o que sai da plataforma é chamado de verdade, com o mesmo
   pedido HTTP que iria para produção. O receptor fica na camada HTTP (WebMock), depois de todo o nosso código, e grava
   cada chamada para o spec conferir destino, modelo aprovado e campos.
4. **Relógio adiantado (F9.8).** Esperas de minutos, dias e meses rodam com `travel` e a varredura
   (`VarreduraJob`), nunca com `sleep` nem com o `due_at` gravado na mão.
5. **IA num dublê nesta etapa (F9.8).** Os passos de IA chamam o `PassoDeIa` de verdade, com a chave da conta; quem
   responde é o dublê no endereço da OpenAI, com a resposta roteirizada por exemplo. A IA real roda **uma vez, no
   fim**, com o OK do Rodrigo e orçamento combinado (ver 3.4).
6. **Exemplo que ainda não roda fica pendente com o motivo.** O spec existe para os 20; o que depende de uma lacuna é
   marcado como pendente, com o código da lacuna. Quando a lacuna fecha, o pendente vira teste de verdade. O épico só
   fecha com os 20 passando (F9.8).

## 2. Estrutura dos specs

```
spec/fechamento/automacao/
  exemplo_10_cliente_bravo_spec.rb         # roda hoje (passos 1–5 e 7; 6, 8 e "tirar da agente de IA" pendentes)
  pendentes_spec.rb                         # os outros 19, um `it` pendente por exemplo, com as lacunas
  aceite_a_conferir_spec.rb                 # Parte A: F3.7, F3.10 e F6.7 contra o texto do aceite (seção 7)
spec/support/fechamento_automacao.rb        # montagem como o dono, receptor, dublê de IA, relógio
```

- Tag `:fechamento_automacao`. Cada exemplo é um arquivo, com o nome do termo de aceite.
- O CI roda a pasta: o job "RSpec - plano" (`.github/workflows/testes.yml`) lista todo `spec/**/*_spec.rb` e divide
  entre os shards de "RSpec (n/12)".
- Rede fechada: o `spec_helper` liga `WebMock.disable_net_connect!`; o receptor e o dublê de IA são stubs do WebMock.
  Nenhuma chamada sai e nada é cobrado.
- Cada `it` é uma frase do **Resultado** do exemplo (o que o dono vê), não um passo técnico.
- O spec de um exemplo segue a ordem do termo: monta a conta, monta a automação pela API, liga, provoca o gatilho,
  adianta o relógio quando o exemplo espera, e confere o resultado no banco (card, etiqueta, nota, sino) e no receptor
  (o que saiu).
- Hard-assert: nada de "inconclusivo". Tempo esgotado ou chamada faltando é falha.

### 2.1 O apoio (`spec/support/fechamento_automacao.rb`)

| Peça | O que faz |
|---|---|
| `montar_automacao(dono, account, nome:, receita:)` | `POST /autonomia/automacoes` como o dono, confere 201 e devolve o id e a versão. |
| `ligar_automacao(dono, account, automacao)` | `POST /autonomia/automacoes/:id/ligar` como o dono, confere 200 e `ativa`. |
| `cliente_escreve(conversa, texto)` | Grava a mensagem recebida e roda os jobs (despacho, rodadas do motor, envio) um por vez. |
| `rodar_jobs` / `jobs_fora` | Drena os jobs do caminho de produção; `jobs_fora` lista os que ficaram sem rodar. |
| `adiantar(tempo)` (a fazer) | `travel` + `VarreduraJob`, com o primeiro exemplo que espera dias (G11 no exemplo 10, ou G6). |
| `receptor` | As chamadas gravadas (método, host, caminho, corpo em JSON). |
| `ia_responde(conta, roteiro)` | O dublê da OpenAI: responde pelo nome do schema que o passo manda (`automacao_decidir`, `automacao_resumir`…) e grava o que a IA recebeu. |

## 3. Peças

### 3.1 Montagem pela API pública

A receita de cada exemplo é escrita no formato do esquema (`lib/operator_guide/automacao-receita.schema.json`), com
os ids da conta de teste. É a mesma receita que o Guia ou o editor gravariam. O spec confere a resposta da API: 201
ao criar, 200 ao ligar, e 422 com a frase quando a receita não serve (esse 422 é útil: mostra a lacuna em frase).

As flags ligadas são as da conta piloto: `automacao_fundacao`, `automacao_motor`, `automacao_mensagens`,
`automacao_ia`, `automacao_editor`, e as de cada fase quando chegarem.

### 3.2 Receptor de teste (F9.7)

Uma porta por canal, todas na camada HTTP, gravando a chamada:

| Saída | Onde o pedido sai | Receptor | O spec confere |
|---|---|---|---|
| WhatsApp oficial (Cloud) | `graph.facebook.com/…/messages` (`SendReplyJob` → `Whatsapp::Providers::WhatsappCloudService`) | WebMock grava e responde `wamid.*` | número do cliente, texto, e o `template.name` + parâmetros quando for modelo aprovado |
| WhatsApp Híbrido | Dentro da janela de 24 h, pela Cloud (`receptor_whatsapp_cloud`). Fora dela, pela WAHA (`WAHA_API_URL`, `/api/sendText`) | `receptor_waha` grava qualquer pedido à WAHA | com a janela aberta, a saída pela Cloud e nada na WAHA (#2701) |
| Instagram | `graph.instagram.com/v22.0/<conta>/messages` (`Instagram::SendOnInstagramService`, corpo em formulário) | `receptor_instagram` grava; `respostas_do_instagram` separa a mensagem do "digitando" | recipient id e texto (#2701) |
| E-mail (a fazer) | ActionMailer (`deliveries`) | `ActionMailer::Base.deliveries` | destinatário, assunto, corpo |
| Webhook para outro sistema (F8) (a fazer) | URL configurada no passo | WebMock grava e devolve a resposta roteirizada (ex.: número da proposta, ou recusa) | URL, campos escolhidos; a resposta voltando para o card |

O WhatsApp oficial, o Híbrido e o Instagram estão montados; as outras portas entram com o primeiro exemplo que
mandar por elas. A entrada também é a real (`spec/support/fechamento_automacao_canais.rb`, #2701): o webhook da Cloud e o
do Instagram, assinados como a Meta assina, e o job do canal grava a mensagem do cliente. No Híbrido, a mensagem do
cliente entra pela Cloud: o motor (WAHA) só avisa status e recibo, e só manda com a janela fechada.
O receptor não é um mock do nosso código: o `SendReplyJob`, o serviço do canal e o cliente HTTP rodam inteiros, e só
a rede é trocada. Por isso o pedido gravado é o que iria para produção.

### 3.3 Relógio adiantado (F9.8)

`adiantar(30.days)` = `travel(30.days)` + `VarreduraJob.perform_now` com os `AvancarJob` enfileirados rodando. A
varredura de tempo (gatilhos "N dias antes", F6 PR3a) e a recorrente (F8 PR3b) entram no mesmo `adiantar` quando
chegarem. O fuso é o da conta (`custom_attributes.timezone`), e o spec do exemplo 1 e do 6 conferem o dia certo nele.

### 3.4 IA: dublê agora, real uma vez no fim (F9.8)

- **Agora:** `ia_responde` responde no endereço da OpenAI (`api.openai.com/v1/responses`), como o `executor_ia_spec`.
  O `PassoDeIa` roda inteiro: chave da conta, schema, conferência da resposta, custo no registro (o exemplo 10
  confere os tokens no registro do "decidir"). O dublê grava a
  entrada, para o spec conferir que a IA recebeu a conversa e nunca o e-mail ou o telefone.
- **No fim:** uma rodada com a IA real, só dos passos de IA dos 20 exemplos, com a chave de teste. Custo estimado
  antes de rodar; só roda com o OK do Rodrigo e o orçamento combinado. Ela confere o caminho escolhido e os campos
  extraídos contra o que o exemplo promete.

## 4. O que roda hoje (main `4bd7168c0f`)

Na main estão os gatilhos de conversa (criada, aberta, resolvida, mensagem criada, com filtros da mensagem, da
conversa e do contato), os passos esperar, esperar até, se e parar, a ação da plataforma pela lista permitida
(etiquetas, atributos, contato, empresa, conversa, atribuição, card alterar e mover, etapa, agente na caixa), mensagem
ao cliente dentro da janela, aviso à equipe pelo sino e os quatro passos de IA.

**Na integração do #2414 (09/11), o 9 fecha:** com a G58 (#2784) sobre a G21 (#2706), a busca grava os `card_ids` dos cards criados e a campanha de cada segunda vai só a eles; `exemplo_09_prospeccao_semanal_spec.rb` roda à risca e o 9 saiu do `pendentes_spec`. **Placar em 09/11: 2 de 20 inteiros (3 e 13).** O 9 tem spec próprio com a G21 (#2706), mas o passo 4 manda a campanha a todo contato com a etiqueta, não só às empresas da execução: **o exemplo 9 só fecha junto com a G58 (#2784)**, o público da execução (a campanha de cada segunda vai só às empresas criadas nesta execução). A G21 sozinha não o fecha. **Placar em 07/11, depois da auditoria dos termos (#2678): 0 de 20 inteiros.** O ex. 10 e o ex. 13 voltaram a pendente pela G28 (lote 2, #2679): no 10, os passos 4, 6 e 7 montam só aproximados; no 13, o resumo da festa (a IA não lê o card) e o extrair que grava no card em 2 passos. Os specs próprios deles seguem rodando os passos que montam, e o 13 agora fecha a festa (card ganho) antes dos passos de data. Base: a auditoria dos termos de 07/11 (Issue #2678). Lacunas fechadas: G1, G2, G3, G4, G5, G6, G11, G14, G16. Exemplo só conta inteiro e com spec verde; parcial não conta.

Com a G4 (#2628), **o exemplo 10 (cliente bravo) roda inteiro**: o passo 8 (card no quadro "Melhorias") roda desde a
G4; o 2 (tirar da agente de IA), desde a G15. Os outros 19 começam por um gatilho
ou dependem de um passo que ainda não existe na main.

## 5. Lacunas: o que falta, por fase

Cada lacuna tem um código e uma frente dona (distribuição da Automação, 05/11). "Em PR" quer dizer que a frente já está fazendo.

| Código | O que falta | Fase | Situação em 05/11 | Dono | Exemplos que segura |
|---|---|---|---|---|---|
| G1 | Mandar pelo **modelo aprovado do WhatsApp** fora da janela de 24 h | F4 (F4b) | **Fechada** (#2586): campo `modelo` do passo "mensagem" | F1 | 1, 2, 3, 4, 5, 6, 8, 11, 13, 14, 18, 19, 20 |
| G2 | Mandar **e-mail** ao contato (pela caixa de e-mail da conta) | F4 / F8.2 | **Fechada** (#2601) | F1 | 1, 3, 12, 13, 19, 20 |
| G3 | **Criar retorno** para a equipe (com e sem envio automático) | F6 "Retorno" | **Fechada** (#2629): passo `retorno`, prova em `g3_criar_retorno_spec.rb` | F2 | 1, 2, 3, 4, 5, 9, 12, 14, 15, 16, 19 |
| G4 | **Criar card** num funil/etapa para a conversa ou o contato (e "abrir card de retenção", "card no quadro X") | F6 | **Fechada** (#2628): passo `card` (`etapa_id`), com a criação do `CardNaEtapa` (`CardNovo`); pede a chave de funis | F2 | 4, 6, 8, 9, 10, 11, 16, 18 |
| G5 | Gatilhos do **card**: criado, entrou/saiu da etapa, ganho, perdido (atualizado e campo mudou ficam na G27) | F6 | **Fechada** (#2554) | Gatilhos | 2, 3, 4, 5, 7, 8, 11, 12, 13, 14, 15, 18, 20 |
| G6 | Gatilhos de **tempo**: parado há X dias; N dias antes/depois de uma data do card ou do contato (vencimento, aniversário, próxima revisão, data da festa) | F6 | **Fechada** (#2611). Em PR (#2678): a data do card também no card ganho (antes só o aberto) e a opção "todo ano" (dia e mês) para aniversário | Motor | 1, 5, 6, 13, 18 |
| G7 | **Recorrente** com filtro (todo dia 1º, toda segunda 8h, quinta 9h), **uma execução por registro do filtro** (contato ou card), nunca uma execução sem alvo (decisão da Automação, 06/11) | F8 | Em PR (F8 PR3b) | Gatilhos | 7, 8, 9, 16, 17, 20 |
| G8 | Gatilho **mensagem que falhou** na entrega | F8 | **Em PR** (#2637): gatilho `mensagem.falhou`, na conversa, uma vez por mensagem; a falha da mensagem que uma automação mandou segue a cadeia de quem mandou | Gatilhos | 1, 19 |
| G9 | Gatilho **troca de responsável** (do card e da conversa), com o anterior marcado como ausente | F8 | **Em PR** (#2707): `card.responsavel_mudou` e `card.time_mudou`, do gancho único do card (`Crm::CardAvisaAutomacao`, qualquer caminho, inclusive a Lista do CRM em lote); quem cuidava antes em `gatilho.responsavel_anterior_id/_nome/_ausente` (o filtro "a anterior está ausente" do termo) e o time de antes em `gatilho.time_anterior_id/_nome`; `card.responsavel_nome`; o "avisar" chama quem cuida do card. A troca na conversa (F8: `conversa.responsavel_trocado`/`time_trocado`) fica fora: nenhum termo pede | Gatilhos | 17 |
| G10 | Gatilho **etiqueta posta/tirada** | F8 | A fazer (F8 PR2d) | Gatilhos | — |
| G11 | **Esperar a resposta** de alguém: "até o cliente responder" e "até a equipe responder", com prazo | F3/F4 | **Fechada** (#2592): `conversa.equipe_respondeu` e `conversa.cliente_respondeu` no "esperar até"; lote 4 (#2682): `conversa.responsavel_respondeu` (a Fernanda, o Carlos), `gatilho.repetiu` (a 2ª falta do ex. 4) e o card que muda acorda a espera (ex. 12) | Motor | 1, 2, 10, 12, 15, 17, 19, 20 |
| G12 | Gatilho **reunião marcada / remarcada / cancelada** e o **link da agenda** do responsável no texto | F8 | A fazer; o link da agenda não é valor da receita | Gatilhos | 1, 2, 3, 4, 5, 6, 9, 11, 15, 16, 18, 20 |
| G13 | **Webhook de saída** e gravar a resposta no card; recusa vira caminho "deu erro" | F8 | **Fechada** (#2670 pelo #2676, integração 2 do #2414): passo `webhook`, prova em `g13_webhook_spec.rb` (ex. 20, passos 3 e 4) | Gatilhos | 8, 14, 20 |
| G14 | **Campanhas**: pôr e tirar o contato de uma campanha, montar e disparar campanha para quem tem uma etiqueta | novo | **Fechada** (#2630): passo `campanha` com `disparar` (pela Campanha da tela, só em gatilho da conta, `conta.recorrente` da G7) e `nao_receber`; pôr/tirar = etiqueta do público; e-mail dos ex. 3 e 20 pela G2 | F5 | 2, 3, 6, 7, 9, 12, 16, 20 |
| G15 | **Passar a conversa para a agente de IA** e tirar dela | F3 (ação) | **Em PR** (G15): passo próprio "Passar para a agente de IA" (`ia_assumir`), pela Atribuição do CRM; `assignee_type` proibido no atribuir. Tirar = atribuir à pessoa (provado no exemplo 10, passo 2) | F7 | 2, 4, 7, 10, 15, 17, 18 |
| G16 | **Valor calculado no corpo** da ação (gravar "hoje + 6 meses", "indicado por {nome}", motivo da perda no texto) | F3/F4 | **Fechada** (#2593 motor, #2639 editor): `$valor`, `$texto` e `$data` no corpo da ação | Motor | 3, 5, 6, 11, 13, 16, 17 |
| G17 | **Criar contato** (o amigo indicado, o funcionário novo) e **importar em lote** ligado à empresa | novo | `POST contacts` fora da lista; importação não é passo | F2 | 8, 11 |
| G18 | **Agir ou ler em outro registro ligado** ao alvo (o card do João avisa a Maria, que indicou; a resposta lê o motivo da perda no card antigo do mesmo contato). "Para cada card com etiqueta X" é da G7 | F8 / novo | **Em PR** (#2671): passo "em outro registro" (`em_outro_registro`), uma execução filha por registro ligado (o contato num campo do alvo, os cards do contato), com o editor no mesmo PR (#2675, Refs #2672); prova em `g18_em_outro_registro_spec.rb` (ex. 11, passo 7, e ex. 16, passo 4, à risca); a âncora é só um campo do card do tipo **Contato** (decisão 16: a equipe escolhe o contato da conta numa lista; o card recusa contato de outra conta, e o salvar recusa campo de número, que num engano mandaria a mensagem a outro cliente), e a ligação que não acha registro deixa o motivo no histórico da mãe | Motor + editor | 11, 16 |
| G19 | **Nota no contato** (não na conversa) | F3 (ação) | Em PR (#2636): `POST contacts/:contact_id/notes` na lista | F7 | 5, 19 |
| G20 | Passos de IA **lendo anexo** (PDF, foto do currículo, documento) | F7 | Em PR (#2669): `le: anexos` — foto e PDF vão como estão ao modelo do passo, áudio pela transcrição; o que passa do limite do provedor pula com motivo | F7 | 3, 8, 14, 18 |
| G21 | **Prospecção**: rodar busca salva e conferência de WhatsApp como passo | novo | **Fechada** (#2706): passo `prospeccao` com `buscar` (repete uma busca do histórico, espera a conferência de WhatsApp até 2 h, card por empresa com WhatsApp e etiqueta no contato; só em gatilho sem alvo, G7) e `recusar` (recusa do lead); ponta a ponta do ex. 9 em `exemplo_09_prospeccao_semanal_spec.rb` | F5 | 9 |
| G22 | **Avisar quem não está na conversa** (o RH da empresa cliente por mensagem) | F4 | **Fechada** (integração 2 do #2414): o "para cada item" (G24, `ItemDoParaCada`) grava no card que cria quem pediu (`crm_cards.solicitante_contact_id`, o contato da conversa que mandou a lista); o card que já existia fica como está. Com o gravador (`Solicitados::GRAVADORES = %w[para_cada]`), o salvar aceita a condição e a tela a oferece. A seleção `solicitante_de` do `contato.recorrente` pega um RH por empresa com card aberto e campo de marcar em branco, só entre os cards que quem ligou vê; o valor `contato.solicitados_faltando` lista quem falta e o quê, e a mensagem sai pela conversa nova (G33) com o modelo (G1). Prova do passo em `g22_avisar_o_rh_spec.rb`; a sonda roda o "para cada item" pelo motor e confere o texto ao RH. A outra metade do título ("a equipe quando o alvo não tem conversa") não aparece em nenhum termo e fica fora | F1 | 8 |
| G23 | Condição sobre **disponibilidade de uma pessoa** (a responsável voltou de férias) | F8 | Fechada (#2737): "ausente até" na pessoa (Equipe e perfil) e os valores `card.responsavel_ausente` e `conversa.responsavel_ausente`. O "responsável anterior ausente" vem com a G9 (#2707) | Motor | 17 |
| G24 | **Encadear duas automações** em que a primeira cria N registros e a segunda roda em cada um | F6/F8 | Fechada (#2771): o passo "para cada item" (`para_cada`) acha a lista na conversa pela IA e abre um card por item, com o contato achado pelo telefone ou criado pela linha do Importar contatos; cada card nasce numa raiz própria da cadeia, os outros campos (a data de nascimento) vão para o contato como colunas extras do import, e a automação de `card.criado` roda em todos (`para_cada_cadeia_spec.rb`; ex. 8, passos 1 a 5, em `exemplo_08_funcionario_novo_spec.rb`) | Motor | 8 |
| G25 | **Fechar card** como ganho/perdido/resolvido com motivo | F6 (ação) | **Fechada** (#2654, integração 2 do #2414): ação `POST crm/cards/:id/close` com `result` ganho ou perdido e o motivo opcional; o card da conversa é só para ler (decisão 19), então o fechar roda num gatilho de card ou no "em outro registro" | F2 | 4, 6, 12, 18 |
| G26 | **Aplicar SLA** à conversa | F3 (nativo) | Fora do catálogo do Guia (termo, nota da seção dos exemplos) | F2 | — |
| G27 | Gatilho **card atualizado / campo mudou** (o valor acima de R$ 50 mil no 15; o card ficou completo no 8) | F6 | **Em PR** (#2661): gatilho `card.atualizado` com a `mudanca` (o valor de venda ou um campo personalizado, e a condição); o card que nasce conta como vindo do vazio. Nasce do próprio card (`Crm::CardAvisaAutomacao`, #2687), o mesmo caminho que acorda o "esperar até": vale tela, API, upsert, IA, lote e passo da automação | Gatilhos | 8, 15 |
| G28 | O **texto da IA vira valor entre passos** (`ia.<passo>`): os cuidados do procedimento saem pelo modelo aprovado fora da janela; o "mesmo resumo" vai à dona sem outra ida à IA | F7 | **Fechada** (#2688, absorveu #2674): o "escrever" e o "resumir" guardam o texto na execução, que some quando ela termina; o "escrever" tem o destino "Só guardar"; a "mensagem" com modelo leva o texto numa variável. A filha do "em outro registro" (G18) é outra execução e lê o `ia.*` da mãe vazio (pula com faltou_valor). | F7 | 3, 4, 5, 10, 19 |
| G29 | **Origem do card do formulário** na receita: o gatilho filtra "card criado pelo formulário de um anúncio" e o passo lê o nome do anúncio (etiqueta com o nome dele) | F6 | A fazer: o formulário grava `source` e `metadata.meta_lead_form` (anúncio, formulário, campanha) no card, mas nenhum caminho de `Valores` lê isso; o filtro só tem o funil (achado no exemplo 2, 07/11) | Gatilhos | 2 |
| G30 | **Responsável por anúncio**: o corretor responsável por aquele anúncio (retorno para ele, link da agenda dele) | F6 | A fazer: o card do formulário ganha o dono pela regra do `Crm::Cards::Creator`, que não olha o anúncio. A Atribuição (`Crm::Entrega`) liga funil e etapa a pessoa (a fixa ou quem cuida do funil), nunca anúncio; nenhum cadastro liga anúncio a pessoa (achado no exemplo 2, 07/11) | F2 | 2 |
| G31 | **Decidir a cada resposta**: voltar a esperar e decidir de novo enquanto a IA diz "ainda conversando" | F3/F7 | Em PR (G31): opção `de_novo` do decidir (`caminhos` que voltam a esperar e `prazo`); toda volta consome uma resposta nova do cliente e é uma ida paga à IA; vencido o prazo sem resposta (24 horas no exemplo 2), a execução encerra sem mandar nada, e os passos depois do decidir não rodam (decisão do Rodrigo, 09/11). Prova em `g31_decidir_a_cada_resposta_spec.rb` | Motor | 2 |
| G32 | **Esperar a reunião ser marcada** no meio da execução ("visita marcada: move o card e avisa") | F8 | Feito na branch `feat/2703-g32-reuniao` (#2703): valor `card.tem_reuniao_marcada` na condição e no "esperar até" (acorda no evento de reunião do card); filtro `pagina_id` (página de agendamento) nos três gatilhos de reunião; "quem atende a reunião" (`para.da_reuniao`) no avisar. Na mesma branch: `contato.tem_reuniao_marcada` (#2710, a reunião em qualquer card do contato, que acorda quem espera no card ganho; serve à #2704) e o gatilho de tempo `card.antes_da_reuniao` (#2709, lembrete N minutos/horas/dias antes, com `pagina_id`) | Motor | 1, 2, 5, 6, 18, 20 |
| G33 | **Mandar mensagem a quem não tem conversa** (o lead do formulário, o contato do aniversário): a caixa por onde abrir | F4 | **Fechada** (#2680): `gatilho.conversa_nova.caixa_id`; a mensagem abre a conversa, e a espera, a IA e a agente usam ela | Motor | 2, 6 |
| G34 | **Resposta em outra conversa do contato** (a do e-mail) e **a mensagem mandada como valor** (`envio.texto`, `envio.situacao`) | G11 | **Fechada** (#2680): o ramo "se o envio falhou, manda por e-mail o mesmo texto" monta sem a G8 | Motor | 1, 19 |
| G35 | A **IA lê o card** (`le: card`): título, etapa, funil, status, motivo da perda e campos; o valor só com a permissão (#2597) | F7 | Em PR (#2679): só se quem ligou vê o card | F7 | 12, 13, 15 |
| G36 | A **IA lê as notas internas** da conversa (`le: notas`), como a nota do mecânico | F7 | Em PR (#2679) | F7 | 5 |
| G37 | **Público da campanha com exclusão**: "a mesma campanha para todos os outros" e "perguntou na Black e não comprou" | F6 | **Fechada** (#2686; prova de ponta a ponta no exemplo 7, `exemplo_07_black_friday_spec.rb`, lote 3 do #2414, com a sonda de comportamento ligada): o passo campanha manda para quem tem as etiquetas ou para todos os contatos da conta (`publico: todos`, "a mesma campanha para todos os outros"); `sem_etiquetas` grava `ExcludeLabel` no público, e o `CampanhaSemEtiquetas` tira quem tem uma delas no envio, também no público importado (achado no exemplo 7, 07/11) | Gatilhos | 7 |
| G38 | **Respondeu à campanha X** como filtro do gatilho da mensagem | F6 | **Fechada** (#2686; prova de ponta a ponta no exemplo 7, `exemplo_07_black_friday_spec.rb`, lote 3 do #2414, com a sonda de comportamento ligada): `mensagem.campanha` no filtro do gatilho da mensagem, o nome da última campanha recebida nesta caixa antes da mensagem (achado no exemplo 7, 07/11) | Gatilhos | 7 |
| G39 | **Gatilho numa data única** ("a quinta antes da Black Friday, às 9h") | F6 | Em PR (#2753): frequência `uma_vez` no recorrente da conta e do contato, com `data` e `hora` no fuso da conta; roda uma vez e nunca mais, mudar só a hora não repete, data passada não salva (achado no exemplo 7, 07/11); prova de ponta do passo 1 do exemplo 7 (a campanha sai na data e na hora, só para a etiqueta) em `g39_data_unica_spec.rb` | Gatilhos | 7 |
| G40 | **Esperar só a pessoa que atende** a conversa ("espera a Fernanda até 30 min"), não a equipe inteira | F8 | **Fechada** (lote 4, #2682): `conversa.responsavel_respondeu` | Motor | 10, 15 |
| G41 | **Instrução no resumir** ("o que já foi prometido") e **avisar o responsável quando a agente de IA atende** a conversa | F7 | **Fechada** (#2759): `instrucao` opcional no resumir, junto do texto fixo; no aviso, com a agente de IA atendendo, "Responsável" é o dono do card da conversa, e sem card ou sem dono o passo pula com `sem_responsavel` | F7 | 10 |
| G44 | **Link da agenda de uma página escolhida** ("o link da agenda do professor", "o link das turmas de outros horários", implantação e treinamento) | novo | **Fechada** (#2756): o link da agenda de uma página escolhida na receita, não só o do responsável | Motor | 4, 20 |
| G45 | A automação que começa pela **conversa lê o card dela** no "Só se" (só para ler) e o filtro sabe se **a mensagem tem anexo** | F6 | **Fechada** (#2716, PR1) | Gatilhos | 14, 18 |
| G50 | **Reentrada: o gatilho que se repete no mesmo alvo com a execução ainda aberta** ("a segunda falta no mês") | novo | Em construção (#2682, item 2): `gatilho.se_repetir: comeca_outra` abre outra execução (paralela) no mesmo alvo com a primeira ainda esperando, nos gatilhos de evento (menos `mensagem.criada`); `card.entrou_de_novo` na condição do "esperar até" do gatilho de etapa, e a nova entrada acorda a espera. Exemplo 4: os 30 dias do passo 1 também são esse "esperar até", e a etiqueta-contador só sai se o aluno não faltou de novo (a de uma falta mais nova fica). Migration de índice (`paralela`): o índice novo é conferido válido antes de o velho sair, e a volta para com paralela aberta. Ponta a ponta: `g50_reentrada_spec.rb` | Motor | 4 |
| G52 | **Pôr o contato numa campanha de e-mail** (o termo do ex. 20, passo 9; a G14 cobre só WhatsApp, e etiqueta + G7 + G2 é adaptar) | novo | **Fechada** (#2787, #2760): lista de e-mail com nome (por baixo, uma etiqueta) e passo `lista_de_email`; a campanha de e-mail com a lista vai para quem está nela na hora do envio, e quem recusou ou se descadastrou fica de fora. Prova em `exemplo_20_venda_fechada_spec.rb`, passo 9 | F5 | 6, 20 |
| G42 | **O resumo lê tudo o que a execução tentou** (o modelo no WhatsApp, o e-mail em conversa própria, o link da agenda) | F7 | Em PR (#2763): o resumir lê também o que a execução mandou (o envio recusado marcado) e as respostas nas outras conversas dela; a resposta só entra se todos que veem a conversa do alvo também a veem | F7 | 1 |
| G43 | **Mandar ao número novo** do contato depois que a automação o atualiza (ex. 19, passos 4 e 7) | F4 | **Fechada** (#2700): no WhatsApp e no SMS, quando o número da conversa morreu (a última mensagem da empresa nela falhou, e o cliente não escreveu depois) e o telefone do contato é outro, o passo "mensagem" manda na conversa do número novo, na mesma caixa (`NumeroNovo`), e a janela (a oficial e o WhatsApp API da caixa híbrida) é a do número novo; os passos seguintes usam essa conversa, e no card ela vira a principal. No passo 7, o aviso à Fernanda é o "resumir" da G42, que lê o e-mail mandado e o modelo recusado no número novo (`g43_numero_novo_spec.rb`) | Gatilhos | 19 |
| G49 | **O registro que um passo criou vira valor e alvo dos passos seguintes** (ex. 11, passo 3: o João, criado pelo `POST contacts`, ganha o card em "Indicações" com "indicado por Maria"; passo 5: a mensagem ao João no card dele. Ex. 6, passos 5 e 6: gravar no card que a automação do contato criou) | F8 / G18 | Fechada (#2675 → PR da G49): `criado.<passo>` (o id do contato ou do card que o passo criou nesta execução, pelo caderno do Guia), o "criar card" com `contato` e o "em outro registro" com a ligação `criado_no_passo`. Vale só na execução que criou; quem age é sempre quem ligou | Motor | 6, 11 |
| G65 | **O passo em outro registro lê os valores do registro de origem** (ex. 11, passo 7: a filha, na Maria, manda "O João virou cliente!" com o nome do João, que está no card ganho) | F8 / G18 | **Fechada** (#2842, no #2675, integração 2 do #2414): `origem.<caminho>` só nos passos de dentro do "em outro registro", lido na hora no alvo da mãe, com a permissão de quem ligou; o salvar recusa fora do ramo e o caminho que o gatilho da mãe não alcança. Quem ligou precisa ainda alcançar o registro de origem (decisão 17): se perdeu o acesso entre a mãe e a filha, o passo que lê `origem.*` pula com `origem_fora_do_alcance` e nada desse registro sai. Telefone e e-mail da origem são liberados (decisão 17); a IA nunca recebe valor protegido para escrever (decisão 9). O e-mail no ramo também lê `origem.*`, no assunto e no texto | Motor + editor | 11 |
| G55 | **Campanha a partir de um gatilho de card** (ex. 16, passo 2: "para cada card perdido" põe a etiqueta, e a campanha sai uma vez para todos com ela) | F6 / G14 | **Fechada** (#2823, lote 3 do #2414): no `card.recorrente` e no `contato.recorrente` a campanha é uma só por vez (`CampanhaDaOcorrencia`), saindo quando nenhuma execução da vez está mais a caminho do passo; prova em `g55_campanha_no_card_spec.rb` e de ponta a ponta no exemplo 16 (`exemplo_16_reconquista_spec.rb`) | Gatilhos | 16 |
| G53 | **O conteúdo da mensagem que falhou** como valor da receita (ex. 19, passo 2: "manda por e-mail o mesmo conteúdo") | F8 | **Em PR** (#2783): valor `falhou.texto`, só no gatilho `mensagem.falhou`, relido pela marca da execução e preso à conta e à conversa do alvo; sem texto (só anexo, apagada) o passo pula com `faltou_valor`; o ensaio mostra o texto da última mensagem recusada da conversa. Prova em `g53_conteudo_da_falha_spec.rb` | Gatilhos | 19 |
| G54 | **Esperar a entrega** da mensagem (ex. 19, passo 5: "Chegou: tira a etiqueta") | F8 | **Fechada** pela G34 (#2680): "esperar até `envio.situacao` igual a entregue"; a mudança de situação acorda a espera | Gatilhos | 19 |
| G47 | **Card criado pela página de agendamento ganha a conversa do contato** ("revisão cancelada: manda o link da agenda de novo") | novo | **Fechada** (#2766): o card em que a página põe a reunião (o novo, ou o aberto sem conversa) ganha a conversa mais recente do contato na caixa dos avisos da página (o WhatsApp escolhido na tela) ou, sem ela, na caixa da agenda; a conversa de quem chama vale mais. Prova: passo 8 do `exemplo_05_revisao_do_carro_spec.rb`, com a janela fechada e o modelo aprovado | Agendamento | 5 |
| G62 | **Campo do card do tipo pessoa da equipe**: a responsável original gravada no card, o nome e se ela está ausente, para devolver o card a ela | F8 | **Em PR** (#2832, #2829): tipo `pessoa` no campo do card (só card; escolha por ChoiceSelect; o card recusa quem não é da conta), `card.atributos.<campo>.nome` e `.ausente`; fora da extração da IA | Motor | 17 |
| G63 | **Repetir a espera a cada mensagem do cliente** na mesma automação ("a cada mensagem do cliente, espera a Renata por até 2 horas") | F3/F4 | **Em PR** (#2830, branch `feat/g63-g64-enquanto-espera`): campo opcional `a_cada_mensagem` do "esperar até", um galho que roda a cada mensagem nova do cliente (régua do G31, `Resposta.novas_desde`) e volta à mesma espera. Uma espera só (decisão 11): a mensagem que chega enquanto o galho roda não abre outra rodada nem recomeça o prazo. Teto de 200 voltas por execução. Recusado no gatilho da conta, dentro de outro galho e com o `de_novo.desde` (G46) apontando para dentro dele. Prova em `exemplo_17_ferias_spec.rb` | Motor | 17 |
| G64 | **Conferir toda manhã na mesma automação** ("toda manhã, se a responsável original já está disponível de novo, devolve o card") | F3/F6 | **Em PR** (#2839, junto da G63): campo opcional `conferir_as` (0–23, fuso da conta) do "esperar até" sem prazo. A condição só é conferida nessa hora (mensagem e mudança do card não adiantam); a volta do galho da G63 confere na hora. Na tela, nasce às 8h (decisão 12). Horário de verão pela hora local (`Tempo.proxima_hora`) | Motor | 17 |
| G66 | **A conversa acompanha a troca do dono do card** (ex. 17, passo 4: "espera a Renata responder [...] passa a conversa para a agente de IA") | F3/F8 | **Fechada** (#2843, decisão 14): passo `conversa_ao_responsavel` ("Passar a conversa para o responsável do card"), só com gatilho de card, pelo mesmo pedido do Atribuir da conversa, como quem ligou. A troca do dono fora da automação continua sem mexer na conversa. `conversa.responsavel_respondeu` passa a esperar a Renata. Decisão 18, corrigida (sem vai e vem): o "Passar para a agente de IA" ganha a opção `cobrir_pessoa`, "Cobrir a pessoa enquanto ela não responde" (desligada por padrão; a G15 e a D1 valem sem ela). Ligada, a agente assume a conversa da Renata, com `tirada_de` no histórico, e fica com ela; enquanto cobre, a mensagem do cliente não abre o galho "a cada mensagem" (`ia_cobrindo`). Quando a Renata escreve na conversa, a conversa volta sozinha para ela (escuta da automação e `Cobertura`, registro `pessoa_voltou`), sem passo nem condição na receita. A cobertura é o registro `cobrindo_pessoa`, gravado na transação da troca; se a execução fecha, a automação é desligada ou o Motor sai, a conversa volta para a pessoa (`cobertura_encerrada`), e a IA nunca fica presa. A IA só segura o galho enquanto pode atender (Fase 2, agente atendendo, vínculo na caixa). Na devolução do card, o passo G66 leva a conversa à Júlia | Motor | 17 |
| G67 | **O resumo da volta lê as férias inteiras** (ex. 17, passo 6: "a IA resume para a Júlia o que aconteceu durante as férias") | F7 | **Fechada** (#2844): na execução, o `resumir` lê as mensagens desde o começo dela (`Decisores::Estado`, `periodo`), nunca menos que as 5 de sempre, até `PassoDeResumir::MAX_MENSAGENS_DO_PERIODO` (40), as mais recentes; as além das 5 vão cortadas em `MAX_CARACTERES_ANTERIORES` (600). Passou do teto, a IA recebe `omitted_older_messages` e diz que o resumo começa depois delas. O "Testar este passo" lê a janela de sempre | Motor | 17 |
| G68 | **O extrair lê a resposta que chegou por e-mail** (ex. 19, passo 3: "a IA extrai o número novo da resposta") | F7 | **Fechada** (#2864, integração 2 do #2414): o `extrair` lê também as conversas da própria execução, como o `resumir` (G42, `EnviosDaExecucao`): a resposta na conversa do e-mail vai à IA em `other_conversations`, com data e hora no fuso da conta. As mesmas regras: só a conversa que quem ligou vê e que todos que veem a do alvo também veem (a que fica de fora vai em `conversas_fora` no histórico); das outras, só mensagens, nunca nota privada; nunca valor protegido (decisão 9). Prova: `exemplo_19_cliente_sumiu_spec.rb`, passos 3 e 4. Achada na integração do lote 1 (#2859). |
| G69 | **Retorno em meses** (ex. 16, passo 6: "grava um retorno para daqui a 11 meses") | F6 | **Fechada** (Issue #2879, lote 3 do #2414, decisão do Rodrigo de 10/11: "a plataforma fala o termo"): o `daqui` do retorno aceita `meses` (definição `daqui_do_retorno`, até 120), além de minutos, horas e dias. Meses contam no calendário, no fuso da conta (`Duracao.vencimento`): 11 meses a partir de 15/01 vencem em 15/12; o dia que o mês não tem vira o último dia dele. O editor oferece meses só no retorno (`unidades_do_retorno` do catálogo). Prova: `passo_de_retorno_spec.rb` ("daqui em meses") e `exemplo_16_reconquista_spec.rb`, passo 6; sonda por comportamento `SondasDoRetorno` | F6 | 16 |
| G70 | **A IA anota campos do card** (ex. 2, passo 9, e ex. 7, passo 4: "grava no card"), sem a cópia pela conversa | F7 | **Fechada** (Issue #2880, lote 3 do #2414, decisão 20 do Rodrigo, 10/11, "IA só anota campos"): o `extrair` aceita destino `card.atributos.<chave>` no gatilho de card e no de conversa (também no ramo do "em outro registro" que roda num card ou numa conversa). Grava no card que a execução criou antes (passo "criar card"); senão, no card alvo; senão, no card da conversa que quem ligou vê (o assunto atual, como o card que a IA de assunto abriu). O tipo do campo é conferido de novo ao rodar: o que virou pessoa ou contato fica ausente. Grava pelo `PATCH crm/cards/:id`, como quem ligou, com a chave de funis de quem salva e de quem ligou; nunca `card.valor` (decisão 9) nem campo do tipo pessoa. É a única exceção à decisão 19: fechar, mover, trocar o dono, webhook e `card.id` em caminho ou corpo seguem recusados no card da conversa. Sem card que quem ligou veja, o campo fica ausente. Prova: `extrair_no_card_spec.rb`, `exemplo_02_lead_do_anuncio_spec.rb` (passo 9) e `exemplo_07_black_friday_spec.rb` (passo 4, o card nasce da IA de assunto, dublê, depois da resposta); sonda por comportamento `SondasDoExtrairNoCard` | F7 | 2, 7 |
| G46 | **O laço dos documentos** (ex. 14, passos 2 a 6: "a cada foto ou PDF que chega [...] 2 dias sem documento novo: lembra uma vez [...] 4 dias: cria retorno"), numa automação só | F3/F7 | **Em PR** (#2791): valor `conversa.cliente_mandou_documento` no "esperar até" (foto ou PDF, `FotoOuPdf.escopo`, só na conversa da execução) e `de_novo.desde` no "decidir": o caminho marcado roda os passos dele e volta ao "esperar até" de antes. O prazo de 2 dias recomeça a cada documento; texto e áudio não recomeçam; um lembrete por pausa (decisão do Rodrigo, 09/11). Depois do retorno, a execução acaba. Leitura `anexos_novos`: o extrair lê só os anexos que ainda não leu, entre dois marcos (a régua do G31: id lido e margem de commit atrasado), sem o teto das 5 últimas mensagens, então nenhum anexo vai duas vezes à IA e nada se perde com 6 ou mais documentos; cada documento tem o seu campo no card, e o "decidir" lê o card. Prova em `exemplo_14_documentacao_spec.rb` | Motor | 14 |
| G48 | **Campo do card preenchido acorda o "esperar até"** (ex. 12, passo 3: "espera até a Ana responder ou o campo ser preenchido") | F8 | **Fechada** pelo gancho único do card do lote 4 (#2682, `Crm::CardAvisaAutomacao`): a gravação que muda uma coluna lida (`custom_attributes` entre elas) acorda a espera que lê `card.*`, sem esperar o prazo. A G9 e a G27 estendem esse gancho, sem outro callback. Prova: `g48_campo_do_card_spec.rb` | Motor | 12 |
| G56 | Gatilho **reunião atendida** ("Atendida: no dia seguinte pede uma foto do resultado") | F6 | Em PR (depende do #2687): `card.reuniao_atendida`, o primeiro "Aconteceu" da reunião na Agenda (`first_held` na atividade `meeting_outcome_recorded`); "Não compareceu", salvar as anotações de novo e voltar para "Aconteceu" não abrem outra execução. O "no dia seguinte" é o passo esperar 1 dia. Prova: `g56_reuniao_atendida_spec.rb` | Gatilhos | 6 |
| G59 | **Esperar a reunião acontecer** no meio da automação (ex. 6, passo 8, na automação do aniversário) | F8 | Em PR (#2816, com a G56): `contato.reuniao_atendida` na condição do "esperar até", o primeiro "Aconteceu" de uma reunião em qualquer card do contato que quem ligou vê, durante a espera; o resultado da reunião acorda a espera (`EsperaDaReuniao`). Prova: `g59_reuniao_atendida_na_espera_spec.rb` | Gatilhos | 6 |
| G60 | **Link da agenda** numa automação que roda no contato (ex. 6, passo 2) | F8 | Em PR (#2816): já lia pela ponte da conversa nova (#2680): `conversa.link_da_agenda` é a página de quem atende a conversa do contato na caixa escolhida. Sem ninguém atendendo (ou sem conversa na caixa), vale a página de agenda de reserva escolhida no gatilho (`gatilho.agenda_de_reserva.pagina_id`, decisão 10 do Rodrigo: página da conta, que quem salva vê). Sem reserva, o passo pula com `faltou_link_da_agenda` (`sem_responsavel`); reserva desligada ou apagada depois, com `agenda_de_reserva_indisponivel`. Nunca o link de outra pessoa. Prova: `g59_reuniao_atendida_na_espera_spec.rb` e `g60_agenda_de_reserva_spec.rb` | Gatilhos | 6 |
| G61 | **Avisar quem atende a reunião** fora dos gatilhos de reunião (ex. 6, passo 6: "Marcou: avisa a profissional") | F8 | Em PR (#2816): `para.da_reuniao` vale em qualquer gatilho; fora dos de reunião é quem atende a próxima reunião marcada do contato, em card que quem ligou vê. Prova: `g59_reuniao_atendida_na_espera_spec.rb` | Gatilhos | 6 |
| G58 | **Campanha só para quem a execução criou** (ex. 9, passo 4: "monta a campanha e manda" logo depois de criar um card por empresa; a etiqueta do mês reenviaria toda semana) | novo | **Fechada** (#2784, Issue #2779): `publico: desta_execucao` no passo campanha; os contatos que os passos anteriores criaram (`card_ids`/`contato_ids` no registro) viram um Público (source `automacao`) e a Campanha sai pela da tela. Ao salvar, pede antes um passo que crie card ou contato; a tela só oferece a escolha quando o catálogo tem um que roda num gatilho da conta (o `prospeccao` da G21). Contrato com a G21 na integração do #2414: a busca grava `card_ids` dos cards criados nesta rodada (nunca o que já existia; `BuscaDaProspeccao#dos_envios`). Prova: `g58_publico_da_execucao_spec.rb` (salvar e envio) e, pelo caminho real (busca da G21 grava o registro, a campanha lê), o passo 4 e o passo 8 do `exemplo_09_prospeccao_semanal_spec.rb` | F5 | 9 |
| G57 | **Retorno para hoje** (ou amanhã), numa hora ou no fim do dia, no fuso da conta (ex. 1, passo 7: "recotar para hoje") | F7 | Em PR (#2769): `quando: { dia: 'hoje' \| 'amanha', hora? }` no retorno, além do `daqui`; hora de hoje que já passou vale em seguida | F7 | 1 |

### 5.1 A sonda de cada lacuna

Cada lacuna tem uma sonda em `spec/support/fechamento_automacao.rb` (`FechamentoAutomacao::Lacunas::SONDAS`): uma
pergunta ao código da main, como "o esquema da receita tem um passo `retorno`?" ou "algum gatilho roda no card?". O
exemplo pendente é `pending` com corpo real: confere que as lacunas dele fecharam. Quando todas fecham, o pendente passa,
o RSpec acusa ("Expected pending … to fail", com a instrução do que fazer), e o exemplo ganha o spec de ponta a ponta
e sai da lista. A sonda roda antes do `pending`: sonda quebrada (classe renomeada) é erro vermelho, nunca pendente.

A frente que fecha uma lacuna ajusta a sonda no mesmo PR se o nome que deu for outro (ex.: o passo se chama
`criar_retorno`, não `retorno`). Sonda vazia (`nil`, como a G22, desligada até um passo gravar o solicitante) é
lacuna ainda sem prova: a frente troca a sonda pela prova.

## 6. Os 20 exemplos: o que existe e o que falta

Legenda: ✅ na main · 🟡 em PR · ⛔ lacuna (código). "Começa" é o gatilho.

| # | Exemplo | Começa | Passos que já rodam na main | Faltam | Roda hoje |
|---|---|---|---|---|---|
| 1 | Renovação do seguro | ✅ G6 (30 dias antes do vencimento) | mover card ✅, etiqueta ✅, modelo fora da janela ✅ (G1), recusado vai por e-mail ✅ (G34, G2), esperar a resposta ✅ (G11), extrair → copiar ao card ✅, decidir ✅, retorno ✅ (G3), avisar ✅, link da agenda e reunião marcada/cancelada ✅ (G12), resumo de tudo o que a execução tentou ✅ (G42), retorno "para hoje" no fuso da conta ✅ (G57) | — | **Sim** (`exemplo_01_renovacao_do_seguro_spec.rb`) |
| 2 | Lead do anúncio | ✅ G5 (card criado), ⛔ G29 ("pelo formulário de um anúncio") | etiqueta ✅, mensagem pelo modelo ✅ (G1), mensagem ao lead sem conversa ✅ (G33), esperar a resposta ✅ (G11), retorno ✅ (G3), passar para a agente de IA ✅ (G15), decidir a cada resposta 🟡 (G31), link da agenda ✅ (G12), mover ✅, resumir/avisar ✅, extrair ✅, etiqueta da campanha ✅ (G14) | G29, G30, G32 | Não |
| 3 | Pós-procedimento da clínica | ✅ G5 (entrou em "Atendida") | extrair ✅, escrever ✅, decidir ✅ (lendo a foto, G20), etiqueta ✅, prioridade ✅, avisar ✅, retorno ✅, e-mail no lugar da campanha "Manutenção" ✅, mover ✅ | — | **Sim** (`exemplo_03_pos_procedimento_spec.rb`) |
| 4 | Aluno que começa a faltar | 🟡 G5 (entrou em "Faltou") | se com etiqueta do contato ✅, etiqueta pôr/tirar ✅, escrever ✅, decidir ✅, avisar ✅, esperar 30 dias ✅, a segunda falta com a primeira esperando ✅ (G50), link de página escolhida ✅ (G44, passos 6 e 8), fechar o card de retenção criado ✅ (G49, passo 10) | — (G1, G3, G4, G5, G12, G15, G25, G28, G44, G49: fechadas; G50 no #2853) | **Sim** (`exemplo_04_aluno_que_falta_spec.rb`, à risca, passos 1 a 10; sai do pendentes com a G50, #2682) |
| 5 | Revisão do carro | 🟡 G5 (card ganho) | extrair ✅ (contato), etiqueta ✅, mover ✅ | G1, G3, G5, G6, G12, G16, G19, G28 (lembrete da IA pelo modelo), G32 ("não marcou em 5 dias", passos 6 e 7), G36 (nota do mecânico: `g35_g36_ia_le_card_e_nota_spec.rb`), G47 (passo 8). Spec à risca: `exemplo_05_revisao_do_carro_spec.rb`, passos 1 a 7 passam na main; o 8, com a G47 (#2766) | Não |
| 6 | Aniversário | ✅ G6 (data de nascimento do contato) | escrever ✅, modelo com o link da agenda ✅ (G60, página de reserva), etiqueta ✅, criar card ✅, decidir ✅, estender o presente e gravar no card criado ✅ (G49), avisar quem atende a reunião ✅ (G61), lembrete sem reunião marcada ✅ (G32), foto depois da atendida ✅ (G56, G59), extrair ✅, fechar o card e campanha "Saudade" ✅ (G25, G14) | — | **Sim** (`exemplo_06_aniversario_spec.rb`, à risca, passos 1 a 10; saiu do pendentes na integração 2 do #2414; também `g59_reuniao_atendida_na_espera_spec.rb`, numa automação só) |
| 7 | Black Friday | 🟡 G7 (toda quinta 9h, #2635); 🟡 G39 em PR (#2753, só a quinta antes da Black) | decidir ✅, extrair ✅ (card), etiqueta ✅, mensagem ✅ (na janela), disparar campanha ✅ (G14) | G5, G7, G14, G15, G37, G38, G39 | Não |
| 8 | Funcionário novo no plano | ✅ mensagem do RH (1ª); ✅ G24 (2ª, em cada card, #2771); ✅ toda sexta (3ª, G22) | decidir ✅, para cada item ✅ (G24: nome, data de nascimento e telefone, da mensagem ou da foto; contatos pela linha do Importar contatos, na empresa do RH, registrados como importação em Contatos > Importações com o rótulo "Automação"; card por funcionário, com o RH de solicitante), mensagem ao RH com a contagem ✅, modelo aprovado a cada funcionário pela conversa nova ✅, laço dos documentos ✅ (G46: extrair dos anexos novos, marcar no card, decidir com volta à espera), pedido só do que falta em 3 dias ✅ (escrever dentro do modelo aprovado), completo → "Enviar à operadora" e operadora ✅ (G13, `webhook`), aviso de sexta ao RH ✅ (G22) | — | **Sim** (`exemplo_08_funcionario_novo_spec.rb`, à risca, passos 1 a 9; saiu do pendentes na integração 2 do #2414) |
| 9 | Prospecção semanal | ✅ G7 (`conta.recorrente`, segunda 8h) | buscar e conferir WhatsApp ✅ (G21), card com etiqueta no contato ✅ (G21), campanha pelo modelo ✅ (G14) só às empresas desta execução ✅ (G58), decidir ✅, link da agenda ✅ (G12), etiqueta ✅, retorno ✅ (G3), recusa na Prospecção ✅ (G21), mover ✅, resumir/avisar ✅, reunião cancelada ✅ (G12) | — (G58 no passo 4: fechada) | **Sim** (`exemplo_09_prospeccao_semanal_spec.rb`, à risca; saiu do pendentes com a G58, #2784, na integração do #2414) |
| 10 | **Cliente bravo** | ✅ mensagem do cliente | decidir ✅, atribuir ✅, prioridade ✅, etiqueta ✅, resumir+avisar ✅, mensagem ✅, o mesmo resumo à dona sem outra ida à IA ✅ (G28) | — (G40 no passo 6, G41 nos passos 4 e 7: fechadas) | **Sim** (`exemplo_10_cliente_bravo_spec.rb`, à risca; saiu do pendentes com o lote 4, #2682) |
| 11 | Indicação que vira presente | ✅ mensagem do cliente | decidir ✅, extrair ✅, criar o contato do amigo ✅ (G17), o card dele com quem indicou ✅ (G4, G49), mensagem a Maria ✅, a mensagem à Maria com o nome do João lido no card ganho ✅ (G65, `origem.contato.nome`), o "indicado por" num campo do card do tipo Contato ✅ (decisão 16), mensagem ao João pelo modelo com o link da agenda ✅ (G49, G18, G1, G12, G33), reunião marcada move o card ✅ (G12), o card do João ganho ou perdido age na Maria ✅ (G5, G18) | — | **Sim** (`exemplo_11_indicacao_spec.rb`) |
| 12 | Visita que aconteceu | 🟡 G5 (entrou em "Visita feita") | mensagem ✅ (na janela), decidir ✅, extrair ✅, mover ✅, etiqueta ✅, avisar ✅ | — | **Sim** (`exemplo_12_visita_feita_spec.rb`, à risca; saiu do pendentes com a G25, #2654, sobre a G48 na integração 2 do #2414) |
| 13 | Festa do contrato ao depoimento | ✅ G5 (card ganho) + ✅ G6 (datas da festa) | e-mail ✅ (G2), modelo fora da janela ✅ (G1), data calculada ✅ (G16), extrair → copiar ao card (2 passos) ✅, resumir/avisar lendo o card ✅ (G35), decidir ✅, etiqueta ✅ | — | **Sim** (`exemplo_13_festa_do_contrato_spec.rb`) |
| 14 | Documentação para emitir | ✅ G5 (entrou em "Documentação") | mensagem pelo modelo ✅ (G1), extrair lendo só a foto ou o PDF ainda não lido ✅ (G46, `anexos_novos`) → copiar ao card, um campo por documento ✅, decidir com volta ao "esperar até" ✅ (G46), escrever ✅, lembrete pelo modelo ✅, retorno ✅ (G3), etiqueta ✅, mover ✅, mandar à seguradora e gravar a proposta ✅ (G13, `webhook`), avisar a Dona Cida com o motivo da recusa ✅ (G13, `se_recusar`) | — | **Sim** (`exemplo_14_documentacao_spec.rb`, à risca, passos 1 a 8; saiu do pendentes com a G13 na integração 2 do #2414) |
| 15 | **Cliente grande** | ✅ G27 (card criado ou valor mudou e está acima de R$ 50 mil, `maior_que`, #2661) | se com etiqueta → parar ✅, atribuir (tira da agente de IA) ✅, etiqueta no contato ✅, prioridade ✅, resumir+avisar ✅, mensagem ✅, link da agenda de quem atende ✅ (G12), esperar o Carlos ✅ (G40), o mesmo resumo de novo sem outra ida à IA ✅ (G28), esperar o card fechar ✅ (sem prazo, só pela condição, #2750; o card que muda acorda, #2687), retorno ✅ (G3), a IA lê o card e resume o motivo da perda ✅ (G35) | — | **Sim** (`exemplo_15_cliente_grande_spec.rb`, à risca; saiu do pendentes com o G27 sobre o lote 4) |
| 16 | Reconquistar | ✅ G7 (`card.recorrente` mensal, `fechado_entre_dias`; o motivo no "Só se" com `card.motivo_da_perda`) | etiqueta ✅, decidir ✅, escrever ✅, a IA escreve a resposta lendo o card antigo, com o motivo da perda ✅ (G18: passo "escrever" com `le: card` no ramo) | G55 (passo 2: a campanha num gatilho de card), G38 (passo 3: cada resposta à campanha), G3, G4, G7, G12, G14, G16, G18 | Não |
| 17 | Vendedora de férias | 🟡 G9 (troca de responsável com a anterior ausente, #2707) | resumir ✅, mensagem ✅, gravar no card a responsável original ✅ (G62), etiqueta ✅, passar a conversa à nova responsável 🟡 (G66, decisão 14), a cada mensagem do cliente espera a Renata e, sem resposta, a agente de IA assume cobrindo a Renata até ela escrever 🟡 (G63, G66, decisão 18), conferir toda manhã às 8h 🟡 (G64), devolver o card com a conversa e tirar a etiqueta 🟡 (G62, G66, decisão 18), resumir para a Júlia as férias inteiras 🟡 (G67) | — | À risca, numa automação só (`exemplo_17_ferias_spec.rb`); o passo G66 aparece duas vezes na receita (depois da troca e depois da devolução; decisão 14). Sem vai e vem (decisão 18, corrigida): com a IA cobrindo, a 2ª mensagem do cliente não devolve a conversa; a Renata escreve e volta a ser dona |
| 18 | Seleção de candidatos | ✅ mensagem com anexo na caixa de vagas (G45, `mensagem.tem_anexo`) | extrair do currículo ✅ (G20), criar card ✅ (G4), decidir ✅, link da página "Entrevistas" ✅ (G44), etiqueta ✅, resumo à doutora ✅, agradecer e fechar o card criado ✅ (G49, `criado.card_da_selecao`), agente de IA da vaga ✅ (G15), lembrete antes da entrevista ✅ (G32), fechar no "Não compareceu" ✅ (G5, G25) | — | **Sim** (`exemplo_18_selecao_de_candidatos_spec.rb`, à risca, passos 1 a 9; saiu do pendentes na integração 2 do #2414) |
| 19 | Cliente que sumiu do WhatsApp | ✅ G8 (mensagem falhou) | etiqueta ✅, extrair ✅ (telefone; lê a resposta do e-mail, G68), escrever ✅, avisar ✅, o mesmo conteúdo no e-mail ✅ (G53), mandar ao número novo ✅ (G43) | — | **Sim** (`exemplo_19_cliente_sumiu_spec.rb`, à risca, passos 1 a 7; saiu do pendentes com a G68 na integração 2 do #2414) |
| 20 | Venda fechada no sistema da empresa | ✅ G5 (card ganho) | extrair direto no card ✅ (G70), perguntar só o que falta e esperar 2 dias ✅ (G11), cobrança pelo "webhook" com o número de cliente no card ✅ (G13), aviso da recusa ao financeiro ✅, e-mail de boas-vindas com o link da página "Implantação" ✅ (G2, G44), reunião marcada → mover e etiqueta ✅ (G32), 30 dias depois pelo modelo ✅ (G1), decidir ✅, link do "Treinamento" ✅ (G44), resumo ao Ricardo ✅, lista "Dicas do mês" ✅ (G52) | — | **Sim** (`exemplo_20_venda_fechada_spec.rb`, à risca, passos 1 a 9; saiu do pendentes com a G52, #2787) |

### 6.1 As lacunas que destravam mais exemplos

| Lacuna | Exemplos que dependem | Contagem |
|---|---|---|
| G1 modelo aprovado | 1, 2, 3, 4, 5, 6, 8, 11, 13, 14, 18, 19, 20 | 13 |
| G12 reunião e link da agenda | 1, 2, 3, 4, 5, 6, 9, 11, 15, 16, 18, 20 | 12 |
| G5 gatilhos do card (fechada, #2554) | 2, 3, 4, 5, 7, 8, 11, 12, 13, 14, 15, 18, 20 | 13 |
| G3 criar retorno | 1, 2, 3, 4, 5, 9, 12, 14, 15, 16, 19 | 11 |
| G4 criar card | 4, 6, 8, 9, 10, 11, 16, 18 | 8 |
| G11 esperar resposta | 1, 2, 10, 12, 15, 17, 19, 20 | 8 |
| G14 campanhas | 2, 6, 7, 9, 12, 16 | 6 |

Sugestão de ordem para as frentes (maior desbloqueio por esforço): G5 e G6 (já em PR) → G1 (F4b, #2468) → G3 →
G11 → G4 → G12 → G14. G16, G17, G18 e G20 destravam os exemplos mais longos (5, 8, 11, 18) e podem esperar.

### 6.2 Notas do exemplo 10

- **Qualquer canal: provado (#2701).** O termo diz "toda mensagem do cliente, em qualquer canal". O spec do exemplo prova
  cada passo pelo WhatsApp oficial, e `exemplo_10_outros_canais_spec.rb` roda a mesma receita (passos 1 a 5) com o
  cliente escrevendo pelo webhook real do Híbrido e do Instagram. A resposta sai pelo canal dele. No Híbrido, com a
  janela aberta, ela sai pela Cloud e nada passa pela WAHA.
- **Nota do "decidir" em toda mensagem normal: decidido.** O "decidir" deixa uma nota privada com o caminho e o porquê
  (F7.4), mas não no "nenhum se aplica" (#2578, PR #2589). Com o gatilho em toda mensagem do cliente, a mensagem normal
  não ganha nota. O spec confere isso.

### 6.3 Notas do exemplo 6

- **"Fim do mês" na data calculada (#2705).** `exemplo_06_fim_do_mes_spec.rb` prova só a parte da data dos passos 5 e
  10. O exemplo inteiro segue pendente pelas outras lacunas (`pendentes_spec.rb`).
- **Fonte.** O texto completo do termo não está no repositório. O spec segue o resumo da auditoria dos termos de 07/11
  (#2678, exemplo 6, passos 5 e 10). No passo 5, "não pode agora"
  grava no card o presente até o fim do mês que vem (`$data` hoje + 1 mês, `fim_do: "mes"`). No passo 10, o gatilho
  de data do card (`card.data`) dispara nesse dia, e não no anterior.
- **O que fica para depois.** No passo 10, o spec põe a etiqueta "saudade" no lugar de fechar o card e pôr na campanha
  "Saudade", e não confere o "sem marcar". Fechar o card entra com a G25, a campanha com a G14, e o "sem marcar"
  (reunião marcada como condição) com a G32. Quando entrarem, o passo 10 troca a etiqueta por elas.

### 6.4 Notas do exemplo 9

`exemplo_09_prospeccao_semanal_spec.rb` segue o termo passo a passo, em quatro automações montadas pela API como o
André montaria: a da segunda às 8h (`conta.recorrente`: `prospeccao` faz `buscar`, depois `campanha` faz `disparar`), a
da resposta (decidir com três caminhos), a da reunião marcada e a da reunião cancelada. A borda é dublê na camada HTTP:
Google Places, a WAHA da conferência de WhatsApp, a Graph e a OpenAI.

- **Busca salva.** A Prospecção guarda as buscas no histórico, sem nome: o passo repete a busca do histórico. O
  "abertas este mês" vai como texto ao Google; não há filtro de data de abertura.
- **Etiquetas sem espaço** (regra da etiqueta): `prospecção-novembro`, `tem-contador`, `frio`.
- **"Card com a etiqueta".** A etiqueta vai no contato de cada card criado (decisão da G21), que é o público da campanha.
- **6 meses = 180 dias.** Escrito antes da G69 (#2879), quando o retorno contava só em minutos, horas ou dias. O
  retorno já conta em meses; o ex. 9 segue com os 180 dias, sem mudança nesta passada.
- **"Cancelou duas vezes".** Nenhum valor da receita conta reuniões canceladas: no primeiro cancelamento entra a
  etiqueta `cancelou-uma-vez`; com ela, o segundo põe `frio`. O link vai nos dois; fora da janela, pelo modelo aprovado.
- **Link da agenda.** É o do responsável da conversa: no interesse, a automação primeiro passa a conversa para o André.
- **Resumo da reunião.** O `resumir` lê o card e as mensagens recentes (`le: card, mensagens_recentes`).
- **A espera da conferência** de WhatsApp não grava linha no histórico (`registrar: false` no executor): o spec confere a
  execução esperando, sem card, e acordando 2 minutos depois.
- **O mundo usa o "Outro canal" do CRM** (`crm_outro_canal`): ele liga a conversa da resposta ao card da prospecção.
  Sem ele, a deduplicação da caixa só reaproveita card da mesma caixa (`AutoCreateDeduplicator`), o card da prospecção
  nasce sem caixa, e a resposta abre um segundo card para a mesma empresa.
- **Passo 4 à risca (G58, #2784, fechada na integração do #2414).** A campanha de cada segunda usa o público desta
  execução (`publico: desta_execucao`), não a etiqueta: vai só às empresas cujo card a busca criou nesta segunda. O
  caminho é o real: a busca da G21 grava `card_ids` no registro (só os criados agora) e a campanha da G58 lê esse
  registro (`ContatosDaExecucao`). O spec confere o público (passo 4) e, na 2ª segunda, que a nova recebe, a que recusou
  nunca e as da semana anterior não recebem de novo (passo 8).

## 7. Os 5 itens "a conferir" (Parte A do #2570)

Provados contra o texto do aceite, na main `4bd7168c0f`.

| Item | Veredito | Evidência | Falta |
|---|---|---|---|
| F3.7 quem ligou perdeu a caixa: pausa e "Assumir e religar" | **Não passa** (o motor passa, a tela não) | Motor: `spec/services/autonomia/automacao/executor_spec.rb:335`. API: `spec/fechamento/automacao/aceite_a_conferir_spec.rb` (F3.7): pausa, histórico com "Assuma e religue", ligar de novo troca quem ligou. Tela: `LivreLigar.vue` mostra só "Ligar" e "Está desligada" | #2572 |
| F3.10 etiqueta e atributo criados levam descrição | **Passa** | `aceite_a_conferir_spec.rb` (F3.10): sem descrição, 422 com a frase; com descrição, a etiqueta e o atributo nascem com ela. Regra em `lib/operator_guide/automacao-recursos.yml` (`exige`) | — |
| F4.4 fora da janela: caminho validado ou para com motivo | **Passa** (com a correção da #2573) | Com modelo aprovado, sai o modelo (`passo_de_mensagem_spec.rb`, #2468). Sem ele, a execução para com o motivo (decisão do Rodrigo, 05/11): `aceite_a_conferir_spec.rb` (F4.4) prova a mensagem e o "escrever" parando, e o pular por outro motivo seguindo; `passo_de_mensagem_spec.rb` prova `falhou / fora_da_janela` e `falhou / limite_da_caixa` com a execução `parada` | #2573 |
| F5.4 ligar com mensagem ou IA pede confirmação e custo | **Não passa** | Ligar chama a API direto: `useEditorLivre.js:155` e `LivreListaPage.vue:137`; não há confirmação nem custo | #2574 |
| F6.7 card movido pela automação não é desfeito pela IA do funil | **Passa** | Ponta a ponta em `aceite_a_conferir_spec.rb` (F6.7): o motor move o card, e a avaliação seguinte com "Mover automaticamente" ligado sai `automacao_mexeu_na_etapa` e o card fica. Metades: `movimento_da_automacao_livre_spec.rb`, `evaluator_movimento_da_automacao_spec.rb` | — |

## 8. Fora deste esqueleto

- A IA real (F9.8) e o eval do F7.1: dependem do OK do Rodrigo e de orçamento.
- O canal Instagram e o Híbrido no receptor: entram com o primeiro exemplo que mandar por eles.
- F9.1 a F9.5 (migração do antigo): outro trabalho, mesma fase.
