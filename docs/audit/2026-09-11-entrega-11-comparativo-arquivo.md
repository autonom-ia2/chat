# Entrega 11 — a comparação chega como arquivo, não como link

Data: 11/09/2026. Plano: entrega 11 do Agente de Cotação (5 termos de aceite). Issue-mãe: #291.
Branch `feat/entrega-11-comparativo-arquivo`. Depende das entregas 4 (o comparativo sai no
encerramento parcial) e 2 (a placa no bloco `vehicle`).

## O desenho, em uma frase

A ferramenta continua sem conhecer conversa nem mensagem: ela entrega, no lugar do texto
"Comparativo com todas as opções:\n<url>", uma ENTREGA DE ARQUIVO (`Tools::EntregaDeArquivo`, na
forma serializada que atravessa o `Progress`, o handle e os argumentos do `AsyncPublishJob`): a URL
que o portal gerou, o NOME do arquivo ("Comparativo de seguro — placa HIK9383.pdf"), a legenda e a
RESERVA (o texto com o link, palavra por palavra o de antes). Quem baixa é o publicador
(`AsyncPublisher`), na hora de publicar, FORA do lock da conversa, pelo `SafeFetch` (o cliente
HTTP da casa sobre o `ssrf_filter`, rodada 6), com as guardas — o endereço efetivamente conectado
(nada de rede privada, nem por DNS), o status lido ANTES do corpo, teto de tamanho (10 MB,
anunciado e medido em fluxo), PRAZO TOTAL de 20 s (conexão de até 5 s dentro dele; cada leitura
espera só o que resta; abaixo dos 25 s de shutdown do Sidekiq) e assinatura de PDF (`%PDF-`, mais
o tipo declarado que não pode desmentir) —, sem seguir redirecionamento, GRAVA o blob no
armazenamento ainda fora do lock e fora de transação (`EntregaDeArquivo#gravar`, rodadas 3 e 6) e
anexa o blob gravado (pelo `signed_id`) pelo
`Messages::MessageBuilder`, o mesmo caminho do agente humano que manda um arquivo. Quando o
download ou a gravação não entregam um PDF, sai a reserva com o mesmo token de idempotência, e o
motivo (código curto) vai ao log: a falha do arquivo não apaga os preços que já saíram, e nunca é
silenciosa.

### Por que aqui e não na ferramenta

Bytes não cabem no handle nem no Sidekiq (o `AsyncPublishJob` re-enfileira a entrega adiada com os
argumentos do job), e a ferramenta não tem canal para a conversa. O publicador já é quem cria a
mensagem, já decide nota privada × pública, já espera a cadeia humanizada e já é idempotente por
token — o arquivo entra por ali com o menor número de decisões novas. A ordem e as sentinelas do
handle (`DELIVERED_KEY`, `PDF_SENT_KEY`, `CLOSED_KEY`) não mudam: a sentinela do comparativo é
gravada quando a ENTREGA sai da ferramenta, seja qual for a forma em que o publicador a faça chegar.

### O que mudou

- `app/services/autonomia/agents/tools/entrega_de_arquivo.rb` (novo): forma serializada
  (`to_h`/`.de`), validação da forma (https, nome `.pdf` sem separador, legenda e reserva
  presentes), identidade (`arquivo:<url>`) e `#gravar` (download pelo `SafeFetch` desde a rodada 6
  — antes `Down` — com `max_bytes`, `open_timeout`, `total_timeout`, `max_redirects: 0`;
  `Indisponivel` com motivo curto FECHADO: `url_insegura`, `redirecionamento`, `http_<status>`,
  `tamanho`, `tempo`, `download`, `tipo_invalido`, `nao_e_pdf`, `armazenamento`).
- `tools/progress.rb`: a peneira aceita a entrega de arquivo (legenda e reserva passam pela mesma
  regra de texto de cliente; Hash que não é entrega de arquivo é descartado com log).
- `tools/async_publisher.rb`: `publish` reconhece texto ou arquivo; `Corpo` (texto, token, anexo);
  `post_arquivo` baixa fora do lock e cai para a reserva com o mesmo token; `build_message!` passa
  `attachments:` ao `MessageBuilder`.
- `native/insurance_quote/comparativo.rb` (novo concern): `comparison_pdf` (movido da classe, que
  está no teto de linhas) devolve a entrega de arquivo; `nome_do_comparativo` (placa normalizada;
  sem placa, o ramo com espaço no lugar do sublinhado). `LEGENDA`, `RESERVA`, `NOME`.
- `async_run_job.rb`, `async_publish_job.rb`: o argumento passa a chamar-se `entrega` (texto ou
  forma serializada); nenhuma lógica nova — a forma já era serializável.

### Rodada 2 (revisão cega, achado P2): a forma que a entrega recusa

O adapter só garante que o comparativo vem numa URL (`z.string().url()`, `http/quote.ts`); https
não é promessa dele. `comparison_pdf` montava a `EntregaDeArquivo` e serializava SEM conferir
`valida?`, e o Hash inválido morria adiante com dois sintomas: no caminho da consulta (`apply`) o
`Progress` o descartava com a sentinela `PDF_SENT_KEY` já gravada — o cliente sem arquivo e sem
link, e a execução dizendo "comparativo enviado"; no encerramento (`closing_deliveries`, que NÃO
passa pelo `Progress`) o publicador só descartava texto em branco, e o `to_s` do Hash chegava ao
cliente como mensagem literal. Duas guardas, na causa raiz:

- `Comparativo#entrega_do_comparativo`: monta a entrega; se `valida?` reprova, devolve a RESERVA
  (o texto com o link, o de antes) e registra `comparativo sem forma de arquivo … defeito=<campo>;
  vai como link`. A falha da forma não apaga a entrega.
- `AsyncPublisher#nada_a_publicar`: o que não é texto nem entrega de arquivo reconhecida
  (`EntregaDeArquivo.de` → nil) é `Result(:skipped)` com `entrega descartada run=… não é texto nem
  arquivo (<Classe>)` — nunca `to_s` para a conversa. A guarda passa a existir onde a mensagem é
  criada, e não só no `Progress`.
- `EntregaDeArquivo#defeito`: o campo que reprovou a forma (`url`, `nome`, `legenda`, `reserva`),
  para o log dizer o quê sem a URL nem o texto; `valida?` = `defeito.nil?`. `Result#skipped?`.

### Rodada 3 (revisão cega: 1 P2 + 3 P3): a falha do ANEXO, o redirect, o tempfile e o lock

**P2 — a reserva só cobria o DOWNLOAD.** O upload do blob ao armazenamento acontecia no
`after_commit` da mensagem (é assim que o ActiveStorage sobe um `UploadedFile`), fora do
`rescue Indisponivel` de `post_arquivo`: download 200 com PDF válido → mensagem COMMITADA com a
legenda e o `Attachment` → upload falha (S3/IAM fora) → exceção que não é `Indisponivel` →
`publish` devolve `:blocked`. Sonda do revisor: mensagens = [preço, LEGENDA], 1 anexo órfão (blob
nunca gravado), `PDF_SENT_KEY=true`, nenhum link, nenhum retry (o token já postado faria o retry
virar duplicado). Era o "NÃO: anexo que só funciona quando tudo dá certo". Causa raiz: a
materialização do anexo estava fora da fronteira de reserva. Correção:

- `EntregaDeArquivo#gravar` (novo): `baixar` → `ActiveStorage::Blob.create_and_upload!(io:,
  filename:, content_type: TIPO_PDF, identify: false)` dentro de `ActiveStorage::Blob.transaction`
  (o `create_and_upload!` salva a linha ANTES de subir o arquivo, para evitar colisão de chave; a
  transação é o que faz a subida que falha não deixar linha de blob sem arquivo) → qualquer
  `StandardError` vira `Indisponivel('armazenamento', causa: <classe da exceção>)`. O tempfile é
  fechado no `ensure`, gravado ou não.
