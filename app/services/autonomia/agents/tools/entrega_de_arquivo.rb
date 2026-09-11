# A ENTREGA QUE É UM ARQUIVO, e não um texto (entrega 11 do Agente de Cotação).
#
# Até 11/09/2026 toda entrega de uma ferramenta assíncrona era uma String, e o comparativo em PDF
# chegava ao cliente como "Comparativo com todas as opções:\n<url>". Quem está no WhatsApp espera o
# arquivo na conversa — um link é uma aba do navegador, um arquivo é o que ele guarda e reencaminha.
#
# O QUE VIAJA é a forma serializada (`to_h`, chaves de texto): a entrega atravessa o `Progress`, o
# handle e os argumentos do `AsyncPublishJob` (Sidekiq), e bytes não cabem ali. Os bytes só existem
# no momento da publicação (`#gravar`), dentro do job, com três guardas no download — teto de
# tamanho, teto de tempo e assinatura de PDF — porque a URL vem de fora (o blob do portal do AGGER)
# e o que ela responde não é promessa nossa: um 404 do armazenamento do portal vem como XML de
# `BlobNotFound`, e sem a assinatura esse XML chegaria ao cliente com nome de PDF.
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
  # worker não engolir o que quer que a URL responda — o arquivo é baixado ANTES do lock da conversa.
  TETO_BYTES = 10.megabytes
  # Tetos de rede abaixo dos 25 s de shutdown do Sidekiq desta instalação: um deploy no meio do
  # download não pode deixar a publicação pela metade.
  ABERTURA_SEGUNDOS = 5
  LEITURA_SEGUNDOS = 15
  # NENHUM redirecionamento: o blob do portal é servido direto, e "só https" (URL_SEGURA) valeria
  # só para o primeiro salto — um 302 para http levaria o download para o transporte sem proteção
  # que a forma recusou.
  REDIRECIONAMENTOS = 0
  ASSINATURA_PDF = '%PDF-'.freeze
  TIPO_PDF = 'application/pdf'.freeze
  # O que um servidor pode declarar sem desmentir um PDF: o tipo certo, ou "bytes" (é assim que o
  # armazenamento do portal responde). Qualquer outro tipo é recusa, mesmo com os bytes certos.
  TIPOS_ACEITOS = [TIPO_PDF, 'application/octet-stream', 'binary/octet-stream'].freeze
  # Só https: o arquivo vai para a conversa de um cliente com o nosso nome; a URL sem transporte
  # protegido pode ser trocada no caminho.
  URL_SEGURA = %r{\Ahttps://\S+\z}i
  NOME_DE_PDF = %r{\A[^/\\]+\.pdf\z}i

  # O download ou a gravação não puderam entregar um PDF. `motivo` é um código curto (nunca o
  # texto da resposta nem da exceção): vai para o log, e o publicador cai para a reserva. `causa` é
  # o NOME DA CLASSE da exceção de origem, quando há uma — o armazenamento falha de muitos jeitos
  # (rede, credencial, integridade) e o log precisa dizer qual, sem a mensagem.
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

  # -> `ActiveStorage::Blob` gravado (arquivo já no armazenamento, linha salva), pronto para ser
  # anexado pelo `signed_id`. Levanta `Indisponivel` na falha do download (`#baixar`) e na do
  # armazenamento (motivo `armazenamento`, com a classe da exceção em `causa`). O arquivo
  # temporário é fechado sempre — publicado ou não.
  #
  # `create_and_upload!` salva a linha ANTES de subir o arquivo (é assim que o Rails evita a
  # colisão de chave); a transação em volta é o que faz a subida que falha não deixar uma linha
  # de blob sem arquivo no banco. `identify: false` porque o tipo já foi conferido pelos bytes.
  def gravar
    tempfile = baixar
    begin
      ActiveStorage::Blob.transaction do
        ActiveStorage::Blob.create_and_upload!(io: tempfile, filename: nome, content_type: TIPO_PDF, identify: false)
      end
    rescue StandardError => e
      raise Indisponivel.new('armazenamento', causa: e.class.name)
    end
  ensure
    tempfile&.close!
  end

  # -> o `Tempfile` com o PDF (o que o `Down` baixou), aberto e rebobinado. Levanta `Indisponivel`
  # em qualquer falha: resposta que não é 200, redirecionamento, tamanho acima do teto (anunciado
  # ou medido durante o download), tempo, o que a camada HTTP levantar, tipo declarado que
  # desmente, bytes sem a assinatura de PDF — e, na recusa, o arquivo temporário já baixado é
  # fechado aqui, porque quem chama não o recebe. Quem recebe o `Tempfile` é quem o fecha.
  #
  # A transferência e a conferência são dois métodos porque os rescues da transferência não podem
  # alcançar a conferência: `conferir` levanta `Indisponivel` com o motivo dela (`nao_e_pdf`,
  # `tipo_…`), e um `rescue StandardError` no mesmo corpo a reembrulharia como `download`.
  def baixar
    conferir(transferir)
  end

  private

  # -> o `Tempfile` cru, como o `Down` o baixou. O Down (5.4.0, `request_error!`) só dá classe sua
  # a tempo, `SystemCallError`, `EOFError`/`IOError`/`SocketError` e SSL; o resto — uma resposta
  # HTTP malformada (`Net::HTTPBadResponse`), `Net::WriteTimeout`, erro de `Zlib` — sobe cru. O
  # contrato de `baixar` é "`Indisponivel` em qualquer falha", e sem o último rescue a exceção crua
  # saía do publicador como `blocked`: o cliente sem arquivo NEM link (rodada 5, 11/09/2026). O
  # motivo é `download` com a classe da causa — o mesmo padrão de `gravar` para o armazenamento.
  def transferir
    Down.download(url, max_size: TETO_BYTES, open_timeout: ABERTURA_SEGUNDOS,
                       read_timeout: LEITURA_SEGUNDOS, max_redirects: REDIRECIONAMENTOS)
  rescue Down::TooLarge
    raise Indisponivel, 'tamanho'
  rescue Down::TimeoutError
    raise Indisponivel, 'tempo'
  rescue Down::TooManyRedirects
    raise Indisponivel, 'redirecionamento'
  rescue Down::ResponseError => e
    raise Indisponivel, "http_#{e.response&.code.to_s.gsub(/[^0-9]/, '').presence || 'erro'}"
  rescue Down::Error => e
    raise Indisponivel, e.class.name.demodulize.underscore
  rescue StandardError => e
    raise Indisponivel.new('download', causa: e.class.name)
  end

  # As duas conferências sobre o que já foi baixado. O `Tempfile` fica em disco até o GC se a
  # recusa sair sem fechá-lo: são até 10 MB por comparativo recusado, no worker.
  def conferir(tempfile)
    conferir_tipo!(tempfile.content_type)
    conferir_assinatura!(tempfile)
    tempfile
  rescue Indisponivel
    tempfile.close!
    raise
  end

  def conferir_tipo!(tipo)
    declarado = tipo.to_s.split(';').first.to_s.strip.downcase
    return if declarado.blank? || TIPOS_ACEITOS.include?(declarado)

    raise Indisponivel, "tipo_#{declarado.gsub(/[^a-z0-9]+/, '_')[0, 40]}"
  end

  def conferir_assinatura!(tempfile)
    tempfile.rewind
    inicio = tempfile.read(ASSINATURA_PDF.bytesize).to_s
    tempfile.rewind
    raise Indisponivel, 'nao_e_pdf' unless inicio == ASSINATURA_PDF
  end
end
