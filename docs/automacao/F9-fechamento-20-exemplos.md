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

**Placar em 07/11, depois da auditoria dos termos (#2678): 0 de 20 inteiros.** O ex. 10 e o ex. 13 voltaram a pendente pela G28 (lote 2, #2679): no 10, os passos 4, 6 e 7 montam só aproximados; no 13, o resumo da festa (a IA não lê o card) e o extrair que grava no card em 2 passos. Os specs próprios deles seguem rodando os passos que montam, e o 13 agora fecha a festa (card ganho) antes dos passos de data. Base: a auditoria dos termos de 07/11 (Issue #2678). Lacunas fechadas: G1, G2, G3, G4, G5, G6, G11, G14, G16. Exemplo só conta inteiro e com spec verde; parcial não conta.

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
| G9 | Gatilho **troca de responsável** (do card e da conversa), com o anterior marcado como ausente | F8 | A fazer (F8 PR2d); "ausente" não é valor que a receita lê | Gatilhos | 17 |
| G10 | Gatilho **etiqueta posta/tirada** | F8 | A fazer (F8 PR2d) | Gatilhos | — |
| G11 | **Esperar a resposta** de alguém: "até o cliente responder" e "até a equipe responder", com prazo | F3/F4 | **Fechada** (#2592): `conversa.equipe_respondeu` e `conversa.cliente_respondeu` no "esperar até" | Motor | 1, 2, 10, 12, 15, 17, 19, 20 |
| G12 | Gatilho **reunião marcada / remarcada / cancelada** e o **link da agenda** do responsável no texto | F8 | A fazer; o link da agenda não é valor da receita | Gatilhos | 1, 2, 3, 4, 5, 6, 9, 11, 15, 16, 18, 20 |
| G13 | **Webhook de saída** e gravar a resposta no card; recusa vira caminho "deu erro" | F8 | A fazer (F6/F8 PR4) | Gatilhos | 8, 14, 20 |
| G14 | **Campanhas**: pôr e tirar o contato de uma campanha, montar e disparar campanha para quem tem uma etiqueta | novo | **Fechada** (#2630): passo `campanha` com `disparar` (pela Campanha da tela, só em gatilho da conta, `conta.recorrente` da G7) e `nao_receber`; pôr/tirar = etiqueta do público; e-mail dos ex. 3 e 20 pela G2 | F5 | 2, 3, 6, 7, 9, 12, 16, 20 |
| G15 | **Passar a conversa para a agente de IA** e tirar dela | F3 (ação) | **Em PR** (G15): passo próprio "Passar para a agente de IA" (`ia_assumir`), pela Atribuição do CRM; `assignee_type` proibido no atribuir. Tirar = atribuir à pessoa (provado no exemplo 10, passo 2) | F7 | 2, 4, 7, 10, 15, 17, 18 |
| G16 | **Valor calculado no corpo** da ação (gravar "hoje + 6 meses", "indicado por {nome}", motivo da perda no texto) | F3/F4 | **Fechada** (#2593 motor, #2639 editor): `$valor`, `$texto` e `$data` no corpo da ação | Motor | 3, 5, 6, 11, 13, 16, 17 |
| G17 | **Criar contato** (o amigo indicado, o funcionário novo) e **importar em lote** ligado à empresa | novo | `POST contacts` fora da lista; importação não é passo | F2 | 8, 11 |
| G18 | **Agir ou ler em outro registro ligado** ao alvo (o card do João avisa a Maria, que indicou; a resposta lê o motivo da perda no card antigo do mesmo contato). "Para cada card com etiqueta X" é da G7 | F8 / novo | O passo age só no alvo da execução | Motor | 11, 16 |
| G19 | **Nota no contato** (não na conversa) | F3 (ação) | Em PR (#2636): `POST contacts/:contact_id/notes` na lista | F7 | 5, 19 |
| G20 | Passos de IA **lendo anexo** (PDF, foto do currículo, documento) | F7 | Em PR (#2669): `le: anexos` — foto e PDF vão como estão ao modelo do passo, áudio pela transcrição; o que passa do limite do provedor pula com motivo | F7 | 3, 8, 14, 18 |
| G21 | **Prospecção**: rodar busca salva e conferência de WhatsApp como passo | novo | Sem passo | F5 | 9 |
| G22 | **Avisar quem não está na conversa** (o RH da empresa cliente por mensagem; a equipe quando o alvo não tem conversa) | F4 | O "avisar" é nota com menção na conversa do alvo; card sem conversa pula com `sem_conversa` | F1 | 8 |
| G23 | Condição sobre **disponibilidade de uma pessoa** (a responsável voltou de férias) | F8 | Fechada (#2737): "ausente até" na pessoa (Equipe e perfil) e os valores `card.responsavel_ausente` e `conversa.responsavel_ausente`. O "responsável anterior ausente" vem com a G9 (#2707) | Motor | 17 |
| G24 | **Encadear duas automações** em que a primeira cria N registros e a segunda roda em cada um | F6/F8 | Depende de G4, G5 e G17 | Motor | 8 |
| G25 | **Fechar card** como ganho/perdido/resolvido com motivo | F6 (ação) | `PATCH crm/cards` aceita `lost_reason`, mas não muda o status; a conferir qual rota ganha/perde | F2 | 4, 6, 12, 18 |
| G26 | **Aplicar SLA** à conversa | F3 (nativo) | Fora do catálogo do Guia (termo, nota da seção dos exemplos) | F2 | — |
| G27 | Gatilho **card atualizado / campo mudou** (o valor passou de R$ 50 mil no 15; o card ficou completo no 8) | F6 | A fazer: a lista de gatilhos só tem card criado, etapa, ganho, perdido e reunião | Gatilhos | 8, 15 |
| G28 | O **texto da IA vira valor entre passos** (`ia.<passo>`): os cuidados do procedimento saem pelo modelo aprovado fora da janela; o "mesmo resumo" vai à dona sem outra ida à IA | F7 | **Fechada** (#2688, absorveu #2674): o "escrever" e o "resumir" guardam o texto na execução, que some quando ela termina; o "escrever" tem o destino "Só guardar"; a "mensagem" com modelo leva o texto numa variável. A filha do "em outro registro" (G18) é outra execução e lê o `ia.*` da mãe vazio (pula com faltou_valor). | F7 | 3, 4, 5, 10, 19 |
| G29 | **Origem do card do formulário** na receita: o gatilho filtra "card criado pelo formulário de um anúncio" e o passo lê o nome do anúncio (etiqueta com o nome dele) | F6 | A fazer: o formulário grava `source` e `metadata.meta_lead_form` (anúncio, formulário, campanha) no card, mas nenhum caminho de `Valores` lê isso; o filtro só tem o funil (achado no exemplo 2, 07/11) | Gatilhos | 2 |
| G30 | **Responsável por anúncio**: o corretor responsável por aquele anúncio (retorno para ele, link da agenda dele) | F6 | A fazer: o card do formulário ganha o dono pela regra do `Crm::Cards::Creator`, que não olha o anúncio. A Atribuição (`Crm::Entrega`) liga funil e etapa a pessoa (a fixa ou quem cuida do funil), nunca anúncio; nenhum cadastro liga anúncio a pessoa (achado no exemplo 2, 07/11) | F2 | 2 |
| G31 | **Decidir a cada resposta**: voltar a esperar e decidir de novo enquanto a IA diz "ainda conversando" | F3/F7 | A fazer: a receita não tem laço; cada passo roda uma vez por execução (achado no exemplo 2, 07/11) | Motor | 2 |
| G32 | **Esperar a reunião ser marcada** no meio da execução ("visita marcada: move o card e avisa") | F8 | Feito na branch `feat/2703-g32-reuniao` (#2703): valor `card.tem_reuniao_marcada` na condição e no "esperar até" (acorda no evento de reunião do card); filtro `pagina_id` (página de agendamento) nos três gatilhos de reunião; "quem atende a reunião" (`para.da_reuniao`) no avisar. Na mesma branch: `contato.tem_reuniao_marcada` (#2710, a reunião em qualquer card do contato, que acorda quem espera no card ganho; serve à #2704) e o gatilho de tempo `card.antes_da_reuniao` (#2709, lembrete N minutos/horas/dias antes, com `pagina_id`) | Motor | 1, 2, 5, 6, 18, 20 |
| G33 | **Mandar mensagem a quem não tem conversa** (o lead do formulário, o contato do aniversário): a caixa por onde abrir | F4 | **Fechada** (#2680): `gatilho.conversa_nova.caixa_id`; a mensagem abre a conversa, e a espera, a IA e a agente usam ela | Motor | 2, 6 |
| G34 | **Resposta em outra conversa do contato** (a do e-mail) e **a mensagem mandada como valor** (`envio.texto`, `envio.situacao`) | G11 | **Fechada** (#2680): o ramo "se o envio falhou, manda por e-mail o mesmo texto" monta sem a G8 | Motor | 1, 19 |
| G35 | A **IA lê o card** (`le: card`): título, etapa, funil, status, motivo da perda e campos; o valor só com a permissão (#2597) | F7 | Em PR (#2679): só se quem ligou vê o card | F7 | 12, 13, 15 |
| G36 | A **IA lê as notas internas** da conversa (`le: notas`), como a nota do mecânico | F7 | Em PR (#2679) | F7 | 5 |
| G37 | **Público da campanha com exclusão**: "a mesma campanha para todos os outros" e "perguntou na Black e não comprou" | F6 | A fazer: o público do passo campanha só soma etiquetas (`PassoDeCampanha`), sem "menos quem tem a etiqueta X" (achado no exemplo 7, 07/11; G33 e G34 são do lote 3, #2680, G35 e G36 da F7, #2688; fecha com o lote 5, #2686) | Gatilhos | 7 |
| G38 | **Respondeu à campanha X** como filtro do gatilho da mensagem | F6 | A fazer: os valores da receita não têm campanha; `mensagem.criada` pega toda mensagem da conta (achado no exemplo 7, 07/11; fecha com o lote 5, #2686) | Gatilhos | 7 |
| G39 | **Gatilho numa data única** ("a quinta antes da Black Friday, às 9h") | F6 | A fazer: o recorrente (G7) repete toda semana ou todo mês; não há "uma vez, nesta data" (achado no exemplo 7, 07/11; fecha com o PR do exemplo 7 da G14, #2681 parte 4) | Gatilhos | 7 |
| G40 | **Esperar só a pessoa que atende** a conversa ("espera a Fernanda até 30 min"), não a equipe inteira | F8 | Em PR: `conversa.responsavel_respondeu` (lote 4, #2682) | Motor | 10 |
| G41 | **Instrução no resumir** ("o que já foi prometido") e **avisar o responsável quando a agente de IA atende** a conversa | F7 | Em PR (#2752): `instrucao` opcional no resumir, junto do texto fixo; no aviso, com a agente de IA atendendo, "Responsável" é o dono do card da conversa, e sem card ou sem dono o passo pula com `sem_responsavel` | F7 | 10 |
| G44 | **Link da agenda de uma página escolhida** ("o link da agenda do professor", "o link das turmas de outros horários", implantação e treinamento) | novo | A fazer, depois da G32: `card.link_da_agenda` e `conversa.link_da_agenda` são a página do responsável; com duas ou mais, ficam vazios (`varias_paginas`), e uma página escolhida no passo não existe (achado nos exemplos 20 e 4) | Motor | 4, 20 |
| G45 | A automação que começa pela **conversa lê o card dela** no "Só se" (só para ler) e o filtro sabe se **a mensagem tem anexo** | F6 | Em PR (#2716, PR1) | Gatilhos | 14, 18 |
| G48 | **Campo do card mudado acorda o "esperar até"** ("espera até a Ana responder ou o campo ser preenchido") | novo | A fazer: o "esperar até" acorda com a conversa, o contato e a reunião (Escuta#acordar); o campo do card preenchido só é lido quando o prazo vence (achado no exemplo 12, passo 3) | Motor | 12 |
| G50 | **Reentrada: o gatilho que se repete no mesmo alvo com a execução ainda aberta** ("a segunda falta no mês") | novo | Em construção (#2682, item 2): `gatilho.se_repetir: comeca_outra` abre outra execução (paralela) no mesmo alvo com a primeira ainda esperando, nos gatilhos de evento (menos `mensagem.criada`); `card.entrou_de_novo` na condição do "esperar até" do gatilho de etapa, e a nova entrada acorda a espera. Exemplo 4: os 30 dias do passo 1 também são esse "esperar até", e a etiqueta-contador só sai se o aluno não faltou de novo (a de uma falta mais nova fica). Migration de índice (`paralela`): o índice novo é conferido válido antes de o velho sair, e a volta para com paralela aberta. Ponta a ponta: `g50_reentrada_spec.rb` | Motor | 4 |
| G56 | **Reunião atendida gera evento** ("Atendida: no dia seguinte pede a foto") | novo | A fazer: o "Aconteceu" grava `outcome: held` na reunião (`Crm::Meetings::RecordOutcomeService`), mas nenhum evento sai dele e não há gatilho de reunião atendida; usar a etapa "Atendida" adaptaria o termo (achado no exemplo 6, passos 8 e 9) | Gatilhos | 6 |
| G42 | **O resumo lê tudo o que a execução tentou** (o modelo no WhatsApp, o e-mail em conversa própria, o link da agenda) | F7 | Em PR (#2763): o resumir lê também o que a execução mandou (o envio recusado marcado) e as respostas nas outras conversas dela; a resposta só entra se todos que veem a conversa do alvo também a veem | F7 | 1 |
| G43 | **Mandar ao número novo** do contato depois que a automação o atualiza (ex. 19, passos 4 e 7) | F4 | A fazer (#2700): a conversa fica presa ao número com que nasceu; depois do lote 3 (#2689), que traz a porta da frente da conversa nova | Gatilhos | 19 |
| G53 | **O conteúdo da mensagem que falhou** como valor da receita (ex. 19, passo 2: "manda por e-mail o mesmo conteúdo") | F8 | A fazer: a mensagem do gatilho só tem tipo, privada e primeira (`valores.rb`); o `envio.texto` (G34) é o da própria execução, e a mensagem que falhou foi de outra | Gatilhos | 19 |
| G54 | **Esperar a entrega** da mensagem (ex. 19, passo 5: "Chegou: tira a etiqueta") | F8 | **Fechada** pela G34 (#2680): "esperar até `envio.situacao` igual a entregue"; a mudança de situação acorda a espera | Gatilhos | 19 |
| G47 | **Card criado pela página de agendamento ganha a conversa do contato** ("revisão cancelada: manda o link da agenda de novo") | novo | A fazer, PR próprio depois da G32: com o card do serviço já ganho, a página cria um card novo para a reunião, sem conversa, e a mensagem do gatilho de reunião pula com `sem_conversa` (achado no exemplo 5, passo 8). Caminho: o Booker liga ao card novo a conversa do contato na caixa da página | Agendamento | 5 |

### 5.1 A sonda de cada lacuna

Cada lacuna tem uma sonda em `spec/support/fechamento_automacao.rb` (`FechamentoAutomacao::Lacunas::SONDAS`): uma
pergunta ao código da main, como "o esquema da receita tem um passo `retorno`?" ou "algum gatilho roda no card?". O
exemplo pendente é `pending` com corpo real: confere que as lacunas dele fecharam. Quando todas fecham, o pendente passa,
o RSpec acusa ("Expected pending … to fail", com a instrução do que fazer), e o exemplo ganha o spec de ponta a ponta
e sai da lista. A sonda roda antes do `pending`: sonda quebrada (classe renomeada) é erro vermelho, nunca pendente.

A frente que fecha uma lacuna ajusta a sonda no mesmo PR se o nome que deu for outro (ex.: o passo se chama
`criar_retorno`, não `retorno`). Sonda vazia (G16, G18, G22, G24) é lacuna que nenhuma pergunta simples
responde: a frente troca a sonda pela prova.

## 6. Os 20 exemplos: o que existe e o que falta

Legenda: ✅ na main · 🟡 em PR · ⛔ lacuna (código). "Começa" é o gatilho.

| # | Exemplo | Começa | Passos que já rodam na main | Faltam | Roda hoje |
|---|---|---|---|---|---|
| 1 | Renovação do seguro | ✅ G6 (30 dias antes do vencimento) | mover card ✅, etiqueta ✅, modelo fora da janela ✅ (G1), recusado vai por e-mail ✅ (G34, G2), esperar a resposta ✅ (G11), extrair → copiar ao card ✅, decidir ✅, retorno ✅ (G3), avisar ✅, link da agenda e reunião marcada/cancelada ✅ (G12), resumo de tudo o que a execução tentou ✅ (G42) | — | **Sim** (`exemplo_01_renovacao_do_seguro_spec.rb`) |
| 2 | Lead do anúncio | ✅ G5 (card criado), ⛔ G29 ("pelo formulário de um anúncio") | etiqueta ✅, mensagem pelo modelo ✅ (G1), mensagem ao lead sem conversa ✅ (G33), esperar a resposta ✅ (G11), retorno ✅ (G3), passar para a agente de IA ✅ (G15), decidir ✅, link da agenda ✅ (G12), mover ✅, resumir/avisar ✅, extrair ✅, etiqueta da campanha ✅ (G14) | G29, G30, G31, G32 | Não |
| 3 | Pós-procedimento da clínica | ✅ G5 (entrou em "Atendida") | extrair ✅, escrever ✅, decidir ✅ (lendo a foto, G20), etiqueta ✅, prioridade ✅, avisar ✅, retorno ✅, e-mail no lugar da campanha "Manutenção" ✅, mover ✅ | — | **Sim** (`exemplo_03_pos_procedimento_spec.rb`) |
| 4 | Aluno que começa a faltar | 🟡 G5 (entrou em "Faltou") | se com etiqueta do contato ✅, etiqueta pôr/tirar ✅, escrever ✅, decidir ✅, avisar ✅, esperar 30 dias ✅ | G1, G3, G4, G5, G12, G15, G25, G28 (a IA escreve a pergunta e manda pelo modelo), G44 (passos 6 e 8), G18 (passo 10). G50 (passos 2 e 10) em construção. Spec à risca: `exemplo_04_aluno_que_falta_spec.rb` | Não |
| 5 | Revisão do carro | 🟡 G5 (card ganho) | extrair ✅ (contato), etiqueta ✅, mover ✅ | G1, G3, G5, G6, G12, G16, G19, G28 (lembrete da IA pelo modelo), G32 ("não marcou em 5 dias", passos 6 e 7), G36 (nota do mecânico: `g35_g36_ia_le_card_e_nota_spec.rb`), G47 (passo 8). Spec à risca: `exemplo_05_revisao_do_carro_spec.rb`, passos 1 a 7 passam | Não |
| 6 | Aniversário | ⛔ G6 (data de nascimento do contato) | escrever ✅, etiqueta ✅, decidir ✅, extrair ✅, avisar ✅ | G1, G4, G6, G12, G14, G16, G25, G33, G56 (passos 8 e 9), G44 (passo 2), G18 (passo 5), G32 (passos 6, 7 e 10). Spec à risca: `exemplo_06_aniversario_spec.rb` | Não |
| 7 | Black Friday | 🟡 G7 (toda quinta 9h, #2635); ⛔ G39 (só a quinta antes da Black) | decidir ✅, extrair ✅ (card), etiqueta ✅, mensagem ✅ (na janela), disparar campanha ✅ (G14) | G5, G7, G14, G15, G37, G38, G39 | Não |
| 8 | Funcionário novo no plano | ✅ mensagem do RH (1ª); ⛔ G24 (2ª) | decidir ✅, mensagem ao RH ✅ | G1, G4, G5, G7, G13, G17, G20, G22, G24, G27 | Não |
| 9 | Prospecção semanal | ⛔ G7 (segunda 8h) | decidir ✅, etiqueta ✅, mover ✅, resumir ✅ | G3, G4, G7, G12, G14, G21 | Não |
| 10 | **Cliente bravo** | ✅ mensagem do cliente | decidir ✅, atribuir ✅, prioridade ✅, etiqueta ✅, resumir+avisar ✅, mensagem ✅, o mesmo resumo à dona sem outra ida à IA ✅ (G28) | G40 (passo 6: esperar só a Fernanda), G41 (passo 4: a instrução no resumir; passo 7: avisar com a agente de IA atendendo) | Não (#2678: voltou a pendente) |
| 11 | Indicação que vira presente | ✅ mensagem do cliente | decidir ✅, extrair ✅, mensagem a Maria ✅ | G1, G4, G5, G12, G16, G17, G18 | Não |
| 12 | Visita que aconteceu | 🟡 G5 (entrou em "Visita feita") | mensagem ✅ (na janela), decidir ✅, extrair ✅, mover ✅, etiqueta ✅, avisar ✅ | G2, G3, G5, G11, G14, G25, G35 (a IA lê a frase do corretor no card), G48 (passo 3, campo do card). Spec à risca: `exemplo_12_visita_feita_spec.rb` | Não |
| 13 | Festa do contrato ao depoimento | ✅ G5 (card ganho) + ✅ G6 (datas da festa) | e-mail ✅ (G2), modelo fora da janela ✅ (G1), data calculada ✅ (G16), extrair → copiar ao card (2 passos) ✅, resumir/avisar lendo o card ✅ (G35), decidir ✅, etiqueta ✅ | — | **Sim** (`exemplo_13_festa_do_contrato_spec.rb`) |
| 14 | Documentação para emitir | 🟡 G5 (entrou em "Documentação") | extrair ✅, escrever ✅, etiqueta ✅, mover ✅, avisar ✅ | G1, G3, G5, G13, G20 | Não |
| 15 | Cliente grande | 🟡 G5 (card criado) + ⛔ G27 (valor mudou) | se com etiqueta ✅, atribuir ✅, etiqueta ✅, prioridade ✅, resumir ✅, mensagem ✅ | G3, G5, G11, G12, G15, G27, G35 (a IA resume o motivo da perda: `g35_g36_ia_le_card_e_nota_spec.rb`) | Não |
| 16 | Reconquistar | ⛔ G7 (dia 1º, perdidos há 11 meses) | etiqueta ✅, decidir ✅, escrever ✅ | G3, G4, G7, G12, G14, G16, G18 | Não |
| 17 | Vendedora de férias | ⛔ G9 (troca de responsável) | resumir ✅, mensagem ✅, etiqueta ✅ | G7 (toda manhã, por card com a etiqueta), G9, G11, G15, G16, G23 | Não |
| 18 | Seleção de candidatos | ✅ mensagem na caixa de vagas | decidir ✅, etiqueta ✅, avisar ✅ | G1, G4, G5, G6, G12, G15, G20, G25, G18 (passos 4 e 6), G32 (passo 8, passa desde o #2751), G45 (gatilho). Spec à risca: `exemplo_18_selecao_de_candidatos_spec.rb` | Não |
| 19 | Cliente que sumiu do WhatsApp | ⛔ G8 (mensagem falhou) | etiqueta ✅, extrair ✅ (telefone), escrever ✅, avisar ✅ | G1, G2, G3, G8, G11, G19, G28 (o recado da IA pelo modelo), G34, G43 (o número novo), G53 (o mesmo conteúdo no e-mail) | Não |
| 20 | Venda fechada no sistema da empresa | 🟡 G5 (card ganho) | extrair ✅, decidir ✅, mover ✅, etiqueta ✅, avisar ✅ | G1, G2 (boas-vindas e "Dicas do mês" por e-mail), G5, G7 (todo mês, por contato com a etiqueta), G11, G12, G13 | Não |

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
