# Texto pronto do convite (#1190, J1-A12): o da página (`invite_text`) ou o padrão do catálogo do fork no idioma
# da conta. `{nome}` vira o primeiro nome do contato e `{link}` o link do convite, por `String#gsub` com STRING
# (nunca regex: o texto é escrito por uma pessoa e não se interpreta).
#
# Com `button: true` (#1517, `Notices::Button.allowed?`, hoje só no "Testar no meu WhatsApp"), o link vai no botão:
# o padrão sai sem o link cru; o texto da página que já põe `{link}` sai como está e sem botão (duplicaria o link).
# `#carries_link?`: o texto que sai leva o link.
class Crm::BookingV2::InviteText
  NAME_TOKEN = '{nome}'.freeze
  LINK_TOKEN = '{link}'.freeze
  # Contato do WhatsApp sem nome costuma vir com o próprio número no lugar do nome.
  PHONE_CHARS = '+0123456789 -().'.chars.freeze

  def self.first_name(contact)
    name = contact&.name.to_s.strip
    return '' if name.empty? || name.chars.all? { |char| PHONE_CHARS.include?(char) }

    name.split.first.to_s
  end

  def initialize(invite, button: false)
    @invite = invite
    @button = button && own_template.to_s.exclude?(LINK_TOKEN)
  end

  # O `content_attributes.rich_message` do botão, ou nil quando o convite vai só em texto.
  def rich_message
    Crm::BookingV2::Notices::Button.rich_message(invite.url, locale: locale) if @button
  end

  def carries_link?
    template.include?(LINK_TOKEN)
  end

  # Bloco em vez de segundo argumento: um nome com "\1" ou "\0" sairia como referência de grupo.
  def to_s
    template.gsub(NAME_TOKEN) { first_name }.gsub(LINK_TOKEN) { invite.url }
  end

  private

  attr_reader :invite

  def template
    own_template || default_template
  end

  def own_template
    invite.booking_profile.invite_text.presence
  end

  def default_template
    key = "#{@button ? 'button_text' : 'default_text'}#{'_without_name' if first_name.empty?}"
    I18n.t("crm.booking_v2.invite.#{key}", locale: locale)
  end

  def first_name
    @first_name ||= self.class.first_name(invite.contact)
  end

  def locale
    raw = invite.account.locale.presence
    raw.present? && I18n.available_locales.map(&:to_s).include?(raw.to_s) ? raw : I18n.default_locale
  end
end
