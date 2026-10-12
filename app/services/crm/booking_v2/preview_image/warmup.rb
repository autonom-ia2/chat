# Pré-aquecimento da imagem de prévia do link (#1303): desenhar em job, fora do pedido web, para o robô de prévia
# encontrar a imagem já guardada.
#
# Quando roda:
# - a página foi salva pelo painel (marca, logo, foto, título, pessoas, publicar);
# - um pedido web achou o teto de desenhos cheio;
# - a varredura achou o teto cheio para uma página;
# - o desenho mudou (`Content::RENDER_VERSION` subiu) e todas as imagens guardadas ficaram velhas: `sweep_once`, no
#   primeiro pedido que não acha a imagem guardada, enfileira UMA varredura das páginas no ar por versão do desenho.
#
# Nos três primeiros casos, `later_once`: no máximo UM job esperando na fila por página. A marca sai quando o job começa
# (`PreviewImageWarmJob#perform`), então uma gravação feita durante o job ainda enfileira outro, e o job lê a página
# como ela está quando roda. Sem isso, quem tem login conseguia encher a fila `low` (que vem antes de outras filas no
# Sidekiq) repetindo gravações. A marca expira em `QUEUED_SECONDS` se o job sumir.
#
# O pedido web continua podendo desenhar (dentro do teto do `DrawLimit`) quando chega antes do job: a versão da imagem
# também depende de coisas que não passam pelo painel da página (nome e foto do perfil de quem atende, idioma da
# conta), e responder a imagem neutra no primeiro pedido deixaria a prévia errada na conversa de quem recebeu o link.
#
# Tudo aqui é idempotente: imagem já guardada na versão atual não é desenhada de novo.
class Crm::BookingV2::PreviewImage::Warmup
  QUEUED_PREFIX = 'CRM_BOOKING_PREVIEW_IMAGE_WARM_QUEUED'.freeze
  QUEUED_SECONDS = 5.minutes.to_i
  SWEEP_PREFIX = 'CRM_BOOKING_PREVIEW_IMAGE_SWEPT'.freeze
  SWEEP_SECONDS = 30.days.to_i

  def self.later_once(profile)
    enqueue_once(queued_key(profile.id), QUEUED_SECONDS) { ::Crm::BookingV2::PreviewImageWarmJob.perform_later(profile.id) }
  end

  def self.sweep_once
    enqueue_once(sweep_key, SWEEP_SECONDS) { ::Crm::BookingV2::PreviewImageSweepJob.perform_later }
  end

  def self.queued_key(profile_id)
    "#{QUEUED_PREFIX}::#{profile_id}"
  end

  def self.sweep_key
    "#{SWEEP_PREFIX}::#{::Crm::BookingV2::PreviewImage::Content::RENDER_VERSION}"
  end

  # Desenha o que falta da página: a imagem dela e a de cada link por pessoa. Devolve o resultado de cada endereço
  # (`:stored`, `:drawn`, `:neutral`, `:failed` ou o motivo de não ter desenhado: ver `Store#skipped`).
  def self.page(profile)
    [profile.slug, *profile.agent_booking_links.pluck(:slug)].map { |slug| image(slug) }
  end

  # Um endereço que falha não impede os outros. A falha fica marcada no `Store` (não é tentada de novo a cada job).
  def self.image(slug)
    preview = ::Crm::BookingV2::LinkPreview.for_slug(slug)
    return :neutral if preview.neutral?

    ::Crm::BookingV2::PreviewImage::Store.new(::Crm::BookingV2::PreviewImage::Content.new(preview)).warm
  rescue StandardError, LoadError => e
    Rails.logger.error("Booking preview warmup failed: #{e.class.name}")
    ChatwootExceptionTracker.new(e).capture_exception
    :failed
  end
  private_class_method :image

  # A marca só fica se o job entrou na fila: falhou ao enfileirar, a próxima tentativa enfileira de novo.
  def self.enqueue_once(key, seconds)
    return unless ::Redis::Alfred.set(key, '1', nx: true, ex: seconds)

    begin
      yield
    rescue StandardError
      ::Redis::Alfred.delete(key)
      raise
    end
  end
  private_class_method :enqueue_once
end
