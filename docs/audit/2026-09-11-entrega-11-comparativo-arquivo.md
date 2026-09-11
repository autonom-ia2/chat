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
anunciado e medido em fluxo), PRAZO DO CORPO COM TETO POR LEITURA de 20 s (monotônico; conexão de
até 5 s e espera pelos cabeçalhos limitadas a ele como teto por operação; cada leitura do corpo
espera só o que resta; abaixo dos 25 s de shutdown do Sidekiq — o que ele NÃO cobre está na ressalva
da rodada 7) e assinatura de PDF (`%PDF-`, mais
o tipo declarado que não pode desmentir) —, sem seguir redirecionamento, GRAVA o blob no
armazenamento ainda fora do lock e fora de transação (`EntregaDeArquivo#gravar`, rodadas 3 e 6), com
a MARCA da execução no `metadata` (rodada 7), RECONFERE a autorização sob o lock da conversa, sem
cache, imediatamente antes de criar a mensagem (rodada 7) e anexa o blob gravado (pelo `signed_id`)
pelo `Messages::MessageBuilder`, o mesmo caminho do agente humano que manda um arquivo. Quando o
download ou a gravação não entregam um PDF, sai a reserva com o mesmo token de idempotência, e o
motivo (código curto) vai ao log: a falha do arquivo não apaga os preços que já saíram, e nunca é
silenciosa. E a mensagem no banco só é `published` quando o ENVIO ao canal foi disparado (rodada 7):
a exceção depois do commit é reconciliada pelo envio, não pela mensagem.

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
- Rodada 7: `tools/vigia_de_envio.rb` (novo: escuta `enqueue.active_job`/`enqueue_at.active_job`
  durante a publicação e anota o `SendReplyJob` que ENTROU na fila); `async_publisher.rb`
  (revalidação sob o lock sem cache, `publicar_sob_lock`; reconciliação pelo envio, `reconciliar`/
  `reenviar`; sem memo de vínculo; `post`/`post_arquivo`/`publicar_anexo` sem o parâmetro
  `agent_inbox`); `entrega_de_arquivo.rb` (`gravar(run_id:)` marca o blob — `marca`, `blobs_sem_dono`;
  `PRAZO_TOTAL_SEGUNDOS` → `PRAZO_SEGUNDOS`); `reap_stale_runs_job.rb` (`recolher_blobs_sem_dono`,
  `BLOB_SEM_DONO_IDADE = 1.hour`); `lib/safe_fetch/deadline.rb` (degradação `sem_socket` registrada
  uma vez por transferência) e comentários do `SafeFetch` sobre o que o prazo cobre.
- Rodada 8: `tools/pendencia_de_envio.rb` (novo: a marca `autonomia_envio_pendente` na mensagem, escrita
  atômica na forma do coder); `async_publisher.rb` (`retomar`, `enfileirar_envio` com o `false`);
  `entrega_de_arquivo.rb` (`blobs_sem_dono` por JSON com cast protegido).
- Rodada 9: `tools/retomada_de_envio.rb` (novo: `retomar`/`reenviar` — a mecânica que saiu do
  publicador — e `recuperar`, a retomada pelo varredor sob o lock da conversa);
  `tools/autorizacao_da_execucao.rb` (novo módulo: `autorizacao`, `recusada?`, `vinculo_autorizado`,
  `mesmo_vinculo?`, incluído por publicador e retomada); `pendencia_de_envio.rb` (`NULLIF`; a execução
  na marca; `marcadas` com cast protegido; `abandonar`; `execucao_id`); `async_publisher.rb`
  (`publicar_sob_lock` retoma sob o lock; `Duplicada`/`RECUSAS` removidos; 140 linhas de código);
  `reap_stale_runs_job.rb` (`retomar_envios_pendentes`, janela 2 dias, limite 200);
  `entrega_de_arquivo.rb` (`jsonb_typeof … = 'number'`); `spec/support/fila_de_envio_helper.rb` (novo).

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
(tetos por operação não limitados pelo total). *[Rodada 7: "total" neste parágrafo é o nome da
opção (`total_timeout:`), que ficou; o que ela cobre é o prazo do CORPO com teto por leitura, mais
o teto por operação da conexão e dos cabeçalhos — DNS, cabeçalhos que gotejam e linhas de controle
do chunked NÃO estão cobertos. Ver a ressalva da rodada 7.]*

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

### Rodada 7 (revisão do Codex sobre `3124e0d7a1`: 1 P1 + 3 P2 + 1 ressalva; os 8 achados anteriores fechados): a autorização sob o lock, o envio, o blob sem dono, o que o prazo não cobre

Decisões do orquestrador, obrigatórias; cada correção com spec e mutação (edita → roda → restaura →
md5). Onde este texto se afasta da letra da decisão, diz onde e por quê.

