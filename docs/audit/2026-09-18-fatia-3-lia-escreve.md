# Fatia 3 do #420: a Lia escreve os preços (18/09/2026)

## Decisão

CEO, 18/09/2026: quem responde ao cliente é a Lia ou o especialista; o código entrega os dados ao modelo e só
confere. Revoga "valor em reais e nome de seguradora são escritos pelo código". Os textos de reserva ficam como
rede contra silêncio, e cada um que sai vai ao log.

## O que mudou

| Antes | Agora |
|---|---|
| Cada consulta publicava o lote de preços que chegou (`QuoteOffers.describe`) | A consulta grava `resultado_por_seguradora` e `entregues` (quem cotou) e não publica nada |
| Aviso de renovação sem bônus junto do primeiro lote | Na legenda do comparativo |
| Nenhuma mensagem entre o pedido e o fim | Passados 120 s sem terminar, sai uma vez a frase `espera` (`AsyncRunJob#sinal_de_vida`), fora do contador de entregas |
| PDF falhou nas 3 tentativas: fecho de quem tem resultado (os lotes estavam na tela) | Papel novo `valores_na_conversa`: a pessoa pode pedir os valores ali mesmo |
| `ver_resultado_da_cotacao` anexava a lista do código depois da fala | Devolve ao modelo, por seguradora, valor com período e parcelamento; quem não fez proposta vai com o nome (e a categoria quando perguntada) |
| Fala da Lia publicada como veio | `ConferenciaDePrecos`: todo valor em reais e toda seguradora da cotação citada precisam estar no texto que a ferramenta devolveu no turno; senão uma reescrita, depois a versão sem valores, depois o recuo registrado |
| Recuo publicado sem rastro | `AsyncPublisher#registrar_recuos`: `[autonomia][recuo] run= slug= papel=` em toda mensagem nova que leva um recuo |

Saíram: `Tools::Delivery#anexar/anexo/anexos`, o que o `Operate::Responder` ganhou para anexos (volta ao de
antes da fatia 2), `LISTA_ANEXADA`, `QuoteOffers.describe/item` e as três aberturas de lote (os papéis
`primeiros_precos`, `mais_um_preco`, `mais_precos`), `AVISO_SENT_KEY`, `Fecho#registrar_entrega_de_preco`.

## Estados verificados

- **Encerramento e fecho.** `closing_deliveries` pedia o comparativo só com lote aceito; sem lote isso calaria o
  PDF de toda execução que acaba pelo prazo. Passa a pedir quando alguém cotou, e grava a identidade do PDF na
  linha antes de publicar. `resultado_entregue?` das execuções novas é o comparativo assumido.
- **Dois defeitos achados pela suíte e corrigidos:** (1) PDF na conversa com envio pendente e contador zero caía
  em "não consegui" (o lote mantinha o contador acima de zero): o fecho pergunta primeiro à ferramenta; (2) PDF
  adiado pelo próprio encerramento com a escrita do aceite falhando levava a "peça os valores" ao lado do PDF:
  a entrega aceita no encerramento (`entregou`) conta como resultado.
- **Nenhum desfecho duplicado:** `valores_message` entrou em `FRASES_DE_FECHO`.
- **"Com preço" e pedido repetido:** `entregues` continua sendo a união de quem cotou (a medida conta igual);
  `conta_como_pedido?` segue pelo contador ou pelo resultado guardado. Travado em
  `async_run_job_fecha_sem_esperar_o_portal_spec` (medida e texto de concluída).
- **Recotar à toa:** manual da Lia diz que pedir os preços não é pedir outra cotação; `PedidoRepetido` inalterado.

## Validação

- Base antes: `spec/services/autonomia spec/jobs spec/models/autonomia` 2268 exemplos, 0 falhas, 5 pendentes, exit 0.
- Depois: mesmas pastas, 2237 exemplos, 0 falhas, 5 pendentes, exit 0 (saíram os exemplos do lote e do anexo).
- `spec/requests/api/v1/accounts/autonomia`, `spec/controllers/super_admin/insurance_measurements_controller_spec.rb`,
  `spec/services/crm/ai`: 292 exemplos, 0 falhas, exit 0.
- RuboCop com lista explícita: 40 arquivos, 0 ofensas, exit 0. `zeitwerk:check` ok.
- md5 reassinados: `especialista_auto.md` inteiro, §7.1 e bloco `ver_resultado_da_cotacao` do `principal.md`.

## Mutações (as que importam)

| Mutação | Resultado |
|---|---|
| A conferência deixa passar valor inventado (`divergencias` vazio) | reprovada: 9 exemplos caem |
| O lote automático volta (`em_andamento` publica a lista) | reprovada: 4 caem |
| O sinal de vida aos 60 s | reprovada |
| O sinal de vida sem a guarda de tempo | reprovada |

## Resíduos declarados

- A conferência só roda no turno em que `ver_resultado_da_cotacao` foi chamada. Valor escrito sem chamar a
  ferramenta não é conferido; o manual manda chamar.
- Seguradora fora da cotação não é reconhecida como nome (não há catálogo), e valor trocado entre duas
  seguradoras da mesma resposta passa (cada valor existe nos dados).
- O sinal de vida reusa a frase `espera`. Se ela já saiu no começo (turno mudo), o publicador acha a mesma
  identidade e não a repete. O sinal é adquirido antes de publicar: publicação recusada não tenta de novo.
- O aviso sem bônus viaja com o PDF; sem PDF, a Lia o recebe nos dados quando o cliente pergunta.
- Pedido do que falta com lista de rótulos escrita pelo código: #453 (resíduo da regra nova).

## Deploy e rollback

Sem migration. Execuções em voo: a primeira consulta desta versão grava `preco_legado` a partir de `entregues`,
e a prova legada continua valendo para quem já tinha lote na tela. Rollback volta os lotes; execuções abertas
nesta versão não têm `entregas_de_preco`; na versão anterior o comparativo assumido também é resultado
(`Fecho#resultado_entregue?`), então quem recebeu o PDF recebe o fecho de quem tem resultado.
