# Aviso de clique de uma página (botão "falar no WhatsApp" de uma landing page, #1011).
#
# A página abre o WhatsApp na hora com `#TOKEN` no texto e, em paralelo, avisa aqui com
# `navigator.sendBeacon` (corpo text/plain, sem preflight). Quando o cliente manda a
# mensagem, o Ctwa::TrackedLinkAttributor acha o clique pelo token e liga a conversa.
#
# Endpoint anônimo: sem sessão, sem CSRF, só origens que o dono do link autorizou. O header
# Origin não autentica (fora do navegador ele é forjável): a defesa real contra volume é o
# limite por link (Rack::Attack + teto diário aqui).
# Contrato: docs/crm/ponte-lp-atribuicao.md (seção 2).
# rubocop:disable Rails/ApplicationController
class Public::TrackedLinkSignalsController < ActionController::Base
  MAX_BODY_BYTES = Middleware::TrackedLinkSignalGuard::MAX_BODY_BYTES
  CORS_MAX_AGE = '600'.freeze

  skip_forgery_protection
  # O corpo nunca vira params: o Middleware::TrackedLinkSignalGuard troca o content-type para
  # text/plain antes do Rails; isto impede o Rails de copiar params para uma chave embrulhada.
  wrap_parameters false
  before_action :skip_session
  before_action :load_tracked_link
  before_action :authorize_origin

  def preflight
    head :no_content
  end

  def create
    body = read_body
    return head :content_too_large if body.nil?

    signal = Ctwa::WebsiteSignal.new(body: parse_json(body), origin: @origin, remote_ip: request.remote_ip, user_agent: request.user_agent)
    return head :unprocessable_entity unless signal.valid_token?

    head(existing_click_status(signal.token) || new_click_status(signal))
  end

  private

  def skip_session
    request.session_options[:skip] = true
  end

  def load_tracked_link
    code = request.path_parameters[:code].to_s.upcase
    @tracked_link = Ctwa::TrackedLink.find_by(code: code)
    head :not_found unless @tracked_link&.website?
  end

  def authorize_origin
    origin = request.headers['Origin']
    return head :forbidden unless @tracked_link.origin_allowed?(origin)

    @origin = Ctwa::TrackedLink.normalize_origin(origin)
    set_cors_headers
  end

  def set_cors_headers
    response.set_header('Access-Control-Allow-Origin', @origin)
    response.set_header('Vary', 'Origin')
    response.set_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
    response.set_header('Access-Control-Allow-Headers', 'Content-Type')
    response.set_header('Access-Control-Max-Age', CORS_MAX_AGE)
  end

  # nil quando passa do limite; lê no máximo um byte além dele.
  def read_body
    return if request.content_length.to_i > MAX_BODY_BYTES

    raw = request.body.read(MAX_BODY_BYTES + 1).to_s
    raw.bytesize > MAX_BODY_BYTES ? nil : raw
  end

  def parse_json(raw)
    JSON.parse(raw.force_encoding(Encoding::UTF_8))
  rescue JSON::ParserError, EncodingError
    {}
  end

  # Mesmo token no mesmo link = reenvio (204, nada muda). Em outro link = conflito.
  def existing_click_status(token)
    click = Ctwa::TrackedLinkClick.find_by(token: token)
    return if click.blank?

    click.tracked_link_id == @tracked_link.id ? :no_content : :conflict
  end

  def new_click_status(signal)
    return daily_limit_reached if @tracked_link.signals_daily_limit_reached?

    record_click!(signal)
    :no_content
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    # Só a corrida do mesmo token (o segundo aviso perde no índice/validação de unicidade)
    # vira resposta; qualquer outro erro de gravação sobe.
    raise unless token_race?(e)

    status = existing_click_status(signal.token)
    raise if status.nil?

    status
  end

  def token_race?(error)
    error.is_a?(ActiveRecord::RecordNotUnique) || error.record.errors.of_kind?(:token, :taken)
  end

  # Volume anormal (CA-1.11): uma página real não passa do teto num dia; acima, é abuso ou
  # ataque ao teto. O aviso legítimo também é recusado, então o bloqueio não pode ser
  # silencioso: vai ao log com o link, e a tela mostra (signals_blocked no payload).
  def daily_limit_reached
    Rails.logger.warn("[TrackedLinkSignals] daily limit reached: tracked_link_id=#{@tracked_link.id} " \
                      "account_id=#{@tracked_link.account_id} limit=#{Ctwa::TrackedLink::SIGNALS_DAILY_LIMIT}")
    :too_many_requests
  end

  def record_click!(signal)
    now = Time.current
    click = ActiveRecord::Base.transaction do
      created = Ctwa::TrackedLinkClick.create!(signal.click_attributes.merge(account_id: @tracked_link.account_id, tracked_link: @tracked_link))
      # rubocop:disable Rails/SkipsModelValidations
      Ctwa::TrackedLink.where(id: @tracked_link.id)
                       .update_all(['clicks_count = clicks_count + 1, last_signal_at = ?, updated_at = ?', now, now])
      # rubocop:enable Rails/SkipsModelValidations
      created
    end
    # O aviso pode chegar DEPOIS da mensagem com #TOKEN (rede lenta): procura essa mensagem.
    Ctwa::LateClickReconcileJob.perform_later(click.id)
  end
end
# rubocop:enable Rails/ApplicationController
