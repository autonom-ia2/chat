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
(`AsyncPublisher`), na hora de publicar, FORA do lock da conversa, com três guardas — teto de
tamanho (10 MB, anunciado e medido), tetos de tempo (5 s de conexão, 15 s de leitura, abaixo dos
25 s de shutdown do Sidekiq) e assinatura de PDF (`%PDF-`, mais o tipo declarado que não pode
desmentir) —, sem seguir redirecionamento, GRAVA o blob no armazenamento ainda fora do lock
(`EntregaDeArquivo#gravar`, rodada 3) e anexa o blob gravado (pelo `signed_id`) pelo
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
  presentes), identidade (`arquivo:<url>`) e `#baixar` (Down com `max_size`, `open_timeout`,
  `read_timeout`, `max_redirects`; `Indisponivel` com motivo curto: `tamanho`, `tempo`,
  `http_404`, `tipo_text_html`, `nao_e_pdf`…).
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

### Termos (5)

| # | Termo | Guarda / evidência |
|---|---|---|
| 1 | A comparação chega como ARQUIVO na conversa | `async_run_job_comparativo_arquivo_spec` ("entrega o comparativo como anexo, nomeado pela placa, e depois o fecho": job real + ferramenta real + conector mock + WebMock 200 → `Message` com `Attachment` `file`, `application/pdf`, bytes iguais, legenda sem URL); `async_publisher_spec` "publica o PDF como anexo" |
| 2 | Falha no download não apaga os preços; o link vai como hoje | job spec "cai para o link quando o download falha, sem apagar o preco que ja saiu" (preço publicado ANTES pelo publicador real fica; `delivered_count` igual; texto = `RESERVA + "\n" + url`, o de antes); M1. Rodada 2: URL que a forma recusa → job spec "entrega o link em texto pela consulta…" (caminho `apply`: link em texto, `PDF_SENT_KEY` true, `delivered_count` 2, `done`) e comparativo spec "quando a URL do portal nao tem a forma segura"; M7. Rodada 3: falha do ANEXO (armazenamento) → job spec "…quando o armazenamento falha depois do download" e publisher spec "…sem anexo orfao"; R1 |
| 3 | Exemplo automatizado do caminho de falha | os três exemplos de falha do job spec (404, HTML, armazenamento) + `async_publisher_spec` "cai para o texto com o link… e registra o motivo" (log `motivo=http_404`) e "…quando o armazenamento falha…" (log `motivo=armazenamento causa=…`) + 8 exemplos de recusa em `entrega_de_arquivo_spec` (inclusive 302 e armazenamento) |
| 4 | O arquivo abre no WhatsApp de verdade | **pendente_prova_real** (orquestrador; ver "Produção") |
| 5 | O nome diz o que ele é, sem dado pessoal além do que o cliente já vê | `insurance_quote_comparativo_arquivo_spec` (placa `hik-9383` → "Comparativo de seguro — placa HIK9383.pdf"; sem CPF/CEP no nome; sem placa → ramo); M2 |
| NÃO | Anexo que só funciona quando tudo dá certo | o caminho de falha é exemplo (termo 3) e a reserva é a mesma identidade (M5); Hash que não é entrega nunca vira mensagem (`async_publisher_spec` "descarta, registrado e sem mensagem…", M8); a falha do ANEXO cai na mesma reserva que a do download (R1), sem mensagem com anexo órfão |

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
   indisponivel run=<id> motivo=<http_404|armazenamento causa=…|…>; vai como link`. Nenhum
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
bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia --format json --out ampla.json
npx tsx src/cli/main.ts agger quote proposal <id>  (×3, só print; nenhum quote start) + curl -I na URL → 404 BlobNotFound
```
