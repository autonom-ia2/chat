# A partir do Chatwoot 4.16 a criacao de inbox por Embedded Signup, a reconfiguracao
# de inboxes embedded e a migracao embedded -> manual passaram a exigir flags de conta
# (coluna feature_flags_ext_1, todas com enabled: false por padrao). No fork o fluxo de
# Embedded Signup sempre esteve disponivel para todas as contas; sem esta migration as
# contas existentes perderiam o botao sem nenhum erro visivel. Mudar o default em
# config/features.yml so afeta contas novas, por isso o backfill aqui. Idempotente.
#
# Refs #274 (upgrade Chatwoot 4.17.1).
class EnableWhatsappEmbeddedSignupFlagsForExistingAccounts < ActiveRecord::Migration[7.1]
  FLAGS = %w[
    whatsapp_embedded_signup_inbox_creation
    whatsapp_reconfigure
    whatsapp_manual_transfer
  ].freeze

  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!(*FLAGS) }
    end
  end

  def down
    # Nao desliga: as flags refletem o comportamento que o fork sempre teve.
  end
end
