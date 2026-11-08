# Resumo diário e alerta de Anúncios da Meta no WhatsApp do dono (#1100, F4b). Administrador ou `meta_ads_manage`
# (#2070), pela policy da conexão (Crm::MetaAdsConnection :update?), também na leitura: ela traz o telefone de quem
# recebe e os números das caixas (#1794, `meta_ads_view` não alcança).
#
# GET   whatsapp_report      → configuração, números de origem conectados, texto dos modelos do Oficial e horários
# PATCH whatsapp_report      → liga/desliga, escolhe a origem e o número que recebe (chaves ausentes ficam)
# POST  whatsapp_report/test → manda o resumo de ontem agora, com "[Teste]"; até TEST_LIMIT por hora por conta
#
# Ligar/mudar (PATCH) e testar pedem também os valores de venda em R$ (#2075, Crm::ValorDeVenda.ve?): o texto do
# resumo leva o valor vendido. Sem eles, 403 { error: 'sales_value_forbidden' }. A leitura, o envio das 8h e o alerta
# não mudam (o envio é da conta, não de uma pessoa).
#
# Erros de regra: 422 { error: code } (ver Crm::MetaAds::WhatsappReport::Settings e ::Sender).
class Api::V1::Accounts::Crm::MetaAdsWhatsappReportsController < Api::V1::Accounts::Crm::BaseController
  TEST_LIMIT = 3
  TEST_WINDOW = 1.hour
  TEST_KEY_PREFIX = 'crm:meta_ads:whatsapp_report:test'.freeze
  PERMITTED = %w[enabled alert_enabled inbox_id phone].freeze
  FEATURE = 'meta_ads_hub'.freeze

  before_action :ensure_manage
  before_action :ensure_sales_values, only: [:update, :test_send]
  before_action :ensure_feature, only: [:update, :test_send]
  before_action :ensure_connection, only: [:update, :test_send]

  def show
    return render json: { whatsapp_report: nil } if connection.blank?

    render json: { whatsapp_report: settings.payload }
  end

  def update
    settings.update!(report_params)
    render json: { whatsapp_report: settings.payload }
  rescue Crm::MetaAds::WhatsappReport::Settings::Error => e
    render_unprocessable(e.code)
  end

  def test_send
    settings.origin!
    return render json: { error: 'rate_limited' }, status: :too_many_requests unless test_allowed?

    digest = Crm::MetaAds::WhatsappReport::Digest.new(connection).payload
    Crm::MetaAds::WhatsappReport::Sender.new(connection, settings: settings).send_summary(digest, test: true)
    render json: { sent: true, sent_at: Time.current.iso8601 }
  rescue Crm::MetaAds::WhatsappReport::Settings::Error => e
    render_unprocessable(e.code)
  end

  private

  def ensure_manage
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).update?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def ensure_sales_values
    render json: { error: 'sales_value_forbidden' }, status: :forbidden unless ::Crm::ValorDeVenda.ve?(Current.account_user)
  end

  # Os envios agendados só saem com Anúncios da Meta ligado; ligar e testar seguem a mesma regra.
  def ensure_feature
    render json: { error: 'feature_disabled' }, status: :forbidden unless Current.account.feature_enabled?(FEATURE)
  end

  def ensure_connection
    render_unprocessable('not_connected') if connection.blank?
  end

  def connection
    @connection ||= ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end

  def settings
    @settings ||= Crm::MetaAds::WhatsappReport::Settings.new(connection)
  end

  # Só as chaves enviadas: as ausentes ficam como estão.
  def report_params
    params.fetch(:whatsapp_report, {}).permit(*PERMITTED).to_h
  end

  # Teto de testes por hora por conta: protege o número de origem de rajada.
  def test_allowed?
    key = "#{TEST_KEY_PREFIX}:#{Current.account.id}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, TEST_WINDOW.to_i) if count == 1
    count <= TEST_LIMIT
  end
end
