# Imagem de prévia do link de agendamento (#1282): `GET /book/:slug/preview/:version.png`, o `og:image` das páginas
# `/a/…`, `/book/…` e `/b/…`. Sem login: como na casca, só o slug opaco identifica a página.
#
# O `:version` do endereço não escolhe nada: só existe a imagem atual da página. Endereço na versão atual: a imagem,
# com cache de um ano (o endereço muda quando a marca muda) e ETag (quem já tem a imagem recebe 304 sem o servidor
# ler o arquivo). Endereço em outra versão — antigo, guardado por quem montou a prévia antes da mudança, ou
# inventado: redireciona para o atual, sem ler nem desenhar nada, então inventar versões não gera trabalho.
#
# NUNCA 500 e nunca 404: página que não pode ser marcada (inexistente, pausada, antiga, conta sem a flag) responde a
# imagem neutra de `public/booking-preview.png`, com cache curto — a mesma resposta para todos os casos, então a
# imagem não conta se a página existe. Desenho em andamento em outro pedido, desenho que falhou há pouco, teto de
# desenhos da instalação cheio (#1303), libvips ausente ou qualquer erro: a mesma imagem neutra, mas SEM cache
# (`no-store`), para ninguém guardar a neutra no endereço de uma página que tem imagem própria. O motivo vai para o log.
#
# O desenho normalmente já foi feito em job (`PreviewImage::Warmup`, #1303). O pedido que chega antes do job desenha
# aqui mesmo, dentro do teto global (`PreviewImage::DrawLimit`): um robô pedindo páginas diferentes não ocupa mais
# que esse teto, e o resto recebe a neutra.
#
# Herda de ActionController::Base, como a casca (`PagesController`): rota pública, sem sessão nem login.
class PublicBooking::PreviewImagesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  CURRENT_TTL = 1.year
  REDIRECT_TTL = 5.minutes
  NEUTRAL_TTL = 5.minutes

  def show
    preview = ::Crm::BookingV2::LinkPreview.for_slug(params[:slug])
    return send_neutral(cache: true) if preview.neutral?

    content = ::Crm::BookingV2::PreviewImage::Content.new(preview)
    return redirect_to_current(preview.page.slug, content.version) unless params[:version].to_s == content.version

    send_page_image(preview, content)
  rescue StandardError, LoadError => e
    Rails.logger.error("Booking preview image failed: #{e.class.name}")
    ChatwootExceptionTracker.new(e).capture_exception
    send_neutral(cache: false)
  end

  private

  def send_page_image(preview, content)
    expires_in CURRENT_TTL, public: true
    response.cache_control[:extras] = ['immutable']
    return unless stale?(etag: content.version, public: true)

    store = ::Crm::BookingV2::PreviewImage::Store.new(content)
    png = store.stored || draw(store, preview.profile)
    return send_neutral(cache: false) if png.nil?

    send_data png, type: ::Crm::BookingV2::PreviewImage::CONTENT_TYPE, disposition: 'inline'
  end

  # Não há imagem guardada na versão atual. Se foi o desenho que mudou, as outras páginas estão na mesma situação:
  # a varredura (uma por versão do desenho) cuida delas em job. Esta é desenhada agora, se houver vaga; com o teto
  # cheio, vai para a fila e este pedido leva a neutra.
  def draw(store, profile)
    ::Crm::BookingV2::PreviewImage::Warmup.sweep_once
    png = store.draw
    return png if png

    Rails.logger.info("Booking preview image not drawn: #{store.skipped}")
    ::Crm::BookingV2::PreviewImage::Warmup.later_once(profile) if store.skipped == :draw_limit
    nil
  end

  # Caminho no próprio site, com o slug da página achada e a versão calculada aqui: nada vem do pedido.
  def redirect_to_current(slug, version)
    expires_in REDIRECT_TTL, public: true
    redirect_to "/book/#{slug}/preview/#{version}.png", status: :found
  end

  def send_neutral(cache:)
    response.headers.delete('ETag')
    cache ? expires_in(NEUTRAL_TTL, public: true) : no_store
    send_file ::Crm::BookingV2::PreviewImage.neutral_path, type: ::Crm::BookingV2::PreviewImage::CONTENT_TYPE, disposition: 'inline'
  end
end
