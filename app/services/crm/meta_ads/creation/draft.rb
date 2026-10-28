# O rascunho do anúncio novo como a tela manda (#2198), revalidado antes de qualquer chamada à Meta (ponto 5). Cada
# recusa tem um código que a tela traduz. Valores em reais, sem float; datas como a tela mostrou ("2026-10-27"), no
# fuso da conta de anúncios. A Página e a conta do Instagram dela são conferidas no criar, contra as Páginas que o token
# alcança.
class Crm::MetaAds::Creation::Draft
  SITE_ACTIONS = %w[LEARN_MORE SHOP_NOW].freeze
  MEDIA_KINDS = %w[image video].freeze
  CARDS_MAX = 10
  NAME_LIMIT = 255
  TEXT_LIMIT = 2_000
  # A chave de idempotência é o UUID que a tela gera (crypto.randomUUID): 8-4-4-4-12 dígitos hexadecimais.
  UUID_GROUPS = [8, 4, 4, 4, 12].freeze
  HEX_DIGITS = '0-9a-fA-F'.freeze
  DIGEST_IGNORED = %i[idempotency_key recreate_unconfirmed].freeze

  attr_reader :values

  # `zone`: o fuso da conta de anúncios, ou um bloco que o lê (só é chamado para as datas, a última conferência).
  def initialize(params, account:, zone:)
    @params = params.to_h.deep_symbolize_keys
    @account = account
    @zone = zone
  end

  def validate!
    @values = {
      idempotency_key: idempotency_key, name: name, destination: destination,
      page_id: page_id, whatsapp_number: whatsapp_number, site_url: site_url, site_action: site_action,
      media: media(@params[:media]), cards: cards, text: text, headline: @params[:headline].to_s.strip.presence,
      ready_message: @params[:ready_message].to_s.strip.presence, placement: placement,
      special_category: flag(:special_category), recreate_unconfirmed: flag(:recreate_unconfirmed), **audience, **budget
    }
    self
  end

  def [](key)
    @values[key]
  end

  # SHA-256 do pedido validado, sem a chave da tentativa nem a liberação de recriar: o mesmo anúncio pedido com outra
  # chave tem o mesmo digest (Crm::MetaAds::Creation::Attempt). As chaves dos hashes vão em ordem; lista que é conjunto
  # (os estados) já sai em ordem do #audience; lista que é sequência (os cartões do carrossel) fica na ordem dela.
  def digest
    Digest::SHA256.hexdigest(canonical(@values.except(*DIGEST_IGNORED)).to_json)
  end

  private

  # Hashes com as chaves em ordem, para o mesmo pedido dar o mesmo texto.
  def canonical(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_s, canonical(item)] }.sort.to_h
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def fail!(code)
    raise Crm::MetaAds::Creation::Error, code
  end

  def flag(key)
    ActiveModel::Type::Boolean.new.cast(@params[key]) || false
  end

  def required_string(key, code)
    @params[key].to_s.strip.presence || fail!(code)
  end

  # Só UUID: cabe no índice único e não carrega texto livre.
  def idempotency_key
    value = @params[:idempotency_key].to_s.strip
    uuid = value.split('-', -1).map(&:length) == UUID_GROUPS && value.delete('-').delete(HEX_DIGITS).empty?
    uuid ? value : fail!('invalid_params')
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

  # Carrossel: as mídias depois da primeira, até 10 no total. A ordem é a do carrossel (a primeira aparece primeiro), então
  # entra no #digest como veio: outra ordem é outro anúncio.
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
    # Conjunto, não sequência: em ordem, para SP→RJ e RJ→SP serem o mesmo pedido (#digest). Brasil todo não leva estados.
    states = region == 'BR' ? [] : Array(@params[:states]).map(&:to_s).uniq.sort
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

  # Em reais, BigDecimal com até 2 casas (Crm::MetaAds::Creation::Money); a Meta recebe em centavos inteiros.
  def budget
    amount = Crm::MetaAds::Creation::Money.parse(@params[:daily_amount])
    limits = Crm::MetaAds::Creation::Options::MIN_DAILY..Crm::MetaAds::Creation::Options::MAX_DAILY
    fail!('invalid_amount') unless amount && limits.cover?(amount)
    start_date, end_date = dates
    { daily_amount: amount, start_date: start_date, end_date: end_date }
  end

  # Início não antes de hoje; fim, se houver, depois do início.
  def dates
    start_date = Date.iso8601(@params[:start_date].to_s)
    end_date = @params[:end_date].present? ? Date.iso8601(@params[:end_date].to_s) : nil
    fail!('invalid_dates') if start_date < zone.today || (end_date && end_date <= start_date)
    [start_date, end_date]
  rescue Date::Error
    fail!('invalid_dates')
  end

  def zone
    @zone.respond_to?(:call) ? @zone.call : @zone
  end
end