- `AsyncPublisher#post_arquivo`: `blob = arquivo.gravar` (fora do lock) e `anexo: blob.signed_id`
  no `Corpo` — `Messages::MessageBuilder#attachment_file_type` já aceita `signed_id`, e
  `has_one_attached` resolve por `find_signed!`; como o blob já está no armazenamento, o
  `after_commit` da mensagem não sobe nada. A falha da gravação cai no MESMO `rescue Indisponivel`
  do download → reserva com o mesmo token. O blob que não virou anexo (retry que encontrou a
  mensagem no ar; `post` que levantou) é apagado no `ensure` — gravado antes da mensagem, ele não
  tem dono até ela existir.
- Guardas (termo 3, caminho de falha do ANEXO): `async_publisher_spec` "cai para o texto com o
  link quando o armazenamento falha depois do download, sem anexo orfao" (serviço de armazenamento
  levantando `Errno::ECONNREFUSED` depois de um 200 → mensagem = RESERVA + url, sem anexo,
  `ActiveStorage::Blob.count == 0`, mesmo token, log `motivo=armazenamento
  causa=Errno::ECONNREFUSED; vai como link`); `async_run_job_comparativo_arquivo_spec` "entrega o
  link em texto pela consulta quando o armazenamento falha depois do download" (caminho `apply`,
  poll `done`: [preço, RESERVA + url], sem anexo nem blob, `PDF_SENT_KEY` true, `delivered_count`
  2, `done`); `entrega_de_arquivo_spec` `#gravar` (blob gravado com nome/tipo/bytes e
  `find_signed!`; falha da subida → `armazenamento` + causa, sem linha de blob; download recusado
  → nada gravado); retry "nao publica de novo…" agora afirma `Blob.count == 0`.

**P3 — "só https" valia só para o primeiro salto.** `max_redirects: 2` seguia um 302 para
`http://`. Correção: `REDIRECIONAMENTOS = 0` (o blob do portal é servido direto) e
`Down::TooManyRedirects` → `Indisponivel('redirecionamento')`. Guarda: "recusa o redirecionamento,
sem seguir para onde ele aponta" (302 → http stubado com 200 PDF; `Indisponivel` e
`a_request(:get, destino)` nunca feita); "baixa com teto de tempo, de tamanho e sem
redirecionamento" afirma `max_redirects: 0` no `Down.download`.

**P3 — tempfile aberto até o GC na recusa.** `conferir_tipo!`/`conferir_assinatura!` levantavam
com o tempfile (até 10 MB) em disco, e o `ensure` de `post_arquivo` não o alcançava (`pdf` nil).
Correção: `conferir(tempfile)` fecha (`close!`) e relança na recusa; `gravar` fecha no `ensure`.
`baixar` devolve o `Tempfile` (quem recebe, fecha); o `UploadedFile` não existe mais. Guardas:
"fecha e apaga o arquivo temporario quando recusa o que baixou", "…depois de gravar", "…tambem
quando a subida falha" (o tempfile é capturado com `and_wrap_original` no `Down.download` e
`path` tem de ser nil).

**P3 — "baixa fora do lock" era comentário, não regra.** Guarda: "baixa e grava o arquivo antes
de travar a conversa" — assinatura em `sql.active_record`: nenhum SQL com `FOR UPDATE` pode ter
saído antes de o `Down.download` começar, e algum tem de sair depois (a publicação trava).

**Fato novo do orquestrador (11/09 11:00Z), corrigindo a seção "O ACHADO" abaixo:** o 404
`BlobNotFound` do `quote/proposal` NÃO existe em produção — os 4 comparativos enviados na conversa
real (10/09 20:30, 11/09 06:55/08:04/08:49) abrem (206, `application/pdf`). O 404 veio de testar a
URL como a CLI a imprime: `emitir` redige o nome do arquivo (ele contém o NOME DO SEGURADO) e a URL
vira `…/files/<REDACTED>.pdf`. Não há defeito no adapter; nenhuma issue. O que fica registrado: o
nome do arquivo no portal carrega o nome do segurado — dado pessoal na URL do portal, fora do
nosso controle —, e o NOSSO nome de arquivo continua sendo só a placa (termo 5). Os comentários
de código e de spec que afirmavam "404 real" foram corrigidos.

### Rodada 4 (revisão cega, veredito APROVADO com 1 P3): a limpeza do blob sem dono

**P3 — o `purge` do `ensure` era síncrono e podia levantar.** `ActiveStorage::Blob#purge`
(7.2.3.1) faz `destroy` (apaga a linha) e depois `delete` (apaga o arquivo no serviço), e o
`delete` do S3 não engole erro de rede. Sonda do revisor (S2): a primeira publicação sai como
anexo; o retry grava um segundo blob, encontra a mensagem no ar (`:duplicate`) e, no `ensure`, o
`delete` acha o armazenamento fora → a exceção sai do `ensure` por cima do resultado → `publish`
rescue → `Result(:blocked)` e "publish failed" no log para uma entrega que JÁ está no ar (1
mensagem, sequência 1), com o arquivo do retry órfão (a linha foi destruída antes do `delete`). No
caminho em que `post` levantou (S1), um purge que falhe TROCA a exceção original: o log passa a
apontar a classe do erro do purge, não a causa da publicação. Sem impacto no cliente, mas era
regra sem guarda: nenhum spec cobria o purge que levanta. Causa raiz: a limpeza falava com o
armazenamento na hora, dentro do `ensure`, no mesmo fluxo cujo resultado ela não pode alterar.
Correção (decisão do orquestrador): `blob.purge_later` — o caminho que o próprio Rails documenta
para "transaction, callback or any other real-time scenario". O `ActiveStorage::PurgeJob` vai
para a fila `default` do Sidekiq — `queue_as { ActiveStorage.queues[:purge] }`, e
`config.active_storage.queues.purge` não está configurado nesta instalação (a fila
`active_storage_purge` existe em `config/sidekiq.yml`, mas nada a usa; a rodada 4 escreveu o nome
errado, corrigido na rodada 5) — e o Sidekiq retenta o job que falhar. Registro honesto do limite: se o `delete` falhar DEPOIS do `destroy`
dentro do job, o retry seguinte encontra `RecordNotFound` (o `PurgeJob` descarta) e o arquivo fica
órfão no armazenamento — é a mesma limitação do `Blob#purge` de sempre, agora sem custar uma
mensagem nem um log com a causa errada.

Guardas (`async_publisher_spec`, "entrega de arquivo"):
- "mantem a entrega publicada quando o armazenamento falha ao apagar o blob do retry" (S2 do
  revisor: primeira publicação como anexo; `ActiveStorage::Blob.service.delete` levantando
  `Errno::ECONNREFUSED`; retry → `published`, 1 mensagem, nenhum "publish failed" no log,
  `PurgeJob` enfileirado uma vez, e a linha do blob do retry inteira — `Blob.count == 2` — nada
  destruído pela metade);
- "registra a causa da publicacao que levantou, e nao a da limpeza do blob" (S1:
  `Messages::MessageBuilder.new` levantando `ActiveRecord::ConnectionTimeoutError` e o `delete`
  levantando → `blocked`, 0 mensagens, log `publish failed run=<id>
  ActiveRecord::ConnectionTimeoutError`, `PurgeJob` enfileirado uma vez);
