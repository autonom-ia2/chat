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
4. nenhuma leitura mandada pelo próprio sistema na conversa nos últimos 2 min (`ConversaCanal::LeituraDoSistema`,
   gravada pela lida ao abrir/ao responder e pelo "digitando" da Cloud, que também marca como lida).

O visto vai até o fim do segundo da mensagem lida (não a hora da leitura), só para a frente, sem sino.
A recebida pela Cloud guarda no Redis o id físico tirado do wamid (7 dias), para o ack encontrá-la.

## Não provado (passo 0 da Issue, depende de teste real com o número do Rodrigo)

- que o celular principal chega como aparelho 0 e a lida pela Cloud (coexistência) não;
- que o id físico dentro do wamid da recebida é o mesmo dos `MessageIDs` do ack;
- confirmação de leitura desligada no celular vira `read-self` e o GOWS não emite: nada muda para esses negócios.

Erro de qualquer hipótese leva a "bolinha continua acesa", nunca a "apaga sem ninguém ler", exceto se a lida pela
Cloud chegar como aparelho 0 FORA da janela de 2 min. Por isso a flag nasce só no piloto.

## Validação local

Specs dirigidos em banco próprio (`chatwoot_test_2246leituracelular`), rubocop nos arquivos tocados,
`autonomia:guia:formatos:check` em dia.
