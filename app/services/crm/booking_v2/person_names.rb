# Apelido de cada pessoa no link curto de uma página "um link por pessoa" (#1282): o `<pessoa>` de
# `/a/<nome>/<pessoa>`.
#
# Por que um apelido gravado, e não o identificador que o link individual já tem: o identificador é um UUID de 36
# caracteres (o link deixaria de ser curto), e o id interno da pessoa exporia um número da base. O apelido sai do
# primeiro nome ("ana"), ganha número quando repete dentro da página ("ana-2") e fica gravado no link
# (`metadata['short_name']`): trocar o nome da pessoa depois não muda um endereço já divulgado. A unicidade é só
# dentro da página; quem garante o endereço global é o nome curto da página.
class Crm::BookingV2::PersonNames
  KEY = 'short_name'.freeze
  MAX_LENGTH = 24
  FALLBACK = 'p'.freeze
  SEPARATOR = '-'.freeze

  def self.for(link)
    link.metadata.to_h[KEY].presence
  end

  def initialize(profile)
    @profile = profile
  end

  # Dá apelido aos links que ainda não têm, inclusive os desligados (se a pessoa voltar, o endereço dela é o mesmo).
  # Não mexe em quem já tem.
  def assign_missing!
    links = profile.agent_booking_links.includes(:agent).order(:id).to_a
    taken = links.filter_map { |link| self.class.for(link) }.to_set
    links.each do |link|
      next if self.class.for(link)

      name = free_name(link.agent, taken)
      taken << name
      store(link, name)
    end
  end

  def find_link(person)
    wanted = person.to_s.strip.downcase
    return if wanted.empty?

    profile.agent_booking_links.includes(:agent).find { |link| self.class.for(link) == wanted }
  end

  private

  attr_reader :profile

  # Só o apelido, sem as validações do link: um link antigo que hoje não passaria nelas (pessoa que saiu da conta)
  # não pode impedir a página de ganhar o nome curto.
  def store(link, name)
    link.update_columns(metadata: link.metadata.to_h.merge(KEY => name), updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def free_name(agent, taken)
    base = base_for(agent)
    return base if taken.exclude?(base)

    (2..).each do |number|
      candidate = "#{base}#{SEPARATOR}#{number}"
      return candidate if taken.exclude?(candidate)
    end
  end

  def base_for(agent)
    first = agent&.name.to_s.split.first.to_s.parameterize.tr('_', SEPARATOR)
    first.first(MAX_LENGTH).split(SEPARATOR).reject(&:empty?).join(SEPARATOR).presence || FALLBACK
  end
end
