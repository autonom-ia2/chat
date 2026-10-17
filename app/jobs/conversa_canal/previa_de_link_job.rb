# Monta a prévia de link de uma mensagem (#1702), fora do caminho da mensagem: fila low, depois do create.
# Grava `content_attributes.link_preview = { url, title, description, site_name, image_url }` e o update dispara
# o message.updated de sempre, que leva a prévia ao painel. `image_url` é o caminho da cópia no nosso servidor
# (ConversaCanal::ImagemDaPrevia), nunca o endereço do site.
# Falha (site fora, lento, recusado pelo SafeFetch, sem título) = mensagem sem prévia: log info e mais nada,
# sem erro para ninguém e sem nova tentativa. O que a página diz fica em cache por endereço por 24 h; falha de
# rede não entra no cache, para a próxima mensagem com o mesmo endereço tentar de novo.
# Cota por conta: qualquer cliente manda texto com endereço, e cada um faz o servidor ler uma página de fora. Passou de
# COTA leituras novas no minuto, a mensagem fica sem prévia (o cache continua servindo os endereços já lidos).
class ConversaCanal::PreviaDeLinkJob < ApplicationJob
  queue_as :low

  CACHE_VALIDADE = 24.hours
  COTA = 30
  JANELA_DA_COTA = 1.minute
  SEM_PREVIA = {}.freeze

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message && ConversaCanal::PreviaDeLink.buscar?(message)

    url = ConversaCanal::PreviaDeLink.endereco(message.content)
    pagina = ler_com_cache(url, message)
    return if pagina.blank?

    gravar(message, pagina)
  end

  private

  def ler_com_cache(url, message)
    chave = "conversa_canal:previa_de_link:#{Digest::SHA256.hexdigest(url)}"
    guardada = Rails.cache.read(chave)
    return guardada unless guardada.nil?
    return sem_cota(message) unless dentro_da_cota?(message.account_id)

    pagina = ConversaCanal::LeitorDeOpenGraph.ler(url) || SEM_PREVIA
    Rails.cache.write(chave, pagina, expires_in: CACHE_VALIDADE)
    pagina
  rescue SafeFetch::Error, Nokogiri::SyntaxError, Encoding::Error => e
    registrar(message.id, e)
    nil
  end

  def dentro_da_cota?(account_id)
    chave = "conversa_canal:previa_de_link:cota:#{account_id}:#{Time.current.to_i / JANELA_DA_COTA.to_i}"
    leituras = Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, JANELA_DA_COTA.to_i * 2) if leituras == 1
    leituras <= COTA
  end

  def sem_cota(message)
    Rails.logger.info("[conversa_canal][previa_de_link] sem prévia message=#{message.id} cota da conta no minuto")
    nil
  end

  def gravar(message, pagina)
    imagem = imagem_da(message, pagina['image_source'])
    previa = pagina.except('image_source').merge('image_url' => imagem).compact

    message.with_lock do
      ConversaCanal::GravarNaMensagem.atualizar!(
        message, content_attributes: message.content_attributes.merge(ConversaCanal::PreviaDeLink::CHAVE => previa)
      )
    end
  end

  # Sem imagem a prévia continua, só com texto.
  def imagem_da(message, endereco)
    return if endereco.blank?

    ConversaCanal::ImagemDaPrevia.new(message, endereco).guardar
  rescue SafeFetch::Error, ActiveStorage::Error => e
    registrar(message.id, e)
    nil
  end

  # Só a classe e a mensagem: o endereço pode ter dado pessoal na query string.
  def registrar(message_id, erro)
    Rails.logger.info("[conversa_canal][previa_de_link] sem prévia message=#{message_id} #{erro.class}")
  end
end
