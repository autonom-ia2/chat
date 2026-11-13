# #2907 — Aviso da Meta de que perdemos (ou recuperamos) o acesso a uma conta do WhatsApp (`field: account_update`).
# Prependido em `Webhooks::WhatsappController` por `config/initializers/whatsapp_access_loss.rb`; o arquivo do Chatwoot
# fica intacto. Como o aviso de modelo (#1337), ele vem sem número no payload e no job do Chatwoot seria descartado.
#
# Só o POST em que TODAS as mudanças são `account_update` vem para cá; POST misto segue o caminho de sempre. Assinatura
# obrigatória com o segredo do app (`WHATSAPP_APP_SECRET`): o aviso é do app, não de uma caixa. A lista
# `INACTIVE_WHATSAPP_NUMBERS` não vale aqui, como no aviso de modelo: ela é do número da URL, e o aviso é da WABA.
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
    return @account_update_only = false unless params[:object] == 'whatsapp_business_account'

    changes = account_update_entries.flat_map { |entry| entry_changes(entry) }
    @account_update_only = changes.present? && changes.all? { |change| account_update_change?(change) }
  end

  # Entrada fora do formato vira `nil` e derruba o desvio: o POST segue pelo caminho do Chatwoot, como antes.
  def entry_changes(entry)
    entry.is_a?(ActionController::Parameters) ? Array(entry.fetch(:changes, [])) : [nil]
  end

  def account_update_change?(change)
    change.is_a?(ActionController::Parameters) && change[:field] == FIELD
  end

  def account_update_entries
    Array(params.fetch(:entry, []))
  end

  def account_update_changes
    account_update_entries.flat_map do |entry|
      entry.fetch(:changes, []).map do |change|
        { 'entry_id' => entry[:id].to_s, 'value' => change[:value].respond_to?(:to_unsafe_h) ? change[:value].to_unsafe_h.to_h : {} }
      end
    end
  end

  def meta_signature_verification_required?
    account_update_only? || super
  end

  def meta_app_secrets
    return super unless account_update_only?

    secret = GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    Rails.logger.warn('[WHATSAPP ACCESS] account_update recusado: WHATSAPP_APP_SECRET vazio') if secret.blank?
    [secret]
  end
end
