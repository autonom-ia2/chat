# A5 — leitura diagnóstica limitada do fechamento inválido

Este pacote é uma candidata local sobre A4. A coleta Hub preservada em
`proof-auth-binding-2067d1c6c42841c4929bf37d54c1cd6e.json` observou um cabeçalho
`close` com 175 bytes declarados depois de enviar o token próprio A à URL da
sessão sintética B. A4 recusou o frame antes do payload; não conhecemos ainda
o código nem a razão enviados pelo servidor. `frames=[]` não significa ausência
de bytes recebidos. Nenhuma recusa de acesso ou elegibilidade de corte foi
concluída por aquela coleta.

## Alteração mínima

O novo módulo puro `ssm_close_diagnostic.py` é chamado somente no ramo A→B,
depois da rejeição original. A classe `FrameReader` permanece idêntica à de A4,
assim como o parser `ssm_metadata.py` e o serviço. O wrapper acrescenta o módulo
ao payload em stdin e ao mapa de hashes. O preflight fixa os três hashes novos.

| Fronteira | Contrato da candidata |
| --- | --- |
| Frame elegível | Apenas `close`, rejeitado por `control_payload_over_125`, com comprimento declarado de 126 a 512 bytes |
| Antes de receber | Verificar novamente os limites existentes de frame, contagem, total e o mesmo prazo monotônico; reservar a contagem e os bytes declarados |
| Leitura | Uma tentativa pelo `reader.exact()` existente; nenhum segundo frame, ACK, resposta, ressincronização ou retry |
| Exclusões | `close` de um byte, `ping`, `pong`, tamanho acima de 512 e orçamento/prazo esgotado não leem o payload |
| EOF ou timeout | `complete=false`, estado `incomplete` e motivo de uma lista fechada; payload parcial não é exportado |
| Resultado do protocolo | O motivo continua `control_frame_invalid`; o frame não entra no parser e o socket é fechado pelo `finally` existente |
| C0 | Não faz essa leitura de fechamento inválido; permanece uma observação parcial do protocolo próprio |

Os limites antigos continuam em 32 frames físicos, 64 KiB por frame e 256 KiB
de payload total; o teto adicional de A5 é 512 bytes. O cabeçalho já lido conta
separadamente nos bytes físicos. O prazo de HTTP/observação é limitado depois
de TCP/TLS; não se afirma um SLA global de dez segundos para DNS/TCP/TLS. O
timeout externo não prova o término remoto quando SSH tem resultado ambíguo.

## Projeção pública e limites de interpretação

O payload completo fica somente em memória. Os primeiros dois bytes são
projetados como inteiro sem sinal; o restante passa por decodificação UTF-8
estrita. A saída contém apenas enums, inteiros e booleanos. Não retorna corpo,
texto da razão, objetos JSON do servidor, tokens, URLs, identificadores
literais ou hash do payload.

`typed_error_code` reconhece apenas literais de uma lista fechada em campos
explícitos de código JSON ou no prefixo textual literal `Codigo:`. Chaves JSON
duplicadas, códigos conflitantes, valores desconhecidos e namespaces/prefixos
arbitrários ficam desconhecidos. Isso é uma descrição da forma observada;
não se afirma que o formato ainda desconhecido do servidor seja uma API
documentada, nem se atribui uma camada interna de autorização.

`known_session_context_valid` significa apenas que um token textual exatamente
igual a um dos IDs conhecidos aparece em algum lugar da razão. Não valida um
campo `SessionId` do protocolo. `typed_code_with_session_context` significa
somente código reconhecido mais essa presença textual: não demonstra nexo
causal, que o erro se refere a B, ou recusa de acesso. Os indícios lexicais são
booleanos informativos e podem existir em frases negativas ou ambíguas.

Mesmo um código de fechamento reconhecido, uma mensagem tipada e a presença de
um ID exigem interpretação conjunta com o controle próprio e o contexto real.
`authentication_classified`, `access_classified`, `foreign_access_classified`
e `cutover_eligible` continuam falsos. O estado `diagnostic_complete` descreve
conclusão operacional e cleanup, não um resultado positivo de isolamento.
Nenhum compositor ou consumidor de cutover é alterado por esta candidata.

O RFC 6455 limita controles a 125 bytes e descreve o código de dois bytes seguido
por razão UTF-8 no fechamento. A5 mantém a violação do frame explícita e usa uma
leitura diagnóstica estreita; não passa a aceitá-lo como válido. O significado
do motivo depende da aplicação; o código 1008 é genérico e não atribui IAM.
Fonte primária: [RFC 6455, §§5.5, 5.5.1 e 7.4.1](https://www.rfc-editor.org/rfc/rfc6455).

## Testes focais e execução futura

`python3 test_close_diagnostic.py` executa oito testes focais, com rede externa,
AWS, VPS e processos de plugin substituídos por fixtures. Cobre os limites
126/175/512, segundo frame preservado, tentativa única, exclusões sem leitura,
orçamentos e prazo antes do payload, truncamento/timeout parcial, privacidade,
duplicatas/conflitos/prefixos maliciosos, handler real sem parser inválido,
C0 sem leitura extra e vínculo do helper no mapa do wrapper. O harness anterior
é importado; as baterias antigas não são repetidas.

O recibo e log `auth-a5-fixture-cloud-*` preservam o resultado no ambiente cloud.
O recibo e log sem `cloud` serão produzidos pela execução local no Mac, com os
mesmos fontes. `PREPARED.json` fixa os hashes e a igualdade da classe
`FrameReader` com A4. Nenhuma chamada AWS/VPS ou promoção é feita pelos testes.

Uma eventual promoção precisa preservar A4 e seus recibos, criar o helper novo
exclusivamente, fixar todos os hashes e obter leitura exata. Uma coleta futura
exige autorização coordenada, preflight atual e C0 novo com o mapa de fontes A5
e CURRENT compatíveis. O C0 A4 não é reutilizável com este mapa novo. Esta
preparação não autoriza uma execução real.