- "nao publica de novo o que ja saiu…" ajustado: afirma `PurgeJob` enfileirado uma vez e
  `Blob.count == 0` DEPOIS de `perform_enqueued_jobs(only: ActiveStorage::PurgeJob)`.

RED confirmado antes da implementação: os 3 exemplos falhando pelos motivos certos (0 jobs
enfileirados; `blocked` em vez de `published`; log com `Errno::ECONNREFUSED`), 20 antigos
passando (`e11r4/red.json`). Nada mais mudou nesta rodada.

### Rodada 5 (revisão cega, veredito APROVADO com 5 P3 — última passada): as frestas do "só quando tudo dá certo"

**P3 — o Down não classifica tudo, e `baixar` prometia "qualquer falha".** `request_error!`
(Down 5.4.0) só dá classe do Down a tempo, `SystemCallError`, `EOFError`/`IOError`/`SocketError`
e SSL; uma resposta HTTP malformada (`Net::HTTPBadResponse`), `Net::WriteTimeout` ou erro de
`Zlib` sobem crus. Sonda do revisor (P5, WebMock `to_raise(Net::HTTPBadResponse)`): `publish` →
`blocked`, 0 mensagens — nem arquivo nem link, com `PDF_SENT_KEY` já gravada no caminho `apply`.
Era o "NÃO" do termo por uma fresta estreita. Causa raiz: o contrato do método cobria a lista do
Down, não "qualquer falha". Correção: a transferência (`#transferir`, privado) separada da
conferência (`#baixar` = `conferir(transferir)`), porque os rescues da transferência não podem
alcançar `conferir` (que levanta `Indisponivel` com o motivo dela — um `rescue StandardError` no
mesmo corpo reembrulharia `nao_e_pdf` como `download`); em `transferir`, depois dos rescues
específicos, `rescue StandardError => e → Indisponivel.new('download', causa: e.class.name)` — o
mesmo padrão de `gravar` para o armazenamento. Guardas: `entrega_de_arquivo_spec` "recusa com
motivo `download` e a classe da causa quando a camada HTTP levanta o que o Down nao classifica";
`async_publisher_spec` "cai para o texto com o link quando a camada HTTP levanta o que o Down nao
classifica" (`published`, mensagem = reserva, sem anexo, log `motivo=download
causa=Net::HTTPBadResponse; vai como link`). Mutação N1.

**P3 — o AGENDAMENTO da limpeza também fala com o Redis, dentro do `ensure`.** A rodada 4 tirou o
`delete` síncrono do `ensure`, mas `purge_later` enfileira o `PurgeJob` — e o Redis fora no meio
do job Sidekiq (sondas P2/P2b do revisor: `PurgeJob.perform_later` levantando `Errno::ECONNREFUSED`)
reproduzia a MESMA classe do P3 fechado: retry devolvendo `blocked` para uma entrega já no ar, e
a causa da publicação trocada pela do enfileiramento. Correção: `agendar_limpeza(blob)` —
`purge_later` com `rescue StandardError` que REGISTRA (`blob sem dono nao agendado run=… blob=<id>
causa=<classe>`) e não levanta: a limpeza é cortesia e não pode alterar o resultado; o id do
blob no log é o que permite a limpeza manual. Guardas (`async_publisher_spec`): "mantem a entrega
publicada quando a fila nao aceita a limpeza do blob do retry" (`published`, 1 mensagem, nenhum
"publish failed", log do blob sem dono, `Blob.count == 2`); "registra a causa da publicacao que
levantou tambem quando a fila nao aceita a limpeza" (`blocked`, log `publish failed …
ActiveRecord::ConnectionTimeoutError` E a linha do blob sem dono). Mutações N2 (rescue removido)
e N2b (rescue sem registro).

**P3 — a fila do `PurgeJob` é `default`, não `active_storage_purge`.** Sonda P1 do revisor no
ambiente real: `ActiveStorage::PurgeJob.new(blob).queue_name == "default"`; não existe
`config.active_storage.queues.purge` em `config/` nem `lib/`. Sem defeito funcional (a fila
`default` é consumida pelo Sidekiq); era prosa apontando o operador para a fila errada. Corrigidos
o comentário de `post_arquivo` e o registro da rodada 4 acima. A alternativa maior
(`config.active_storage.queues.purge = :active_storage_purge` em `config/application.rb`) muda o
roteamento de TODO purge da app e fica fora desta PR, como decidiu o orquestrador.

**P3 — a reserva passava pela peneira só como intenção.** A mutação V5 do revisor
(`reserva = entrega.reserva`, sem `texto()`, em `Progress#arquivo`) sobrevivia a 79 exemplos:
só a legenda tinha spec. Guarda: `progress_spec` "descarta o arquivo cuja reserva levaria caminho
de campo ao cliente" (reserva `"Faltou insured.document\n<url>"` — a URL sai antes de olhar, e o
caminho de campo que sobra reprova). Mutação V5.

**P3 — "o blob ANEXADO nunca é apagado" tinha guarda só indireta.** A mutação V2 do revisor
(`purge_later if blob`, sem `&& !anexado` — em produção apagaria o PDF de toda mensagem entregue
minutos depois) reprovava 1 de 28, e não o exemplo que fala do anexo: com o `PurgeJob` só
enfileirado, `anexo.file.download` ainda funciona. Guarda direta: `expect(ActiveStorage::PurgeJob)
.not_to have_been_enqueued` em "publica o PDF como anexo" (publisher) e "entrega o comparativo como
anexo…" (job). Mutação V2.

RED confirmado antes da implementação (`e11r5/red.json`): 4 exemplos falhando pelos motivos
certos (`Net::HTTPBadResponse` cru; `blocked` ×2; log sem a causa da publicação), 60 antigos
passando; os dois specs-guarda (anexo sem `PurgeJob`; reserva com caminho de campo) já passavam
no código atual — o que eles provam é pela mutação. Nada além dos cinco achados mudou.

### Rodada 6 (revisão do Codex sobre `67bdc99454`: 2 P1 + 4 P2 + 1 P3 + 1 ressalva): a rede, o corpo, o tempo, o anexo

O que as cinco rodadas anteriores tinham deixado como INTENÇÃO no download, o Codex apontou como
regra sem guarda — e duas delas eram de segurança. Todas as decisões abaixo são do orquestrador;
cada correção veio com spec e mutação. O que se corrigiu de prosa: os comentários e esta auditoria
prometiam "tetos de tempo (5 s + 15 s)" e "termina em 20 s" quando o teto era POR LEITURA — um
servidor que entrega um byte por segundo nunca o estourava.

**P1 — SSRF: `URL_SEGURA` só conferia o esquema.** `Down.download` não bloqueia IP privado nem um
nome que resolve para dentro (DNS rebinding): a URL vem do portal, e um `https://10.0.0.7/x.pdf`
ou um `https://nome-que-resolve-para-169.254.169.254/x.pdf` levaria o worker a ler o que não deve
e a anexar a resposta com nome de PDF. Causa raiz: a forma protegia o transporte, não o destino.
Correção: o download passa a ser `SafeFetch.fetch` (lib da casa sobre `ssrf_filter` 1.5.0, a
mesma do upload por URL, do avatar e dos webhooks), que resolve o nome ANTES de conectar, recusa
endereço privado (v4, v6, mapeados, NAT64, metadata da nuvem) e conecta no IP validado
(`ipaddr:`), sem TOCTOU de DNS. As nossas conferências continuam (tipo declarado, assinatura
`%PDF-`, teto de bytes). Motivo fechado `url_insegura` (também para esquema inválido). Guardas
(`entrega_de_arquivo_spec`, "o endereco"): IPv4 privado, IPv6 privado (`[fd00::1]`) e nome que
resolve para `10.0.0.7` → `url_insegura` e NENHUM pedido feito ao destino (`a_request … not_to
have_been_made`). Mutação S1 (voltar ao `Down`/`URL_SEGURA`).

