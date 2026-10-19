# Callback `after_update_commit` de Account (chat#1709, fase 2): quando a flag `whatsapp_rich_native` é LIGADA numa
# conta, a capacidade dos motores é lida na hora (Waha::EngineCapabilitiesRefreshJob, uma vez), em vez de esperar o
# próximo cron (até 5 min). Só na passagem de desligada para ligada e só com motores em `WAHA_RICH_NATIVE_ENGINES`.
# Leve: compara o bit gravado antes e depois; não consulta o banco. Nunca interrompe a gravação da conta.
class Waha::RichNative::ColdStart
  COLUMN = 'feature_flags_ext_1'.freeze

  def self.after_commit(account)
    return unless turned_on?(account) && Waha::EngineCapabilities.engines.any?

    Waha::EngineCapabilitiesRefreshJob.perform_later
  rescue StandardError => e
    Rails.logger.error("[waha] rich native cold start account=#{account.id} #{e.class}")
  end

  def self.turned_on?(account)
    before, after = account.saved_changes[COLUMN]
    return false if after.nil?

    bit = Account.flag_mapping[COLUMN][:"feature_#{Waha::RichNative::FLAG}"]
    before.to_i.nobits?(bit) && after.to_i.anybits?(bit)
  end
end
