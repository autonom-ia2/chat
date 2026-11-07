# O segredo da assinatura do passo "webhook" (G13, #2670), um por automação. Não fica guardado: é derivado da chave da
# instalação (`secret_key_base`, pelo key_generator do Rails) com o id da automação e a geração dele. A geração é um
# contador, não é segredo, e mora na própria automação (`autonomia_automacoes.segredo_geracao`). Nada no banco permite
# remontar o segredo sem a chave da instalação.
#
# - Trocar sobe a geração: o segredo anterior deixa de valer na hora, inclusive nos envios que ainda vão sair.
# - Trocar o SECRET_KEY_BASE da instalação troca o segredo de todas as automações (o outro sistema precisa do novo).
# - Ver e trocar: o administrador ou a função com `token_manage` (AutomacoesWebhookController), como os outros segredos
#   que a plataforma gera.
class Autonomia::Automacao::SegredoDoWebhook
  SAL = 'autonomia/automacao/webhook'.freeze

  def initialize(automacao)
    @automacao = automacao
  end

  def valor
    OpenSSL::HMAC.hexdigest('SHA256', self.class.chave, "#{@automacao.id}:#{geracao}")
  end

  # Sobe a geração num UPDATE só: duas trocas ao mesmo tempo somam as duas, sem ler e depois gravar.
  def trocar!
    tabela.update_counters(@automacao.id, segredo_geracao: 1) # rubocop:disable Rails/SkipsModelValidations
    valor
  end

  def self.chave = (@chave ||= Rails.application.key_generator.generate_key(SAL, 32))

  private

  def tabela = ::Autonomia::Automacao::Definicao

  # Lida direto do banco: a automação carregada pela execução pode ser de antes da troca.
  def geracao = tabela.where(id: @automacao.id).pick(:segredo_geracao).to_i
end