**P1 — a autorização era conferida ANTES do download e não reconferida sob o lock.** `post`
recarregava `@run` mas não olhava `dead?`, e reutilizava `@authorized_inbox` memoizado: um agente
desligado, uma allowlist que mudou ou uma execução supersedida DURANTE a transferência (segundos)
publicavam mesmo assim — o buraco do cabeçalho do arquivo ("agente que já foi desligado falando com
cliente real") por outra porta. Correção (`async_publisher.rb`): a conferência que VALE é a de
`publicar_sob_lock`, sob o `with_lock` da conversa e imediatamente antes de `build_message!`, SEM
cache — `@run.reload.dead?` → recusa `execucao_morta`; `Operate.authorized_agent_inbox(conversation)`
recalculado sobre a conversa que o lock acabou de recarregar (conta habilitada, agente ligado e ativo,
allowlist, mesma caixa) e `same_binding?` → recusa `vinculo_mudou`. A mensagem é construída com o
vínculo RECALCULADO, não com o da entrada; o memo `@authorized_inbox` deixou de existir
(`vinculo_autorizado` lê o banco a cada chamada) e `post`/`post_arquivo`/`publicar_anexo` perderam o
parâmetro `agent_inbox`. A recusa sai `blocked`, registrada (`publicacao recusada run=<id>
motivo=<execucao_morta|vinculo_mudou>`), e o blob gravado sem dono vai para a limpeza (`anexado`
falso → `agendar_limpeza`). A conferência de ENTRADA (`authorized_conversation`) continua, para não
baixar arquivo nenhum do que já não pode publicar. Guardas (`async_publisher_spec`, "quando a
autorizacao cai durante a transferencia"): outro processo supersede a execução no meio da gravação
(`update_all` fora do objeto do publicador) → `blocked`, nenhuma mensagem, sequência 0, log
`motivo=execucao_morta`, `PurgeJob` uma vez; o operador desliga o agente no meio da gravação →
idem com `motivo=vinculo_mudou`. Mutações X1 (`dead?` não reconferido), X2 (vínculo memoizado — a
conferência sob o lock reutiliza a da entrada), X3 (revalidação removida inteira).

**P2 — a reconciliação tratava mensagem persistida como entregue.** `execute_after_create_commit_callbacks`
da `Message` roda, nesta ordem, `reopen_conversation`, `mark_pending…`, `set_conversation_activity`,
`dispatch_create_events` (Redis: ActionCable e `EventDispatcherJob`), `send_reply`
(`SendReplyJob.perform_later`, com `wait: 2.seconds` quando há anexo), `execute_message_template_hooks`,
`update_contact_activity`. Se o despacho levanta, o `send_reply` NUNCA roda: a mensagem está no
banco, o token está publicado, e nada foi enviado — `published` no papel, e o token impede repetir.
O sinal correto, lido no código: `source_id` só existe DEPOIS de o canal responder
(`Whatsapp::SendOnWhatsappService#send_session_message` → `message.update!(source_id:)`), então não
serve para saber se o envio foi DISPARADO; o que existe é o instrumento do ActiveJob — todo `enqueue`
emite `enqueue.active_job`/`enqueue_at.active_job` com o job, e `successfully_enqueued?` diz se
entrou (falso quando o adapter levantou). Daí o `VigiaDeEnvio` (arquivo novo): assina esses eventos
durante o `post` e anota o id da mensagem de cada `SendReplyJob` que ENTROU na fila (assinatura do
processo pelo tempo do bloco; o que outras threads enfileiram cai na lista e é inofensivo, porque a
pergunta é sempre por UMA mensagem). A idempotência do `SendReplyJob`, provada no código:
`Base::SendOnChannelService#perform` → `invalid_message?` → `outgoing_message_originated_from_channel?`
→ `message.source_id.present?` → não envia; e `private?` → não envia. Ou seja: é no-op para mensagem
JÁ enviada e para nota privada, mas NÃO para uma mensagem cujo job está na fila e ainda não rodou —
dois jobs correriam para o mesmo `send_message` sem lock. Por isso a recuperação só dispara quando o
vigia diz que o `send_reply` não enfileirou. Correção (`post` → `reconciliar`): a exceção depois do
commit, da mensagem que ESTA chamada criou e que FICOU no banco (`publicado.persisted?` — o rollback
restaura `new_record`), é reconciliada assim: `private?` OU `source_id.present?` OU o vigia viu o
`SendReplyJob` desta mensagem → `published` sem mensagem nova; senão `SendReplyJob.perform_later(id)`
→ log `envio reenfileirado run= message=` → `published`; se nem isso entra na fila → log `publicacao
incompleta run= message= motivo=mensagem_sem_envio causa=<classe>` e `blocked` — a mensagem e o
anexo ficam (o blob tem dono: `blob.attachments.exists?`), ninguém conta a entrega, e a falha é
explícita. A reconciliação SUBIU de `publicar_anexo` para `post` porque o achado é de classe, não
de caso: a mensagem de TEXTO (a reserva, o preço, a frase de falha) tinha o mesmo defeito por outro
caminho — `post` levantava depois do commit e `publish` devolvia `blocked` com a mensagem no banco e,
se o `send_reply` tinha rodado, o cliente a recebia sem que ninguém contasse. Só a mensagem desta
chamada é reconciliada (não uma achada pelo token): uma mensagem de OUTRO publicador poderia ter um
envio dele a caminho, e reenfileirar duplicaria. Desvio da letra da decisão: o código fechado é
`mensagem_sem_envio`, não `anexo_sem_envio` — nomeia a classe (vale para a reserva e para o texto),
já que a reconciliação é uma só. Guardas (`async_publisher_spec`, "quando a publicacao levanta depois
do commit"): o despacho levanta → `published`, 1 mensagem com o PDF, `SendReplyJob` enfileirado com o
id dela UMA vez, log `envio reenfileirado`, `PurgeJob` não; o gancho de templates (DEPOIS do
`send_reply`) levanta → `SendReplyJob` UMA vez (o do `send_reply`), nenhum `envio reenfileirado`;
nota privada + despacho levanta → `published`, `SendReplyJob` nenhum; o adapter da fila recusa o
`SendReplyJob` (o do `send_reply` E o da recuperação; o resto entra) → `blocked`, mensagem com o anexo
no banco, `SendReplyJob` nenhum, `PurgeJob` não, log `motivo=mensagem_sem_envio
causa=Redis::CannotConnectError`; `advance_sequence!` levanta uma vez (a transação volta DEPOIS de
criar a mensagem) → nenhuma reconciliação: a reserva com o mesmo token, `anexo falhou
causa=ActiveRecord::StatementInvalid`, `PurgeJob` uma vez. Mutações Y1 (mensagem persistida tratada
como entregue sem conferir o envio), Y2 (vigia ignorado: reenfileira com o `send_reply` já na fila —
dois envios), Y3 (falha da recuperação devolve `published`), Y4 (vigia conta o enfileiramento que
FALHOU), Y5 (`post` sem reconciliação: reserva por cima da mensagem no ar), Y6 (reconciliação sem
`persisted?`: a mensagem da transação desfeita é reconciliada), V2b (o blob da mensagem reconciliada
tratado como sem dono).

**P2 — morte do processo entre `save!` do blob e o anexo.** A linha do blob (com ou sem arquivo)
ficava sem dono e ninguém a reconhecia: o `ensure` do publicador só roda se o processo vive.
Correção: `EntregaDeArquivo#gravar(run_id:)` — palavra-chave OBRIGATÓRIA, para que nenhum chamador
grave sem marca — constrói o blob com `metadata: { 'autonomia_tool_run_id' => <id>,
'autonomia_finalidade' => 'entrega_de_arquivo' }` (`EntregaDeArquivo.marca`); e o
`ReapStaleRunsJob` (já periódico: `*/10 * * * *`, `config/schedule.yml`) ganha
`recolher_blobs_sem_dono`: `EntregaDeArquivo.blobs_sem_dono(antes_de: 1.hour.ago, limite: 500)` =
`ActiveStorage::Blob.unattached` (LEFT JOIN sem anexo) + `created_at < antes_de` + `metadata LIKE
'%"autonomia_finalidade":"entrega_de_arquivo"%'` (o par tal como o coder JSON do Rails o grava, sem
espaços — `marca_no_texto`), cada um para `agendar_limpeza(contexto: 'varredor')`. Os três filtros
são a guarda: sem a marca apagaríamos blobs alheios; sem a idade, um upload em andamento (a linha
existe antes do anexo — a transferência cabe em segundos, uma hora é folga); sem "sem anexo", o PDF
de uma mensagem entregue. Desvio da letra da decisão: a finalidade é `entrega_de_arquivo`, não
`comparativo` — nomeia QUEM GRAVA (a classe), para que outra ferramenta que entregue arquivo por aqui
continue reconhecida pelo varredor. Custo, registrado: `active_storage_blobs` só tem índice em `key`;
a consulta é uma varredura sequencial da tabela a cada 10 min (a anti-junção usa
`index_active_storage_attachments_on_blob_id`), com `LIMIT 500` — aceitável no volume desta
instalação, e um índice parcial sobre a marca fica como item para quando a tabela pedir (nenhuma
migração nesta PR). Guardas: `entrega_de_arquivo_spec` "grava o PDF baixado…" afirma a marca no
`metadata`; `reap_stale_runs_job_spec` "blobs sem dono da entrega de arquivo": quatro blobs —
marcado/velho/sem anexo (apagado), marcado/recente (fica), velho/sem marca (fica),
marcado/velho/ANEXADO a uma mensagem (fica) — e o Redis recusando o agendamento → registrado
(`blob sem dono nao agendado varredor blob=<id>`), a varredura não cai. Mutações Z1 (blob sem a
marca), Z2 (sem o filtro da marca), Z3 (sem o filtro de idade), Z4 (sem "sem anexo"), Z5 (varredura
removida do `perform`).

**P2 — o prazo "total" não cobre DNS, cabeçalhos lentos nem as linhas de controle do chunked.**
DECISÃO: NÃO implementar orçamento cancelável nesta PR — uma thread vigia fechando o socket é risco
maior que o benefício aqui. RESSALVA, com o modelo de ameaça: a URL vem do NOSSO adapter (o blob do
portal, https, sem redirecionamento), `open_timeout` 5 s, cada leitura do corpo limitada pelo saldo
(`Deadline#tighten!`), conexão e espera pelos cabeçalhos limitadas ao prazo como TETO POR OPERAÇÃO
(`RequestOptions#bounded_by_total`); o que evade é um gotejamento de cabeçalhos abaixo do saldo, ou
linhas de controle do chunked entre dois `enforce!` (cada uma uma leitura com o teto do saldo) — e o
shutdown do Sidekiq (25 s) encerra o job de qualquer forma [NOTA da rodada 8: não é assim — os 25 s
são a folga de um SHUTDOWN, não um teto de execução; sem deploy, a thread fica ocupada enquanto o
servidor gotejar; ver rodada 8, "Texto"]. A resolução de DNS já estava registrada
como fora do prazo. O que mudou de prosa e nome: `PRAZO_TOTAL_SEGUNDOS` → `PRAZO_SEGUNDOS` (uma
constante chamada "total" que não é total é a mentira que este projeto não aceita); os comentários de
`entrega_de_arquivo.rb`, `async_publisher.rb`, `lib/safe_fetch.rb`, `deadline.rb`,
`request_options.rb` e `fetcher.rb` chamam o prazo de "prazo do corpo com teto por leitura" e dizem o
que ele não cobre; a opção `total_timeout:` do `SafeFetch` (API da lib, 1 consumidor) manteve o
nome. Esta auditoria: o resumo do desenho e o termo 3 corrigidos; o texto histórico da rodada 6
recebeu a nota. Pendência da auditoria (não issue): orçamento cancelável, se um dia o adapter deixar
de ser a única origem da URL.

**Ressalva do Codex — `Deadline#tighten!` aceitava socket ausente em silêncio.** Sem socket não há
teto por leitura e o prazo vale só entre pedaços: é assim sob WebMock (a resposta não tem socket) e
seria assim se um Net::HTTP futuro deixasse de expor o ivar `@socket` que o `Fetcher` lê por
`instance_variable_get`. Escolha, justificada: REGISTRAR, não levantar — levantar reprovaria todo
download sob WebMock (nenhum socket) e, em produção, trocaria uma degradação (prazo entre pedaços)
por uma falha total do download; ficar em silêncio era o que o Codex apontou. `Deadline` registra
`[safe_fetch] total_timeout degradado motivo=sem_socket…` UMA vez por transferência (código fechado;
em produção, se aparecer, é o acoplamento com o net-http rompido — e o spec de socket real também
reprova). Guardas (`safe_fetch_spec`, "with total_timeout"): `enforce!(nil)` duas vezes → um `warn`,
`binding?` falso, prazo preservado; um socket com `read_timeout` → apertado ao saldo, `binding?`
verdadeiro, nenhum `warn`. Mutações W1 (registro removido), W2 (registrado a cada leitura).

**O que continua em aberto, dito com todas as letras:** com o Redis fora no despacho E no
enfileiramento, a mensagem com o anexo fica no banco (visível na conversa do painel) sem envio ao
canal, `blocked` e o log `mensagem_sem_envio`. Ninguém a reenvia sozinho [SUPERADO na rodada 8: a
pendência fica gravada na mensagem e a tentativa seguinte — a reemissão da mesma entrega — reenvia] —
um reconciliador periódico de "mensagem outgoing nossa sem `source_id`" reenviaria também as que
FALHARAM no canal
(`status: failed`, fora da janela) e as dos canais que nunca gravam `source_id` (WebWidget/API), e
correria contra um `SendReplyJob` atrasado na fila. É a falha explícita que a decisão pediu; a
recuperação, se necessária, é operacional, pelo id da mensagem no log.

### Rodada 8 (revisão do Codex sobre `4c81cf5c26`: 3 P2 + 1 texto + 1 ressalva; o P1 fechado): a pendência de envio na mensagem, a marca do blob como JSON, o que o shutdown não faz

Decisões do orquestrador, obrigatórias; cada correção com spec e mutação (edita → roda → restaura →
md5). Onde este texto se afasta da letra da decisão, diz onde e por quê.

**P2 — a recuperação malsucedida virava falso sucesso no retry.** Mensagem commitada, o envio original
E o reenfileiramento falham (Redis fora) → `blocked` preservando mensagem e token; na tentativa
seguinte (a reemissão da mesma entrega pelo poll da ferramenta — `AsyncRunJob#apply` publica
`progress.deliveries` a cada passada, idempotente pelo token — ou o encerramento), `DUPLICADA`
devolvia `published` sem conferir nem recuperar o envio: o cliente sem arquivo e sem link, contado
como entregue. Correção (decisão 7 do `async_publisher.rb`; `pendencia_de_envio.rb`, arquivo novo):
quando a recuperação falha, `PendenciaDeEnvio.marcar` grava `content_attributes['autonomia_envio_pendente']
= true` na própria mensagem — UMA escrita, atômica (`||` sobre o JSON dentro do UPDATE, sem
lê-modifica-escreve e sem callbacks da `Message`: o `after_update_commit` fala com o Redis, que é
justamente quem está fora); o log `publicacao incompleta … motivo=mensagem_sem_envio
causa=<classe|enqueue_recusado>` e o `blocked` continuam. `publicar_sob_lock` devolve
`Duplicada(mensagem)` (a mensagem achada pelo token, lida sob o lock; `entrega_publicada` no lugar de
`delivery_posted?`) em vez do símbolo; `resultado` → `retomar`: sem pendência → `published`, como
antes; com a marca E `source_id` vazio E não privada → log `envio pendente encontrado run= message=`
e `reenviar` de novo — entrou → `PendenciaDeEnvio.limpar` (a escrita atômica inversa, `-` sobre o
JSON) → `envio reenfileirado` → `published`; não entrou → `mensagem_sem_envio` de novo, `blocked`, a
marca fica. Token encontrado só significa entregue quando não há pendência conhecida.

Desvios da letra da decisão, ditos: (1) "uma escrita, sob o mesmo lock" — a escrita é uma e atômica,
mas NÃO toma o lock da conversa: o lock não fecharia a janela entre quem lê a marca (sob o lock, na
tentativa seguinte) e quem a grava (depois do lock, na tentativa que falhou) — a leitura anterior à
escrita diz `published`, a escrita diz `blocked`, e a reemissão seguinte acha a marca; um statement
atômico é o que basta, sem abrir transação para um UPDATE. (2) A FORMA NO BANCO: `content_attributes`
é coluna `json`, mas o `store :content_attributes, coder: JSON` da `Message` codifica DUAS vezes — a
coluna guarda uma STRING JSON com o objeto dentro. Provado na rodada 8 com uma sonda (apagada antes
do commit): `json_typeof(content_attributes)` = `'string'`, bruto `"{\"autonomia_async_token\":…}"`,
numa mensagem criada pela factory. Um `||` direto sobre o escalar produzia um ARRAY, e a `Message`
deixava de conseguir ler `content_attributes` (`TypeError: no implicit conversion of Array into
String`, visto na primeira passada dos specs). A escrita extrai o objeto com `#>> '{}'`, mescla como
jsonb e regrava com `to_json(text)` (`PendenciaDeEnvio::OBJETO_SQL`, `MARCAR_SQL`, `LIMPAR_SQL`).
(3) A falha da PRÓPRIA escrita da marca (banco) é registrada (`pendencia de envio nao gravada run=
message= motivo=<marca_nao_gravada|marca_nao_limpa> causa=<classe>`) e não levanta nem troca o
resultado: `marca_nao_gravada` é o caso raro em que a tentativa seguinte fica cega (o banco falhando
logo depois de commitar a mensagem); `marca_nao_limpa` deixa uma marca velha, que a tentativa
seguinte reenvia uma vez (no-op se o canal já confirmou).

Guardas (`async_publisher_spec`, "quando a publicacao levanta depois do commit"): a fila recusa o
envio → `blocked`, marca `true`, token intacto; a fila volta → tentativa seguinte `published`, 1
mensagem, `SendReplyJob` com o id dela UMA vez, marca limpa, logs `envio pendente encontrado` e
`envio reenfileirado`, `PurgeJob` uma vez (o blob da tentativa seguinte); marcar e limpar preservam
token, sequência e anexo; a fila continua fora → `blocked` de novo, marca fica, `SendReplyJob`
nenhum; a mensagem marcada com `source_id` (o canal confirmou) → `published` sem reenviar; a mensagem
achada sem pendência (o retry do link) → UM `SendReplyJob`, o do `send_reply`.
`pendencia_de_envio_spec` (novo, 4): marca mesclando na forma que a `Message` lê (`json_typeof` =
`'string'`); limpa só a chave; não é pendência com `source_id`, privada, ou sem marca; a falha do
banco registra e não levanta. Mutações P1 (`retomar` ignora a pendência), P2 (`Duplicada` devolvida
como `published` sem `retomar`), P3 (pendência não gravada), P4 (pendência não limpa), P6 (sem exigir
`source_id` vazio), P7 (sem excluir a nota privada), P8 (marca por substituição: perde token e
sequência), P9 (marca gravada como objeto, não como a string do coder), P10 (falha da escrita sobe),
P11 (falha engolida sem registro).

**Ressalva do Codex — `reenviar` ignorava o retorno de `perform_later`.** `ActiveJob::Enqueuing#enqueue`
devolve `false`, SEM exceção, quando `raw_enqueue` levanta `EnqueueError` ou um callback de enqueue
barra (`activejob 7.2.3.1`, lido). Correção: `enfileirar_envio` trata `false` como falha, código
`enqueue_recusado`, mesmo caminho de `mensagem_sem_envio`. Fatos lidos: nesta instalação NADA
levanta `EnqueueError` (`activejob 7.2.3.1` só a define; `sidekiq 7.3.10` não a usa) e
`SendReplyJob` não tem callbacks de enqueue — é contrato da API, não caminho alcançável hoje; pelo
mesmo motivo o `send_reply` da própria `Message` (que também ignora o `false`) não é tocado (núcleo
do Chatwoot; registrado abaixo como aberto). Guarda: `redis_cai_no_despacho` +
`SendReplyJob.perform_later` devolvendo `false` → `blocked`, marca, log `causa=enqueue_recusado`.
Mutação P5.

**P2 — Redis aceita o enfileiramento e perde a resposta: dois envios.** DECISÃO: NÃO alterar o
`SendReplyJob`/serviço de canal (núcleo do Chatwoot, fora do escopo). RESSALVA explícita, no
comentário de `reenviar`, no cabeçalho do `VigiaDeEnvio` e aqui: o caso exige o Redis ACEITAR o job
e PERDER a resposta na mesma chamada; aí o adapter levanta, `successfully_enqueued?` fica falso, o
vigia não anota o job que entrou, e a recuperação põe um segundo. O `SendReplyJob` só se protege por
`source_id` lido no começo (`Base::SendOnChannelService#invalid_message?`), gravado DEPOIS de o canal
responder: com as threads da fila, os dois podem enviar antes de qualquer um gravar. O custo é UM
DOCUMENTO DUPLICADO ao cliente, escolhido conscientemente contra a alternativa (cliente sem arquivo
e sem link). Issue aberta: autonom-ia2/chat#393 "Envio da mesma mensagem não é serializado no
SendReplyJob" (Part of #291) — serializar por mensagem com lock e `source_id` relido sob ele.

**P2 — `blobs_sem_dono` usava `metadata LIKE` com `_`.** `_` é curinga do `LIKE`
(`entrega_de_arquivo` casava `entregaXdeXarquivo`; `autonomia_finalidade`, `autonomiaXfinalidade`),
a marca aninhada em outro objeto casava, e o id da execução não era exigido — três jeitos de
selecionar um blob alheio ainda sem anexo. Correção (`entrega_de_arquivo.rb`): seleção por JSON no
NÍVEL SUPERIOR, com as DUAS chaves — `metadata::jsonb ->> 'autonomia_finalidade' =
'entrega_de_arquivo' AND metadata::jsonb ? 'autonomia_tool_run_id'` (binds NOMEADOS, para o `?` do
jsonb não ser tomado como bind posicional; o ActiveRecord pula `::jsonb` nos binds nomeados —
`replace_named_bind_variables`, "skip PostgreSQL casts", lido no `activerecord 7.2.3.1`), sobre
`unattached`, `created_at < 1.hour.ago`, `LIMIT 500`. O CAST É PROTEGIDO: a coluna é `text`, e o
único escritor é o coder JSON do `ActiveStorage::Blob` (`store :metadata, coder:
ActiveRecord::Coders::JSON`; nenhum SQL cru sobre `active_storage_blobs` em `app/`, `lib/`,
`db/migrate/`, `config/`) — mas uma linha que não fosse JSON derrubaria a varredura inteira, então
`METADATA_JSON_SQL = CASE WHEN metadata IS JSON OBJECT THEN metadata::jsonb END`: o `CASE` é a única
construção em que o Postgres garante não avaliar o ramo quando a condição falha (num `AND` a ordem é
do planejador). `IS JSON` pede Postgres 16+: CI `pgvector/pgvector:pg16`
(`.github/workflows/testes.yml`), local 16.13, produção 18.3 (RDS, memória de 02/09). `marca_no_texto`
deixou de existir. Guardas (`reap_stale_runs_job_spec`, "nao apaga o que so PARECE marcado"): curinga
(`autonomiaXfinalidade`/`entregaXdeXarquivo`, com run id), marca aninhada (`{"origem": {marca}}`),
marca sem run id, e `metadata = 'nao e json'` (escrito por SQL cru — `update_all` com Hash passaria
pelo coder e viraria a string JSON `"nao e json"`, válida) — um `PurgeJob` só, os quatro impostores
ficam, a varredura não levanta. Mutações Q1 (volta ao `LIKE`), Q2 (cast sem a guarda `IS JSON` →
`PG::InvalidTextRepresentation` derruba a varredura), Q3 (run id não exigido); Z2–Z4 reajustadas ao
SQL novo.

**Texto — "25 s de shutdown do Sidekiq" NÃO é teto de execução do job.** O `:timeout: 25` do Sidekiq
é a folga que um SHUTDOWN dá ao job antes de matá-lo; sem deploy, o worker fica ocupado enquanto o
servidor gotejar. Corrigido no comentário do `PRAZO_SEGUNDOS` (`entrega_de_arquivo.rb`): o que limita
é o teto por leitura com o saldo do prazo; o gotejamento de cabeçalhos abaixo do saldo evade e NÃO tem
teto de execução; o sinal em produção é o tempo do job (`AsyncRunJob`/`AsyncPublishJob`) fora da casa
dos segundos. O `20 < 25` continua sendo a razão do valor (um download NORMAL termina dentro da folga
de um shutdown). A rodada 7 desta auditoria recebeu a nota; o comentário do `ReapStaleRunsJob` já
usava os 25 s no sentido certo (worker morto num deploy).

**Rubocop obrigou um desmembramento honesto:** `Metrics/ClassLength` (184/175) no publicador → a
pendência virou colaborador (`PendenciaDeEnvio`: `pendente?`, `marcada?`, `marcar`, `limpar`, com a
forma da coluna documentada lá); `RSpec/MultipleExpectations` (13/7) → o exemplo grande virou dois,
com a primeira tentativa bloqueada num helper (`tentativa_bloqueada`).

**O que continua em aberto, dito com todas as letras:** `marca_nao_gravada` (o banco falha na escrita
da marca logo depois de commitar a mensagem) deixa a tentativa seguinte cega, e ela diz `published`
— o log é o único sinal; a janela entre a leitura da marca sob o lock e a escrita fora dele converge
pela reemissão seguinte (documentado no colaborador); o `false` do `send_reply` da própria `Message`
continua sem sinal (inalcançável hoje, ver acima); e o duplo envio da ressalva (#393). A mensagem
marcada e nunca reemitida (a execução fechou sem outra passada) continua no banco sem envio, com o
log `mensagem_sem_envio` e a marca — recuperação operacional pelo id (`SendReplyJob.perform_later(<id>)`).

### Rodada 9 (revisão do Codex sobre `a0e502edb5`: 2 P2 + 1 P3 + 1 ressalva; o P2 do LIKE fechado, #393 aceito como escopo) + merge da main: a retomada sob o lock, o recuperador durável, a string vazia, o id do blob

Antes da rodada, a PR estava DIRTY: a main recebeu chat#390 (entrega 13: `quote_offers.rb`,
`premium_text.rb`, `registrar_sem_periodo`/`SEM_PERIODO_KEY` em `insurance_quote.rb`), chat#391
(entrega 7: `build_progress` grava `seguradoras_acionadas`) e chat#387 (#380). `git merge origin/main`
(sem rebase) → merge commit `4829d669bf`. UM conflito, em `insurance_quote.rb`, nas constantes: a main
acrescentou `ACIONADAS_KEY` e `PROPOSTAS_KEY` logo antes de `PDF_SENT_KEY`, cuja explicação esta
branch tinha estendido — resolvido preservando os dois lados (as duas constantes novas E o comentário
estendido). `insurance_quote_ramo_auto_spec.rb` mesclou sozinho (a main acrescentou exemplos da entrega
13 no mesmo `describe` onde esta branch mexeu no helper). A suíte ampla pós-merge achou 2 falhas reais
em `async_run_job_comparativo_arquivo_spec` — os dois exemplos "cotação completa, todos os preços já
entregues" gravavam `DELIVERED_KEY => %w[8 3 47]`, e o `Mock` da main (chat#390) trocou a Justos (47)
pela `OFERTA_SEM_PERIODO` da Bp Assinatura (55): o poll entregava "Mais uma opção" antes do link. É
o dado do mock que mudou, não a regra: `%w[8 3 55]`.

Decisões do orquestrador, obrigatórias; cada correção com spec e mutação (edita → roda → restaura →
md5). Onde este texto se afasta da letra da decisão, diz onde e por quê.

**P2 — dois retries recuperavam a MESMA pendência ao mesmo tempo.** `publicar_sob_lock` achava a
mensagem pelo token sob o lock e devolvia `Duplicada`; `retomar`/`reenviar` corriam FORA do lock, em
`resultado`. Duas tentativas concorrentes (o retry do Sidekiq e a reemissão pelo poll; `AsyncPublishJob`
adiado ×2) liam a marca uma depois da outra, cada uma sob o seu lock, e as duas reenfileiravam — dois
`SendReplyJob`, o documento duas vezes. Correção: a retomada INTEIRA (reler, decidir, enfileirar,
limpar a marca) acontece dentro do `with_lock` — `publicar_sob_lock` devolve `retomar(existente)`
(um `Result`) para a mensagem achada; `resultado` só repassa. A mecânica do reenvio saiu do publicador
(que estava em 168/175 linhas de código) para o colaborador novo `tools/retomada_de_envio.rb`
(`retomar`, `reenviar`, `recuperar`), e a autorização reconferida sob o lock (rodada 7) virou o módulo
`tools/autorizacao_da_execucao.rb` (`autorizacao` → vínculo ou `execucao_morta`/`vinculo_mudou`;
`recusada?`; `vinculo_autorizado`; `mesmo_vinculo?`), incluído pelo publicador E pela retomada — a
MESMA pergunta nos dois lugares. `Duplicada` e `RECUSAS` (no publicador) deixaram de existir; a
publicação recusada continua `blocked` com o mesmo log. FATO LIDO que sustenta o desenho: o
enfileiramento dentro do lock é IMEDIATO — `ActiveJob::Base.enqueue_after_transaction_commit` tem
default `:never` (`activejob 7.2.3.1`, `enqueuing.rb:54`), o app está em `load_defaults 7.0` sem a
chave em `config/`, e só em `:default` o `raw_enqueue` adiaria para depois do commit marcando
`successfully_enqueued = true` ANTES de enfileirar (`enqueue_after_transaction_commit.rb`; o adapter do
Sidekiq 7.3.10 responde `true`). Se um dia esse default mudar, `reenviar` diria "entrou" sem ter
entrado — por isso há uma GUARDA de comportamento, não só o comentário. Guardas (`async_publisher_spec`,
"retomada da pendencia sob o lock da conversa" — o concorrente é simulado no ponto exato do lock,
embrulhando o `with_lock` da conversa que o publicador recebe): (1) o concorrente resolve a pendência
um instante ANTES de o lock ser adquirido → a mensagem é RELIDA sob o lock, UM `SendReplyJob` (o
dele), marca limpa, `published`; (2) o concorrente entra logo DEPOIS de o lock ser solto → não acha
pendência, UM `SendReplyJob` (o nosso); (3) o job está na fila AINDA dentro do lock, antes do commit
(`enqueued_jobs` contado no fim do bloco). Um teste com duas threads reais não é possível aqui: os
specs são transacionais (`use_transactional_fixtures`), e a segunda conexão não veria a conversa. A
`RetomadaDeEnvio` tem spec próprio para o que o job não mostra: `FOR UPDATE` ANTES do `enqueue.active_job`
do `SendReplyJob` (ordem observada por `ActiveSupport::Notifications`) e o objeto VELHO com a marca não
reenvia o que o banco já não tem. Mutações L1 (retomada fora do lock: 2 exemplos), L2 (mensagem lida
antes do lock e usada dentro dele), L3 (recuperar sem o lock), L4 (decidir pelo objeto da varredura,
sem reler); X1–X3 e Y1–Y6 da rodada 7 reajustadas ao módulo e ao colaborador.

**P2 — a marca era persistida, e NENHUM recuperador a consumia.** `AsyncRunJob#apply` publica e
encerra; `comparativo_enviado` impede nova emissão do PDF; `AsyncPublishJob` para em `blocked`; o
Redis voltar não dispara nada. A pendência dependia de uma reemissão que não existe. Correção:
recuperação DURÁVEL no `ReapStaleRunsJob` (`*/10`), `retomar_envios_pendentes`: `PendenciaDeEnvio.marcadas`
varre as mensagens de `AgentBot` criadas nos últimos 2 dias (`index_messages_on_created_at`), `LIMIT
200`, com o predicado SQL da marca — e o CAST PROTEGIDO como em `blobs_sem_dono`: `CASE WHEN
(content_attributes #>> '{}') IS JSON OBJECT THEN (content_attributes #>> '{}')::jsonb END ? :chave`
(binds nomeados). Na escrita uma linha que não é JSON falha sozinha e registrada; na varredura ela
derrubaria a passada inteira. Para cada marcada, o varredor resolve a execução pela própria marca —
`marcar` passou a gravar `autonomia_tool_run_id` ao lado de `autonomia_envio_pendente` (o MESMO nome
da marca do blob, de propósito: é o mesmo conceito em dois lugares) — e chama
`RetomadaDeEnvio.new(run:).recuperar(mensagem)`: trava a conversa da mensagem, RELÊ a mensagem sob o
lock (`Message.find_by`), e decide: sem a marca (outro resolveu) → nada; `source_id` presente →
abandona `canal_confirmou`; nota privada → `nota_privada`; autorização caiu (`autorizacao`, a mesma do
publicador) → abandona `execucao_morta`/`vinculo_mudou`; senão o MESMO `retomar` da tentativa seguinte
(`envio pendente encontrado` → `SendReplyJob.perform_later` → `limpar` → `envio reenfileirado`; ou
`mensagem_sem_envio` de novo, marca mantida). "Abandonar" (`PendenciaDeEnvio.abandonar`) limpa a marca
E a execução e registra `envio pendente abandonado <contexto> message=<id> motivo=<código fechado>`
(`execucao_morta`, `vinculo_mudou`, `canal_confirmou`, `nota_privada`, `sem_conversa`, `sem_execucao`);
a marca sem execução (ou de execução apagada) é abandonada pelo próprio varredor (`contexto=varredor`).
Uma retomada que levanta é registrada (`retomada de envio falhou varredor message=<id> <classe>`) e não
derruba as outras; a marca fica para a próxima passada. Uma execução `done`/`failed` NÃO é morta
(`dead?` é `superseded|discarded|blocked`): a mensagem pendente de uma cotação já encerrada É enviada
pelo varredor — é o caso comum (o Redis caiu na última entrega). Guardas pelo JOB inteiro
(`reap_stale_runs_job_spec`, "envios pendentes"; a mensagem é criada pelo publicador de verdade com a
fila recusando o envio, como em produção): fila volta → exatamente UM `SendReplyJob` com o id dela,
marca e execução saem, token fica, logs `encontrado`/`reenfileirado`; execução `superseded` → nada
enviado, marca limpa, `motivo=execucao_morta`; agente desligado → `vinculo_mudou`, e a marca que não
aponta para execução → `varredor … motivo=sem_execucao`; `source_id` presente → `canal_confirmou`; a
fila continua fora → marca fica, `mensagem_sem_envio`; marcada há 3 dias → fora da janela, intocada.
`pendencia_de_envio_spec` (`.marcadas`): só as do bot com a marca, dentro da janela, as mais antigas
primeiro, até o limite; NULL, `""`, `"nao e json"` não derrubam, e o objeto direto é lido; `abandonar`
limpa e registra. Mutações L5 (sem revalidar), L6 (varredura sem o predicado da marca), L7 (abandonar
sem limpar), L8 (sem registrar), L9 (varredura removida do `perform`), L11 (cast desprotegido), L12
(sem a janela), L13 (sem exigir mensagem do bot), L14 (`canal_confirmou` não abandona), L15 (marca sem
a execução), L16 (marca sem execução não abandonada), L17 (rescue do varredor removido).

**P3 — a string JSON vazia quebrava o cast da marca.** `OBJETO_SQL` era `COALESCE((content_attributes
#>> '{}')::jsonb, '{}')`: com a coluna em `""` (string JSON vazia — o coder nunca a escreve, o banco
aceita), `#>> '{}'` dá `''`, e `''::jsonb` recusa — `marca_nao_gravada` no log e a tentativa seguinte
cega. Correção, na letra da decisão: `COALESCE(NULLIF(content_attributes #>> '{}', ''), '{}')::jsonb`.
Guarda: a MATRIZ das quatro formas (string com objeto, NULL, objeto direto, string vazia) — a marca
entra nas quatro, `json_typeof` volta `'string'`, a `Message` lê de volta, e nada de
`marca_nao_gravada` no log. Mutação L10.

**Ressalva — a chave `autonomia_tool_run_id` no filtro de blobs só precisava existir.** O `?` do jsonb
aceitava `{"autonomia_tool_run_id": null}`. Correção (`blobs_sem_dono`): `jsonb_typeof(metadata::jsonb
-> 'autonomia_tool_run_id') = 'number'` — é o que `marca(run_id:)` grava (inteiro). Guarda: o quinto
impostor (`execucao_nula`) em "nao apaga o que so PARECE marcado". Mutação L18 (volta ao `?`); Q1–Q3
e Z2–Z4 reajustadas ao SQL novo.

**A corrida "B lê antes de A gravar a pendência e devolve `published`" — registrada como pedido.** A
sequência: A cria a mensagem (commit), o despacho levanta (Redis fora), A reconcilia, `reenviar` falha
e A grava a marca FORA do lock (o lock já acabou — a exceção veio depois do commit); B entra no lock
entre o commit de A e a marca de A, acha a mensagem pelo token SEM marca, devolve `published`, e o job
conta a entrega (`record_delivery!`). A marca de A fica, e antes desta rodada ninguém voltava. ESTÁ
FECHADA, mas não por prevenção — por CONVERGÊNCIA: a retomada sob o lock fecha o duplo envio entre
concorrentes que ACHAM a marca; o varredor fecha o "ninguém volta": em até 10 min ele acha a marca de
A, trava a conversa, relê, reconfere a autorização (a execução `done` não é morta) e envia. O que resta,
dito com todas as letras: (a) o cliente recebe até 10 min depois, e o `delivered_count` já contava a
entrega — o desfecho ao cliente não muda de forma; (b) `marca_nao_gravada` (o banco falha na escrita
da marca logo depois de commitar a mensagem) continua invisível para o varredor — o log é o único
sinal; (c) o commit do lock que falha DEPOIS de `reenviar` ter enfileirado (a conexão cai no `COMMIT`)
desfaz a limpeza da marca com o job já na fila → o varredor reenfileira → é a classe do #393 (o
`SendReplyJob` é no-op se o primeiro já gravou `source_id`; só a corrida entre os dois envia em dobro);
(d) `marca_nao_limpa` pela mesma razão do (c), com a mesma convergência (`canal_confirmou` quando o
envio já saiu). Nenhum dos quatro é silencioso.

**Desvios da letra da decisão, ditos:** (1) "extraia um método compartilhado" virou um MÓDULO
(`AutorizacaoDaExecucao`) incluído por duas classes, porque o publicador estava a 7 linhas do
`Metrics/ClassLength` e a retomada precisou de classe própria (`RetomadaDeEnvio`) — o método é um só,
o lugar é um módulo. (2) A retomada pelo varredor abandona também a marcada com `source_id` e a nota
privada (motivos `canal_confirmou`/`nota_privada`), que a decisão não nomeava: sem isso a marca velha
seria achada a cada 10 min para sempre. (3) A marca ganhou a execução (`autonomia_tool_run_id`) em vez
de o varredor derivar a execução do token (`execution_key:digest`): é o dado direto, e some com a marca.
(4) Os helpers da fila (`fila_recusa_o_envio`/`fila_volta`) foram para `spec/support/fila_de_envio_helper.rb`:
três specs precisavam da mesma pré-condição.

### Termos (5)

| # | Termo | Guarda / evidência |
|---|---|---|
| 1 | A comparação chega como ARQUIVO na conversa | `async_run_job_comparativo_arquivo_spec` ("entrega o comparativo como anexo, nomeado pela placa, e depois o fecho": job real + ferramenta real + conector mock + WebMock 200 → `Message` com `Attachment` `file`, `application/pdf`, bytes iguais, legenda sem URL); `async_publisher_spec` "publica o PDF como anexo" |
| 2 | Falha no download não apaga os preços; o link vai como hoje | job spec "cai para o link quando o download falha, sem apagar o preco que ja saiu" (preço publicado ANTES pelo publicador real fica; `delivered_count` igual; texto = `RESERVA + "\n" + url`, o de antes); M1. Rodada 2: URL que a forma recusa → job spec "entrega o link em texto pela consulta…" (caminho `apply`: link em texto, `PDF_SENT_KEY` true, `delivered_count` 2, `done`) e comparativo spec "quando a URL do portal nao tem a forma segura"; M7. Rodada 3: falha do ANEXO (armazenamento) → job spec "…quando o armazenamento falha depois do download" e publisher spec "…sem anexo orfao"; R1 |
| 3 | Exemplo automatizado do caminho de falha | os três exemplos de falha do job spec (404, HTML, armazenamento) + `async_publisher_spec` "cai para o texto com o link… e registra o motivo" (log `motivo=http_404`), "…quando o armazenamento falha…" (log `motivo=armazenamento causa=…`), "…quando o tipo declarado desmente o PDF…" (`tipo_invalido`) e "…quando o anexo nao pode ser publicado…" (`anexo falhou`) + 15 exemplos de recusa em `entrega_de_arquivo_spec` (inclusive 302, IP privado, DNS para dentro, 404 de 32 MB em socket real, prazo do corpo em socket real e armazenamento). Rodada 7: a exceção depois do commit com o envio não disparado → `envio reenfileirado` ou `publicacao incompleta … mensagem_sem_envio` (`blocked`); a autorização que cai durante a transferência → `publicacao recusada … execucao_morta|vinculo_mudou`. Rodada 8: a tentativa seguinte com a pendência gravada → `envio pendente encontrado` + `envio reenfileirado` (ou `mensagem_sem_envio` de novo); a marca que o banco não grava → `pendencia de envio nao gravada … marca_nao_gravada`. Rodada 9: o varredor → os mesmos dois logs, ou `envio pendente abandonado … motivo=<execucao_morta|vinculo_mudou|canal_confirmou|nota_privada|sem_conversa|sem_execucao>`, ou `retomada de envio falhou varredor …` |
| 4 | O arquivo abre no WhatsApp de verdade | **pendente_prova_real** (orquestrador; ver "Produção") |
| 5 | O nome diz o que ele é, sem dado pessoal além do que o cliente já vê | `insurance_quote_comparativo_arquivo_spec` (placa `hik-9383` → "Comparativo de seguro — placa HIK9383.pdf"; sem CPF/CEP no nome; sem placa → ramo); M2 |
| NÃO | Anexo que só funciona quando tudo dá certo | o caminho de falha é exemplo (termo 3) e a reserva é a mesma identidade (M5); Hash que não é entrega nunca vira mensagem (`async_publisher_spec` "descarta, registrado e sem mensagem…", M8); a falha do ARMAZENAMENTO cai na mesma reserva que a do download (R1), sem mensagem com anexo órfão; a falha ao ANEXAR sem mensagem no banco cai na reserva (Y5, M1), e a exceção depois do commit não duplica nem apaga (rodada 6) — e só é `published` com o ENVIO disparado (Y1–Y6, rodada 7); a autorização é reconferida sob o lock (X1–X3, rodada 7); o blob sem dono tem marca e varredor (Z1–Z5, rodada 7); a pendência de envio fica na mensagem e a tentativa seguinte reenvia — token encontrado não é entrega com pendência conhecida (P1–P11, rodada 8); a marca do blob é lida como JSON no nível superior, com as duas chaves e o cast protegido (Q1–Q3, rodada 8); a retomada acontece INTEIRA sob o lock (um job, nunca dois) e o varredor é o recuperador durável da marca que ninguém reemite, com a mesma autorização reconferida (L1–L17, rodada 9); o id da execução no blob tem de ser número (L18) |

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

Rodada 7 (`e11r7/mutacoes_e11_r7.py` no scratchpad: edita → roda → restaura → md5 conferido
antes/depois nos 9 arquivos de código, inclusive `vigia_de_envio.rb`, `reap_stale_runs_job.rb` e os
3 do `SafeFetch`; `mutacoes_r7.json`). X1–X3 (P1), Y1–Y6 (P2 envio), Z1–Z5 (P2 blob), W1–W2
(ressalva) e V2b são as regras novas (17); S1–S8, R5, N1, N2, N2b, V2, V5, Q1, Q2, R1, R2, T1 e
M1–M8 repetidas com o texto reajustado (`PRAZO_SEGUNDOS`; `gravar(run_id:)`; `post` sem
`agent_inbox`; S3b com o `registrar_sem_socket`). S4a virou Y5 e S4b deixou de existir (a
reconciliação pelo token saiu; o que a substitui é Y1–Y6). Na PRIMEIRA passada duas sobreviveram —
Y6 (a spec da transação desfeita levantava em `advance_sequence!`, ANTES da atribuição, e o
`persisted?` nunca era consultado) e Z4 (o `purge` de blob anexado já é barrado pela FK do Rails; a
spec olhava só a existência dos blobs) — e as duas specs foram trocadas pela guarda certa (o
`before_commit` da mensagem levantando; UM `PurgeJob` agendado) e reexecutadas (`--so=Y6,Z4`,
`mutacoes_r7_so.json`): 47 de 47 reprovam. Cada linha: exemplos que reprovam / rodados.

| # | Mutação | Reprova |
|---|---|---|
| X1 | (P1) dead? nao reconferido sob o lock (a execucao supersedida durante o download publica) | 1 de 35 |
| X2 | (P1) vinculo memoizado: a conferencia sob o lock reutiliza a da entrada (agente desligado durante o download publica) | 1 de 35 |
| X3 | (P1) revalidacao sob o lock removida inteira | 2 de 35 |
| Y1 | (P2) mensagem persistida tratada como entregue sem conferir o envio (published no papel) | 2 de 35 |
| Y2 | (P2) vigia ignorado: reenfileira mesmo com o send_reply ja na fila (dois envios) | 1 de 35 |
| Y3 | (P2) falha da recuperacao devolve published (o cliente sem arquivo e sem link, contado como entrega) | 1 de 35 |
| Y4 | (P2) vigia conta o enfileiramento que FALHOU (ignora successfully_enqueued?) | 1 de 35 |
| Y5 | post sem reconciliacao (a excecao depois do commit sobe: reserva por cima da mensagem no ar) | 3 de 35 |
| Y6 | reconciliacao sem exigir persisted? (a mensagem da transacao desfeita e reconciliada) | 1 de 35 |
| Z1 | (P2) blob gravado sem a marca da execucao | 1 de 27 |
| Z2 | (P2) varredor sem o filtro da marca (apaga blob alheio) | 1 de 6 |
| Z3 | (P2) varredor sem o filtro de idade (apaga upload em andamento) | 1 de 6 |
| Z4 | (P2) varredor sem "sem anexo" (apaga o PDF de mensagem entregue) | 1 de 6 |
| Z5 | (P2) varredura dos blobs removida do perform | 2 de 6 |
| W1 | (ressalva) degradacao sem socket em silencio (registro removido) | 1 de 51 |
| W2 | (ressalva) degradacao registrada a cada leitura, nao uma vez por transferencia | 1 de 51 |
| S1 | (P1 SSRF) download de volta ao Down, so com URL_SEGURA: IP privado e DNS para dentro passam | 14 de 27 |
| S2 | (P1) status nao conferido dentro do bloco: o corpo do 404/302 e lido inteiro antes da recusa | 5 de 78 |
| S2b | tamanho anunciado nao conferido antes do corpo | 2 de 78 |
| S3 | (P2) prazo removido da entrega (so tetos por operacao) | 2 de 27 |
| S3f | (P2) prazo nao aplicado no Fetcher (enforce! removido) | 2 de 78 |
| S3b | (P2) cada leitura NAO usa o tempo restante (socket nao apertado; prazo so entre pedacos) | 3 de 78 |
| S3c | tetos por operacao nao limitados pelo prazo | 1 de 51 |
| S5 | (P2) subida do arquivo dentro de transacao | 3 de 27 |
| S5b | (P2) volta ao create_and_upload! em transacao (linha sem arquivo nao vai para a limpeza) | 5 de 67 |
| S6 | (P2) cabecalho externo dentro do motivo (tipo_text_html) | 2 de 62 |
| S8 | so a gravacao (upload) movida para dentro do lock da conversa | 1 de 35 |
| R5 | download e gravacao movidos para dentro do lock da conversa | 1 de 35 |
| N1 | rescue do que ninguem classifica removido: a excecao crua sobe (publish -> blocked) | 2 de 62 |
| N2 | rescue do agendamento da limpeza removido: o Redis fora sobrescreve o resultado / a causa | 4 de 68 |
| N2b | agendamento engolido sem registro (rescue sem warn) | 4 de 68 |
| V2 | o blob ANEXADO tambem vai para a limpeza (sem && !anexado) | 6 de 40 |
| V2b | o blob da mensagem reconciliada (sem mensagem nova) e tratado como sem dono | 3 de 35 |
| V5 | a reserva da entrega de arquivo nao passa pela peneira de texto de cliente | 1 de 11 |
| Q1 | volta ao purge sincrono cru no ensure (a falha do delete sobrescreve o resultado do post) | 9 de 35 |
| Q2 | purge sincrono engolido em rescue no ensure (some o agendamento; o blob sem dono fica) | 9 de 35 |
| R1 | rescue do armazenamento removido: a falha do upload sobe crua (publish -> blocked) | 4 de 67 |
| R2 | redirecionamento seguido de novo (max_redirects 2) | 2 de 27 |
| T1 | temporario do download nao fechado (ensure do with_tempfile removido) | 3 de 78 |
| M1 | fallback removido: post_arquivo sem o rescue Indisponivel | 8 de 40 |
| M2 | nome generico do arquivo | 4 de 11 |
| M3 | teto de tamanho removido (sem max_bytes: o padrao de 40 MB do SafeFetch) | 3 de 27 |
| M4 | assinatura de PDF nao conferida | 2 de 27 |
| M5 | identidade do arquivo trocada pela legenda | 3 de 35 |
| M6 | Progress aceita qualquer Hash como entrega | 4 de 11 |
| M7 | comparativo sem a guarda de forma (Hash invalido sai mesmo assim) | 2 de 11 |
| M8 | publicador sem a guarda (o to_s do Hash vira mensagem, como antes) | 1 de 35 |

Rodada 9 (`e11r9/mutacoes_e11_r9.py` no scratchpad: edita → roda → restaura → md5 conferido
antes/depois nos 12 arquivos de código, inclusive `retomada_de_envio.rb` e `autorizacao_da_execucao.rb`;
`mutacoes_r9.json`). L1–L18 são as regras novas desta rodada (18; L1 e L2 têm DUAS edições cada, para
reproduzir a retomada fora do lock e a leitura antes dele). Na PRIMEIRA passada L17 SOBREVIVEU (o
`rescue` que isola uma retomada que levanta não era exercitado por exemplo nenhum) — regra sem guarda é
intenção: ganhou "registra a retomada que levanta e segue para as outras" no `reap_stale_runs_job_spec`
e foi reexecutada sozinha (`--so=L17`, `mutacoes_r9_so.json`). P1–P11, Q1–Q3, X1–X3, Y1–Y6, Z1–Z5, W1–W2,
S1–S8, R5, N1, N2, N2b, V2, V2b, V5, Q1x, Q2x, R1, R2, T1 e M1–M8 repetidas com o texto reajustado
(P1/P3/P4/P5/Y3 à `RetomadaDeEnvio`; P2 ao `return retomar(existente)`; X1/X2 ao módulo
`AutorizacaoDaExecucao`; X3 à `autorizacao`/`recusada?`; Q1/Q3/Z2–Z4 ao `jsonb_typeof`; Z5 ao `perform`
com a varredura nova). 79 de 79 reprovam e restauram. Cada linha: exemplos que reprovam / rodados.

| # | Mutação | Reprova |
|---|---|---|
| L1 | (P2) retomada FORA do lock: a mensagem achada sob o lock e retomada depois de solta-lo (dois SendReplyJob) | 2 de 43 |
| L2 | (P2) mensagem lida ANTES do lock e usada dentro dele (sem releitura: o concorrente que resolveu um instante antes nao e visto) | 1 de 43 |
| L3 | (P2) varredor: recuperar SEM o lock da conversa | 1 de 2 |
| L4 | (P2) varredor: decide pelo objeto que veio da varredura, sem reler sob o lock | 1 de 2 |
| L5 | (P2) varredor: sem revalidar a autorizacao (execucao morta / agente desligado reenviam) | 2 de 13 |
| L6 | (P2) varredura sem o predicado da marca (toda mensagem do bot entra) | 2 de 8 |
| L7 | (P2) abandonar sem limpar a marca (o varredor a acharia a cada 10 min) | 4 de 21 |
| L8 | abandonar sem registrar o motivo | 4 de 21 |
| L9 | (P2) varredura dos envios pendentes removida do perform | 5 de 13 |
| L10 | (P3) OBJETO_SQL sem NULLIF (a string JSON vazia derruba a marca) | 1 de 8 |
| L11 | varredura com cast desprotegido (a linha que nao e JSON derruba a passada) | 1 de 8 |
| L12 | varredura sem a janela de dois dias | 2 de 21 |
| L13 | varredura sem exigir mensagem do bot | 1 de 8 |
| L14 | varredor: a marcada que o canal ja confirmou fica marcada (sem abandonar) | 1 de 13 |
| L15 | (P2) a marca sem a execucao que publicou (o varredor nao tem autorizacao para reconferir) | 6 de 13 |
| L16 | varredor: a marca sem execucao nao e abandonada (RetomadaDeEnvio com run nil levanta, e a marca fica) | 1 de 13 |
| L17 | varredor: uma retomada que levanta derruba as outras (rescue removido) | 1 de 14 |
| L18 | (ressalva) blob: o id da execucao so precisa existir (null passa) | 1 de 13 |
| P1 | (P2) retomar ignora a pendencia: token encontrado e sempre published (falso sucesso no retry) | 6 de 56 |
| P2 | (P2) a mensagem achada pelo token e devolvida como published sem passar por retomar | 4 de 43 |
| P3 | (P2) pendencia nao gravada quando a recuperacao falha | 9 de 43 |
| P4 | pendencia nao limpa quando o reenvio entra (marca velha reenvia de novo) | 3 de 43 |
| P5 | (ressalva) false de perform_later tratado como sucesso | 1 de 43 |
| P6 | pendencia sem exigir source_id vazio (reenvia o que o canal ja confirmou) | 2 de 51 |
| P7 | pendencia sem excluir a nota privada | 1 de 8 |
| P8 | marca gravada por substituicao (perde token e sequencia) | 10 de 51 |
| P9 | marca gravada como objeto JSON, nao como a string que o coder da Message le | 12 de 51 |
| P10 | falha da escrita da marca sobe (rescue removido) | 1 de 8 |
| P11 | falha da escrita da marca engolida sem registro | 1 de 8 |
| Q1 | (P2) varredor de blobs de volta ao LIKE sobre o texto (curinga, aninhado, sem run id) | 1 de 13 |
| Q2 | (P2) cast para jsonb sem a guarda IS JSON (linha nao-JSON derruba a varredura) | 1 de 13 |
| Q3 | (P2) id da execucao nao exigido na marca do blob | 1 de 13 |
| X1 | (P1) dead? nao reconferido sob o lock (a execucao supersedida durante o download publica) | 2 de 43 |
| X2 | (P1) vinculo memoizado: a conferencia sob o lock reutiliza a da entrada (agente desligado durante o download publica) | 1 de 43 |
| X3 | (P1) revalidacao sob o lock removida inteira | 2 de 43 |
| Y1 | (P2) mensagem persistida tratada como entregue sem conferir o envio (published no papel) | 10 de 43 |
| Y2 | (P2) vigia ignorado: reenfileira mesmo com o send_reply ja na fila (dois envios) | 1 de 43 |
| Y3 | (P2) falha da recuperacao devolve sucesso (o cliente sem arquivo e sem link, contado como entrega) | 9 de 43 |
| Y4 | (P2) vigia conta o enfileiramento que FALHOU (ignora successfully_enqueued?) | 8 de 43 |
| Y5 | post sem reconciliacao (a excecao depois do commit sobe: reserva por cima da mensagem no ar) | 11 de 43 |
| Y6 | reconciliacao sem exigir persisted? (a mensagem da transacao desfeita e reconciliada) | 1 de 43 |
| Z1 | (P2) blob gravado sem a marca da execucao | 1 de 27 |
| Z2 | (P2) varredor sem o filtro da marca (apaga blob alheio) | 2 de 13 |
| Z3 | (P2) varredor sem o filtro de idade (apaga upload em andamento) | 1 de 13 |
| Z4 | (P2) varredor sem "sem anexo" (apaga o PDF de mensagem entregue) | 1 de 13 |
| Z5 | (P2) varredura dos blobs removida do perform | 3 de 13 |
| W1 | (ressalva) degradacao sem socket em silencio (registro removido) | 1 de 51 |
| W2 | (ressalva) degradacao registrada a cada leitura, nao uma vez por transferencia | 1 de 51 |
| S1 | (P1 SSRF) download de volta ao Down, so com URL_SEGURA: IP privado e DNS para dentro passam | 14 de 27 |
| S2 | (P1) status nao conferido dentro do bloco: o corpo do 404/302 e lido inteiro antes da recusa | 5 de 78 |
| S2b | tamanho anunciado nao conferido antes do corpo | 2 de 78 |
| S3 | (P2) prazo removido da entrega (so tetos por operacao) | 2 de 27 |
| S3f | (P2) prazo nao aplicado no Fetcher (enforce! removido) | 2 de 78 |
| S3b | (P2) cada leitura NAO usa o tempo restante (socket nao apertado; prazo so entre pedacos) | 3 de 78 |
| S3c | tetos por operacao nao limitados pelo prazo | 1 de 51 |
| S5 | (P2) subida do arquivo dentro de transacao | 3 de 27 |
| S5b | (P2) volta ao create_and_upload! em transacao (linha sem arquivo nao vai para a limpeza) | 5 de 75 |
| S6 | (P2) cabecalho externo dentro do motivo (tipo_text_html) | 2 de 70 |
| S8 | so a gravacao (upload) movida para dentro do lock da conversa | 1 de 43 |
| R5 | download e gravacao movidos para dentro do lock da conversa | 1 de 43 |
| N1 | rescue do que ninguem classifica removido: a excecao crua sobe (publish -> blocked) | 2 de 70 |
| N2 | rescue do agendamento da limpeza removido: o Redis fora sobrescreve o resultado / a causa | 4 de 83 |
| N2b | agendamento engolido sem registro (rescue sem warn) | 4 de 83 |
| V2 | o blob ANEXADO tambem vai para a limpeza (sem && !anexado) | 7 de 48 |
| V2b | o blob da mensagem reconciliada (sem mensagem nova) e tratado como sem dono | 4 de 43 |
| V5 | a reserva da entrega de arquivo nao passa pela peneira de texto de cliente | 1 de 11 |
| Q1x | volta ao purge sincrono cru no ensure (a falha do delete sobrescreve o resultado do post) | 10 de 43 |
| Q2x | purge sincrono engolido em rescue no ensure (some o agendamento; o blob sem dono fica) | 10 de 43 |
| R1 | rescue do armazenamento removido: a falha do upload sobe crua (publish -> blocked) | 4 de 75 |
| R2 | redirecionamento seguido de novo (max_redirects 2) | 2 de 27 |
| T1 | temporario do download nao fechado (ensure do with_tempfile removido) | 3 de 78 |
| M1 | fallback removido: post_arquivo sem o rescue Indisponivel | 8 de 48 |
| M2 | nome generico do arquivo | 4 de 11 |
| M3 | teto de tamanho removido (sem max_bytes: o padrao de 40 MB do SafeFetch) | 3 de 27 |
| M4 | assinatura de PDF nao conferida | 2 de 27 |
| M5 | identidade do arquivo trocada pela legenda | 5 de 43 |
| M6 | Progress aceita qualquer Hash como entrega | 4 de 11 |
| M7 | comparativo sem a guarda de forma (Hash invalido sai mesmo assim) | 2 de 11 |
| M8 | publicador sem a guarda (o to_s do Hash vira mensagem, como antes) | 1 de 43 |

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

- Rodada 7: `async_publisher_spec` 35 (era 29: +5 "quando a publicacao levanta depois do commit",
  +2 "quando a autorizacao cai durante a transferencia"; o exemplo antigo da exceção depois do
  commit passou a exigir o `SendReplyJob` enfileirado), `entrega_de_arquivo_spec` 27 (marca do blob
  afirmada; `gravar(run_id:)`), `reap_stale_runs_job_spec` 6 (era 4), `safe_fetch_spec` 51 (era 49),
  `async_run_job_comparativo_arquivo_spec` 5: specs alvo 124 exemplos, 0 falhas, 0 erros fora
  (`e11r7/alvo1.json`, exit 0; `alvo3.json` depois das duas guardas trocadas: 41, 0 falhas); rubocop
  nos 12 arquivos tocados (+ `vigia_de_envio.rb`): 0 ofensas (`e11r7/rubocop*.json` — a única ofensa
  da primeira passada foi uma linha de 154 colunas na spec, quebrada); 47 mutações, todas reprovam e
  restauram, md5 idêntico antes/depois nos 9 arquivos de código (`e11r7/mutacoes_r7.json`;
  `mutacoes_r7_so.json` para Y6 e Z4, que sobreviveram na primeira passada e ganharam a guarda
  certa); suíte ampla `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia spec/lib/safe_fetch_spec.rb spec/lib/webhooks/trigger_spec.rb
  spec/jobs/avatar/avatar_from_url_job_spec.rb
  spec/enterprise/services/voice/provider/twilio/recording_attachment_service_spec.rb`: 1170 exemplos,
  0 falhas, 3 pendentes anteriores a esta PR (`RegistrationCheckout::Provisioner` ×2,
  `Sso::Provisioner`), 0 erros fora de exemplo, exit 0 (`e11r7/ampla_r7.json`). Sob WebMock, todo
  download com `total_timeout` agora registra `total_timeout degradado motivo=sem_socket` no log de
  teste — é o registro da degradação, esperado ali (não há socket) e inexistente em produção.

- Rodada 8: `async_publisher_spec` 40 (era 35: +5 em "quando a publicacao levanta depois do commit" —
  a tentativa seguinte reenvia e limpa a marca; preserva token/sequência/anexo; a fila continua fora;
  `false` de `perform_later`; a mensagem marcada que o canal confirmou; e o retry do link passou a
  exigir UM `SendReplyJob`), `pendencia_de_envio_spec` 4 (novo), `entrega_de_arquivo_spec` 27,
  `reap_stale_runs_job_spec` 7 (era 6: os impostores da marca e o `metadata` que não é JSON): 78
  exemplos, 0 falhas, 0 erros fora (`e11r8/alvo4.json`, exit 0); consumidores do publicador
  (`async_run_job_comparativo_arquivo_spec`, `async_run_job_encerramento_parcial_spec`,
  `async_run_job_spec`, `progress_spec`, `insurance_quote_comparativo_arquivo_spec`): 46 exemplos, 0
  falhas (`e11r8/alvo3.json`, exit 0). A primeira passada dos specs novos (`e11r8/alvo1.json`) achou 5
  falhas reais — o UPDATE com `||` direto sobre o `content_attributes` virava ARRAY (a coluna guarda
  uma STRING JSON): sonda no banco (`e11r8/sonda.txt`: `json_typeof` = `string`), SQL corrigido
  (`#>> '{}'` + `to_json`), verde em `alvo2.json`. rubocop nos 7 arquivos tocados (+
  `pendencia_de_envio.rb` e o spec dele): 0 ofensas (`e11r8/rubocop2.json` + `rubocop3.json`; as
  duas ofensas da passada anterior — `ClassLength` 184/175 e `MultipleExpectations` 13/7 — viraram o
  colaborador e o exemplo dividido; as duas linhas longas do spec novo foram quebradas). 61
  mutações (14 novas — P1–P11, Q1–Q3 — e as 47 da rodada 7 reajustadas: Y3 ao `causa`, Z2–Z4 ao SQL
  novo), todas reprovam e restauram, md5 idêntico antes/depois nos 10 arquivos de código
  (`e11r8/mutacoes_r8.json`). Suíte ampla `spec/services/autonomia spec/jobs/autonomia
  spec/models/autonomia spec/requests/api/v1/accounts/autonomia spec/lib/safe_fetch_spec.rb
  spec/lib/webhooks/trigger_spec.rb spec/jobs/avatar/avatar_from_url_job_spec.rb
  spec/enterprise/services/voice/provider/twilio/recording_attachment_service_spec.rb`: 1180
  exemplos, 0 falhas, 3 pendentes anteriores a esta PR (`RegistrationCheckout::Provisioner` ×2,
  `Sso::Provisioner`), 0 erros fora de exemplo, exit 0 (`e11r8/ampla_r8.json`).

- Rodada 9 (depois do merge da main, `4829d669bf`): `async_publisher_spec` 43 (era 40: +3 "retomada
  da pendencia sob o lock da conversa"), `retomada_de_envio_spec` 2 (novo), `pendencia_de_envio_spec`
  8 (era 4: a matriz das quatro formas, `abandonar`, e `.marcadas` ×2), `reap_stale_runs_job_spec` 14
  (era 7: +7 "envios pendentes", e o quinto impostor do blob), `entrega_de_arquivo_spec` 27,
  `async_run_job_comparativo_arquivo_spec` 5 (os dois exemplos da cotação completa com `%w[8 3 55]`,
  o que o mock da main passou a devolver): 98 exemplos, 0 falhas, 0 erros fora
  (`e11r9/alvo4.json`, exit 0; `alvo5.json`: o varredor com o exemplo de L17, 14, 0 falhas). A primeira passada (`alvo1.json`) achou 1 falha real — o caminho do
  varredor ia direto a `reenviar` e não registrava `envio pendente encontrado`; `decidir` passou a
  terminar no MESMO `retomar` da tentativa seguinte, e o log conta a mesma história dos dois lados. A
  terceira (`alvo3.json`) achou outra — `lock!` recusa registro com mudança não persistida
  (`display_id` do `let`); o spec passou a ler a mensagem do banco, como o varredor lê. rubocop nos 16
  arquivos tocados (código, specs, `spec/support/fila_de_envio_helper.rb`): 0 ofensas
  (`e11r9/rubocop1.json`, `rubocop2.json`, `rubocop3.json`, `rubocop4.json`). 79 mutações, todas reprovam e restauram,
  md5 idêntico antes/depois nos 12 arquivos de código (`e11r9/mutacoes_r9.json`, `md5_antes.txt` =
  `md5_depois.txt`). Suíte ampla `spec/services/autonomia spec/jobs/autonomia spec/models/autonomia
  spec/requests/api/v1/accounts/autonomia spec/lib/safe_fetch_spec.rb spec/lib/webhooks/trigger_spec.rb
  spec/jobs/avatar/avatar_from_url_job_spec.rb
  spec/enterprise/services/voice/provider/twilio/recording_attachment_service_spec.rb
  spec/controllers/super_admin/insurance_measurements_controller_spec.rb`: 1364 exemplos,
  0 falhas, 3 pendentes anteriores a esta PR, 0 erros fora de exemplo,
  exit 0 (`e11r9/ampla_r9.json`). Pós-merge, antes da rodada (`suite_pos_merge.json`): 1348 exemplos,
  2 falhas — as duas do mock (acima).

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
   Rodada 7: `publicacao recusada run=<id> motivo=<execucao_morta|vinculo_mudou>` é a autorização
   que caiu durante a transferência (nada publicado; o blob vai ao `PurgeJob`); `publicacao levantou
   depois do commit run=<id> message=<id> causa=<classe>` seguido de `envio reenfileirado …` é a
   mensagem no banco com o envio disparado pelo publicador (o cliente recebe); `publicacao incompleta
   run=<id> message=<id> motivo=mensagem_sem_envio causa=<classe>` é a mensagem no banco SEM envio
   (o Redis recusou também a recuperação) — recuperação operacional pelo id da mensagem
   (`SendReplyJob.perform_later(<id>)`, que é no-op se ela já saiu). O varredor (`*/10`) apaga os
   blobs marcados (`metadata` com `autonomia_finalidade=entrega_de_arquivo`) sem anexo há mais de
   1 h; `blob sem dono nao agendado varredor blob=<id>` é o Redis recusando esse agendamento.
   `[safe_fetch] total_timeout degradado motivo=sem_socket` em produção significa o acoplamento com
   o net-http rompido (sem teto por leitura; o prazo vale só entre pedaços) — não deve aparecer.
   Rodada 8: depois de um `publicacao incompleta … mensagem_sem_envio`, a mensagem carrega
   `content_attributes.autonomia_envio_pendente = true`; a reemissão seguinte da mesma entrega mostra
   `envio pendente encontrado run=<id> message=<id>` seguido de `envio reenfileirado …` (o cliente
   recebe; a marca sai) ou de outro `mensagem_sem_envio` (a marca fica). `pendencia de envio nao
   gravada … motivo=<marca_nao_gravada|marca_nao_limpa>` é o banco falhando na marca — com
   `marca_nao_gravada`, a reemissão seguinte dirá `published` sem reenviar: recuperação operacional
   pelo id. `causa=enqueue_recusado` é o `perform_later` devolvendo `false` sem exceção (não deve
   aparecer com o Sidekiq). O varredor de blobs passou a exigir Postgres 16+ (`IS JSON`; produção é
   18): um `PG::SyntaxError` em `recolher_blobs_sem_dono` seria um Postgres anterior — não é o caso.
   Rodada 9: depois de um `publicacao incompleta … mensagem_sem_envio`, em até 10 min o varredor mostra
   `envio pendente encontrado run=<id> message=<id>` + `envio reenfileirado …` (o cliente recebe, sem
   depender de reemissão) — ou `envio pendente abandonado run=<id> message=<id> motivo=<execucao_morta|
   vinculo_mudou|canal_confirmou|nota_privada|sem_conversa>` (a marca sai, nada é enviado; `canal_confirmou`
   é a marca velha de um envio que já saiu), ou `envio pendente abandonado varredor message=<id>
   motivo=sem_execucao` (marca sem execução — não deve aparecer com mensagens desta versão). `retomada
   de envio falhou varredor message=<id> <classe>` é uma retomada que levantou (a marca fica para a
   próxima passada). A varredura das marcadas (`marcadas`) também exige Postgres 16+ (`IS JSON`).
   Dois `SendReplyJob` para a mesma mensagem só pela classe do #393 (o Redis aceita e perde a resposta;
   ou o `COMMIT` do lock cai depois do enfileiramento) — o segundo é no-op se o primeiro já gravou
   `source_id`.
3. Rollback: reverter o deploy; não há dado novo no banco (o handle não mudou de forma; a marca do
   blob é `metadata` de linhas novas, ignorada por quem não a conhece).

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
uv run --no-project python3 e11r7/mutacoes_e11_r7.py                    # rodada 7: X1–X3, Y1–Y6, Z1–Z5, W1–W2, V2b (17 novas) + 30 anteriores reajustadas (47), todas reprovam, md5 restaurado
uv run --no-project python3 e11r8/mutacoes_e11_r8.py                    # rodada 8: P1–P11, Q1–Q3 (14 novas) + 47 anteriores reajustadas (61), todas reprovam, md5 restaurado
git fetch origin main && git merge origin/main                          # rodada 9: 1 conflito (insurance_quote.rb, constantes), os dois lados preservados → 4829d669bf
uv run --no-project python3 e11r9/mutacoes_e11_r9.py                    # rodada 9: L1–L18 (18 novas) + 61 anteriores reajustadas (79), todas reprovam, md5 restaurado
gh issue create --repo autonom-ia2/chat --title "Envio da mesma mensagem não é serializado no SendReplyJob" --body-file e11r8/issue_sendreply.md   # → #393
bundle exec rspec spec/lib/safe_fetch_spec.rb spec/jobs/avatar/avatar_from_url_job_spec.rb spec/services/autonomia/agents/tools/http_executor_spec.rb spec/services/twilio/media_download_service_spec.rb spec/services/website_branding_service_spec.rb spec/lib/webhooks/trigger_spec.rb spec/controllers/api/v1/upload_controller_spec.rb   # consumidores do SafeFetch, antes e depois: 109 ex, 0 falhas
bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia --format json --out ampla.json
npx tsx src/cli/main.ts agger quote proposal <id>  (×3, só print; nenhum quote start) + curl -I na URL → 404 BlobNotFound
```
