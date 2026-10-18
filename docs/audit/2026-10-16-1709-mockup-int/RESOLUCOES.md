# #1709 sobre #1702b: resoluções do merge (receita do merge real)

Ensaio feito em 16/10/2026 num clone descartável no M2 (`/Users/Shared/maccluster-demo-1709-int/src`, branch local
`demo/integrado-1709`, sem push). Ordem que vai valer na main:

| Passo | Fonte | SHA | Resultado |
|---|---|---|---|
| base | `origin/main` | `74f4f3ff2` | — |
| 1 | #1740 `feat/1732-formatacao-whatsapp` | `2fe406170` | limpo (`d7a1aac7a`) |
| 2 | #1702b `feat/1702b-whatsapp-2026` | `79d3c0bf3` | 1 conflito gerado (`01920d3b0`) |
| 3 | #1709 `feat/1709-ricas-waha` | `f76943105` | 7 conflitos + 4 ajustes de integração (`cca3a03a6`) |

O #1740 já traz parte do #1702b (base comum `848b48c12`): 4 commits só dele, 17 só do #1702b.

## Passo 2 (#1702b sobre main + #1740)

- `lib/operator_guide/formatos-das-acoes-cobertura.md`: gerado. Provisório com o lado do #1702b; regenerado no passo 3.

## Passo 3 (#1709 sobre main + #1740 + #1702b): conflitos

1. **`config/features.yml`**: o #1702b vem primeiro: `conversa_cara_do_canal` fica no **bit 30** e `whatsapp_rich_native`
   vai para o **bit 31** (2147483648), com o comentário do #1709 atualizado ("logo depois de `conversa_cara_do_canal`").
   A coluna `feature_flags_ext_1` é `bigint`: o bit 31 cabe.
2. **`spec/models/account_spec.rb`**: a mesma ordem: `feature_conversa_cara_do_canal: 1 << 30,` e
   `feature_whatsapp_rich_native: 1 << 31`.
