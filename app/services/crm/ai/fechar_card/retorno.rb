# IA entende a conversa, F3 — o lembrete de retorno do "adiou" (regra a). É o retorno de sempre
# (Crm::FollowUps::CallbackScheduler: modo do funil, um pendente por card, `source` = ai_callback), com a data do
# cliente ou a padrão, e com o motivo no metadata para a equipe (e a medição) saberem de onde veio.
#
# A data: `retorno_em` do fechamento ("YYYY-MM-DD"); senão, a do pedido de retorno que a mesma avaliação leu; senão,
# hoje + RETORNO_DO_ADIOU. Sempre no futuro e dentro do horizonte do retorno (Crm::Ai::Config::CALLBACK_MAX_HORIZON_DAYS);
# a data dita fora disso cai na padrão. Hora: CALLBACK_DEFAULT_HOUR no fuso do contato ou da conta.
class Crm::Ai::FecharCard::Retorno < Crm::FollowUps::CallbackScheduler
  def initialize(card:, retorno_em:, pedido_de_retorno: nil)
    @retorno_em = retorno_em
    @pedido_de_retorno = pedido_de_retorno.respond_to?(:with_indifferent_access) ? pedido_de_retorno.with_indifferent_access : {}
    super(card: card, callback: nil)
    @callback = { detected: true, confidence: 1.0, requested_at: requested_at, requested_at_text: nil }.with_indifferent_access
  end

  private

  def requested_at
    zona = ActiveSupport::TimeZone[timezone]
    hoje = zona.today
    data = [data_do_retorno_em, data_do_pedido(zona)].compact.find { |dia| dia > hoje && dia <= hoje + Config::CALLBACK_MAX_HORIZON_DAYS - 1 }
    data ||= hoje + Crm::Ai::FecharCard::RETORNO_DO_ADIOU
    format('%<dia>sT%<hora>02d:00', dia: data.iso8601, hora: Config::CALLBACK_DEFAULT_HOUR)
  end

  def data_do_retorno_em
    Date.iso8601(@retorno_em.to_s) if @retorno_em.present?
  rescue Date::Error
    nil
  end

  # O pedido de retorno da mesma avaliação (Crm::Ai::StageClassifier, `callback_request`), quando o modelo pôs a data
  # lá e não no fechamento.
  def data_do_pedido(zona)
    return unless ActiveModel::Type::Boolean.new.cast(@pedido_de_retorno[:detected]) && @pedido_de_retorno[:requested_at].present?

    zona.parse(@pedido_de_retorno[:requested_at].to_s)&.to_date
  rescue ArgumentError
    nil
  end

  def title
    I18n.t('crm.ai_fechar_card.retorno', locale: @card.account.locale.presence || I18n.default_locale)
  end

  def metadata
    super.merge('motivo' => Crm::Ai::FecharCard::ADIOU)
  end
end
