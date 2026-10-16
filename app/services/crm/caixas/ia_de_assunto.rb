# #1676: a IA de assunto da caixa gravada pela tela de Caixas (Crm::Caixas::Gravador) e mostrada para a caixa ainda sem
# configuração (Crm::Caixas::Retrato). Com a flag `crm_avaliar_toda_mensagem` (contas 1, 16 e 18 por enquanto), fica em
# Automática também na caixa de 1 funil, em 'chegou' ou à mão: um funil pode ter mais de um assunto (dois produtos no
# mesmo funil). Sem a flag, desligada com 1 funil, como antes. Com vários funis vale o que a tela mandou.
module Crm::Caixas::IaDeAssunto
  module_function

  def padrao(account)
    Crm::Conversations::CardEmFoco.ligada?(account) ? 'auto' : 'off'
  end

  def ao_gravar(account:, pipeline_ids:, modo:)
    return 'off' if pipeline_ids.empty?

    pipeline_ids.size == 1 ? padrao(account) : modo
  end
end
