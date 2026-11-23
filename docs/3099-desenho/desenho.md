# #3099 · F3 do épico #3095 — Duas versões da mensagem (campanha e Automação livre)

Onda 1: desenho + telas reais sem servidor. Nada aqui chama API; os componentes recebem tudo por props.
Absorve o item 7 do #3063 ("Teste A/B de modelo de mensagem").

Na tela não existe "A/B", "variante" nem "teste estatístico". A pessoa lê **"duas versões da mensagem"**,
**"versão 1"** e **"versão 2"**, **"a que tiver mais respostas"** e **"mandar esta para o resto"**.

---

## 1. Mapa do código que a fase toca (lido antes de desenhar)

Nova campanha (assistente):

| Arquivo | O que é | Como a F3 usa |
|---|---|---|
| `app/javascript/dashboard/routes/dashboard/campaigns/journey/NewCampaignPage.vue` | Página da Nova campanha (1.232 linhas). Junta os passos, `reviewBlocks`, `update(patch)` e a ponte de Modelos do WhatsApp | PR de ligação: põe `DuasVersoesMensagem` no slot novo do passo 2 e `ResumoDuasVersoes` no slot `#modelo` da revisão |
| `components-next/CampaignJourney/StepMessage.vue` | Passo 2: canais, nome, formulário de cada canal, prévia | **Mudou nesta onda:** ganhou o slot `duas-versoes` abaixo da mensagem do canal (só aparece com canal da jornada) |
| `components-next/CampaignJourney/SmsJourneyMessage.vue`, `WhatsAppApiMessage.vue`, `EmailJourneyStep.vue`, `TemplateVariableBindings.vue`, `WhatsAppPreview.vue` | A versão 1 de cada canal | Intactos. A versão 2 reusa as mesmas peças (`audienceTokens.js`, `smsSegments.js`) |
| `components-next/CampaignJourney/StepReview.vue` + `MedirVendas.vue` | Passo 3 (revisão), "Quando começa" e "Quem comprou depois" (F2) | **Não mexido** (F5, #3101, mexe no "Quando começa"). O resumo entra pelo slot `#modelo`, que já existe |
| `components-next/CampaignJourney/campaignDraft.js` | Rascunho no navegador (`emptyDraft`) | PR de ligação: campo `duasVersoes` (`duasVersoesVazias()`) |
| `components-next/CampaignJourney/campaignChannels.js`, `audienceTokens.js`, `smsSegments.js`, `localeTag.js`, `textMarks.js` | Canais, campos do contato, contador de SMS, números | Reusados |
| `components-next/choice-select/ChoiceSelect.vue`, `toggle-switch/ToggleSwitch.vue`, `button/Button.vue`, `input/Input.vue` | Peças do painel | Reusadas (sem `<select>` nativo) |
| `dashboard/i18n/locale/*/brandKits.json` (`SUBJECT_VARIANTS`) | A IA do e-mail já sugere 3 assuntos e a pessoa escolhe 1 | As outras sugestões viram "Ideias da IA" para o assunto da versão 2 |

Resultado da campanha:

| Arquivo | O que é | Como a F3 usa |
|---|---|---|
| `routes/dashboard/campaigns/journey/CampaignResultPage.vue` → `components-next/CampaignResult/MessageResultView.vue` e `EmailResultView.vue` | Resultado por canal: cabeçalho, números, faixa do CRM, `ResultVendas` (F2), pessoas | PR de ligação: `ResultDuasVersoes` logo abaixo dos números (`ResultKpiStrip`), quando `result.duas_versoes` vier |
| `components-next/CampaignResult/ResultVendas.vue` + `comparacaoComControle.js` | Régua da F2: "De cada 100…", "o dobro", "quase igual", mínimo para comparar | **Mudou nesta onda:** `pelaDiferenca` passou a ser exportada (uma palavra), para a comparação das versões usar a mesma régua |
| `components-next/CampaignResult/ResultKpiStrip.vue`, `ResultHeader.vue`, `resultMetrics.js` (`wonValueText`) | Cabeçalho, números e dinheiro | Reusados |
| `useCanManage('campaign_send')` em `MessageResultView.vue` | Chave de disparar (#1898) | Quem escolhe a versão à mão precisa dela |

Automação livre:

| Arquivo | O que é | Como a F3 usa |
|---|---|---|
| `routes/dashboard/automacoes/livre/catalogo.js` | Passo `mensagem` nasce `{ id, tipo: 'mensagem', texto: [] }` | Receita ganha `versoes` no passo (ver §5) |
| `routes/dashboard/automacoes/livre/components/LivreAlterar.vue` | Painel "Alterar" do passo: campos nativos (`LivreTexto`, `LivreModelo`…) | PR de ligação: `LivreDuasVersoes` depois dos campos quando `entrada.tipo === 'mensagem'` |
| `.../components/LivreTexto.vue`, `LivreModelo.vue`, `../modeloWhatsapp.js` | Texto com "Pôr um dado"; modelo aprovado para a janela de 24 h fechada | Reusados para a versão 2 |
| `.../components/LivreHistorico.vue` + `ComprasDaAutomacao.vue` | "O que aconteceu" e as compras da automação (F2) | PR de ligação: `ResultDuasVersoes naAutomacao` no histórico, por passo com duas versões |

Servidor (lido para o desenho do backend; nada mudado):
`app/models/campaign_audience_link.rb`, `db/migrate/20261121170000_add_medicao_de_compras_to_campaign_audience_links.rb`,
`app/services/campaign_journey/grupo_de_controle.rb`, `medicao.rb`, `compras_da_campanha.rb`, `message_result.rb`,
`whatsapp_campaign_creator.rb`, `whatsapp_api_campaign_creator.rb`, `sms_campaign_creator.rb`, `email_campaign_creator.rb`,
`config/routes.rb` (namespace `campaign_journey`), `config/schedule.yml` (`StalledCampaignsJob`),
`enterprise/app/models/custom_role.rb` (`campaign_send`, `automation_manage`), tabelas `autonomia_automacao_*`.

---

## 2. Jornada (como a pessoa leiga vive)

### 2.1 Campanha

1. **Passo 2 · Mensagem.** Escolhe o canal e escreve a mensagem como sempre. Embaixo aparece um cartão de uma linha:
   **"Duas versões da mensagem — Testar duas versões"** com o interruptor desligado e a frase
   *"Escreva a mesma mensagem de outro jeito. Uma parte do público recebe cada versão, e a que tiver mais respostas vai
   para o resto."* Quem não quer, não faz nada (cena 01).
2. **Liga o interruptor.** O cartão abre: *"A versão 1 é a mensagem que você já escolheu acima. Agora monte a versão 2."*
   - **SMS / WhatsApp API:** uma caixa de texto com o botão **"Começar com o texto da versão 1"** e os mesmos botões de
     inserir nome/empresa/colunas. Ao lado, **"Como cada versão chega"** com as duas mensagens como o cliente vê
     (cenas 02–03). No SMS, o contador de caracteres e partes (o mesmo da versão 1) e, quando as duas usam quantidades
     diferentes, *"A versão 1 usa 2 SMS por pessoa e a versão 2 usa 1."*
   - **WhatsApp Oficial:** **"Modelo da versão 2"**, uma escolha entre os modelos aprovados da mesma caixa. O da versão 1
     e os que pedem informações diferentes aparecem apagados, com o motivo. Sem outro que sirva: *"Um modelo novo precisa
     ser aprovado pelo WhatsApp, o que pode levar algumas horas. Para mandar agora, desligue “Testar duas versões”."* e
     **"Criar outro modelo"** (cenas 06–07).
   - **E-mail:** a ajuda vira *"A versão 1 é o e-mail que você já montou. Na versão 2, só o assunto muda."*;
     **"Assunto da versão 2"** e as **"Ideias da IA"** num toque. Ao lado, as duas linhas como aparecem na caixa de
     entrada (cena 08, com o público do e-mail: 200 no teste e 780 no resto).
   - Se a versão 2 ficar igual à 1, aviso âmbar: *"Mude alguma coisa para dar para comparar"* (cena 05).
3. **O plano em frases** (fechado, com **"Alterar"**):
   *"Primeiro, 270 pessoas recebem o teste: 135 a versão 1 e 135 a versão 2. Depois de 4 horas, as outras 1.080 pessoas
   recebem a que teve mais respostas. Se as duas ficarem parecidas, segue a versão 1."*
   No **"Alterar"** (cena 04): *Qual versão é a melhor?* (mais respostas · mais compras · eu escolho), *Quanto tempo
   esperar antes de escolher?* (2 h · 4 h · 24 h) e *Como dividir o teste?* (metade cada · mais na versão 1, 70/30);
   **"Pronto"** fecha. "Mais compras" fica apagada, com o motivo, na conta sem compras na ficha (F1). Público pequeno
   (cena 09): *"O público é pequeno, então não dá para testar antes. Cada uma das 120 pessoas recebe uma das duas… No
   fim, mostramos qual foi melhor."* + *"Com menos de 200 pessoas, use o resultado só como pista."*
4. **Passo 3 · Revisar.** Linha **"Duas versões da mensagem"**: as duas versões lado a lado (texto inteiro) e o mesmo
   plano, começando por *"Ao enviar, só 270 pessoas recebem agora: 135 a versão 1 e 135 a versão 2."*, para não brigar
   com o "Vão receber 1.350" e o "Enviar agora"; **"Alterar"** volta ao passo 2 (cena 10). A linha embaixo do "Vão
   receber" (*"Agora vão 270 (o teste). As outras 1.080 vão depois de 4 horas."*) fica para o PR de ligação com a F5
   (#3101), que mexe no StepReview.
5. **Resultado da campanha.** Abaixo dos números, o cartão **"Duas versões da mensagem"**:
   - *Testando* (cena 12, ícone de relógio): *"Testando. Às 15:40, escolhemos a melhor e mandamos para as outras 1.080
     pessoas."* + *"Até agora, a versão 2 teve o dobro de respostas."* Cada versão num cartão (Receberam no teste ·
     Responderam "18 de cada 100" · Compraram + R$, cada apoio numa linha). Selo azul **"Na frente"**.
   - *Esperando você* (critério "eu escolho", cena 13): faixa âmbar *"O teste terminou. Escolha qual versão vai para as
     outras 1.080 pessoas."* e o botão **"Mandar esta para os outros"** em cada cartão — sólido no cartão "Na frente",
     contorno no outro; o leitor de tela ouve *"Mandar a versão 2 para as outras 1.080 pessoas"*. O toque abre a
     pergunta no próprio cartão: *"Mandar a versão 2 para 1.080 pessoas?"* + *"Depois de mandar, não dá para trocar de
     versão."* **Sim, mandar** (recebe o foco) / **Voltar** (cena 14).
   - *Escolhida* (cena 15): faixa verde *"A versão 2 foi para as outras 1.080 pessoas."* + *"A versão 2 teve o triplo de
     compras."*, selo **"Ganhou"** com troféu (verde claro, contraste AA). Empate (cena 16): só a faixa *"A versão 1 foi
     para as outras 1.080 pessoas, porque as duas ficaram parecidas."*; selo **"Foi para o resto"** sem troféu.
   - *Todos* (público pequeno, cena 17): *"Cada pessoa do público recebeu uma das duas versões."* + a comparação
     (ou *"Ainda são poucas respostas para saber qual é melhor."*).
   - Quem não tem a chave de disparar vê os números e, esperando a escolha, *"Quem pode disparar campanhas escolhe a
     versão."*; testando, *"Quem pode disparar campanhas pode escolher antes da hora."*
   - Sem teste e sem carregar (falhou a leitura): *"Não deu para carregar o resultado das duas versões agora."* +
     **"Tentar de novo"**.

### 2.2 Automação livre

1. No **"Alterar"** do passo **Mandar mensagem**, abaixo do texto (e do modelo da janela de 24 h): cartão **"Duas
   versões da mensagem"** com o interruptor *Testar duas versões desta mensagem* (cena 18).
2. Ligado: **"Texto da versão 2"** com o mesmo "Pôr um dado"; **"Modelo da versão 2"** só quando o passo usa modelo
   (cena 19). A versão 2 não repete a ajuda da versão 1 (colchetes, janela de 24 h, custo de propaganda). Plano: *"Cada pessoa que passar por este passo recebe uma das duas, metade cada. Quando 100 pessoas
   tiverem recebido cada versão, esperamos 4 horas e, daí em diante, todas recebem a que teve mais respostas."*
3. **Histórico** da automação: o mesmo cartão de resultado, no jeito da automação — *"Quando 100 pessoas tiverem
   recebido cada versão, esperamos 4 horas e escolhemos a melhor."* + *"Faltam 37 pessoas receberem a versão 2 para
   fechar o teste."* (cena 20; o servidor manda `espera` e `faltam`) e, depois, *"Desde 19 de novembro, todo mundo
   recebe a versão 2."* com selo **"Ficou"** (cena 21).
   Escolha à mão: **"Ficar com esta"**.

---

## 3. Regras (a tela promete o que o servidor faz)

Fonte única no front: `components-next/CampaignJourney/duasVersoes.js` e `components-next/CampaignResult/vencedora.js`.
O servidor implementa as mesmas constantes (e um spec de contrato compara as duas).

- **Tamanho do teste (campanha):** a versão que recebe menos tem pelo menos `MINIMO_POR_VERSAO = 100` pessoas; o
  teste é o maior entre esse mínimo e `PARTE_DO_TESTE = 20%` do público. 50/50 → mínimo 200; 70/30 → mínimo 334.
- **Sem resto que valha (`< MINIMO_NO_RESTO = 100`):** modo **todos** — o público inteiro dividido entre as duas, sem
  espera; o resultado só diz qual foi melhor. Abaixo do mínimo do teste, aviso de "pode ser sorte".
- **Público do teste:** o "Vão receber" já **sem** o grupo de controle da F2 (o sorteio da F2 vem antes).
- **Sorteio das versões:** fixo, pelo hash `link:contato` (mesma técnica do `GrupoDeControle`): rodar de novo dá as
  mesmas pessoas.
- **Espera:** padrão 4 h (respostas e "eu escolho") e 24 h (compras); trocar o critério leva a espera ao padrão dele
  se a pessoa não tiver mexido.
- **Quem ganha:** taxa de cada versão em "de cada 100" (ou 1.000) arredondada, a mesma régua da F2 (`emGente`,
  `pelaDiferenca`): até 15% de diferença = empate; "o dobro", "o triplo", "N vezes". Respostas = quem respondeu em até
  72 h (a mesma conta do CRM, `ResultReplies`); compras = `ComprasDaCampanha` na janela da F2.
- **Cedo demais:** menos de `MINIMO_DE_RESULTADOS = 10` respostas (ou compras) somadas nas duas = "poucos" → conta
  como empate.
- **Empate segue a versão 1** (a que a pessoa escreveu primeiro).
- **"Eu escolho":** depois da espera, o resto fica parado até alguém com `campaign_send` escolher. Escolha à mão vale
  também durante o teste (antecipa).
- **Automação:** cada execução sorteia a versão pelo hash `automacao:passo:alvo`; depois de 100 por versão + espera, a
  vencedora fica para todos (até a pessoa desligar ou mudar o texto, que zera o teste).

---

## 4. Telas novas (componentes reais, onda 1)

| Componente | Lugar | O que faz |
|---|---|---|
| `DuasVersoesMensagem.vue` | `components-next/CampaignJourney/` | Cartão do passo 2: interruptor, versão 2 por canal, aviso de igual/vazia, regra |
| `SegundaVersaoTexto.vue` | idem | Texto da versão 2 (SMS/WhatsApp API), inserir campos, contador SMS, prévia das duas |
| `SegundaVersaoModelo.vue` | idem | Modelo da versão 2 (WhatsApp Oficial), apagados com motivo, "Criar outro modelo" |
| `SegundaVersaoAssunto.vue` | idem | Assunto da versão 2 (e-mail), ideias da IA, linhas da caixa de entrada |
| `DuasVersoesRegra.vue` | idem | Plano em frases + "Alterar" (critério, espera, divisão); serve à automação |
| `ResumoDuasVersoes.vue` | idem | Linha da revisão |
| `useFrasesDoPlano.js`, `duasVersoes.js` | idem | Frases traduzidas do plano; regras puras |
| `ResultDuasVersoes.vue`, `CartaoDaVersao.vue`, `vencedora.js` | `components-next/CampaignResult/` | Resultado da campanha e da automação |
| `LivreDuasVersoes.vue` | `routes/dashboard/automacoes/livre/components/` | Versão 2 no passo de mensagem da automação |

Textos: catálogo novo `duasVersoes.json` (en + pt_BR), registrado em `config/fork_i18n.json`, no `ignore` do
`crowdin.yml` e nos dois `index.js`.

Harness local (fora do repositório): 21 cenas × 1440/390, usadas nos prints da onda 1.

---

## 5. O que o backend vai precisar

### 5.1 Tabelas e colunas (campanha)

Construção aditiva, tabela do fork (o Chatwoot não ganha coluna), como a F2.

Migration `AddDuasVersoesToCampaignAudienceLinks`:

```ruby
add_column :campaign_audience_links, :teste_criterio, :string        # nil = sem duas versões; 'respostas' | 'compras' | 'eu_escolho'
add_column :campaign_audience_links, :teste_divisao, :integer, null: false, default: 50   # 50 | 70 (parte da versão 1)
add_column :campaign_audience_links, :teste_espera_horas, :integer, null: false, default: 4 # 2 | 4 | 24
add_column :campaign_audience_links, :teste_estado, :string          # 'testando' | 'esperando_voce' | 'escolhida' | 'todos'
add_column :campaign_audience_links, :teste_escolhe_em, :datetime    # início do teste + espera
add_column :campaign_audience_links, :teste_vencedora, :integer      # 1 | 2
add_column :campaign_audience_links, :teste_escolhida_por, :string   # 'sistema' | 'voce' | 'empate'
add_column :campaign_audience_links, :teste_escolhida_por_user_id, :bigint # quem escolheu à mão (FK users, nullify)
add_column :campaign_audience_links, :teste_escolhida_em, :datetime
add_column :campaign_audience_links, :segunda_versao, :jsonb          # { message_body } | { template_name, template_language } | { subject }

create_table :campaign_version_contacts do |t|      # quem recebeu qual versão, uma linha por pessoa
  t.references :account, null: false, foreign_key: { on_delete: :cascade }
  t.references :campaign_audience_link, null: false, foreign_key: { on_delete: :cascade }, index: false
  t.references :contact, null: false, foreign_key: { on_delete: :cascade }
  t.integer :versao, null: false        # 1 | 2
  t.string :fase, null: false           # 'teste' | 'resto'
  t.datetime :created_at, null: false
  t.index %i[campaign_audience_link_id contact_id], unique: true, name: 'idx_campaign_version_contacts_link_contact'
  t.index %i[campaign_audience_link_id versao fase], name: 'idx_campaign_version_contacts_link_versao'
end
```

Colunas com default constante e tabela nova vazia: sem reescrever tabela, sem trava longa. Sem job enfileirado na
migration (regra do blue/green): a escolha da vencedora roda por cron.

### 5.2 Envio

- **Criação** (`whatsapp_campaign_creator`, `whatsapp_api_campaign_creator`, `sms_campaign_creator`, `email_campaign_creator`
  + `Medicao#aplicar!`): aceitam `duas_versoes: { criterio, divisao, espera_horas, segunda: {...} }`. Serviço novo
  `CampaignJourney::DuasVersoes` (`aplicar!`, `sortear_teste!(contact_ids)`, `vencedora`, `mandar_resto!(versao, por:)`).
- **Teste:** só as pessoas da fase `teste` viram destinatárias no disparo (como `GrupoDeControle#sem_o_grupo`, mas
  para o resto). Cada destinatário leva o conteúdo da versão dele (texto, modelo ou assunto). O `message_content`
  gravado em `campaign_recipients` já guarda o texto que saiu.
- **Resto:** `CampaignJourney::EscolherVencedoraJob` no `config/schedule.yml` a cada 5 min: pega links com
  `teste_estado = 'testando'` e `teste_escolhe_em <= agora`; critério automático → calcula, grava e dispara o resto
  com a vencedora; "eu escolho" → `esperando_voce`. Disparo do resto pelo mesmo caminho do envio original (WhatsApp
  Oficial: campanha one-off com o modelo vencedor; WhatsApp API: novos recipients; SMS: novos envios; e-mail: sync
  dos recipients restantes com o assunto vencedor).
- **E-mail:** a versão 2 é só o assunto. O motor de e-mail precisa aceitar assunto por destinatário (ou duas
  "remessas" do mesmo e-mail). Conferir o `EmailCampaign` antes de prometer.
- **WhatsApp Oficial:** a versão 2 precisa de modelo aprovado com as mesmas variáveis (bindings da versão 1 valem
  para as duas). Quem está com conversa aberta e recebe o texto livre (#1335) **fica fora da conta do teste**.
- **Limite de mensagens por cliente (#3072) e horário:** continuam valendo; o resto pode cair no dia seguinte por
  horário — o resultado mostra "às 08:00 de amanhã" em vez de "às 15:40".

### 5.3 Endpoints

- `POST /api/v1/accounts/:id/campaign_journey/campaigns` (existente): + `duas_versoes`.
- `PATCH .../campaign_journey/email_medicoes/:id` (existente, e-mail): + `duas_versoes`.
- `POST .../campaign_journey/recipient_previews` (existente): + `duas_versoes.divisao` para devolver o plano
  (`teste`, `versao1`, `versao2`, `resto`) contado pelo servidor.
- `GET .../campaign_journey/results/:channel/:id` (existente): + `duas_versoes` no formato do `ResultDuasVersoes`
  (`estado`, `criterio`, `escolhe_em`, `vencedora`, `escolhida_por`, `escolhida_em`, `resto`, `versoes[]` com
  `receberam`, `responderam`, `compraram`, `valor` — `valor` nulo sem a permissão financeira, como na F2).
- **Novo:** `POST .../campaign_journey/results/:channel/:id/vencedora` `{ versao: 1|2 }` → `mandar_resto!(por: :voce)`.
  Idempotente (segunda chamada com outra versão depois de escolhida = 422).
- **Novo:** `GET .../campaign_journey/assuntos_sugeridos?email_campaign_id=` só se as sugestões da IA não estiverem
  guardadas no e-mail (conferir se `SUBJECT_VARIANTS` persiste; se não, guardar no `EmailCampaign` na geração).

### 5.4 Automação livre

- Receita: passo `mensagem` aceita `versoes: { texto: [...], modelo: {...} | null, criterio, divisao, espera }`.
  Validação no esquema da receita (o mesmo arquivo que o Guia lê) + `formatos-das-acoes.json` regerado
  (`bundle exec rails autonomia:guia:formatos`).
- Tabela `autonomia_automacao_versoes_envios` (`account_id`, `automacao_id`, `passo_id`, `execucao_id`,
  `alvo_type`/`alvo_id`, `contact_id`, `versao`, `created_at`; índice `automacao_id, passo_id, versao`).
- Tabela `autonomia_automacao_versoes_vencedoras` (`automacao_id`, `passo_id`, `vencedora`, `escolhida_por`,
  `escolhida_por_user_id`, `escolhida_em`, `teste_desde`; único `automacao_id, passo_id`). Mudar o texto de
  qualquer versão grava `teste_desde = agora` e zera a vencedora.
- Executor: antes de mandar, `Autonomia::Automacao::DuasVersoes#versao_para(alvo)` (vencedora, se houver; senão
  sorteio). Cron `EscolherVencedoraDaAutomacaoJob` com a mesma régua.
- Endpoint: `GET automacoes/:id/duas_versoes` (ou junto do histórico) e `POST automacoes/:id/duas_versoes/:passo_id/vencedora`.

### 5.5 Permissões

Sem chave nova. Montar as duas versões: `campaign_manage` (campanha) / `automation_manage` (automação). Escolher à mão
e o envio do resto: **`campaign_send`** (é disparo, #1898) / **`automation_manage`**. Valor em R$ no resultado segue a
regra financeira da F2. Sem permissão nova → sem parecer da Funções.

### 5.6 Flag

Flag nova `duas_versoes_mensagem`, **nasce ligada em todas as contas** (regra do épico). Serve só como chave de
desligar em produção.

---

## 6. PRs previstos (uma etapa = um PR)

1. **Telas (esta onda, rascunho):** componentes, i18n, slot no `StepMessage`, export de `pelaDiferenca`, specs. Sem
   ligação. Prints → diretor de arte → OK do Rodrigo.
2. **Campanha · servidor + ligação:** migration, serviço, job no cron, endpoints, `NewCampaignPage` (draft, slot,
   revisão, `canContinue`), `MessageResultView`/`EmailResultView`, Guia. Specs de serviço e request.
3. **Automação livre · servidor + ligação:** receita, executor, tabelas, cron, `LivreAlterar`, `LivreHistorico`,
   formatos do Guia regerados.

Se o e-mail exigir mudança grande no motor de envio (assunto por destinatário), o e-mail sai do PR 2 para um PR 2b.

---

## 7. O que o Guia (`lib/operator_guide/porques.md`) precisa explicar

Blocos novos (o Guia não aceita tela nova sem explicação):

- `testar_duas_versoes_na_campanha` (rota `campaigns_journey_index`) — onde_fica: Campanhas > Campanha > Nova campanha >
  Mensagem > Duas versões da mensagem; passos: ligar, montar a versão 2 por canal, conferir o plano, "Alterar";
  gotchas: WhatsApp Oficial pede outro modelo aprovado com as mesmas informações; e-mail muda só o assunto; público
  pequeno manda as duas para todos; grupo de controle sai antes; empate segue a versão 1; limite por cliente e horário
  podem atrasar o resto; conversa aberta com texto livre fica fora da conta.
- `escolher_a_versao_que_vai_para_o_resto` (resultado) — passos e a chave `campaign_send`; quando o sistema escolhe
  sozinho; o que é "poucas respostas".
- `testar_duas_versoes_na_automacao` (rota `automacoes_lista`) — passo Mandar mensagem; 100 por versão + espera;
  mudar o texto zera o teste; onde ver no Histórico.
- Atualizar `medir_quem_comprou_depois_da_campanha` (F2) com a ligação: "mais compras" usa a mesma janela.

---

## 8. Decisões em aberto para o Rodrigo (só as que mudam o resultado)

**D1 — Como o "resto" funciona na campanha.** A Issue diz "escolher a divisão (padrão 50/50)" e "depois de um mínimo
de envios, manda o resto com a vencedora". Resposta e compra levam horas, então precisa haver uma parte que recebe
antes e espera.
- (a) **Teste numa parte + espera + resto com a melhor** (desenhado): 20% (mín. 200) testam, 4 h depois o resto. Ganha
  mais gente com a melhor; atrasa o resto em horas.
- (b) Todo mundo de uma vez, metade cada, e só o relatório diz qual foi melhor (para a próxima). Simples, sem espera;
  não "segue com a vencedora", contraria a Issue.
- (c) Como (a), mas a pessoa escolhe o tamanho do teste (10/20/30%). Mais controle; mais uma pergunta na tela.
- **Recomendação: (a).** A divisão 50/50 ou 70/30 vale **dentro do teste**; (b) fica automático para público pequeno.

**D2 — E-mail: o que muda entre as versões.**
- (a) **Só o assunto** (desenhado): uma caixa, reusa as ideias da IA, o editor do e-mail não muda.
- (b) O e-mail inteiro (dois layouts): mais poder; dobra o trabalho no editor e no motor.
- **Recomendação: (a)** nesta fase; (b) só se aparecer pedido real.

**D3 — WhatsApp Oficial: modelo da versão 2 com informações diferentes.**
- (a) **Só modelos com as mesmas informações** (desenhado, os outros aparecem apagados com o motivo): uma escolha de
  "de onde vem cada informação" serve às duas.
- (b) Qualquer modelo, com a ligação das informações da versão 2 separada: mais liberdade; dobra a parte mais difícil
  do passo 2.
- **Recomendação: (a).**

**D4 — Com o "melhor horário por cliente" da F5 ligado.** O melhor horário espalha os envios pelo dia; o teste
precisa sair junto para comparar.
- (a) **O teste sai no horário escolhido da campanha; o resto usa o melhor horário de cada um** (recomendado).
- (b) O teste também usa o melhor horário: comparação mais lenta e enviesada pelo horário.
- (c) Não deixar ligar os dois juntos: mais simples; tira opção.
- **Recomendação: (a)**, combinar com a sessão da F5 antes do PR 2.

---

## 9. Riscos

- **Mesmo assistente da F5:** a ligação (PR 2) mexe em `NewCampaignPage.vue` e `campaignDraft.js`, que a F5 também toca.
  Nesta onda só o slot do `StepMessage` (passo da mensagem) mudou. Fazer o PR 2 depois de a F5 entrar, ou combinar os
  pontos de edição.
- **E-mail com assunto por destinatário** pode não existir no motor; ver §5.2.
- **Pouca gente responde** em público médio: muitos testes vão terminar em "poucas respostas" → empate → versão 1. A tela
  diz isso com clareza, mas o valor do recurso cai em contas pequenas.
- **Resto parado no "eu escolho"** se ninguém escolher. Proposta para o PR 2: aviso na tela de Campanhas e, depois de
  3 dias, manda a versão 1 sozinho (pergunta para o Rodrigo se quiser).
- **Conversa aberta (#1335) e grupo de controle (F2)** mudam quem entra no teste; o número da revisão precisa vir do
  servidor (`recipient_previews`) para bater com o envio.
- **eslint:** os avisos `no-dynamic-keys` e `no-missing-keys` dos arquivos novos são os mesmos do resto do painel (o
  `localeDir` do eslint não lê `locale/**`); zero erro.

---

## 10. Decisões tomadas (Rodrigo, 23/11) e o servidor da campanha (Etapa 1)

Todas as recomendações da §8 foram aceitas: **D1 (a)**, **D2 (a)**, **D3 (a)**, **D4 (a)** e **D5**: no "eu escolho"
sem escolha, aviso na lista de Campanhas e, depois de 3 dias, a versão 1 vai sozinha para o resto.

O que o servidor da campanha faz (migration `20261123210000`, uma para a fase inteira, já com as duas tabelas da
automação):

- **Regra e estado** em `campaign_audience_links` (`teste_*`, `segunda_versao`). Além da §5.1, `teste_resto` guarda
  quantas pessoas ficam para depois (o plano; depois da escolha, quantas foram). `teste_escolhida_por_user_id` ficou
  sem chave estrangeira (só mostra quem escolheu; evita travar a tabela de usuários).
- **Sorteio** (`CampaignJourney::DuasVersoes`): fixo pelo hash `versoes:link:contato` (sal próprio, independente do
  grupo de controle, que sai antes). Roda na `CampaignJourney::Medicao`, junto com o grupo de controle, na criação
  (WhatsApp Oficial, SMS, WhatsApp API) ou no `PUT email_medicoes` (e-mail).
- **Teste e resto:** enquanto o resto espera, só quem tem versão recebe (`AudienceContacts.contacts_for` e a fila do
  e-mail, `EmailCampaigns::RitmoDoDestinatario.pendentes_na_vez`). Na escolha (`mandar_resto!`, uma vez só), o resto
  ganha a versão escolhida e `CampaignJourney::EnviarRestoJob` manda pelo caminho de cada canal: WhatsApp Oficial e SMS
  criam os destinatários do resto na mesma campanha (`enviar_resto`, que segue `completed`); WhatsApp API volta a
  `running`; no e-mail o resto já estava na lista, esperando, e o motor volta a andar (a campanha fica `sending` até o
  resto sair).
- **Versão de cada pessoa no envio:** WhatsApp Oficial troca só o modelo (D3: as mesmas informações, conferidas na
  criação); SMS e WhatsApp API usam o texto da versão 2 com os textos padrão dela; e-mail troca só o assunto
  (`DuasVersoes::AssuntoDoEmail`, prepend em `EmailCampaigns::DeliveryEngine` e `DirectInbox::RecipientSender`: o
  motor não aceitava assunto por destinatário).
- **Escolha automática:** `CampaignJourney::EscolherVencedoraJob` (cron a cada 5 min). A hora é o primeiro envio do
  teste + a espera. A régua é a da tela (`DuasVersoes::Vencedora` = `vencedora.js`); empate ou poucas respostas, a versão
  1 (`empate`). "Eu escolho": `esperando_voce` e, depois de 3 dias, a versão 1 (`sistema`).
- **Endpoints:** `duas_versoes` em `POST campaigns` e `PUT email_medicoes`; plano em `POST recipient_previews`
  (`duas_versoes.divisao` + `grupo_de_controle_pct`); bloco `duas_versoes` no `GET results/:channel/:id`; novo
  `POST results/:channel/:id/vencedora` (`campaign_send`, idempotente); `duas_versoes_esperando` no overview (aviso do
  D5).
- **D4 (F5, #3101):** o ponto de extensão é `Autonomia::RitmoDeEnvio::Porteiro`, consultado antes de cada envio em todos
  os canais. A F5 adia a pessoa para o melhor horário lá e pula quem está no teste (`DuasVersoes#fase_de` = `teste`).

Fica para os próximos PRs da fase: a ligação das telas (`NewCampaignPage`, revisão, resultado, aviso na lista), a
automação livre (tabelas já criadas), os blocos do Guia (§7), os formatos do Guia regerados e a flag
`duas_versoes_mensagem`.

---

## 11. A ligação da campanha (Etapa 2)

As telas da onda 1 passaram a falar com o servidor da Etapa 1. Toque mínimo no Chatwoot e no assistente:

- **Rascunho:** `draft.duasVersoes` (`duasVersoesVazias()`) em `campaignDraft.js`. Rascunho antigo sem o campo ganha o
  padrão desligado.
- **Passo Mensagem:** a Nova campanha preenche o slot `duas-versoes` do `StepMessage` com `DuasVersoesMensagem`. Os dados
  saem de `useDuasVersoesNaCampanha` (modelos aprovados da caixa com "mesmas informações", o e-mail criado, as ideias de
  assunto da IA guardadas em `ai_subject_variants`). Modelo da versão 2 que deixou de servir (outra caixa, outro modelo
  na versão 1) volta a ficar vazio. No e-mail, o cartão só aparece depois de o e-mail existir.
- **`canContinue`:** a versão 1 pronta **e** a versão 2 pronta (`motivoDaSegunda`). Com a versão 1 pronta e a 2 vazia, o
  cartão diz "Falta a versão 2", para explicar por que "Continuar" não anda.
- **Plano do servidor:** o mesmo `POST recipient_previews` do "Vão receber" leva `duas_versoes.divisao` e
  `grupo_de_controle_pct` quando as duas versões estão ligadas, e as frases usam `payload.duas_versoes`. Enquanto ele não
  volta, a tela faz a mesma conta (`planoDoTeste`).
- **Revisão:** `ResumoDuasVersoes` no slot `#modelo` e, embaixo do "Vão receber", a linha "Agora vão N (o teste). As
  outras M vão depois de X horas." (`AgoraVaiOTeste`, slot novo `vao-receber` no `StepReview`, uma linha). O "Vão
  receber" e a confirmação continuam com o público inteiro. O "Quando começa" (F5) não mudou.
- **Envio:** `medicaoDaCampanha` leva `duas_versoes` (`criterio`, `divisao`, `espera_horas`, `segunda`) nos quatro canais;
  no WhatsApp Oficial, `segunda` leva o nome e o idioma do modelo. O multipart da WhatsApp API com anexo passou a mandar
  objetos aninhados em qualquer profundidade. Código `segunda_versao_*` recusado vira frase própria
  (`DUAS_VERSOES.ERROS`).
- **Resultado:** `ResultDuasVersoesDaCampanha` (abaixo da linha que fecha os números, no `MessageResultView` e no
  `EmailResultView`) mostra `result.duas_versoes` e, no "Sim, mandar", chama `POST …/vencedora`. 422 (outra versão já
  escolhida) avisa e recarrega.
- **Lista de Campanhas (D5):** `AvisoDuasVersoesEsperando` lê `duas_versoes_esperando` do overview (período de 7 dias,
  o menor) e leva ao resultado de cada campanha; mostra até quando dá para escolher antes de a versão 1 ir sozinha.
- **Guia:** blocos `testar_duas_versoes_na_campanha` e `escolher_a_versao_que_vai_para_o_resto`; os blocos da lista de
  Campanhas e de "Quem comprou depois" ganharam a ligação.

---

## 12. A Automação livre (Etapa 3)

As tabelas já vinham da migration `20261123210000`. Esta etapa liga o passo **Mandar mensagem** às duas versões:

- **Receita:** o passo `mensagem` aceita `versoes: { texto, modelo, criterio, divisao, espera }` (definição `duas_versoes` em
  `lib/operator_guide/automacao-receita.schema.json`). `modelo` é `null` quando o passo não usa modelo. O catálogo do editor
  ganhou o campo `versoes` com a peça `duas_versoes` (`Catalogo::PECAS_DO_ESQUEMA`, `automacao-passos.json`), que o
  `LivreAlterar` mostra com o `LivreDuasVersoes`.
- **Ao salvar** (`Receita::Mensagens`): o texto e as variáveis do modelo da versão 2 passam pela régua de sempre; o modelo
  da versão 2 precisa estar pronto na conta. Regras próprias (`DuasVersoes.problemas_ao_salvar`): com modelo na versão 1, a
  versão 2 precisa do dela; modelo só na versão 2 é recusado; versão 2 igual à 1 é recusada; "mais compras" pede o CRM. A
  tela segura o Salvar antes (`versoesDoPasso.js`: versão 2 pronta e diferente; tirado o modelo da 1, o da 2 sai junto) e o
  Ligar diz o que falta (`COMPLETAR.VERSAO_2`).
- **Executor:** `Executor#passo_nativo` troca a classe do passo com duas versões por `DuasVersoes::Envio`. Ele escolhe a
  versão (a vencedora, se houver; senão o sorteio fixo pelo hash `automacao:passo:alvo`, com a divisão da regra) e manda pelo
  `PassoDeMensagem` de sempre. Só o envio que saiu grava a linha em `autonomia_automacao_versoes_envios` e põe `versao` no
  registro do passo (o Histórico diz "Recebeu a versão 2 da mensagem").
- **Zerar o teste:** `Definicao#salvar_versao!` chama `DuasVersoes.versao_salva!`. Passo que ganhou as duas versões, ou cujo
  texto ou modelo mudou em uma delas, grava `teste_desde = agora` e perde a vencedora. Mudar só a regra não zera.
- **Números** (`DuasVersoes::Numeros`, desde `teste_desde`): receberam = envios; responderam = o contato escreveu em até
  72 h depois do envio (qualquer conversa da conta); compraram = a régua do histórico (7 dias, `ComprasNaJanela`), só com o
  CRM. O teste fecha quando a versão mais atrasada chega a 100 envios; a hora de escolher é o fechamento + a espera.
- **Escolha:** `Autonomia::Automacao::EscolherVencedoraJob` (cron a cada 15 min) usa a régua da campanha
  (`CampaignJourney::DuasVersoes::Vencedora`): empate ou poucas respostas, a versão 1 (`empate`). No "eu escolho" o cron não
  escolhe: o cartão fica em `esperando_voce` e, até alguém escolher, cada pessoa continua recebendo uma das duas (nada fica
  parado, então o D5 dos 3 dias, que é da campanha, não se aplica aqui).
- **Endpoints** (`AutomacoesDuasVersoesController`): `GET automacoes/:id/duas_versoes` (`automation_view`) devolve o bloco
  de cada passo com duas versões da versão ativa; `POST automacoes/:id/duas_versoes/vencedora` `{ passo, versao }`
  (`automation_manage`) grava a versão que fica, uma vez só (a mesma de novo = 200; outra = 422). O id do passo vai no
  corpo porque o da receita é texto livre.
- **Histórico:** `LivreDuasVersoesResultado` (abaixo de Compras depois da automação) junta os números do servidor com o
  texto de cada versão, lido da receita ativa, e mostra o `ResultDuasVersoes` no jeito da automação. "Ficar com esta" pede a
  chave de mudar automações.
- **Guia:** bloco `testar_duas_versoes_na_automacao` (rota `automacoes_livre_editar`).

Fica de fora: o Ensaiar mostra só a versão 1; uma execução que entrou numa versão antiga da automação e manda depois de o
texto mudar conta no teste novo (com o texto antigo).
