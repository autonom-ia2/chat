# Avisa quando a instalação está em produção sem as chaves do Active Record Encryption (#1344).
#
# Sem as três `ACTIVE_RECORD_ENCRYPTION_*`, as colunas declaradas com `encrypts ... if Chatwoot.encryption_configured?`
# passam a gravar segredo de cliente em claro, e nada falha: foi assim que o legado do #1344 se formou sem ninguém
# perceber. O aviso vai para o log e para o Sentry, uma vez por subida do Sidekiq.
class EncryptionAlert
  class KeysMissing < StandardError; end

  MESSAGE = 'ACTIVE_RECORD_ENCRYPTION_* ausente em produção: segredos novos serão gravados em texto puro'.freeze

  def self.check
    return unless Rails.env.production?
    return if Chatwoot.encryption_configured?

    ChatwootExceptionTracker.new(KeysMissing.new(MESSAGE)).capture_exception
  end
end
