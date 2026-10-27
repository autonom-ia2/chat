# O rascunho do anúncio novo como a tela manda (#2198), revalidado antes de qualquer chamada à Meta (ponto 5). Cada
# recusa tem um código que a tela traduz. Valores em reais; datas como a tela mostrou ("2026-10-27"), no fuso da conta de
# anúncios. A Página e a conta do Instagram dela são conferidas no criar, contra as Páginas que o token alcança.
class Crm::MetaAds::Creation::Draft
  SITE_ACTIONS = %w[LEARN_MORE SHOP_NOW].freeze
  MEDIA_KINDS = %w[image video].freeze
  CARDS_MAX = 10
  NAME_LIMIT = 255
  TEXT_LIMIT = 2_000

  attr_reader :values

  def initialize(params, account:, zone:)
    @params = params.to_h.deep_symbolize_keys
    @account = account
    @zone = zone
  end

  def validate!
    @values = {
      idempotency_key: required_string(:idempotency_key, 'invalid_params'), name: name, destination: destination,
      page_id: page_id, whatsapp_number: whatsapp_number, site_url: site_url, site_action: site_action,
      media: media(@params[:media]), cards: cards, text: text, headline: @params[:headline].to_s.strip.presence,
      ready_message: @params[:ready_message].to_s.strip.presence, placement: placement,
      special_category: ActiveModel::Type::Boolean.new.cast(@params[:special_category]) || false, **audience, **budget
    }
    self
  end

  def [](key)
    @values[key]
  end

  private

  def fail!(code)
    raise Crm::MetaAds::Creation::Error, code
  end

  def required_string(key, code)
    @params[key].to_s.strip.presence || fail!(code)
  end

  def name
    value = required_string(:name, 'invalid_params')
    value.length <= NAME_LIMIT ? value : fail!('invalid_params')
  end

  def destination
    value = @params[:destination].to_s
    Crm::MetaAds::Creation::Confirmed::DESTINATIONS.include?(value) ? value : fail!('invalid_destination')
  end

  def page_id
    value = @params[:page_id].to_s
    Crm::MetaAds::Creation::Ids.numeric?(value) ? value : fail!('invalid_page')
  end

  def whatsapp_number
    return unless @params[:destination] == 'WHATSAPP'

    numbers = Crm::MetaAds::Creation::Options.whatsapp_numbers(@account).pluck(:id)
    numbers.include?(@params[:whatsapp_number].to_s) ? @params[:whatsapp_number].to_s : fail!('invalid_whatsapp_number')
  end

  # https e um domínio com ponto, como a tela confere.
  def site_url
    return unless @params[:destination] == 'WEBSITE'

    uri = URI.parse(@params[:site_url].to_s.strip)
    uri.is_a?(URI::HTTPS) && uri.host.to_s.include?('.') ? uri.to_s : fail!('invalid_site')
  rescue URI::InvalidURIError
    fail!('invalid_site')
  end

  def site_action
    return unless @params[:destination] == 'WEBSITE'

    SITE_ACTIONS.include?(@params[:site_action].to_s) ? @params[:site_action].to_s : fail!('invalid_site')
  end

  # Foto: { kind: 'image', hash }. Vídeo: { kind: 'video', video_id, image_hash } (a capa).
  def media(raw)
    value = raw.to_h.symbolize_keys
    case value[:kind]
    when 'image' then { kind: 'image', hash: value[:hash].to_s.presence || fail!('invalid_media') }
    when 'video'
      fail!('invalid_media') unless Crm::MetaAds::Creation::Ids.numeric?(value[:video_id].to_s) && value[:image_hash].present?
      { kind: 'video', video_id: value[:video_id].to_s, image_hash: value[:image_hash].to_s }
    else fail!('invalid_media')
    end
  end

  # Carrossel: as mídias depois da primeira, até 10 no total.
  def cards
    list = Array(@params[:cards])
    fail!('invalid_media') if list.size + 1 > CARDS_MAX
    list.map { |card| media(card) }
  end

  def text
    value = required_string(:text, 'invalid_params')
    value.length <= TEXT_LIMIT ? value : fail!('invalid_params')
  end

  def placement
    value = @params[:placement].to_s
    Crm::MetaAds::Creation::Confirmed.placement?(@params[:destination].to_s, value) ? value : fail!('invalid_placement')
  end

  def audience
    region = @params[:region].to_s == 'BR' ? 'BR' : 'STATES'
    states = Array(@params[:states]).map(&:to_s).uniq
    fail!('invalid_audience') if region == 'STATES' && !valid_states?(states)
    age_min, age_max = ages
    { region: region, states: states, age_min: age_min, age_max: age_max }
  end

  def valid_states?(states)
    states.any? && (states - Crm::MetaAds::Creation::Targeting::STATES.keys).empty?
  end

  # De 18 a 65 (65 quer dizer 65+), a primeira menor ou igual à segunda.
  def ages
    values = [@params[:age_min], @params[:age_max]].map { |age| Integer(age.to_s, exception: false) }
    valid = values.all? { |age| age && Crm::MetaAds::Creation::Targeting::AGES.cover?(age) } && values.first <= values.last
    valid ? values : fail!('invalid_audience')
  end

  def budget
    amount = BigDecimal(@params[:daily_amount].to_s, exception: false)
    limits = Crm::MetaAds::Creation::Options::MIN_DAILY..Crm::MetaAds::Creation::Options::MAX_DAILY
    fail!('invalid_amount') unless amount && limits.cover?(amount)
    start_date, end_date = dates
    { daily_amount: amount.to_f, start_date: start_date, end_date: end_date }
  end

  # Início não antes de hoje; fim, se houver, depois do início.
  def dates
    start_date = Date.iso8601(@params[:start_date].to_s)
    end_date = @params[:end_date].present? ? Date.iso8601(@params[:end_date].to_s) : nil
    fail!('invalid_dates') if start_date < @zone.today || (end_date && end_date <= start_date)
    [start_date, end_date]
  rescue Date::Error
    fail!('invalid_dates')
  end
end
