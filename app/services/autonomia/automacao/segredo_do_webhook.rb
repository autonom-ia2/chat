# O segredo da assinatura do passo "webhook" (G13, #2670), um por automação. Não fica guardado: é derivado da chave da
# instalação (`secret_key_base`, pelo key_generator do Rails) com o id da automação e a geração dele. A geração é um
# contador, não é segredo, e mora no `internal_attributes` da conta. Nada no banco permite remontar o segredo sem a
# chave da instalação.
#
# - Trocar sobe a geração: o segredo anterior deixa de valer na hora, inclusive nos envios que ainda vão sair.
# - Trocar o SECRET_KEY_BASE da instalação troca o segredo de todas as automações (o outro sistema precisa do novo).
# - Ver e trocar são só do administrador (AutomacoesWebhookController): credencial não é delegada por função.
class Autonomia::Automacao::SegredoDoWebhook
  CHAVE = 'automacao_webhook_geracoes'.freeze
  SAL = 'autonomia/automacao/webhook'.freeze

  def initialize(automacao)
    @automacao = automacao
  end

  def valor
    OpenSSL::HMAC.hexdigest('SHA256', self.class.chave, "#{@automacao.id}:#{geracao}")
  end

  # Sobe a geração num UPDATE só, no próprio jsonb: duas trocas ao mesmo tempo somam as duas, sem ler e depois gravar.
  def trocar!
    id = @automacao.id.to_s
    sql = <<~SQL.squish
      internal_attributes = jsonb_set(COALESCE(internal_attributes, '{}'::jsonb), '{#{CHAVE}}',
        COALESCE(internal_attributes -> '#{CHAVE}', '{}'::jsonb) ||
        jsonb_build_object(:id, COALESCE((internal_attributes #>> ARRAY['#{CHAVE}', :id])::integer, 0) + 1))
    SQL
    Account.where(id: @automacao.account_id).update_all([sql, { id: id }]) # rubocop:disable Rails/SkipsModelValidations
    valor
  end

  def self.chave = (@chave ||= Rails.application.key_generator.generate_key(SAL, 32))

  private

  # Lido direto do banco, sem recarregar a conta que a execução está usando.
  def geracao
    Account.where(id: @automacao.account_id).pick(:internal_attributes).to_h.dig(CHAVE, @automacao.id.to_s).to_i
  end
end
