# A linha de vocabulário da conta nas mensagens que a IA escreve ao cliente (#2034): follow-up, retorno combinado, lembrete
# de Atender e modelo fora das 24 h. Vem do pacote do servidor (config/pacotes/seguros/**, #1550). O envio roda em job e
# fora de uma requisição, onde o pacote não vale, então ele entra aqui. Em português porque o pedido ao modelo é em
# português. Conta fora de um pacote recebe vazio e o pedido fica como sempre foi.
module Crm::Ai::Vocabulario
  CHAVE = 'crm.ai.vocabulario'.freeze

  def self.da(account)
    Autonomia::Segmentos::Pacotes.with(account) { I18n.t(CHAVE, locale: :pt_BR, default: '') }
  end
end
