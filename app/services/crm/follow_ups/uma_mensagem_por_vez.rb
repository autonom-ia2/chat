# UMA MENSAGEM POR VEZ POR CARD (#1589). Num funil de Atender, dois motores falam com o mesmo cliente: o follow-up
# automático por silêncio (source ai_followup) e os lembretes de Atender (source service_reminder: andamento, "deu tudo
# certo?" e, na Cobrança, o pagamento). Sem esta regra o cliente recebia os dois no mesmo dia. Agora, enquanto um deles
# está em curso no card (pendente ou enviado há menos de ESPERA), o outro espera.
#
# Quem cede quando os dois já existem: o aviso de andamento e o "deu tudo certo?" (sem data marcada). A cadência que já
# começou segue até o fim e só espera ESPERA depois de um lembrete que saiu. Assim os dois nunca ficam esperando um
# pelo outro. Quem usa: ServiceReminderScheduler#desired (lembrete), AutoFollowupPlanner (início da cadência) e
# AutoFollowupRunner (cada toque).
class Crm::FollowUps::UmaMensagemPorVez
  ESPERA = 24.hours
  AUTOMATICO = 'ai_followup'.freeze
  LEMBRETE = 'service_reminder'.freeze

  def initialize(card, now: Time.current)
    @card = card
    @now = now
  end

  # O lembrete de Atender espera? Cadência automática com toque pendente, ou toque que saiu há menos de ESPERA.
  # Toque pendente só conta com o card aberto (o toque de card fechado para sozinho quando vence) e quando a cadência
  # manda mensagem ao cliente: desligada (o toque fica parado) ou em modo lembrete para a equipe, ela seguraria os
  # avisos sem nunca falar com ninguém.
  def lembrete_espera?
    (@card.open? && automatico_fala_com_cliente? && pendente?(AUTOMATICO)) || livre_em(AUTOMATICO).present?
  end

  # O follow-up automático não começa: há lembrete de Atender pendente ou que saiu há menos de ESPERA. Em modo
  # lembrete para a equipe nada vai ao cliente, então não espera.
  def automatico_espera?
    return false unless automatico_fala_com_cliente?

    pendente?(LEMBRETE) || livre_em(LEMBRETE).present?
  end

  # Toque da cadência que já começou: espera só o lembrete que saiu. Devolve até quando, ou nil.
  def automatico_espera_ate
    livre_em(LEMBRETE) if automatico_fala_com_cliente?
  end

  private

  def pendente?(source)
    da_fonte(source).pending.exists?
  end

  # Quando o último envio desta fonte deixa de segurar o outro motor; nil se nada saiu há menos de ESPERA.
  def livre_em(source)
    enviado_em = da_fonte(source).done.where(completed_at: (@now - ESPERA)..)
                                 .where("metadata ->> 'sent_message_id' IS NOT NULL").maximum(:completed_at)
    enviado_em + ESPERA if enviado_em
  end

  def da_fonte(source)
    Crm::FollowUp.where(account_id: @card.account_id, card_id: @card.id).where("metadata ->> 'source' = ?", source)
  end

  def automatico_fala_com_cliente?
    config = Crm::Ai::Config.auto_followup_settings(@card.pipeline)
    config[:enabled] && config[:mode] != 'ai_reminder'
  end
end
