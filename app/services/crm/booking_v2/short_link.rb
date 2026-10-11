# Link curto da página de agendamento (#1282): `/a/<nome>` e, nas páginas "um link por pessoa", `/a/<nome>/<pessoa>`.
#
# `resolve` troca o endereço curto pelo slug opaco que o resto do sistema já usa (o da página ou o do link
# individual): a casca HTML resolve e a API pública continua recebendo só o slug. Devolve nil para nome que não
# existe, página antiga, conta sem a flag e pessoa desconhecida — o mesmo "não encontrada" para todos.
#
# `url_for` monta o endereço para divulgar: o curto quando a página tem nome (e, com pessoa, a pessoa tem apelido);
# senão o `/book/<slug>` de sempre, que continua funcionando.
class Crm::BookingV2::ShortLink
  def self.base_url
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  def self.resolve(name, person = nil)
    profile = find_profile(name)
    return if profile.nil?
    return profile.slug if person.blank?
    # Link de pessoa só existe em página com um link por pessoa; numa página de um responsável só, um link antigo
    # não responde.
    return unless profile.assignment_mode_per_agent?

    ::Crm::BookingV2::PersonNames.new(profile).find_link(person)&.slug
  end

  def self.find_profile(name)
    short_name = ::Crm::BookingV2::ShortName.normalize(name)
    return if short_name.nil? || ::Crm::BookingV2::ShortName.format_problem(short_name)

    profile = ::Crm::AgentBookingProfile.new_pages.includes(:account).find_by(short_name: short_name)
    profile if profile && ::Crm::Config.booking_v2_enabled?(profile.account)
  end
  private_class_method :find_profile

  def self.url_for(profile, link: nil)
    "#{base_url}#{path_for(profile, link: link)}"
  end

  def self.path_for(profile, link: nil)
    return "/book/#{link ? link.slug : profile.slug}" if profile.short_name.blank?
    return "/a/#{profile.short_name}" if link.nil?

    person = ::Crm::BookingV2::PersonNames.for(link)
    person ? "/a/#{profile.short_name}/#{person}" : "/book/#{link.slug}"
  end
end