**P1 — o teto de bytes não valia para o corpo de um 404/302.** O open-uri (por baixo do Down) lê o
corpo INTEIRO antes de o Down levantar `NotFound`/`TooManyRedirects`: um 404 de 1 GB do portal
seria materializado em memória só para ser recusado. E o `SafeFetch` de antes tinha a MESMA fresta,
por outro caminho: o bloco do `Net::HTTP` fazia `next unless Net::HTTPSuccess`, e depois do bloco
o Net::HTTP lê o corpo inteiro (`HTTPResponse#reading_body` → `body`) — a menos que o bloco
LEVANTE. Correção no `SafeFetch::Fetcher` (retrocompatível: mesma classe e mesma mensagem de erro,
só mais cedo): a resposta que não é 2xx — e não é um 3xx que o ssrf_filter vai seguir — é recusada
DENTRO do bloco (`HttpError`, agora com `#status` inteiro), o que fecha a conexão sem consumir o
corpo; o `Content-Length` acima do teto reprova antes do primeiro byte; o corpo é lido em fluxo,
pedaço a pedaço, para o `Tempfile` do `SafeFetch` (fechado em `ensure` em TODO caminho — o
temporário deixou de ser da entrega), e interrompido ao passar de `max_bytes`. Guardas:
`safe_fetch_spec` "raises before the body of the non-2xx response is read" (uma resposta 404 cujo
`body` marca se foi lido, com o `SsrfFilter.get` emulando o `reading_body` do Net::HTTP: bloco,
depois `body`) e, em SOCKET REAL, "closes the connection instead of reading the body" (servidor
local respondendo 404 com `Content-Length` de 32 MB: o cliente recusa e o servidor conta quantos
bytes conseguiu escrever antes de a conexão cair — tem de ser menos que o total);
`entrega_de_arquivo_spec` "e recusada pelo status, e a conexao e fechada sem materializar o
corpo" (o mesmo servidor, pela entrega: `http_404`). Mutações S2 (voltar ao `next unless`) e S2b
(tamanho anunciado não conferido).

**P2 — sem prazo total.** `open_timeout` + `read_timeout` são por OPERAÇÃO; uma resposta que
chega em pedaços com pausas menores que o `read_timeout` segura o worker além dos 25 s de shutdown
do Sidekiq, e o comentário dizia "termina em 20 s". Correção: `SafeFetch` ganha `total_timeout:`
(`SafeFetch::Deadline`, monotônico), e a entrega passa `PRAZO_TOTAL_SEGUNDOS = 20` (constante
nomeada; `LEITURA_SEGUNDOS` deixou de existir — o prazo total é o teto de qualquer leitura). Cada
leitura do corpo espera SÓ O QUE RESTA: o Net::HTTP guarda o `read_timeout` no `Net::BufferedIO`
da conexão e o consulta a cada espera (`rbuf_fill`), então o `Fetcher` aperta o `read_timeout`
desse socket entre um pedaço e o próximo (`response.instance_variable_get(:@socket)` — o Net::HTTP
0.9.1 não expõe o socket da resposta, e esta é a única alavanca por leitura que existe sem trocar
o cliente HTTP; o acoplamento está registrado no código e a guarda é o spec de socket real). Os
tetos por operação são limitados pelo total já na conexão e na espera pelos cabeçalhos
(`RequestOptions#bounded_by_total`). Estourou → `TotalTimeoutError` (um `FetchError`, para quem já
trata rede) → motivo `tempo`. O que o prazo NÃO cobre, registrado: a resolução de DNS (antes da
conexão, no `Resolv` do sistema). Guardas em socket real (servidor local que manda 10 bytes, e
mais 10 depois de 0,3 s, 0,6 s e 1,2 s; prazo de 1 s): `safe_fetch_spec` "raises TotalTimeoutError
when the total is up, waiting on each read only what is left" e `entrega_de_arquivo_spec` "e
recusada por tempo ao vencer o prazo total, esperando em cada leitura so o que resta" — as duas
afirmam `motivo == tempo` E tempo decorrido < 1,6 s: com o prazo conferido só entre pedaços a
recusa viria aos 2,1 s (o pedaço seguinte), e sem prazo o download terminaria. Mutações S3 (prazo
removido da entrega), S3f (`enforce!` removido do `Fetcher`), S3b (socket não apertado), S3c
(tetos por operação não limitados pelo total).

**P2 — falha ao ANEXAR sem reserva.** Download e gravação bons, e o `post` do anexo levanta: a
exceção saía de `post_arquivo` sem passar pelo `rescue Indisponivel` → `publish` → `blocked`,
nem arquivo nem link. Correção: `publicar_anexo` — qualquer `StandardError` no `post` do anexo é
seguido de RECONCILIAÇÃO pelo token: se `delivery_posted?` → a mensagem existe (a exceção veio
DEPOIS do commit: um `after_commit` da mensagem, o evento que vai ao Redis) → `published` sem
mensagem nova, e o blob tem dono se está anexado a ela (`blob.attachments.exists?` — o retry
concorrente que perdeu a corrida fica sem dono e vai para a limpeza); senão → log `anexo falhou
run=<id> causa=<classe>; vai como link` e a RESERVA com o mesmo token. Se a reserva também
levanta, `publish` devolve `blocked` como sempre. Guardas (`async_publisher_spec`): "cai para o
texto com o link quando o anexo nao pode ser publicado, com um so token e o blob na limpeza"
(`MessageBuilder` levantando `RecordInvalid` só quando há anexo → 1 mensagem = reserva, mesmo
token, `PurgeJob` uma vez) e "mantem a mensagem com o anexo, sem reserva e sem limpeza, quando a
publicacao levanta depois do commit" (o `dispatcher` levantando `Redis::CannotConnectError` no
`message.created` da mensagem com anexo → `published` sem mensagem nova, 1 mensagem com o PDF,
sequência 1, `PurgeJob` NÃO enfileirado, nenhum "publish failed"/"anexo falhou"). O P3 do Codex
(exceção após o commit) é este segundo exemplo. Mutações S4a (sem reconciliação nem reserva) e S4b
(reserva sem reconciliar).

**P2 — upload ao S3 dentro da transação, e blob órfão.** `create_and_upload!` dentro de
`Blob.transaction` segurava a conexão do banco durante a subida ao S3 (os timeouts do cliente S3
são os padrões do aws-sdk — ressalva registrada). Correção: duas fases — `build_after_unfurling`
+ `blob.save!` (um INSERT, na transação curta dele) e `upload_without_unfurling(io)` FORA de
transação; a subida que levanta manda a linha sem arquivo para a limpeza em segundo plano
(`EntregaDeArquivo.agendar_limpeza(blob, contexto: 'gravacao')` — o `agendar_limpeza` do
publicador virou este método de classe, com `contexto: "run=<id>"`, para não duplicar o rescue do
Redis) e recusa `armazenamento` com a classe da causa. Guardas (`entrega_de_arquivo_spec`, "a
gravacao"): "sobe o arquivo fora de transacao" (`open_transactions` durante o `upload` igual ao de
antes de `gravar` — só a do fixture), "recusa … e manda a linha sem arquivo para a limpeza"
(`PurgeJob` uma vez; depois de `perform_enqueued_jobs`, nenhum blob), "mantem o motivo do
armazenamento quando a fila nao aceita a limpeza". Os specs do publicador e do job que afirmavam
`Blob.count == 0` na falha do armazenamento passaram a afirmar `PurgeJob` enfileirado e zero
blobs depois de executá-lo. Mutações S5 (subida dentro de transação) e S5b (volta ao
`create_and_upload!` em transação).

