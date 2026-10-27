# #2246 — leitura no celular apaga a bolinha (opção C), PR do Híbrido

## Decisão

- Canal entregue neste PR: **caixa oficial com WhatsApp Híbrido**. A sessão auxiliar (GOWS) já assina `message.ack` e
  recebe o ack `fromMe=false` (ack 3/4) quando o celular do negócio lê uma mensagem recebida. Antes ele era descartado.
- **WAHA comum** fica para PR próprio: o sinal morre no conector (o app Chatwoot da WAHA só processa ack de mensagem
  nossa). Precisa de patch `c2y-rich-6` no conector + endpoint no fork, com imagem nova do motor, canário e rollback.
- **Cloud/coexistência sem Híbrido**: a Meta não manda evento de leitura feita no app do negócio. Sem solução no canal;
  a saída é ligar o Híbrido.
- Opção A (`source=app`) fora.

## Regra (o que conta como "pessoa leu no celular")

1. flag `leitura_no_celular` da conta (ext_2, posição 5 provisória);
2. `fromMe=false` e ack 3 (lido) ou 4 (ouvido);
3. aparelho que leu = 0 (celular principal), lido do `_data.Sender`; só o número do aparelho vai para a fila;
4. a mensagem lida **não está coberta** por uma leitura que o próprio sistema mandou ao canal
   (`ConversaCanal::LeituraDoSistema`). A marca guarda até qual mensagem o sistema marcou (o `created_at` dela): a lida
   ao abrir/ao responder (`LeituraNoCanal`, pela Cloud marca a mensagem e as anteriores; pelo `sendSeen` do WAHA, o chat
   inteiro) e o "digitando" da Cloud, que também marca a última recebida. Só anda para a frente, dura 1 dia.

O visto vai até o fim do segundo da mensagem lida (não a hora da leitura), só para a frente, sem sino.
A recebida pela Cloud guarda no Redis o id físico tirado do wamid (7 dias), para o ack encontrá-la. O id físico sai do
terceiro pedaço do id do WAHA (`false_<chat>_<ID>`, ou `false_<grupo>_<ID>_<participante>` em grupo).

## Ajustes da revisão adversarial

- **Corrida ack × índice (ALTO).** O índice é gravado no fim do `Webhooks::WhatsappEventsJob` (fila medium, depois da
  transação); o ack chega pela fila default, às vezes antes. Agora `LeituraNoCelular#aplicar` devolve o motivo e, em
  `:sem_indice`, o `WebhookEventJob` reenfileira o ack com espera de 5 s, 15 s e 45 s (3 novas tentativas, ~1 min).
  Depois disso desiste (o ack pode ser de mensagem que nunca foi indexada: anterior à flag, outra caixa).
- **Janela conferida na hora do job (MÉDIO).** A marca deixou de ser "houve leitura do sistema há menos de 2 min" e
  passou a ser "o sistema marcou até a mensagem X". A comparação é entre o `created_at` da mensagem lida e a marca, as
  duas no relógio do servidor; o atraso da fila não entra. Não usei o `timestamp` do corpo do webhook, como sugerido,
  porque ele vem do relógio do motor e a marca do relógio do servidor; a comparação por mensagem dispensa os dois.
- **Robô "digitando" comia a leitura (MÉDIO).** Com a marca por mensagem, o "digitando" a cada pedaço da resposta só
  cobre as mensagens que já existiam quando ele marcou. A pessoa que lê no celular uma mensagem que chegou depois tem a
  leitura contada. Perder a leitura de mensagem coberta não custa nada: o celular não manda leitura de mensagem que já
  está lida. Só se perde quando a marcação do sistema falhou no canal (erra para "não lida").
- **Descarte silencioso (MÉDIO).** Cada decisão (com a flag ligada) vira uma linha de log info, sem telefone e sem id de
  mensagem: `[whatsapp_hybrid][leitura_no_celular] connection=<id> motivo=<...> ack=<n> aparelho=<n> tentativa=<n>`.
  Motivos: `nao_e_leitura`, `aparelho_vinculado`, `sem_indice`, `marca_do_sistema`, `ja_visto`, `andou`.

## O que o piloto mede pelo log

- `aparelho=0 motivo=marca_do_sistema` frequente: a lida do próprio sistema volta como aparelho 0 (hipótese errada; a
  marca está segurando, mas o robô do n8n que marca direto na Meta não deixa marca, ver abaixo).
- `motivo=sem_indice tentativa=3`: o id físico do wamid da recebida não é o dos `MessageIDs` do ack, ou o índice não foi
  gravado.
- `aparelho=<n≠0>` sem nenhum `aparelho=0` numa caixa onde se atende pelo celular: o celular principal não chega como 0.

## Efeitos conhecidos

- **Robô do n8n que marca como lida direto na Meta** (nó "WA API Oficial", citado em
  `autonomia/agents/operate/typing_indicator.rb`): não passa pelo fork, não deixa marca. Ali só a regra do aparelho 0
  protege. Se a lida pela Cloud chegar como aparelho 0, o robô do n8n apaga a bolinha. É o único caminho conhecido de
  falso positivo, e o log acima mostra se ele acontece.
- Marcação do sistema que falhou no canal: a leitura feita depois no celular, da mesma mensagem, é descartada por até
  1 dia (erra para "não lida").

## Não provado (passo 0 da Issue, depende de teste real com o número do Rodrigo)

- que o celular principal chega como aparelho 0 e a lida pela Cloud (coexistência) não;
- que o id físico dentro do wamid da recebida é o mesmo dos `MessageIDs` do ack (a amostra dos specs é de um eco de
  enviada, não de uma recebida);
- confirmação de leitura desligada no celular vira `read-self` e o GOWS não emite: nada muda para esses negócios.

Erro de qualquer hipótese leva a "bolinha continua acesa", nunca a "apaga sem ninguém ler", exceto se a lida pela
Cloud que o fork não marcou (n8n direto na Meta) chegar como aparelho 0. Por isso a flag nasce só no piloto.

## Validação local

Specs dirigidos em banco próprio (`chatwoot_test_2246leituracelular`), inclusive um request spec do corpo assinado do
GOWS até o `agent_last_seen_at` (aparelho 0 apaga, aparelho 5 não), rubocop nos arquivos tocados,
`autonomia:guia:formatos:check` em dia.
