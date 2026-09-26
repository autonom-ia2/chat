# A COTAÇÃO SÓ ABRE NO RAMO QUE TEM ESPECIALISTA NESTA CONTA (conversa 7150, 26/09/2026).
#
# A pessoa perguntou por seguro de vida e a Lia respondeu que a corretora trabalha com ele "com opções em 8
# seguradoras" e que cotava: `consultar_produtos_cotacao` entregava como cotável tudo o que a conexão traz. Só auto,
# residencial e empresarial têm especialista. Seguindo a conversa, o pedido de vida chegaria a esta ferramenta pelo
# caminho genérico, com `dados` livre e sem manual do ramo. Decisão do CEO (opção 1): ramo que a corretora trabalha e a
# IA não cota vai para a equipe, pela fala da Lia de que vai encaminhar (o handoff do CRM).
#
# A lista e o manual da Lia são a primeira porta; esta é a guarda no código. Só no Agente de Cotação, que é onde cada
# ramo tem especialista (`Builder.ramos_que_a_ia_cota`): o agente comum com a ferramenta ligada direto cota como sempre.
# A comparação ignora maiúsculas para nunca recusar o que antes passava: `Auto` segue para o adapter como antes.
module Autonomia::Agents::Tools::Native::InsuranceQuote::RamoSemEspecialista
  extend ActiveSupport::Concern

  # Para o MODELO do especialista (volta pela conferência). Diz o fato, o que não fazer e os dois caminhos: o código
  # certo, quando o pedido é de um ramo que a IA cota e o nome veio errado, ou a equipe.
  SEM_ESPECIALISTA = 'Este tipo de seguro não é cotado pela IA nesta conta, e a cotação não foi aberta. Não peça dados ' \
                     'à pessoa para ele e não tente cotá-lo por outro caminho. Se o pedido é de um dos ramos que a IA ' \
                     'cota aqui (%<ramos>s), chame de novo com esse ramo em produto. Se não é, devolva ao atendente que ' \
                     'este seguro fica com a equipe da corretora, que vai atender a pessoa.'.freeze

  private

  # -> true quando este é o Agente de Cotação e o produto pedido não é de um especialista que atende nesta conta.
  def ramo_sem_especialista?
    return false unless agent&.agent_type == 'insurance_quote'

    ramos_que_a_ia_cota.exclude?(produto.downcase)
  end

  def ramos_que_a_ia_cota
    @ramos_que_a_ia_cota ||= ::Autonomia::Insurance::QuoteAgent::Builder.ramos_que_a_ia_cota(account)
  end

  # A recusa da conferência, e o ramo anotado para a nota da equipe no encaminhamento; nil quando o ramo tem
  # especialista. Conexão fora do ar tira residencial e empresarial de `atende?`: aí o motivo real é a conexão, e quem
  # o diz é a conferência seguinte (`recusa_de_entrada`).
  def conferencia_sem_especialista
    return nil unless ramo_sem_especialista? && !conexao_fora?

    anotar_ramo_pedido
    conferencia('ramo_sem_especialista', format(SEM_ESPECIALISTA, ramos: ramos_que_a_ia_cota.join(', ')), ['produto'])
  end

  # Só o ramo que a conexão traz habilitado vai para a nota: é o que a corretora trabalha. Um nome que o modelo
  # inventou não é ramo, e a equipe não tem o que fazer com ele. Nunca levanta: é cortesia sobre uma recusa.
  def anotar_ramo_pedido
    ramo = produto.downcase
    produtos = ::Autonomia::Insurance::QuoteAgent::Builder.produtos_da_conta(account)
    return unless produtos.any? { |item| item['product'] == ramo && item['enabled'] }

    ::Autonomia::Agents::Tools::RecusasRecentes.anotar_ramo(::Autonomia::Agents::Tools::Recusa.conversa_de(delivery), ramo)
  rescue StandardError
    nil
  end
end
