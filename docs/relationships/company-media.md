# Mídias de Empresa — #757

Extensão Enterprise aditiva. Requer companies e relationships_company_media.
Não altera endpoint, consulta ou layout de mídias de Contato.

## API e escopo

`GET /api/v1/accounts/:account_id/companies/:company_id/media` aceita q (nome), contact_id,
type (image/audio/video/file), from/to (YYYY-MM-DD), group=contact, page e per_page (5/25/50).
A conta, o company_id atual dos contatos, a autorização de conversas existente e mensagens
das conversas permitidas limitam a relação SQL antes da busca, contagem e paginação.
Notas privadas entram quando a pessoa pode acessar a conversa, como no catálogo existente. Nenhuma inferência por company_name ou participantes.
Mover o contato altera o histórico visível pela associação atual, sem copiar originais.

Busca em todo o acervo autorizado; ordem created_at DESC + id DESC. Agrupamento adiciona
contact_id antes dessa ordem no SQL, atravessando páginas. Cada Attachment representa uma
ocorrência; arquivos homônimos e bytes iguais não são deduplicados. Autor da mensagem e
contato da conversa são campos diferentes. Preload cobre arquivo/blob, autor e contato.

`GET /media/contacts?q=...` pesquisa contatos dentro do escopo permitido e limita opções a 50.
`GET /media/:id` revalida a empresa, conta, conversa e devolve URL do storage por 60 segundos,
com disposition attachment; inline=true permite visualização apenas de tipos seguros listados.
`GET /media/:id/preview` repete a autorização, devolve JPEG derivado ou status pending/unavailable.
Respostas são private/no-store. Não há URL nova permanente na listagem.

Período inclui o início de from até o início do dia seguinte a to no reporting_timezone
da conta. Na ausência dessa configuração, UTC, conforme documentado ao usuário. Não se
infere fuso pelo nome da conta ou pelo usuário.

## Conversão

Sob demanda ao abrir arquivos visíveis; nenhum backfill/deploy gera thumbs em massa.
Job na fila low existente. Entrada até 25 MiB, saída JPEG até 2 MiB, subprocesso até 15 s,
CPU 10 s, memória de processo limitada a 512 MiB no Linux, limite de descritores; um conversor por banco via advisory lock 757005.
Lock ocupado reagenda a cada 10 s enquanto a demanda tem menos de dez minutos;
expiração permite nova solicitação. Disputa de capacidade nunca vira falha permanente.
Original único; derivado associado por ActiveStorage. Status por blob em Attachment.meta,
idempotência por derivado e deduplicação de pedidos por dez minutos. O slot é global
entre workers ligados ao mesmo banco; não altera configuração de Sidekiq.

Imagens JPEG/PNG/WebP: assinatura real conferida antes de executar FFmpeg, com demuxer fixo (`jpeg_pipe`, `png_pipe`, `webp_pipe`), protocolo apenas arquivo local e uma thread. Imagens pequenas não são ampliadas. O limite de endereço virtual permanece em 512 MiB, sem depender de iniciar Ruby/libvips dentro do processo limitado. O libvips existente permanece disponível para o restante da aplicação e para conferir as fixtures de teste.
PDF: pdftoppm, primeira página. Vídeo: ffmpeg, um frame, uma thread, protocolo file e demuxer fixo mov/matroska conforme tipo declarado; playlists disfarçadas são recusadas.
Áudio/formatos ativos como SVG: ícone neutro. Não há serviço externo, OCR ou leitura de
conteúdo. Falhas/corrupção/limites mantêm original disponível. O cliente solicita ao entrar no viewport, consulta a cada 5 s por até 11 minutos e oferece
retry explícito. Sair do viewport ou contexto interrompe consultas e descarta respostas.

Runtime declarado: Dockerfile mantém vips/poppler e acrescenta ffmpeg, sem instalar globalmente.
A retomada validou conversão real PNG/PDF/MP4, arquivo corrompido e playlist disfarçada,
usando fixtures sintéticas e as ferramentas portáteis preparadas pelo supervisor.
macOS rejeitou RLIMIT_AS e RLIMIT_RSS com EINVAL; testes nativos nesse sistema não
certificam isolamento de memória. O código aplica RLIMIT_AS de 512 MiB no runtime Linux.
A imagem Linux, expansão adversarial, limites e fila real continuam gates obrigatórios.

## Performance a homologar

Limites definidos para medição: páginas 25/50; crescimento de 25 para 50 ocorrências
não deve acrescentar consultas por registro (tolerância de 2 consultas auxiliares);
consulta sem conversão síncrona; p95 alvo de 500 ms em base sintética de 1.000 ocorrências.
Query count/latência da API ainda não medidos: sandbox bloqueia conexão ao banco isolado.

## Escopo e apresentação

A lateral consulta cinco ocorrências recentes e apresenta tipo MIME e tamanho reais.
Visualizar tudo mantém filtros e abre tabela/paginação 25, com busca e agrupamento no servidor.
O catálogo cobre arquivos armazenados (ActiveStorage). URLs externas não são buscadas,
baixadas nem convertidas no servidor; esses anexos continuam disponíveis pela conversa
original no produto. O texto de escopo deixa essa limitação explícita; não promete todo
acervo externo. Conversa autorizada é condição para metadados, contagens, original e preview.
O derivado só é servido quando ready_blob_id coincide com o blob atual; troca do original
requer outra conversão. Falha de subprocesso não pode promover saída parcial a preview válido.
A adição da dependência no Dockerfile não prova execução na imagem: permanece gate do supervisor.