**P2 — cabeçalho externo no log.** `tipo_text_html` levava o valor do `Content-Type` do servidor
para dentro do código do motivo. Correção: motivo fechado `tipo_invalido`. Guardas: o spec da
entrega afirma o motivo e que a mensagem da exceção não carrega `html`/`charset`; o do publicador
afirma que nenhum `warn` contém `text/html`, `text_html` ou `charset`. Mutação S6.

**Ressalva — "baixa e grava antes de travar" só observava o INÍCIO do download.** Correção: o spec
observa a ORDEM de três eventos (`SafeFetch.fetch` começa, `Blob.service.upload` acontece, o
primeiro `FOR UPDATE` sai) e exige `[download, gravacao, trava]`. Mutações S8 (só a gravação
dentro do lock) e R5 (download e gravação dentro do lock).

**O que mudou no `SafeFetch` (lib da casa, retrocompatível; specs próprios em `safe_fetch_spec`):**
opções novas `max_redirects:` (padrão o do ssrf_filter, 10; validado inteiro ≥ 0) e
`total_timeout:` (padrão nil; validado > 0); `HttpError#status`; `TotalTimeoutError < FetchError`;
`SafeFetch::Deadline` (novo arquivo); recusa do não-2xx dentro do bloco; `Content-Length` acima do
teto reprova antes do corpo; `PrivateNetworkRequest` honra `max_redirects`. Os 7 consumidores
existentes (upload por URL, avatar, executor HTTP das ferramentas, processador de link da base de
conhecimento, mídia do Twilio, branding de site, webhooks/CRM) não mudam de comportamento: 109
exemplos deles rodados antes e depois, 0 falhas.

**Como os specs de socket real funcionam (e o seu limite):** `spec/support/servidor_http_local.rb`
sobe um `TCPServer` em 127.0.0.1 que atende UMA conexão e executa um roteiro (cabeçalhos, pedaços,
pausas), contando os bytes que conseguiu escrever. O WebMock, mesmo para a conexão real permitida
em localhost, lê a resposta INTEIRA antes de entregá-la ao bloco do Net::HTTP (`super(request,
nil, &nil)` no adapter) — nem o tempo nem o fechamento do socket seriam observáveis —, então
esses exemplos o desligam (`WebMock.disable!`/`enable!`) e usam `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`
para o `SafeFetch` aceitar 127.0.0.1: é o caminho `PrivateNetworkRequest`, e não o `SsrfFilter.get`
de produção, mas o `Fetcher` (bloco, prazo, teto, tempfile) é o mesmo nos dois; o caminho do
`SsrfFilter.get` é o exercitado por todos os outros exemplos, via WebMock. A forma da entrega exige
https e o servidor local só fala http: esses exemplos constroem a entrega direto (sem `.de`) e
provam o download, não a forma.

### Termos (5)

| # | Termo | Guarda / evidência |
|---|---|---|
| 1 | A comparação chega como ARQUIVO na conversa | `async_run_job_comparativo_arquivo_spec` ("entrega o comparativo como anexo, nomeado pela placa, e depois o fecho": job real + ferramenta real + conector mock + WebMock 200 → `Message` com `Attachment` `file`, `application/pdf`, bytes iguais, legenda sem URL); `async_publisher_spec` "publica o PDF como anexo" |
| 2 | Falha no download não apaga os preços; o link vai como hoje | job spec "cai para o link quando o download falha, sem apagar o preco que ja saiu" (preço publicado ANTES pelo publicador real fica; `delivered_count` igual; texto = `RESERVA + "\n" + url`, o de antes); M1. Rodada 2: URL que a forma recusa → job spec "entrega o link em texto pela consulta…" (caminho `apply`: link em texto, `PDF_SENT_KEY` true, `delivered_count` 2, `done`) e comparativo spec "quando a URL do portal nao tem a forma segura"; M7. Rodada 3: falha do ANEXO (armazenamento) → job spec "…quando o armazenamento falha depois do download" e publisher spec "…sem anexo orfao"; R1 |
| 3 | Exemplo automatizado do caminho de falha | os três exemplos de falha do job spec (404, HTML, armazenamento) + `async_publisher_spec` "cai para o texto com o link… e registra o motivo" (log `motivo=http_404`), "…quando o armazenamento falha…" (log `motivo=armazenamento causa=…`), "…quando o tipo declarado desmente o PDF…" (`tipo_invalido`) e "…quando o anexo nao pode ser publicado…" (`anexo falhou`) + 15 exemplos de recusa em `entrega_de_arquivo_spec` (inclusive 302, IP privado, DNS para dentro, 404 de 32 MB em socket real, prazo total em socket real e armazenamento) |
| 4 | O arquivo abre no WhatsApp de verdade | **pendente_prova_real** (orquestrador; ver "Produção") |
| 5 | O nome diz o que ele é, sem dado pessoal além do que o cliente já vê | `insurance_quote_comparativo_arquivo_spec` (placa `hik-9383` → "Comparativo de seguro — placa HIK9383.pdf"; sem CPF/CEP no nome; sem placa → ramo); M2 |
| NÃO | Anexo que só funciona quando tudo dá certo | o caminho de falha é exemplo (termo 3) e a reserva é a mesma identidade (M5); Hash que não é entrega nunca vira mensagem (`async_publisher_spec` "descarta, registrado e sem mensagem…", M8); a falha do ARMAZENAMENTO cai na mesma reserva que a do download (R1), sem mensagem com anexo órfão; a falha ao ANEXAR é reconciliada pelo token e cai na reserva (S4a/S4b), e a exceção depois do commit não duplica nem apaga (rodada 6) |

### Mutações (11/09/2026, `mutacoes.py` no scratchpad: edita → roda → restaura → md5 conferido)

| # | Mutação | Reprova |
|---|---|---|
| M1 | Fallback removido: `post_arquivo` sem o `rescue Indisponivel` (levanta em vez de cair para o link) | 3 exemplos (publisher "cai para o texto…", job "cai para o link…" ×2) |
| M2 | Nome genérico: `nome_do_comparativo` devolve `'comparativo.pdf'` | 4 exemplos (3 do nome, 1 do job) |
| M3 | Teto de tamanho removido: `Down.download` sem `max_size` | 3 exemplos (anunciado, medido, tetos passados ao Down) |
| M4 | Assinatura de PDF não conferida | 1 exemplo (HTML com `Content-Type: application/pdf`) |
| M5 | Identidade do arquivo trocada pelo texto (token do link ≠ token do arquivo) | 1 exemplo (token = `delivery_token(identidade)`) |
| M6 | `Progress` aceita qualquer Hash como entrega | 1 exemplo (Hash que não é arquivo é descartado) |

Rodada 2 (`mutacoes_e11_r2.py`: M1–M6 repetidas depois do refactor de `publish`, mais M7 e M8;
todas reprovam, md5 conferido antes/depois; `mutacoes_r2.json`):

| # | Mutação | Reprova |
|---|---|---|
| M1–M6 | as mesmas da rodada 1 | 3, 4, 3, 1, 1, 3 exemplos — nada afrouxou |
| M7 | Comparativo sem a guarda de forma (`return entrega.to_h` sem `if entrega.valida?`) | 2 exemplos (comparativo spec "…registra o defeito da forma"; job spec "entrega o link em texto pela consulta…") |
| M8 | Publicador sem a guarda (volta ao `entrega.to_s.strip.blank?` de antes: o Hash vira mensagem) | 1 exemplo (publisher "descarta, registrado e sem mensagem, um Hash que nao e entrega de arquivo") |

