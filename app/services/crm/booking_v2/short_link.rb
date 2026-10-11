# Link curto da página de agendamento (#1282, #1299): `/a/<conta>/<página>` e, nas páginas "um link por pessoa",
# `/a/<conta>/<página>/<pessoa>`.
#
# `resolve` troca o endereço curto pelo slug opaco que o resto do sistema já usa (o da página ou o do link
# individual): a casca HTML resolve e a API pública continua recebendo só o slug. Devolve nil para endereço que não
# existe, página antiga, conta sem a flag e pessoa desconhecida — o mesmo "não encontrada" para todos.
#
# Ordem da resolução:
# 1. O primeiro pedaço é endereço de conta: formato novo, e só páginas DESSA conta entram. `/a/<conta>` sozinho abre
#    a página da conta quando ela tem uma só no ar. Se o formato novo não acha, vale o formato antigo dentro da
#    mesma conta (a conta cujo endereço é igual ao nome de uma página dela).
# 2. Senão, o formato antigo (#1282): `/a/<página>` e `/a/<página>/<pessoa>`. Só abre enquanto existir exatamente
#    uma página com aquele nome na instalação: com duas, o link não diz de quem é e responde "não encontrada".
#
# O primeiro pedaço nunca abre página de outra conta: endereço de conta não pode ser igual a nome de página de outra
# conta (`AccountAddress.problem`), e com endereço de conta a busca fica dentro dela.
#
# `url_for` monta o endereço para divulgar: o curto quando a página tem nome (e, com pessoa, a pessoa tem apelido);
# senão o `/book/<slug>` de sempre, que continua funcionando.
class Crm::BookingV2::ShortLink
  def self.base_url
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  def self.resolve(first, second = nil, third = nil)
    account = ::Crm::BookingV2::AccountAddress.find_account(first)
    return old_format(::Crm::AgentBookingProfile.new_pages, first, second, third) if account.nil?
    return unless ::Crm::Config.booking_v2_enabled?(account)

    pages = ::Crm::AgentBookingProfile.new_pages.where(account_id: account.id)
    new_format(pages, second, third) || old_format(pages, first, second, third)
  end

  def self.new_format(pages, page_name, person)
    slug_for(page_name.blank? ? only_one(pages.enabled) : named(pages, page_name), person)
  end

  def self.old_format(pages, page_name, person, extra)
    slug_for(named(pages, page_name), person) if extra.blank?
  end

  def self.named(pages, value)
    name = ::Crm::BookingV2::ShortName.normalize(value)
    return if name.nil? || ::Crm::BookingV2::ShortName.format_problem(name)

    profile = only_one(pages.where(short_name: name))
    profile if profile && ::Crm::Config.booking_v2_enabled?(profile.account)
  end

  # A página, se o conjunto tem exatamente uma.
  def self.only_one(pages)
    found = pages.includes(:account).limit(2).to_a
    found.first if found.size == 1
  end

  def self.slug_for(profile, person)
    return if profile.nil?
    return profile.slug if person.blank?
    # Link de pessoa só existe em página com um link por pessoa; numa página de um responsável só, um link antigo
    # não responde.
    return unless profile.assignment_mode_per_agent?

    ::Crm::BookingV2::PersonNames.new(profile).find_link(person)&.slug
  end
  private_class_method :new_format, :old_format, :named, :only_one, :slug_for

  def self.url_for(profile, link: nil)
    "#{base_url}#{path_for(profile, link: link)}"
  end

  def self.path_for(profile, link: nil)
    return "/book/#{link ? link.slug : profile.slug}" if profile.short_name.blank?

    page_path = "/a/#{profile.booking_account_address}/#{profile.short_name}"
    return page_path if link.nil?

    person = ::Crm::BookingV2::PersonNames.for(link)
    person ? "#{page_path}/#{person}" : "/book/#{link.slug}"
  end
end
