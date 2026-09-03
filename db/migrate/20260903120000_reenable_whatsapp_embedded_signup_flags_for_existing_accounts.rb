# Repete o backfill de 20260902120000, que rodou em producao sem persistir nada:
# a migration 20260629000000 (repurpose_quoted_email_reply) consulta Account antes
# de 20260706215758 criar a coluna feature_flags_ext_1, entao o model ficou com o
# cache de colunas anterior, o setter do FlagShihTzu (check_for_column: false)
# escreveu num atributo desconhecido e `save` retornou sem gravar. Reproduzido
# localmente com o schema pre-upgrade + as 40 migrations num unico processo.
#
# Aqui: reset do cache de colunas antes do batch, escrita idempotente e
# verificacao que aborta a migration se alguma conta continuar sem as flags
# (nunca mais falha em silencio).
#
# Refs #274.
class ReenableWhatsappEmbeddedSignupFlagsForExistingAccounts < ActiveRecord::Migration[7.2]
  FLAGS = %w[
    whatsapp_embedded_signup_inbox_creation
    whatsapp_reconfigure
    whatsapp_manual_transfer
  ].freeze

  def up
    Account.reset_column_information

    Account.find_each(batch_size: 100) do |account|
      next if flags_enabled?(account)

      account.enable_features(*FLAGS)
      account.save!(validate: false)
    end

    missing = Account.find_each.reject { |account| flags_enabled?(account) }.map(&:id)
    raise "flags de Embedded Signup nao persistidas nas contas #{missing.inspect}" if missing.any?
  end

  def flags_enabled?(account)
    FLAGS.all? { |flag| account.feature_enabled?(flag) }
  end

  def down
    # Nao desliga: as flags refletem o comportamento que o fork sempre teve.
  end
end