Rodada 3 (`mutacoes_e11_r3.py` no scratchpad: edita → roda → restaura → md5 conferido;
`mutacoes_r3.json`). R1–R7 são as regras novas desta rodada; M1–M8 são as da rodada 2, com o
texto reajustado ao código atual — nada afrouxou. Cada linha: exemplos que reprovam / rodados.

| # | Mutação | Reprova |
|---|---|---|
| R1 | (P2) rescue do armazenamento removido: a falha do upload sobe crua (publish -> blocked) | 4 de 47 |
| R2 | (P3) redirecionamento seguido de novo (max_redirects 2) | 2 de 21 |
| R3 | (P3) tempfile nao fechado na recusa (rescue de conferir removido) | 1 de 21 |
| R4 | (P3) tempfile nao fechado depois de gravar (ensure removido) | 2 de 21 |
| R5 | (P3) download e gravacao movidos para dentro do lock da conversa | 1 de 21 |
| R6 | blob sem dono nao apagado (purge removido) | 1 de 21 |
| R7 | transacao em volta do create_and_upload! removida (linha de blob sem arquivo sobrevive) | 1 de 21 |
| M1 | fallback removido: post_arquivo sem o rescue Indisponivel | 6 de 26 |
| M2 | nome generico do arquivo | 4 de 11 |
| M3 | teto de tamanho removido | 3 de 21 |
| M4 | assinatura de PDF nao conferida | 2 de 21 |
| M5 | identidade do arquivo trocada pela legenda | 2 de 21 |
| M6 | Progress aceita qualquer Hash como entrega | 3 de 10 |
| M7 | comparativo sem a guarda de forma (Hash invalido sai mesmo assim) | 2 de 11 |
| M8 | publicador sem a guarda (o to_s do Hash vira mensagem, como antes) | 1 de 21 |

Rodada 4 (`e11r4/mutacoes_e11_r4.py` no scratchpad: edita → roda → restaura → md5 conferido
antes/depois nos 4 arquivos de código; `mutacoes_r4.json`). Q1 e Q2 são as regras novas; R1–R7 e
M1–M8 repetidas (R6 com o texto reajustado ao `purge_later`) — nada afrouxou. Cada linha:
exemplos que reprovam / rodados.

| # | Mutação | Reprova |
|---|---|---|
| Q1 | (P3) volta ao purge síncrono cru (`blob.purge` no `ensure`) | 3 de 23 (os dois novos + "nao publica de novo…") |
| Q2 | purge síncrono engolido em `rescue` no `ensure` (some o agendamento; o blob sem dono fica) | 3 de 23 |
| R1 | rescue do armazenamento removido | 4 de 49 |
| R2 | redirecionamento seguido de novo | 2 de 21 |
| R3 | tempfile não fechado na recusa | 1 de 21 |
| R4 | tempfile não fechado depois de gravar | 2 de 21 |
| R5 | download e gravação dentro do lock | 1 de 23 |
| R6 | blob sem dono não apagado (`purge_later` removido) | 3 de 23 |
| R7 | transação do `create_and_upload!` removida | 1 de 21 |
| M1 | fallback removido (sem `rescue Indisponivel`) | 6 de 28 |
| M2 | nome genérico do arquivo | 4 de 11 |
| M3 | teto de tamanho removido | 3 de 21 |
| M4 | assinatura de PDF não conferida | 2 de 21 |
| M5 | identidade do arquivo trocada pela legenda | 2 de 23 |
| M6 | Progress aceita qualquer Hash | 3 de 10 |
| M7 | comparativo sem a guarda de forma | 2 de 11 |
| M8 | publicador sem a guarda | 1 de 23 |

Rodada 5 (`e11r5/mutacoes_e11_r5.py` no scratchpad: edita → roda → restaura → md5 conferido
antes/depois nos 4 arquivos de código; `mutacoes_r5.json`). N1, N2, N2b, V2 e V5 são as regras
novas; Q1–Q2, R1–R7 e M1–M8 repetidas (R6, Q1 e Q2 com o texto reajustado ao `agendar_limpeza`;
M3 ao `transferir`) — nada afrouxou. Cada linha: exemplos que reprovam / rodados.

| # | Mutação | Reprova |
|---|---|---|
| N1 | rescue do que o Down nao classifica removido: a excecao crua sobe (publish -> blocked, nem arquivo nem link) | 2 de 48 |
| N2 | rescue do agendamento da limpeza removido: o Redis fora sobrescreve o resultado / a causa | 2 de 26 |
| N2b | agendamento engolido sem registro (rescue sem warn) | 2 de 26 |
| V2 | o blob ANEXADO tambem vai para a limpeza (sem && !anexado): em producao apagaria o PDF de toda mensagem entregue | 3 de 31 |
| V5 | a reserva da entrega de arquivo nao passa pela peneira de texto de cliente | 1 de 11 |
| Q1 | volta ao purge sincrono cru (a falha do delete sobrescreve o resultado do post) | 5 de 26 |
| Q2 | purge sincrono engolido em rescue no ensure (some o agendamento; o blob sem dono fica) | 5 de 26 |
| R1 | rescue do armazenamento removido: a falha do upload sobe crua (publish -> blocked) | 4 de 53 |
| R2 | redirecionamento seguido de novo (max_redirects 2) | 2 de 22 |
| R3 | tempfile nao fechado na recusa (rescue de conferir removido) | 1 de 22 |
| R4 | tempfile nao fechado depois de gravar (ensure removido) | 2 de 22 |
| R5 | download e gravacao movidos para dentro do lock da conversa | 1 de 26 |
| R6 | blob sem dono nao apagado (agendamento removido) | 5 de 26 |
| R7 | transacao em volta do create_and_upload! removida (linha de blob sem arquivo sobrevive) | 1 de 22 |
| M1 | fallback removido: post_arquivo sem o rescue Indisponivel | 7 de 31 |
| M2 | nome generico do arquivo | 4 de 11 |
| M3 | teto de tamanho removido | 3 de 22 |
| M4 | assinatura de PDF nao conferida | 2 de 22 |
| M5 | identidade do arquivo trocada pela legenda | 2 de 26 |
| M6 | Progress aceita qualquer Hash como entrega | 4 de 11 |
| M7 | comparativo sem a guarda de forma (Hash invalido sai mesmo assim) | 2 de 11 |
| M8 | publicador sem a guarda (o to_s do Hash vira mensagem, como antes) | 1 de 26 |

Rodada 6 (`e11r6/mutacoes_e11_r6.py` no scratchpad: edita → roda → restaura → md5 conferido
antes/depois nos 7 arquivos de código, inclusive os 3 do `SafeFetch`; `mutacoes_r6.json`). S1–S8
são as regras novas desta rodada (13 mutações); N1, N2, N2b, V2, V5, Q1, Q2, R1, R2, R5 e M1–M8
repetidas com o texto reajustado ao código atual (N2/N2b agora em `EntregaDeArquivo.agendar_limpeza`;
M3 ao `SafeFetch.fetch`; M4 a `conferir`). R3/R4 (tempfile da entrega) e R6/R7 (purge no publicador
e transação do `create_and_upload!`) deixaram de existir como código e foram substituídas por T1
(o `ensure` do tempfile do `SafeFetch`), S5 e S5b. Cada linha: exemplos que reprovam / rodados.

