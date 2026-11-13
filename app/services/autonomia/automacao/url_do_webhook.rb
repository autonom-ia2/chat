# #2450: a URL de um webhook costuma levar um token. Quem não é administrador nem tem `integration_manage` (quem só vê
# as regras, ou só monta automações) lê a regra automática (automation_rules) e a automação inteiras, com a URL trocada
# pelo endereço do servidor: dá para saber para onde vai, não para chamar. A ação e o passo continuam à vista.
#
# A URL mascarada nunca volta gravada: mudar a regra que tem webhook pede `integration_manage`
# (AutomationExternalActionGuard), e o passo webhook também (PassoDeWebhook.pode_mandar?).
#
# A macro usa a mesma ação (`send_webhook_event`) e a mesma máscara (#2451): mudar a macro com webhook também pede a
# chave (MacrosController#check_webhook_action).
module Autonomia::Automacao::UrlDoWebhook
  CHAVE = 'integration_manage'.freeze
  ESCONDIDO = '•••'.freeze
  ACAO_DA_REGRA = 'send_webhook_event'.freeze
  PASSO = 'webhook'.freeze
  # #2934: o endereço do "buscar em outro sistema" também costuma levar token.
  CONSULTA = 'consultar'.freeze

  module_function

  def ve?(account_user) = account_user.present? && account_user.permission_granted?(CHAVE)

  # "https://hooks.exemplo.com/entrada?token=x" => "https://hooks.exemplo.com/•••".
  def mascarada(url)
    uri = URI.parse(url.to_s)
    uri.host.present? ? "#{uri.scheme}://#{uri.host}/#{ESCONDIDO}" : ESCONDIDO
  rescue URI::InvalidURIError
    ESCONDIDO
  end

  # As ações da regra automática (e da macro), com a URL do webhook mascarada para quem não a vê.
  def acoes_da_regra(acoes, account_user)
    return acoes if ve?(account_user)

    Array(acoes).map do |acao|
      next acao unless acao['action_name'] == ACAO_DA_REGRA

      acao.merge('action_params' => Array(acao['action_params']).map { |url| mascarada(url) })
    end
  end

  # A receita da Automação livre, com a URL de cada passo webhook mascarada (também dentro dos ramos, pela travessia
  # única da Receita) para quem não a vê. A receita gravada não muda: a máscara vai numa cópia.
  def receita(receita, account_user)
    return receita if ve?(account_user) || !receita.is_a?(Hash)

    receita.deep_dup.tap do |copia|
      ::Autonomia::Automacao::Receita.new(copia, conta: nil, account_user: nil).passos.each { |passo| mascarar(passo) if passo.is_a?(Hash) }
    end
  end

  # O endereço do webhook e o do "buscar em outro sistema" (#2934), na cópia.
  def mascarar(passo)
    passo['url'] = mascarada(passo['url']) if passo['tipo'] == PASSO
    fonte = passo['fonte']
    fonte['url'] = mascarada(fonte['url']) if passo['tipo'] == CONSULTA && fonte.is_a?(Hash) && fonte.key?('url')
  end
end
