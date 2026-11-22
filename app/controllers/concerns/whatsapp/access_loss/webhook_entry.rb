# #2907 — Aviso da Meta de que perdemos (ou recuperamos) o acesso a uma conta do WhatsApp (`field: account_update`).
# Prependido em `Webhooks::WhatsappController` por `config/initializers/whatsapp_access_loss.rb`; o arquivo do Chatwoot
# fica intacto. Como o aviso de modelo (#1337), ele vem sem número no payload e no job do Chatwoot seria descartado.
#
# Só o POST em que TODAS as mudanças são `account_update` vem para cá; POST misto ou fora do formato segue o caminho de
# sempre. Assinatura obrigatória com o segredo do app (`WHATSAPP_APP_SECRET`): o aviso é do app, não de uma caixa. A lista
# `INACTIVE_WHATSAPP_NUMBERS` não vale aqui, como no aviso de modelo: ela é do número da URL, e o aviso é da WABA.
#
# Desvio e conteúdo saem do CORPO cru, o mesmo que a assinatura cobre (`meta_request_body`), e não de `params`, que mistura
# a query string: um corpo assinado reaproveitado com outra query não muda o que chega ao job.
module Whatsapp::AccessLoss::WebhookEntry
  FIELD = 'account_update'.freeze

  def process_payload
    return super unless account_update_only?

    Whatsapp::AccessLoss::AccountUpdateJob.perform_later(account_update_changes)
    head :ok
  end

  private

  def account_update_only?
    return @account_update_only if defined?(@account_update_only)

    changes = account_update_body_entries.flat_map { |entry| entry_changes(entry) }
    @account_update_only = changes.present? && changes.all? { |change| change.is_a?(Hash) && change['field'] == FIELD }
  end

  # As entradas do corpo assinado; [] quando o corpo não é um aviso de WABA em JSON.
  def account_update_body_entries
    body = JSON.parse(meta_request_body.to_s)
    return [] unless body.is_a?(Hash) && body['object'] == 'whatsapp_business_account' && body['entry'].is_a?(Array)

    body['entry']
  rescue JSON::ParserError
    []
  end

  # Entrada fora do formato vira `nil` e derruba o desvio: o POST segue pelo caminho do Chatwoot, como antes.
  def entry_changes(entry)
    entry.is_a?(Hash) && entry['changes'].is_a?(Array) ? entry['changes'] : [nil]
  end

  def account_update_changes
    account_update_body_entries.flat_map do |entry|
      entry['changes'].map do |change|
        { 'entry_id' => entry['id'].to_s, 'value' => change['value'].is_a?(Hash) ? change['value'] : {} }
      end
    end
  end

  def meta_signature_verification_required?
    account_update_only? || super
  end

  # Fork (upgrade 4.20.1, #3120): upstream #16548 lets an unsigned POST through when the URL inbox is a manual one still
  # without its own secret, and #16549 checks the 360dialog token of the URL inbox. Neither applies to the app notice:
  # the signature stays mandatory, and the URL inbox is not even looked up (a `value` that is not an object would crash
  # the lookup of `metadata`).
  def app_secret_pending?
    account_update_only? ? false : super
  end

  def verify_webhook_token!
    super unless account_update_only?
  end

  def meta_app_secrets
    return super unless account_update_only?

    secret = GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    Rails.logger.warn('[WHATSAPP ACCESS] account_update recusado: WHATSAPP_APP_SECRET vazio') if secret.blank?
    [secret]
  end
end
