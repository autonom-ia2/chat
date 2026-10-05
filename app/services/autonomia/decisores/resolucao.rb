# A pessoa responde um caso do Decisor (#858): "este é lead".
#
# A resposta vira exemplo (origem pessoa), para o Decisor acertar sozinho da próxima vez. Corrigir uma
# decisão já tomada (pelo Jev ou pelo Guia) soma em `correcoes_count` e não refaz a automação, que já
# agiu ou já parou. Só o caso que estava parado retoma — e só dentro do prazo de 2 dias.
#
# O caso parado é reivindicado (a troca de status só vale se ele ainda estiver parado): duplo clique,
# ou a pessoa e o Guia ao mesmo tempo, retomam a automação uma vez só. Quem perde a troca encontra a
# decisão já tomada e vira correção, se respondeu diferente.
class Autonomia::Decisores::Resolucao
  class Recusada < StandardError; end

  def initialize(decisao:, user:)
    @decisao = decisao
    @decisor = decisao.decisor
    @user = user
  end

  # -> true quando a automação foi retomada.
  def resolver!(resposta)
    raise Recusada, "resposta must be one of: #{@decisor.chaves.join(', ')}" unless @decisor.resposta?(resposta)

    return retomar!(resposta) if no_prazo? && @decisao.reivindicar!(estava: Autonomia::DecisorDecisao::PARADAS, **resolvida(resposta))

    corrigir!(resposta)
    false
  end

  private

  def no_prazo?
    @decisao.parada? && !@decisao.vencida_por_prazo?
  end

  def resolvida(resposta)
    { status: 'resolvida', resposta: resposta, resolvida_por_id: @user&.id }
  end

  # A retomada sai antes do exemplo: se o exemplo falhar, a automação já retomou.
  def retomar!(resposta)
    retomou = Autonomia::Decisores::Retomada.enfileirar(@decisao).present?
    guardar_exemplo!(resposta)
    retomou
  end

  def corrigir!(resposta)
    correcao = @decisao.decidida? && @decisao.resposta != resposta
    ActiveRecord::Base.transaction do
      @decisao.update!(status: status_final, resposta: resposta, resolvida_por: @user)
      guardar_exemplo!(resposta)
      @decisor.update!(correcoes_count: @decisor.correcoes_count + 1) if correcao
    end
  end

  def guardar_exemplo!(resposta)
    estado = Autonomia::Decisores::Estado.da_decisao(@decisao)
    @decisor.guardar_exemplo!(texto: estado.texto_do_exemplo, resposta: resposta, origem: 'pessoa', decisao_id: @decisao.id)
  end

  # O caso parado que passou do prazo fica vencido mesmo respondido: a resposta vale como exemplo,
  # mas a automação não volta.
  def status_final
    @decisao.status == 'vencida' || @decisao.parada? ? 'vencida' : 'resolvida'
  end
end
