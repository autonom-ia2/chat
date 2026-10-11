# Nome curto da página de agendamento (#1282): o `<nome>` de `/a/<nome>`. Único na instalação inteira.
#
# Formato: 3 a 40 caracteres, só letras minúsculas sem acento, números e hífen, sem hífen no começo ou no fim. A
# conferência é caractere a caractere contra um conjunto fechado, sem expressão regular. `RESERVED` guarda nomes que
# são (ou podem virar) endereço do próprio sistema.
#
# `problem` devolve o código do que impede o nome (ou nil); `suggest` monta um nome livre a partir do título da
# página, tirando acentos (`parameterize`) e somando um número quando o nome já tem dono.
class Crm::BookingV2::ShortName
  MIN_LENGTH = 3
  MAX_LENGTH = 40
  ALLOWED_CHARS = 'abcdefghijklmnopqrstuvwxyz0123456789-'.freeze
  SEPARATOR = '-'.freeze
  RESERVED = %w[
    a b l book app api admin administrator super-admin super_admin superadmin www public assets static preview og
    login auth support suporte help ajuda null undefined new edit
  ].freeze
  FALLBACK_BASE = 'agenda'.freeze
  MAX_NUMBERED_TRIES = 50

  def self.normalize(value)
    value.to_s.strip.downcase.presence
  end

  # Só o formato: não consulta o banco.
  def self.format_problem(value)
    name = value.to_s
    length_problem(name) || chars_problem(name) || ('reserved' if RESERVED.include?(name))
  end

  def self.length_problem(name)
    return 'too_short' if name.length < MIN_LENGTH

    'too_long' if name.length > MAX_LENGTH
  end

  def self.chars_problem(name)
    return 'invalid_chars' unless name.each_char.all? { |char| ALLOWED_CHARS.include?(char) }

    'hyphen_edge' if name.start_with?(SEPARATOR) || name.end_with?(SEPARATOR)
  end

  # Resposta da conferência do painel: com nome, se ele serve e está livre (`problem` = o que impede); sem nome, uma
  # sugestão a partir do título.
  def self.check(value, title:, except_id: nil)
    name = normalize(value)
    return { suggestion: suggest(title, except_id: except_id) } if name.nil?

    found = problem(name, except_id: except_id)
    { name: name, available: found.nil?, problem: found }
  end

  # `except_id`: a própria página, que pode salvar de novo o nome que já tem.
  def self.problem(value, except_id: nil)
    name = normalize(value)
    format_problem(name) || ('taken' if taken?(name, except_id: except_id))
  end

  def self.taken?(name, except_id: nil)
    scope = ::Crm::AgentBookingProfile.where(short_name: name)
    scope = scope.where.not(id: except_id) if except_id.present?
    scope.exists?
  end

  def self.suggest(title, except_id: nil)
    base = base_from(title)
    taken = taken_names(base, except_id: except_id)
    candidates = [base] + (2..MAX_NUMBERED_TRIES).map { |number| numbered(base, number.to_s) }
    candidates.find { |name| taken.exclude?(name) && format_problem(name).nil? } || numbered(base, SecureRandom.hex(3))
  end

  # "Avaliação Gratuita!" -> "avaliacao-gratuita". O `parameterize` deixa passar `_`, que aqui vira hífen; pedaços
  # vazios somem, então nunca sobra hífen dobrado nem na ponta.
  def self.base_from(title)
    words = title.to_s.parameterize.tr('_', SEPARATOR).split(SEPARATOR).reject(&:empty?)
    base = trim(words.join(SEPARATOR), MAX_LENGTH)
    base = FALLBACK_BASE if base.empty?
    base = trim("#{FALLBACK_BASE}#{SEPARATOR}#{base}", MAX_LENGTH) if base.length < MIN_LENGTH || RESERVED.include?(base)
    base
  end

  def self.numbered(base, suffix)
    "#{trim(base, MAX_LENGTH - suffix.length - 1)}#{SEPARATOR}#{suffix}"
  end

  # Corta no tamanho sem deixar hífen na ponta.
  def self.trim(text, length)
    text.first(length).split(SEPARATOR).reject(&:empty?).join(SEPARATOR)
  end

  def self.taken_names(base, except_id:)
    prefix = ::Crm::AgentBookingProfile.sanitize_sql_like(trim(base, MAX_LENGTH - 8))
    scope = ::Crm::AgentBookingProfile.where('short_name LIKE ?', "#{prefix}%")
    scope = scope.where.not(id: except_id) if except_id.present?
    scope.pluck(:short_name).to_set
  end

  private_class_method :length_problem, :chars_problem, :base_from, :numbered, :trim, :taken_names
end
