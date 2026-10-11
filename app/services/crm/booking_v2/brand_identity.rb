# Identidade salva das páginas de agendamento (#1289): a pessoa sobe logo, foto e cor uma vez, e as páginas novas já
# nascem com isso. Sem tabela nova:
#
# - cor, lado da logo e frase de boas-vindas ficam em `account.settings['booking_identity']`;
# - a logo é um anexo da conta (`Account#booking_identity_logo`);
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
    brand = page.brand.to_h
    account.with_lock do
      account.booking_identity_logo = page.logo.blob if page.logo.attached?
      account.update!(settings: account.settings.to_h.merge(SETTINGS_KEY => FIELDS.index_with { |field| brand[field].presence }))
      save_photo(page)
    end
  end

  # Põe a identidade salva na página: cor, lado da logo e frase ficam iguais aos salvos (identidade sem frase tira a
  # frase da página). Logo e foto só são trocadas quando há uma salva. Sem identidade salva, a marca fica como está.
  def apply_to!(page)
    assign_to(page)
    page.save!
  end

  # O mesmo, sem gravar: para a página nova nascer com a identidade na mesma gravação que a cria.
  def assign_to(page)
    page.brand = page.brand.to_h.merge(data).compact
    page.logo = logo.blob if logo.attached?
    photo = photo_of(host_of(page))
    page.photo = photo.blob if photo
    page
  end

  private

  attr_reader :account

  def save_photo(page)
    host = host_of(page)
    return if host.blank? || !page.photo.attached?

    availability = Crm::AgentAvailability.find_or_initialize_by(account_id: account.id, user_id: host.id)
    availability.booking_photo = page.photo.blob
    availability.save!
  end
end
