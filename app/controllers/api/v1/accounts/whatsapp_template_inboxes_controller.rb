# As caixas do WhatsApp oficial que têm modelos (#1332, épico #1320): a tela de Modelos e a Nova campanha leem daqui
# quais números existem, quais precisam reconectar e quais dividem a mesma conta do WhatsApp (WABA).
#
#   GET /api/v1/accounts/:account_id/whatsapp_template_inboxes
#   => { payload: [{ id, name, phone_number, group_id, group_name, reconnect, template_sends: { nome => n } }] }
#
# `group_id` é o id da primeira caixa da mesma WABA: a tela agrupa por ele sem receber o id da WABA. `group_name` é o
# nome da conta no Chat2You (uma WABA só) ou o da primeira caixa do grupo (mais de uma). `template_sends`: quantas
# vezes cada modelo saiu pela caixa neste mês (Whatsapp::TemplateSendCount). Ver: whatsapp_templates_view.
class Api::V1::Accounts::WhatsappTemplateInboxesController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    inboxes = Current.account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id)
                     .select { |inbox| Whatsapp::Templates::MetaClient.supported?(inbox) }
    groups = inboxes.group_by { |inbox| inbox.channel.waba_id.to_s }
    sends = Whatsapp::TemplateSendCount.new(account: Current.account, inbox_ids: inboxes.map(&:id)).perform
    render json: { payload: inboxes.map { |inbox| row(inbox, groups).merge(template_sends: sends.fetch(inbox.id, {})) } }
  end

  private

  def check_authorization
    authorize(WhatsappTemplateProfile, :index?, policy_class: WhatsappTemplatePolicy)
  end

  def row(inbox, groups)
    first = groups.fetch(inbox.channel.waba_id.to_s).first
    { id: inbox.id, name: inbox.name, phone_number: inbox.channel.phone_number, group_id: first.id,
      group_name: groups.size == 1 ? Current.account.name : first.name,
      reconnect: inbox.channel.try(:reauthorization_required?) || false }
  end
end