3. **`app/services/waha/client.rb`**: ficam os dois: `set_reaction` (#1702b) e depois `include Waha::Client::RichSends`
   (#1709). Os nomes não colidem (`RichSends` não define `set_reaction`).
4. **`lib/operator_guide/formatos-das-acoes-cobertura.md`** e **`formatos-das-acoes.json`**: regenerados com
   `bundle exec rails autonomia:guia:formatos` (617 ações) e conferidos com `autonomia:guia:formatos:check` ("em dia").
   O JSON também mudou: `leitura_ao_abrir.rb:25` → `:26` (o JSON do #1702b no `79d3c0bf3` já estava fora de dia).
   `pnpm guia:check`: "mapa do Guia em dia — 226 fluxos, 204 telas, 0 sem explicação".
5. **`components-next/message/MessageList.vue`**: os dois filtros juntos. O `isHidden` do #1709 (atividade ou recebida com
   `c2y_hidden`) vale **sempre**, antes do `useCamelCase`; o `ocultaNaPele` do #1702b soma por cima, **só com a pele**.
   O `naoLidaDaLista` do #1702b segue igual.
6. **`components-next/message/Message.vue`**:
   - imports dos dois lados;
   - `contextMenuEnabledOptions`: `baixarAudio`, `reagir`, `encaminhar` (#1702b) + `react: isReactable.value && !pele.value`
     e `edit: isEditable.value` (#1709);
   - template: `BotaoDeReagir` e `BotaoDeEncaminhar` (#1702b), depois `EditedMark v-if="isEdited && !pele"` e
     `MessageReactions v-if="messageReactions.length && !pele"` (#1709). Com a pele valem o `RotuloEditada` e o
     `SeloDeReacoes` do #1702b;
   - `ContextMenu`: `@encaminhar` + `@react` + `@edit`; `MessageActionDialogs` do #1709 continua (o "Editar" só existe no #1709).
   - Não mexido: `hasMessageExtras` (classe `flex-col gap-1` da bolha) ainda conta reação/editada com a pele. Não deu
     defeito visível nos prints.
7. **`modules/conversations/components/MessageContextMenu.vue`**: `emits: ['open', 'close', 'replyTo', 'encaminhar',
   'react', 'edit']` e os quatro itens: Reagir (#1702b), Encaminhar (#1702b), Reagir (#1709, já escondido com a pele pelo
   `enabledOptions`), Editar (#1709). Resultado nos prints: um "Reagir" só no menu.

## Passo 3: ajustes de integração (sem conflito textual)

8. **`app/services/conversa_canal/reacao_do_atendente.rb`**: `perform` começa com
   `return reagir_pelo_conector if pelo_conector?`. `pelo_conector?` = caixa WAHA **e**
   `Waha::RichNative::MessageActions.allowed?(conversa, 'react')`. Aí: confere o emoji (um grafema ou vazio), chama
   `Waha::RichNative::MessageActions.react!(@message, user: @user, emoji: @emoji)` e **não** chama `remetente.enviar`
   nem `gravar`. Recusa → `Recusa`: `:forbidden` → `caixa_sem_reacao`, `:invalid` → `mensagem_invalida` (outro símbolo
   cai em `mensagem_invalida`). Devolve `@message.reload` (o controller lê `reactions`; o formato é o mesmo dos dois PRs).
   Sem a flag ou motor sem a ação: o caminho do #1702b, como antes.
9. **`app/services/conversa_canal/cliente_do_motor.rb`** (novo, 17 linhas): `ConversaCanal::ClienteDoMotor.para(canal)`
   devolve um `Waha::Client` apontado para `Waha::EngineCapabilities.engine_for(canal.webhook_url)` (mesma
   `WAHA_API_KEY`); caixa sem motor listado → `Waha::Client.new` de sempre.
10. **`app/services/conversa_canal/reacao_no_waha.rb`**: `client:` passa a ter padrão `nil`; sem ele,
    `ConversaCanal::ClienteDoMotor.para(message.inbox.channel)`.
11. **`app/services/conversa_canal/leitura_no_canal.rb#enviar_pelo_waha`**:
    `(@waha_client || ConversaCanal::ClienteDoMotor.para(canal)).send_seen(...)`.

## O que o merge real ainda precisa (achado no ensaio)

- **Spec do #1702b contra a resolução 5**: `conversa-canal/specs/baloesDoWhatsapp2026.spec.js:570` ("sem a pele,
  aparece como sempre") espera ver a mensagem com `c2y_hidden` sem a pele; com `isHidden` sempre ligado ela some. Ajustar o
  spec do #1702b no merge.
- **Conflito de comportamento sem conflito de texto**: `app/listeners/conversa_canal/webhook_sem_atualizacao_da_pele.rb:5`
  (#1702b) corta o `message_updated` de reação no webhook de **toda** caixa API (inclusive n8n), com ou sem a pele; o spec do
  #1709 `spec/services/waha/rich_native/silent_update_spec.rb:67` exige que a caixa API que não é WAHA continue recebendo.
  Falha no integrado, passa no #1709 sozinho. Decidir qual regra vale antes do merge (aceite C: "outros usos da API de
  caixa inalterados").
- **Falha do #1740 × #1702b** (antes do #1709): `editadaAudioAlbum2026.spec.js` ("álbum com legenda") quebra em
  `useFormatoDoWhatsapp.js:74` (`messageType` indefinido). Passa no #1702b sozinho e falha em `01920d3b0`
  (main + #1740 + #1702b).

## Validação do integrado (M2, banco de teste próprio)

- RSpec: `spec/services/conversa_canal/`, `spec/models/account_spec.rb`, `spec/services/waha/`, `spec/jobs/waha/`, requests
  de conversa_canal: **564 exemplos, 1 falha** (`silent_update_spec.rb:67`, acima), 1 pendente.
- Vitest: `components-next/message`, `components-next/conversa-canal`, `modules/conversations/components`: **596 testes, 2
  falhas** (as duas acima).

## Merge real (18/10/2026): o que de fato foi feito

Base: `origin/main` `d6e00a776f` (já com #1729, #1753, #1772, #1724, #1793 e o renderer do #1740). O merge é o
`0cc839c0db`; os ajustes vêm em commits pequenos por cima. A ordem da demo (1740 → 1702b → 1709) não vale mais: o 1702b
e o 1740 chegaram à main como #1724/#1793 e o renderer.

Conflitos textuais:
- `config/features.yml` / `spec/models/account_spec.rb`: a main já tinha `memoria_ia` (30) e `conversa_cara_do_canal`
  (31); `whatsapp_rich_native` foi para o **bit 32**. O comentário da flag diz o que vale com e sem ela.
- `app/services/waha/client.rb`: `set_reaction` (#1702) + `include Waha::Client::RichSends`.
- `MessageList.vue`: como no passo 3.5, mais: com a pele, o marcador escondido com `waha_album` passa ao álbum.
- `Message.vue` / `MessageContextMenu.vue`: como nos passos 3.6 e 3.7; `hasMessageExtras` só conta sem a pele; o menu
  ganha "Apagar para todos" com `c2y_revocable`.
- `SharedCard.vue`: o aviso "Localização em tempo real" (pele) e a legenda (`note`, #1709).
- `formatos-das-acoes.json` / `-cobertura.md`: regenerados (622 ações).

Integração (passos 8 a 11 da demo, com o que mudou):
- `ReacaoDoAtendente`: delega para `MessageActions.react!` (passo 8), com as validações de emoji e de mensagem
  reagível; `sem_identificacao` não (o conector não usa `source_id`). Emoji: uma regra só, `Whatsapp::EmojiDeReacao`,
  também no `react!` (ASCII recusado).
- `ClienteDoMotor` (passo 9): o motor da caixa **só com a flag**; sem ela, `Waha::Client.new` como na main.
- `ReacaoNoWaha` / `LeituraNoCanal` (passos 10 e 11): pelo `ClienteDoMotor`.
- `AiLocationText` / `AiContactText`: formatam pelo `ResumoDaMensagemRica` (#1753); o `ResponderLocation` não repete o
  resumo que o histórico da equipe (Fase 2) já escreveu.
- `SilentUpdate`: não delega ao `so_da_pele?` (ele não aceita `content` na edição); as 11 chaves são as mesmas. Silencia
  **só com a flag ou a pele** na conta; com as duas desligadas, igual à main (o `atualizacao_da_pele_spec` da main
  segue intacto).
- `OutgoingHints.whatsapp_text`: `pele: true` (o `WhatsAppDaPeleRenderer` é o que tem paridade com o conector).
- `waha_album` fica na mensagem (com e sem a flag, só do conector).
- `c2y_revocable` (mensagem) só com a flag, nunca em mensagem que falhou; `whatsapp_api_group` (conversa). Spec conta as
  consultas: nenhum dos dois consulta por item da lista.
- `MessageActions.deliver`: pedido que nem sai (sem webhook, trava de transmissão) deixa a nota "não chegou".

Pendência da demo resolvida na main: o `webhook_sem_atualizacao_da_pele` já só corta a caixa WAHA (o n8n recebe).

Mudança de comportamento na pele (revisão do merge): a regra de "reagível" é uma só, `Whatsapp::MensagemReagivel`, no
`ConversaCanal::ReacaoDoAtendente` e no `MessageActions.react!`. Com isso a reação pela pele passa a recusar também
mensagem falhada, mensagem com `external_error` e o aviso de visualização única (antes recusava só nota, atividade,
modelo e apagada). A regra lê o aviso pela chave `view_once_unavailable`, sem depender do código do WAHA. No painel, o
"Reagir" do #1709 some também na apagada pelo cliente; o "Editar" segue o `editable?` do servidor.
