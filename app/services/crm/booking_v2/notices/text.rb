# Texto dos avisos ao cliente (#1192): curto, leigo e genérico (serve qualquer negócio), no idioma da conta, com o
# link de gestão (`/b/<code>`) e SEMPRE a linha para parar os avisos (J2-A9, RA-18). O link de parar é o mesmo link
# de gestão com `?stop_notices=1`: a página abre já oferecendo "Parar avisos".
#
# Reunião marcada pela equipe no painel (#1271, `source: 'panel'`): o aviso "ao marcar" diz quem marcou ("Oi, Ana!
# Juliana marcou seu horário para …"), pelo nome de exibição ou o primeiro nome de `metadata.booked_by_user_id`.
# Sem essa pessoa (apagada ou sem nome), fica o texto de sempre. Só no texto livre: os valores do modelo aprovado
# ({{1}} {{2}} {{3}}) não mudam.
#
# `when_text` também alimenta o modelo aprovado ({{2}}) e as notificações ao agente.
#
# Texto próprio da página (#1354, `Notices::CustomText`): quando o dono escreveu um texto para o aviso, ele vai no
# lugar do padrão, preenchido pelo catálogo de campos (`TemplateFields::Resolver.for_meeting`). A linha de parar vai
# SEMPRE, pelo sistema. Texto salvo que não passa mais na conferência, ou sem dia/hora ou link para preencher: vai o
# padrão e fica no log (sem o texto). O aviso marcado pela equipe usa o padrão `booked_by_team`, porque ele diz quem
# marcou e o texto próprio não tem como dizer. `appendix` e `template_values` (modelos) não mudam.
#
# Link de gestão (#1517): com `button: true` (`Notices::Button.allowed?`), ele vai no botão "Ver meu horário"
# (`#rich_message`) e o texto padrão sai sem a linha do link. Texto próprio que já põe `{{horario.link_gestao}}`
# nunca leva botão (duplicaria o link; tirar a chave deixaria a frase pela metade). Sem botão, o texto que não tem o
# link (próprio, sem a chave) ganha a linha fixa `manage_line` antes da linha de parar: o link chega sempre.
#
# "Parar avisos" como botão (#1562): com o botão (`#button?`), o aviso sai SEM a linha de parar e `#stop_message`
# dá a mensagem 2, que o `Notices::Sender` cria logo depois, na mesma conversa: `stop_prompt` + botão "Parar avisos"
# para `stop_url`. Sem o botão, nada muda: uma mensagem só, com a linha de parar no texto (RA-18 nos dois casos).
class Crm::BookingV2::Notices::Text
  STOP_PARAM = '?stop_notices=1'.freeze
  TEAM_BOOKED_KIND = 'booked'.freeze

  def self.when_text(meeting)
    zone = ActiveSupport::TimeZone[meeting.timezone.to_s] || Time.zone
    format = I18n.t('crm.booking_v2.notices.when_format', locale: locale(meeting.account))
    meeting.starts_at.in_time_zone(zone).strftime(format)
  end

  def self.locale(account)
    Crm::BookingV2::LocationLabel.locale(account)
  end

  def self.stop_url(invite)
    "#{invite.url}#{STOP_PARAM}"
  end

  def self.manage_line(link, locale:)
    I18n.t('crm.booking_v2.notices.manage_line', link: link, locale: locale)
  end

  # page: a página do aviso (`Notices::Scheduler.profile_for`), para o texto próprio. Sem ela, o padrão.
  # button: o canal mostra o botão (`Notices::Button.allowed?`).
  def initialize(meeting:, invite:, kind:, page: nil, button: false)
    @meeting = meeting
    @invite = invite
    @kind = kind.to_s
    @page = page
    @button = button
  end

  def to_s
    button? ? body : "#{body}\n\n#{stop_line}"
  end

  # O `content_attributes.rich_message` do botão, ou nil quando a mensagem vai só em texto.
  def rich_message
    Crm::BookingV2::Notices::Button.rich_message(invite.url, kind: :notice, locale: locale) if button?
  end

  # A mensagem 2 do aviso com botão (#1562): `{ content:, rich_message: }` com o botão "Parar avisos", ou nil sem botão.
  def stop_message
    return unless button?

    { content: I18n.t('crm.booking_v2.notices.stop_prompt', locale: locale),
      rich_message: Crm::BookingV2::Notices::Button.rich_message(self.class.stop_url(invite), kind: :stop, locale: locale) }
  end

  # Corpo acima do limite do botão (`Notices::Button.fits?`; sem a linha de parar, que vai na mensagem 2): cai no texto,
  # com a linha do link e a de parar.
  def button?
    @button && !own_link? && Crm::BookingV2::Notices::Button.fits?(custom_body || sentence)
  end

  # Depois do corpo de um modelo do canal API (que só tem variáveis de contato): dia e hora, link de gestão e a
  # linha de parar.
  def appendix
    "#{self.class.when_text(meeting)} - #{invite.url}\n\n#{stop_line}"
  end

  # Valores do modelo aprovado, na ordem das variáveis: {{1}} primeiro nome, {{2}} dia e hora, {{3}} link de gestão.
  def template_values
    [Crm::BookingV2::InviteText.first_name(invite.contact), self.class.when_text(meeting), invite.url]
  end

  private

  attr_reader :meeting, :invite, :kind, :page

  def body
    return custom_body if own_link?
    return custom_body || sentence if button?

    custom_body ? "#{custom_body}\n\n#{manage_line}" : "#{sentence} #{manage_line}"
  end

  # O texto próprio sai (não caiu no padrão) e já põe o link.
  def own_link?
    custom_body.present? && Crm::BookingV2::Notices::CustomText.with_link?(custom_text)
  end

  # A frase do aviso padrão, sem o link.
  def sentence
    I18n.t("crm.booking_v2.notices.#{body_key}", name: name_part, booker: booker_name, when: self.class.when_text(meeting), locale: locale)
  end

  def manage_line
    self.class.manage_line(invite.url, locale: locale)
  end

  def custom_text
    page&.account_id == meeting.account_id ? page.notice_text(kind) : nil
  end

  def custom_body
    return @custom_body if defined?(@custom_body)

    @custom_body = fill_custom
  end

  def fill_custom
    text = custom_text
    return if text.blank? || booker_name.present?

    body = Crm::BookingV2::Notices::CustomText.fill(text, TemplateFields::Resolver.for_meeting(meeting, invite: invite))
    Rails.logger.warn("[crm][booking_v2][notices] custom_text_fallback page_id=#{page.id} kind=#{kind}") if body.nil?
    body
  end

  def body_key
    booker_name.present? ? 'booked_by_team' : kind
  end

  # Nome de quem marcou pelo painel, só para o aviso "ao marcar".
  def booker_name
    return @booker_name if defined?(@booker_name)

    @booker_name = team_booked? ? user_first_name(booker) : nil
  end

  def team_booked?
    kind == TEAM_BOOKED_KIND && meeting.source == Crm::BookingV2::PanelBooking::SOURCE
  end

  def booker
    user_id = meeting.metadata.to_h['booked_by_user_id']
    user_id.present? ? meeting.account.users.find_by(id: user_id) : nil
  end

  # O nome de exibição, se a pessoa escolheu um; senão, o primeiro nome do cadastro.
  def user_first_name(user)
    return nil if user.nil?

    user.display_name.to_s.strip.presence || user.name.to_s.split.first.presence
  end

  def stop_line
    I18n.t('crm.booking_v2.notices.stop_line', link: self.class.stop_url(invite), locale: locale)
  end

  def name_part
    first = Crm::BookingV2::InviteText.first_name(invite.contact)
    first.empty? ? '' : ", #{first}"
  end

  def locale
    self.class.locale(meeting.account)
  end
end