| # | Mutação | Reprova |
|---|---|---|
| S1 | (P1 SSRF) download de volta ao Down, so com URL_SEGURA: IP privado e DNS para dentro passam | 14 de 27 |
| S2 | (P1) status nao conferido dentro do bloco: o corpo do 404/302 e lido inteiro antes da recusa | 5 de 76 |
| S2b | tamanho anunciado nao conferido antes do corpo | 2 de 76 |
| S3 | (P2) prazo total removido da entrega (so tetos por operacao) | 2 de 27 |
| S3f | (P2) prazo total nao aplicado no Fetcher (enforce! removido) | 2 de 76 |
| S3b | (P2) cada leitura NAO usa o tempo restante (socket nao apertado; prazo so entre pedacos) | 2 de 76 |
| S3c | tetos por operacao nao limitados pelo prazo total | 1 de 49 |
| S4a | (P2) falha ao anexar sem reconciliacao nem reserva: a excecao sobe (publish -> blocked) | 2 de 29 |
| S4b | (P3) reserva sem reconciliar pelo token: a excecao depois do commit manda o blob anexado para a limpeza | 1 de 29 |
| S5 | (P2) subida do arquivo dentro de transacao | 3 de 27 |
| S5b | (P2) volta ao create_and_upload! em transacao (linha sem arquivo nao vai para a limpeza) | 5 de 61 |
| S6 | (P2) cabecalho externo dentro do motivo (tipo_text_html) | 2 de 56 |
| S8 | so a gravacao (upload) movida para dentro do lock da conversa | 1 de 29 |
| R5 | download e gravacao movidos para dentro do lock da conversa | 1 de 29 |
| N1 | rescue do que ninguem classifica removido: a excecao crua sobe (publish -> blocked) | 2 de 56 |
| N2 | rescue do agendamento da limpeza removido: o Redis fora sobrescreve o resultado / a causa | 3 de 56 |
| N2b | agendamento engolido sem registro (rescue sem warn) | 3 de 56 |
| V2 | o blob ANEXADO tambem vai para a limpeza (sem && !anexado) | 4 de 34 |
| V5 | a reserva da entrega de arquivo nao passa pela peneira de texto de cliente | 1 de 11 |
| Q1 | volta ao purge sincrono cru no ensure (a falha do delete sobrescreve o resultado do post) | 6 de 29 |
| Q2 | purge sincrono engolido em rescue no ensure (some o agendamento; o blob sem dono fica) | 6 de 29 |
| R1 | rescue do armazenamento removido: a falha do upload sobe crua (publish -> blocked) | 4 de 61 |
| R2 | redirecionamento seguido de novo (max_redirects 2) | 2 de 27 |
| T1 | temporario do download nao fechado (ensure do with_tempfile removido) | 3 de 76 |
| M1 | fallback removido: post_arquivo sem o rescue Indisponivel | 8 de 34 |
| M2 | nome generico do arquivo | 4 de 11 |
| M3 | teto de tamanho removido (sem max_bytes: o padrao de 40 MB do SafeFetch) | 3 de 27 |
| M4 | assinatura de PDF nao conferida | 2 de 27 |
| M5 | identidade do arquivo trocada pela legenda | 3 de 29 |
| M6 | Progress aceita qualquer Hash como entrega | 4 de 11 |
| M7 | comparativo sem a guarda de forma (Hash invalido sai mesmo assim) | 2 de 11 |
| M8 | publicador sem a guarda (o to_s do Hash vira mensagem, como antes) | 1 de 29 |

### Recusa

Nenhum motivo novo em `MOTIVOS`: cair para o link não é recusa ao modelo (a ferramenta fez o que
o modelo pediu; a forma da entrega é que degradou). O registro é `Rails.logger.warn` com o código
curto do motivo — nunca o corpo da resposta nem a mensagem da exceção.

### Validação

- `entrega_de_arquivo_spec` 13, `progress_spec` 10, `async_publisher_spec` 18,
  `insurance_quote_comparativo_arquivo_spec` 5, `async_run_job_comparativo_arquivo_spec` 3,
  `insurance_quote_ramo_auto_spec`, `async_run_job_encerramento_parcial_spec`, `async_run_job_spec`,
  `reap_stale_runs_job_spec`: 112 exemplos, 0 falhas (`r7.json`).
- rubocop nos 14 arquivos tocados: 0 ofensas.
- Suíte ampla `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia`: 912 exemplos,
  0 falhas, 0 erros fora de exemplo, 3 pendentes (anteriores a esta PR; `ampla.json`).
- Banco de teste próprio: `chatwoot_test_e11`.
- Rodada 2: RED confirmado antes de implementar (4 novos falhando, 39 antigos passando; o do job
  reproduz a sonda P4 do revisor: só o preço chega). Depois: 11 arquivos de spec alvo (inclusive
  `recusa_registro_spec`, `recusa_guarda_spec`, `progress_spec`, `async_run_job_spec`,
  `reap_stale_runs_job_spec`) = 161 exemplos, 0 falhas, 0 erros fora (`green.json`); rubocop nos 7
  arquivos tocados: 0 ofensas (`publish` foi desmembrado para caber na complexidade); suíte ampla:
  916 exemplos, 0 falhas, 0 erros fora de exemplo, 3 pendentes anteriores (`ampla_r2.json`).

- Rodada 3: `entrega_de_arquivo_spec` 21 (era 13), `async_publisher_spec` 21 (era 18),
  `async_run_job_comparativo_arquivo_spec` 5 (era 4): 47 exemplos, 0 falhas, 0 erros fora
  (`e11r3/ent.json`, `e11r3/pub_job.json`); rubocop nos 5 arquivos tocados: 0 ofensas
  (`e11r3/rubocop.json`); 15 mutações, todas reprovam e restauram; suíte ampla
  `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia`: 1055 exemplos, 0 falhas, 0 erros fora de exemplo,
  3 pendentes anteriores a esta PR (`e11r3/ampla_r3.json`, exit 0).

- Rodada 4: `async_publisher_spec` 23 (era 21); specs alvo (publisher, entrega_de_arquivo, job do
  comparativo, encerramento parcial, async_run_job, reap_stale_runs, progress, comparativo): 93
  exemplos, 0 falhas, 0 erros fora (`e11r4/green.json`, exit 0); rubocop nos 2 arquivos tocados:
  0 ofensas (`e11r4/rubocop.json`); 17 mutações, todas reprovam e restauram (`e11r4/mutacoes_r4.json`);
  suíte ampla `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia`: 1057 exemplos, 0 falhas, 0 erros fora de exemplo,
  3 pendentes anteriores a esta PR (`e11r4/ampla_r4.json`, exit 0).

- Rodada 5: `entrega_de_arquivo_spec` 22 (era 21), `async_publisher_spec` 26 (era 23),
  `progress_spec` 11 (era 10), `async_run_job_comparativo_arquivo_spec` 5 (guarda nova no
  exemplo do anexo); specs alvo (publisher, entrega_de_arquivo, job do comparativo, progress,
  encerramento parcial, async_run_job, reap_stale_runs, comparativo): 98 exemplos, 0 falhas,
  0 erros fora (`e11r5/green.json`, exit 0); rubocop nos 6 arquivos tocados: 0 ofensas
  (`e11r5/rubocop.json`); 22 mutações, todas reprovam e restauram (`e11r5/mutacoes_r5.json`);
  suíte ampla `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia`: 1062 exemplos, 0 falhas, 3 pendentes anteriores a esta PR, 0 erros fora de exemplo, exit 0 (`e11r5/ampla_r5.json`).

