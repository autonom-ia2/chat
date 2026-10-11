# Identidade salva das páginas de agendamento (#1289): a pessoa sobe logo, foto e cor uma vez, e as páginas novas já
# nascem com isso. Sem tabela nova:
#
# - cor, lado da logo e frase de boas-vindas ficam em `account.settings['booking_identity']`;
# - a logo é um anexo da conta (`Account#booking_identity_logo`), e a de fundo escuro (#1295) é o anexo irmão
#   (`Account#booking_identity_logo_dark`), com a origem dela em `settings['booking_identity']['logo_dark_source']`;
# - a foto é de cada pessoa que atende (`Crm::AgentAvailability#booking_photo`, uma linha por pessoa e conta).
#
# Os anexos reaproveitam o mesmo arquivo (blob) da página: nada é copiado. Um blob com mais de um anexo não é apagado
# quando um deles é trocado (o Active Storage só apaga blob sem anexo), então trocar a logo de uma página não derruba a
# identidade, e vice-versa.
#
# A foto só entra em página com uma pessoa fixa: página com um link por pessoa tem várias fotos possíveis, e ali a
# página pública já mostra a foto salva de quem atende cada link.
class Crm::BookingV2::BrandIdentity
  SETTINGS_KEY = 'booking_identity'.freeze
  FIELDS = %w[color logo_align headline].freeze
  LOGO_DARK_SOURCE = Crm::BookingV2::LogoDark::SOURCE_KEY

  def initialize(account)
    @account = account
  end

  # O que está salvo: sempre as três chaves (cor, lado da logo e frase), cada uma com o valor ou nil. Vazio = nunca salvou.
  def data
    saved = account.settings.to_h[SETTINGS_KEY]
    saved.is_a?(Hash) ? FIELDS.index_with { |field| saved[field].presence } : {}
  end

  def logo
    account.booking_identity_logo
  end

  def logo_dark
    account.booking_identity_logo_dark
  end

  # A foto salva de uma pessoa (o anexo) ou nil.
  def photo_of(user)
    return if user.blank?

    photo = Crm::AgentAvailability.find_by(account_id: account.id, user_id: user.id)&.booking_photo
    photo if photo&.attached?
  end

  def host_of(page)
    page.default_assignee if page.assignment_mode_fixed?
  end

  # Há algo salvo que serve para esta página?
  def any_for?(page)
    data.present? || logo.attached? || photo_of(host_of(page)).present?
  end

  # Guarda a identidade a partir do que a página tem agora. Cor, lado da logo e frase são gravados sempre, como estão
  # na página (página sem frase salva identidade sem frase). Página sem logo ou sem foto não apaga a imagem já salva.
  # A conta fica travada e é relida antes da troca, e só a chave da identidade muda: o que outra gravação já pôs em
  # `settings` não é pisado por uma cópia velha daqui. (Quem grava `settings` sem travar a conta ainda pode pisar
  # esta chave; a coluna é regravada inteira, como em todo o resto do sistema.)
  def save_from!(page)
    ensure_images!(page)
    brand = page.brand.to_h
    account.with_lock do
      keep_logos(page)
      account.update!(settings: account.settings.to_h.merge(SETTINGS_KEY => saved_fields(page, brand)))
      save_photo(page)
    end
  end

  # Põe a identidade salva na página: cor, lado da logo e frase ficam iguais aos salvos (identidade sem frase tira a
  # frase da página). Logo e foto só são trocadas quando há uma salva. Sem identidade salva, a marca fica como está.
  # A página fica travada (e é relida) enquanto recebe a identidade: um envio de logo ao mesmo tempo não deixa a
  # origem da logo de fundo escuro dizendo uma coisa e a imagem mostrando outra.
  def apply_to!(page)
    page.with_lock do
      assign_to(page)
      page.save!
    end
  end

  # O mesmo, sem gravar: para a página nova nascer com a identidade na mesma gravação que a cria.
  def assign_to(page)
    page.brand = page.brand.to_h.merge(data).compact
    assign_logos(page) if usable?(logo)
    photo = photo_of(host_of(page))
    page.photo = photo.blob if usable?(photo)
    page
  end

  private

  attr_reader :account

  def saved_logo_dark_source
    account.settings.to_h.dig(SETTINGS_KEY, LOGO_DARK_SOURCE)
  end

  # A origem da logo de fundo escuro acompanha a logo: página sem logo não mexe na que já está salva.
  def saved_fields(page, brand)
    source = page.logo.attached? ? brand[LOGO_DARK_SOURCE] : saved_logo_dark_source
    FIELDS.index_with { |field| brand[field].presence }.merge({ LOGO_DARK_SOURCE => source.presence }.compact)
  end

  # As duas logos andam juntas: salvar a identidade de uma página sem logo de fundo escuro tira a que estava salva.
  # Não grava: vai junto com a gravação de `settings`.
  def keep_logos(page)
    return unless page.logo.attached?

    account.booking_identity_logo = page.logo.blob
    account.booking_identity_logo_dark = page.logo_dark.attached? ? page.logo_dark.blob : nil
  end

  # A página fica com as duas logos salvas e a origem da de fundo escuro. Identidade salva antes do #1295 não tem a
  # origem (ou a origem promete uma imagem que não está mais lá): a de fundo escuro é gerada agora, a partir da logo.
  def assign_logos(page)
    page.logo = logo.blob
    page.logo_dark = usable?(logo_dark) ? logo_dark.blob : nil
    page.brand = page.brand.to_h.merge(LOGO_DARK_SOURCE => saved_logo_dark_source).compact
    generator = Crm::BookingV2::LogoDark.new(page)
    generator.assign_generated if generator.pending?
  end

  # Antes de copiar (#1303): as duas logos (inclusive a de fundo escuro gerada) e a foto da página passam pela
  # conferência inteira, com o conteúdo lido do armazenamento, mesmo que tenham entrado antes de a regra existir. Não
  # passou: nada é salvo (nem `booking_identity_logo_dark`), e o erro sai como o de um envio recusado.
  def ensure_images!(page)
    page.errors.clear
    Crm::BookingV2::ImageFile.validate(page, Crm::BookingPageSettings::IMAGE_ATTACHMENTS, only_changed: false)
    raise ActiveRecord::RecordInvalid, page if page.errors.any?
  end

  # Imagem salva que hoje não passa na conferência não vai para a página: o resto da identidade é aplicado, e a
  # página nova nasce sem ela em vez de não nascer.
  def usable?(attached)
    return false unless attached&.attached?

    problem = Crm::BookingV2::ImageFile.problem(attached.record, attached.name)
    Rails.logger.warn("Booking identity image skipped (account #{account.id}, #{attached.name}): #{problem}") if problem
    problem.nil?
  end

  # ATENÇÃO: cria a linha de `Crm::AgentAvailability` de quem atende, se ela ainda não tiver uma. É de propósito: a
  # foto salva é da PESSOA (uma por pessoa e conta), não da conta, e essa é a tabela que já tem uma linha por pessoa e
  # conta; guardar ali evitou tabela nova e coluna em `users`. A linha nasce com `working_hours` vazio e
  # `paused: false`, que é o mesmo que não ter linha: a pessoa continua seguindo o horário de cada página
  # (`Crm::BookingV2::Slots`) e nada muda em "Meus horários". Quem conta ou lista essas linhas não pode ler
  # "tem linha" como "a pessoa ajustou os horários": para isso existe `custom_hours?`.
  def save_photo(page)
    host = host_of(page)
    return if host.blank? || !page.photo.attached?

    availability = Crm::AgentAvailability.find_or_initialize_by(account_id: account.id, user_id: host.id)
    availability.booking_photo = page.photo.blob
    availability.save!
  end
end
