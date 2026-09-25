# O que a nota do Orth lê de um lead (#681, frente A), a partir do hash de atributos que o lead já tem. Nota e contagem
# ausentes ficam nil, porque o Orth trata "sem dado" diferente de zero. As avaliações vêm de :reviews ou, sem ela, do
# raw_payload do Google; as de contato (WhatsApp, decisor, CRM) quem chama preenche.
class Autonomia::Prospecting::Scoring::LeadSignals
  ATTRIBUTES = %i[
    website phone rating reviews_count photo_count reviews open_now search_rank whatsapp_verified decisor_found
    decisor_failed already_in_crm crm_funnel_name recently_contacted days_since_last_contact
  ].freeze
  FLAGS = %i[open_now whatsapp_verified decisor_found decisor_failed already_in_crm recently_contacted].freeze

  attr_reader(*ATTRIBUTES)

  def self.from(lead)
    attributes = lead.to_h.with_indifferent_access
    new(
      website: attributes[:website].present?,
      phone: attributes[:phone].present?,
      rating: numeric(attributes[:rating])&.to_f,
      reviews_count: numeric(attributes[:reviews_count])&.to_i,
      photo_count: photo_count(attributes),
      reviews: reviews(attributes),
      search_rank: attributes[:search_rank].to_i.positive? ? attributes[:search_rank].to_i : nil,
      crm_funnel_name: attributes[:crm_funnel_name].presence,
      days_since_last_contact: attributes[:days_since_last_contact],
      **FLAGS.index_with { |flag| attributes[flag] == true }
    )
  end

  def self.numeric(value)
    value if value.is_a?(Numeric)
  end

  def self.photo_count(attributes)
    return attributes[:photo_count].to_i if attributes[:photo_count].is_a?(Numeric)

    photos = attributes[:raw_payload].to_h.with_indifferent_access[:photos]
    return photos.size if photos.is_a?(Array)

    attributes[:has_photos] == true ? 1 : 0
  end

  def self.reviews(attributes)
    Array(attributes.key?(:reviews) ? attributes[:reviews] : attributes[:raw_payload].to_h.with_indifferent_access[:reviews])
  end
  private_class_method :numeric, :photo_count, :reviews

  def initialize(**attributes)
    ATTRIBUTES.each { |name| instance_variable_set("@#{name}", attributes.fetch(name)) }
  end

  alias website? website
  alias phone? phone

  # A publishTime mais recente que se lê entre as avaliações, ou nil.
  def latest_review_time
    @latest_review_time ||= reviews.filter_map { |review| publish_time(review) }.max
  end

  private

  def publish_time(review)
    value = review[:publishTime] || review[:publish_time] if review.is_a?(Hash)
    Time.zone.parse(value) if value.is_a?(String) && value.strip.present?
  rescue ArgumentError
    nil
  end
end