- Rodada 6: `entrega_de_arquivo_spec` 27 (era 22), `async_publisher_spec` 29 (era 26),
  `safe_fetch_spec` 49 (era 41), `async_run_job_comparativo_arquivo_spec` 5, `progress_spec` 11,
  `insurance_quote_comparativo_arquivo_spec` 6: 127 exemplos, 0 falhas,
  0 erros fora (`e11r6/green.json`, exit 0); rubocop nos 12 arquivos
  tocados (+ `async_run_job_encerramento_parcial_spec`): 0 ofensas (`e11r6/rubocop.json`,
  `e11r6/rubocop_enc.json`); 32 mutações, todas reprovam e restauram, md5 idêntico antes/depois
  nos 7 arquivos (`e11r6/mutacoes_r6.json`); consumidores do `SafeFetch` (upload por URL, avatar,
  executor HTTP, Twilio, branding, webhooks): 109 exemplos, 0 falhas, antes e depois da mudança
  (`e11r6/consumidores_antes.json`); a primeira passada da suíte ampla achou 1 falha real —
  `async_run_job_encerramento_parcial_spec` exercita o download do comparativo e não stubava o DNS de
  `exemplo.test`, que o `SafeFetch` passou a resolver antes de conectar (stub adicionado, como nos
  outros três specs); suíte ampla final `spec/services/autonomia spec/jobs/autonomia
  spec/models/autonomia spec/requests/api/v1/accounts/autonomia` + `safe_fetch_spec` + specs dos
  consumidores: 1185 exemplos, 0 falhas, 3 pendentes anteriores a esta PR,
  0 erros fora de exemplo, exit 0 (`e11r6/ampla_r6_final.json`).

## O ACHADO que o orquestrador precisa saber antes da prova real — SUPERADO na rodada 3

> Registro histórico. O fato novo do orquestrador (acima, rodada 3) mostra que o 404 veio de
> testar a URL com o nome de arquivo REDIGIDO pela CLI, e que os comparativos reais abrem. Não há
> defeito no adapter e a "proposta" de issue abaixo está cancelada. O texto original fica para a
> rastreabilidade do raciocínio.


**A URL do comparativo que o adapter devolve hoje responde 404.** Em 11/09/2026 (09:19Z–09:35Z),
com a conta de teste, `quote proposal` das três cotações reais existentes (renovação
`b0220871…:1`, moto `91bef437…:1`, caminhão `4c278fcf…:1`) devolveu, cada uma, uma URL de
`https://report-files.aggilizador.com.br/…pdf` (60 caracteres, sem query); as três responderam
`HTTP 404`, `application/xml`, 215 bytes: `<Error><Code>BlobNotFound</Code><Message>The specified
blob does not exist…` (Azure Blob), e continuaram 404 depois de 2 minutos e depois de ~15 minutos.
Isto é anterior a esta entrega: o link que saiu nas rodadas A, B e C de 11/09 era esta mesma URL, e
ninguém a abriu. Com esta PR, o cliente recebe o link (reserva) nesse caso — como hoje — e o log
mostra `arquivo indisponivel … motivo=http_404`.

Hipótese, lida no bundle do portal (`chunk-WKHG43P2.js`, `buildPrintBody`/`buscarImagemPerfil`):
a SPA manda em `impressao.company.logo` a URL do avatar da corretora ou, se ela não responder, os
BYTES de `assets/img/corretora.png`; o adapter manda `logo: []` (`buildPrintCompany`,
`http/quote.ts`). No modo `link: true` o portal devolve a URL e gera o PDF depois; um render que
falha (logo vazio?) deixaria a URL sem blob. A SPA, no celular, faz `window.location.href = url`
logo depois do print — ou seja, espera que a URL sirva de imediato. **Isso é do adapter
(`quote/proposal`), fora do escopo desta entrega**; sem resolver, o termo 4 não fecha, porque não
há arquivo para anexar. Proposta: issue no `autonomia-adapters` para reproduzir o print com o
logo como a SPA manda (o `print` não gasta cotação) e ler o blob de volta.

## Produção (depois do deploy) — o que o orquestrador confere

1. Cotação real com pelo menos um preço → a mensagem do comparativo chega ao WhatsApp como
   documento (`Comparativo de seguro — placa <PLACA>.pdf`), com a legenda "Comparativo com todas
   as opções." — no WhatsApp Cloud o `filename` vai no payload (`build_attachment_content`); no
   WAHA (conversa 5045) o envio é do app externo, a partir do `data_url` do webhook.
2. Se o download ou a gravação falharem (portal 404, armazenamento fora), o cliente recebe o
   texto com o link (como hoje) e o log do worker mostra `[autonomia][tool][async] arquivo
   indisponivel run=<id> motivo=<url_insegura|redirecionamento|http_<status>|tamanho|tempo|download
   causa=…|tipo_invalido|nao_e_pdf|armazenamento causa=…>; vai como link` — ou, na falha ao
   anexar depois de gravar, `anexo falhou run=<id> causa=<classe>; vai como link`. Uma linha do
   blob sem arquivo (subida que falhou) também vai ao `PurgeJob`, com `contexto=gravacao` no log
   se o Redis recusar o agendamento. O blob do retry que não virou anexo é apagado pelo `ActiveStorage::PurgeJob` na fila
   `default` do Sidekiq; se o Redis recusar o agendamento, o log mostra `blob sem dono nao agendado
   run=<id> blob=<id> causa=<classe>` (limpeza manual pelo id) e a entrega não é afetada. Nenhum
   rollout, nenhuma migração, nenhuma variável nova. Pré-requisito que já vale hoje para o agente
   humano: o serviço do ActiveStorage do worker (`ACTIVE_STORAGE_SERVICE`) grava — é nele que o
   PDF entra, antes da mensagem.
3. Rollback: reverter o deploy; não há dado novo no banco (o handle não mudou de forma).

## Comandos

```
git -C ~/dev/chat2you worktree add -b feat/entrega-11-comparativo-arquivo ~/dev/worktrees/chat2you/entrega-11-comparativo-arquivo origin/main
export POSTGRES_DATABASE=chatwoot_test_e11; RAILS_ENV=test bundle exec rails db:create db:schema:load
bundle exec rspec <specs tocados> --format json --out r7.json          # 112 ex, 0 falhas
bundle exec rubocop --format json <14 arquivos tocados>                 # 0 ofensas
uv run python3 mutacoes.py                                              # M1–M6, todas reprovam, md5 restaurado
uv run python3 mutacoes_e11_r2.py                                       # rodada 2: M1–M8, todas reprovam, md5 restaurado
uv run python3 e11r3/mutacoes_e11_r3.py                                 # rodada 3: R1–R7 + M1–M8, todas reprovam, md5 restaurado
uv run python3 e11r4/mutacoes_e11_r4.py                                 # rodada 4: Q1–Q2 + R1–R7 + M1–M8, todas reprovam, md5 restaurado
uv run python3 e11r5/mutacoes_e11_r5.py                                 # rodada 5: N1, N2, N2b, V2, V5 + as 17 anteriores, todas reprovam, md5 restaurado
uv run python3 e11r6/mutacoes_e11_r6.py                                 # rodada 6: S1–S8 (13 novas) + N1, N2, N2b, V2, V5, Q1, Q2, R1, R2, R5, T1, M1–M8 (32), todas reprovam, md5 restaurado
bundle exec rspec spec/lib/safe_fetch_spec.rb spec/jobs/avatar/avatar_from_url_job_spec.rb spec/services/autonomia/agents/tools/http_executor_spec.rb spec/services/twilio/media_download_service_spec.rb spec/services/website_branding_service_spec.rb spec/lib/webhooks/trigger_spec.rb spec/controllers/api/v1/upload_controller_spec.rb   # consumidores do SafeFetch, antes e depois: 109 ex, 0 falhas
bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia --format json --out ampla.json
npx tsx src/cli/main.ts agger quote proposal <id>  (×3, só print; nenhum quote start) + curl -I na URL → 404 BlobNotFound
```
