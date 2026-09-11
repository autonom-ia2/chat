# A ENTREGA QUE É UM ARQUIVO, e não um texto (entrega 11 do Agente de Cotação).
#
# Até 11/09/2026 toda entrega de uma ferramenta assíncrona era uma String, e o comparativo em PDF
# chegava ao cliente como "Comparativo com todas as opções:\n<url>". Quem está no WhatsApp espera o
# arquivo na conversa — um link é uma aba do navegador, um arquivo é o que ele guarda e reencaminha.
#
# O QUE VIAJA é a forma serializada (`to_h`, chaves de texto): a entrega atravessa o `Progress`, o
# handle e os argumentos do `AsyncPublishJob` (Sidekiq), e bytes não cabem ali. Os bytes só existem
# no momento da publicação (`#gravar`), dentro do job, e o download é do `SafeFetch` (o cliente HTTP
# da casa, sobre o `ssrf_filter`): a URL vem de fora (o blob do portal do AGGER) e o que ela responde
# não é promessa nossa — o endereço efetivamente conectado é conferido (nada de rede privada, nem
# por DNS), o status é lido antes do corpo, o corpo é lido em fluxo com teto de bytes e prazo do corpo
# com teto por leitura, e os bytes têm de começar com a assinatura de PDF: um 404 do armazenamento do
# portal vem como XML de `BlobNotFound`, e sem a assinatura esse XML chegaria ao cliente com nome de PDF.
#
# O ARQUIVO É GRAVADO NO ARMAZENAMENTO AQUI (`#gravar`), antes de existir mensagem: o ActiveStorage
# sobe o arquivo no `after_commit` da mensagem, e uma subida que falhasse ali deixaria a mensagem
# no ar com a legenda e um anexo sem bytes — o cliente sem arquivo e sem link, e o token já
# publicado fazendo qualquer retry virar duplicado (rodada 3 de revisão, 11/09/2026). Gravando
# antes, a falha do armazenamento é `Indisponivel` como a do download, e cai na mesma reserva.
#
# A RESERVA é o texto com o link, o mesmo de antes: quando o download ou a gravação falham, o
# cliente recebe o link como recebia — os preços que já saíram não voltam, e a falha do arquivo não
# pode apagar a entrega. O publicador decide isso; este objeto só carrega os dois caminhos.
class Autonomia::Agents::Tools::EntregaDeArquivo
  CHAVE = 'arquivo'.freeze
  # Um comparativo de auto tem dezenas de KB; o teto é folga de cem vezes, não medida. Existe para o
  # worker não engolir o que quer que a URL responda: o tamanho anunciado reprova antes do primeiro
  # byte, e o corpo é lido em fluxo e interrompido ao passar do teto — o arquivo é baixado ANTES do
  # lock da conversa.
  TETO_BYTES = 10.megabytes
  # PRAZO DO CORPO COM TETO POR LEITURA (`total_timeout:` do `SafeFetch`), monotônico, abaixo dos 25 s
  # de shutdown do Sidekiq desta instalação: um deploy no meio do download não pode deixar a
  # publicação pela metade. Teto por leitura sozinho não segura um servidor que entrega um byte por
  # segundo — ele nunca estoura a leitura e prende o worker pelo tempo que quiser (rodada 6,
  # 11/09/2026); com o prazo, cada leitura do corpo espera no máximo o que resta dele, e a conexão e
  # a espera pelos cabeçalhos ficam limitadas a ele como teto por operação.
  #
  # O QUE O PRAZO NÃO COBRE (ressalva registrada na rodada 7, decisão de não implementar um orçamento
  # cancelável — uma thread vigia fechando o socket é risco maior que o benefício aqui): a resolução
  # de DNS (antes da conexão, no `Resolv` do sistema), cabeçalhos que gotejam abaixo do teto por
  # leitura, e as linhas de controle do chunked entre dois pedaços. Modelo de ameaça: a URL vem do
  # nosso adapter (o blob do portal, https, sem redirecionamento), a abertura tem 5 s, cada leitura
  # é limitada pelo saldo; só um gotejamento de cabeçalhos abaixo do saldo evade — e o shutdown do
  # Sidekiq (25 s) encerra o job de qualquer forma.
  PRAZO_SEGUNDOS = 20
  # Teto da conexão (TCP + TLS), dentro do prazo.
  ABERTURA_SEGUNDOS = 5
  # NENHUM redirecionamento: o blob do portal é servido direto, e "só https" (URL_SEGURA) valeria
  # só para o primeiro salto — um 302 para http levaria o download para o transporte sem proteção
  # que a forma recusou. O 3xx é recusado sem ler o corpo e sem ir aonde aponta.
  REDIRECIONAMENTOS = 0
  ASSINATURA_PDF = '%PDF-'.freeze
  TIPO_PDF = 'application/pdf'.freeze
  # O que um servidor pode declarar sem desmentir um PDF: o tipo certo, ou "bytes" (é assim que o
  # armazenamento do portal responde). Qualquer outro tipo é recusa, mesmo com os bytes certos.
  TIPOS_ACEITOS = [TIPO_PDF, 'application/octet-stream', 'binary/octet-stream'].freeze
  # Só https, NA FORMA: o arquivo vai para a conversa de um cliente com o nosso nome, e a URL sem
  # transporte protegido pode ser trocada no caminho. A forma não protege a rede — quem confere o
  # endereço efetivamente conectado (IP privado, DNS que resolve para dentro, metadata da nuvem) é
  # o `SafeFetch`, no download (rodada 6, 11/09/2026).
  URL_SEGURA = %r{\Ahttps://\S+\z}i
  NOME_DE_PDF = %r{\A[^/\\]+\.pdf\z}i
  # As classes de tempo que o `SafeFetch` embrulha em `FetchError` (a causa, não a mensagem, é o que
  # separa "tempo" de "rede caída").
  CAUSAS_DE_TEMPO = [Net::OpenTimeout, Net::ReadTimeout].freeze
  # A MARCA do blob (rodada 7, 11/09/2026): a execução que o gravou e a finalidade, no `metadata` do
  # `ActiveStorage::Blob`. A linha do blob é salva ANTES da mensagem, e o processo pode morrer entre
  # uma e a outra — sem a marca, a linha (com ou sem arquivo) ficava sem dono e sem ninguém que a
  # reconhecesse. É por ela que o `ReapStaleRunsJob` acha e apaga o que ficou (`blobs_sem_dono`).
  EXECUCAO_CHAVE = 'autonomia_tool_run_id'.freeze
  FINALIDADE_CHAVE = 'autonomia_finalidade'.freeze
  # A finalidade nomeia QUEM GRAVA (esta classe), não o produto: se outra ferramenta entregar arquivo
  # por aqui, o varredor continua reconhecendo o blob dela.
  FINALIDADE = 'entrega_de_arquivo'.freeze

  # O download ou a gravação não puderam entregar um PDF. `motivo` é um código curto FECHADO (nunca o
  # texto da resposta, um cabeçalho, nem a mensagem da exceção): vai para o log, e o publicador cai
  # para a reserva. `causa` é o NOME DA CLASSE da exceção de origem, quando há uma — o armazenamento
  # e a rede falham de muitos jeitos e o log precisa dizer qual, sem a mensagem.
  class Indisponivel < StandardError
    attr_reader :motivo, :causa

    def initialize(motivo, causa: nil)
      @motivo = motivo
      @causa = causa
      super("arquivo indisponivel: #{motivo}")
    end
  end

  attr_reader :url, :nome, :legenda, :reserva

  # -> a entrega, quando `valor` é uma (o objeto ou a forma serializada dele, válida); nil para
  # qualquer outra coisa — texto comum, Hash de outra forma, forma incompleta.
  def self.de(valor)
    return valor if valor.is_a?(self)
    return nil unless valor.is_a?(Hash)

    forma = valor.deep_stringify_keys[CHAVE]
    return nil unless forma.is_a?(Hash)

    entrega = new(url: forma['url'], nome: forma['nome'], legenda: forma['legenda'], reserva: forma['reserva'])
    entrega.valida? ? entrega : nil
  end

  # A LIMPEZA DE UM BLOB SEM DONO É CORTESIA: `purge_later` fala com o Redis, e o Redis fora não pode
  # trocar o resultado nem a causa de quem chamou (rodadas 4 e 5, 11/09/2026). Registra com o id do
  # blob (para a limpeza manual) e a classe da causa, e não levanta. `contexto` diz de onde veio o
  # pedido (`run=<id>` no publicador; `gravacao` aqui; `varredor` no `ReapStaleRunsJob`). O `PurgeJob`
  # vai para a fila `default` do Sidekiq (`ActiveStorage.queues[:purge]` não está configurado nesta
  # instalação), que retenta.
  def self.agendar_limpeza(blob, contexto:)
    blob.purge_later
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] blob sem dono nao agendado #{contexto} blob=#{blob.id} causa=#{e.class}")
  end

  # O `metadata` que marca o blob de uma execução (ver `EXECUCAO_CHAVE`).
  def self.marca(run_id:)
    { EXECUCAO_CHAVE => run_id, FINALIDADE_CHAVE => FINALIDADE }
  end

  # -> os blobs COM A MARCA desta classe, SEM ANEXO e criados antes de `antes_de` — os que ficaram sem
  # dono porque o processo morreu entre a linha e o anexo. Os três filtros são a guarda: sem a marca,
  # apagaríamos blobs alheios; sem a idade, um upload em andamento (a linha existe antes do anexo);
  # sem "sem anexo", o PDF de uma mensagem entregue. A marca é procurada no `metadata` (texto JSON,
  # escrito pelo coder do Rails) pelo par `"chave":"valor"` tal como ele o grava — o mesmo padrão dos
  # tokens da mensagem. É uma varredura sequencial da tabela de blobs (não há índice para isto); roda a
  # cada 10 min com `limite`, e o custo está registrado na auditoria da rodada 7.
  def self.blobs_sem_dono(antes_de:, limite:)
    ActiveStorage::Blob.unattached
                       .where(created_at: ...antes_de)
                       .where('metadata LIKE ?', "%#{marca_no_texto}%")
                       .order(:created_at).limit(limite)
  end

  # `"autonomia_finalidade":"entrega_de_arquivo"`, como o coder JSON do `metadata` escreve (sem espaços).
  def self.marca_no_texto
    ActiveSupport::JSON.encode(FINALIDADE_CHAVE => FINALIDADE)[1..-2]
  end

  def initialize(url:, nome:, legenda:, reserva:)
    @url = url.to_s.strip
    @nome = nome.to_s.strip
    @legenda = legenda.to_s.strip
    @reserva = reserva.to_s.strip
  end

  def valida?
    defeito.nil?
  end

  # O CAMPO que reprova a forma, como código curto ('url', 'nome', 'legenda', 'reserva'), ou nil
  # quando a forma é válida. É o que vai ao log de quem cai para o link (a ferramenta) ou descarta
  # (o publicador): o nome do campo, nunca o valor — a URL e os textos são dados de fora.
  def defeito
    return 'url' unless url.match?(URL_SEGURA)
    return 'nome' unless nome.match?(NOME_DE_PDF)
    return 'legenda' if legenda.blank?

    'reserva' if reserva.blank?
  end

  def to_h
    { CHAVE => { 'url' => url, 'nome' => nome, 'legenda' => legenda, 'reserva' => reserva } }
  end

  # A identidade da entrega, para o token de publicação: a MESMA como arquivo e como reserva. Um
  # retry que encontra o link já publicado não publica o arquivo por cima, e vice-versa.
  def identidade
    "arquivo:#{url}"
  end

  # -> `ActiveStorage::Blob` gravado (arquivo já no armazenamento, linha salva, com a MARCA da
  # execução `run_id`), pronto para ser anexado pelo `signed_id`. Levanta `Indisponivel` na falha do
  # download (`#baixar`) e na do armazenamento (motivo `armazenamento`, com a classe da exceção em
  # `causa`). O arquivo temporário do download vive só dentro do bloco e é fechado sempre — gravado
  # ou não.
  def gravar(run_id:)
    baixar { |pdf| gravar_blob(pdf, run_id) }
  end

  private

  # Baixa a URL pelo `SafeFetch`, confere o que veio e ENTREGA o `Tempfile` (aberto, rebobinado) ao
  # bloco; devolve o que o bloco devolver. O temporário é do `SafeFetch`: fechado e apagado ao sair
  # do bloco, em qualquer caminho. Levanta `Indisponivel` em QUALQUER falha, com motivo fechado:
  # `url_insegura` (endereço privado, DNS que resolve para dentro, esquema), `redirecionamento`,
  # `http_<status>` (lido ANTES do corpo — o corpo de um 404 nunca é materializado), `tamanho`
  # (anunciado ou medido), `tempo` (o prazo, ou uma conexão/leitura que estourou), `download` com a
  # classe da causa (o resto da rede, e o que o `SafeFetch` não classifica), `tipo_invalido` e
  # `nao_e_pdf` (as conferências). O bloco tem de falhar como `Indisponivel` (é o que `gravar_blob`
  # faz): o último `rescue` não distingue a falha dele da da transferência.
  def baixar
    SafeFetch.fetch(url, validate_content_type: false, max_bytes: TETO_BYTES, max_redirects: REDIRECIONAMENTOS,
                         open_timeout: ABERTURA_SEGUNDOS, read_timeout: PRAZO_SEGUNDOS,
                         total_timeout: PRAZO_SEGUNDOS) do |resposta|
      conferir(resposta)
      yield resposta.tempfile
    end
  rescue Indisponivel
    raise
  rescue SafeFetch::UnsafeUrlError, SafeFetch::InvalidUrlError
    raise Indisponivel, 'url_insegura'
  rescue SafeFetch::HttpError => e
    raise Indisponivel, motivo_http(e.status)
  rescue SafeFetch::FileTooLargeError
    raise Indisponivel, 'tamanho'
  rescue SafeFetch::FetchError => e
    raise indisponivel_da_rede(e)
  rescue StandardError => e
    raise Indisponivel.new('download', causa: e.class.name)
  end

  # Só o INTEIRO do status entra no motivo: a frase da resposta (`e.message`) é do servidor.
  def motivo_http(status)
    return 'redirecionamento' if (300..399).cover?(status.to_i)

    "http_#{status.to_i}"
  end

  # -> a `Indisponivel` da falha de rede que o `SafeFetch` embrulhou: `tempo` para o prazo e para a
  # conexão ou leitura que estourou (pela CAUSA, `e.cause` — o que o Ruby guarda ao relançar; a mensagem
  # não entra), `download` com a classe da causa para o resto.
  def indisponivel_da_rede(erro)
    tempo = erro.is_a?(SafeFetch::TotalTimeoutError) || CAUSAS_DE_TEMPO.any? { |classe| erro.cause.is_a?(classe) }
    return Indisponivel.new('tempo') if tempo

    Indisponivel.new('download', causa: (erro.cause || erro).class.name)
  end

  # DUAS FASES, para o armazenamento ficar FORA de transação: a linha do blob é salva sozinha (um
  # INSERT, na transação curta dele), e só então o arquivo sobe. `create_and_upload!` dentro de uma
  # transação segurava a conexão do banco durante a subida ao S3 — e os timeouts do cliente S3 são
  # os padrões do aws-sdk (rodada 6, 11/09/2026). A subida que falha deixa uma linha sem arquivo:
  # ela vai para a limpeza em segundo plano (`agendar_limpeza`, o mesmo caminho do blob sem dono do
  # publicador), e a recusa é `armazenamento` com a classe da causa. Se o processo morrer entre a
  # linha e o anexo, a MARCA (`metadata`) é o que permite ao varredor apagá-la depois (rodada 7).
  # `identify: false` porque o tipo já foi conferido pelos bytes. `build_after_unfurling`/
  # `upload_without_unfurling` são as duas metades de `create_and_upload!` (activestorage 7.2.3.1).
  def gravar_blob(pdf, run_id)
    blob = ActiveStorage::Blob.build_after_unfurling(io: pdf, filename: nome, content_type: TIPO_PDF, identify: false,
                                                     metadata: self.class.marca(run_id: run_id))
    blob.save!
    blob.upload_without_unfurling(pdf)
    blob
  rescue StandardError => e
    self.class.agendar_limpeza(blob, contexto: 'gravacao') if blob&.persisted?
    raise Indisponivel.new('armazenamento', causa: e.class.name)
  end

  # As duas conferências sobre o que já foi baixado: o tipo declarado (normalizado pelo `SafeFetch`)
  # e a assinatura dos bytes.
  def conferir(resposta)
    conferir_tipo!(resposta.content_type)
    conferir_assinatura!(resposta.tempfile)
  end

  # Motivo FECHADO: o valor do cabeçalho é do servidor e não entra no log — antes saía
  # `tipo_text_html`, com o cabeçalho externo dentro do código (rodada 6, 11/09/2026).
  def conferir_tipo!(tipo)
    declarado = tipo.to_s.strip.downcase
    return if declarado.blank? || TIPOS_ACEITOS.include?(declarado)

    raise Indisponivel, 'tipo_invalido'
  end

  def conferir_assinatura!(tempfile)
    tempfile.rewind
    inicio = tempfile.read(ASSINATURA_PDF.bytesize).to_s
    tempfile.rewind
    raise Indisponivel, 'nao_e_pdf' unless inicio == ASSINATURA_PDF
  end
end
