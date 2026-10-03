# A pessoa responde um caso do Decisor (#858): "este é lead".
#
# A resposta vira exemplo (origem pessoa), para o Decisor acertar sozinho da próxima vez. Corrigir uma
# decisão já tomada (pelo Jev ou pelo Guia) soma em `correcoes_count` e não refaz a automação, que já
# agiu ou já parou. Só o caso que estava parado retoma — e só dentro do prazo de 2 dias.
class Autonomia::Decisores::Resolucao
  class Recusada < StandardError; end

  PARADAS = %w[duvida esperando_pessoa].freeze

  def initialize(decisao:, user:)
    @decisao = decisao
    @decisor = decisao.decisor
    @user = user
  end

  # -> true quando a automação foi retomada.
  def resolver!(resposta)
    raise Recusada, "resposta must be one of: #{@decisor.chaves.join(', ')}" unless @decisor.resposta?(resposta)

    parada = PARADAS.include?(@decisao.status) && !@decisao.vencida_por_prazo?
    correcao = @decisao.decidida? && @decisao.resposta != resposta
    gravar!(resposta, parada, correcao)
    parada && Autonomia::Decisores::Retomada.enfileirar(@decisao).present?
  end

  private

  def gravar!(resposta, parada, correcao)
    estado = Autonomia::Decisores::Estado.new(conversation: @decisao.conversation, message: @decisao.message)
    ActiveRecord::Base.transaction do
      @decisao.update!(status: status_final(parada), resposta: resposta, resolvida_por: @user)
      @decisor.guardar_exemplo!(texto: estado.texto_do_exemplo, resposta: resposta, origem: 'pessoa', decisao_id: @decisao.id)
      @decisor.update!(correcoes_count: @decisor.correcoes_count + 1) if correcao
    end
  end

  # O caso parado que passou do prazo fica vencido mesmo respondido: a resposta vale como exemplo,
  # mas a automação não volta.
  def status_final(parada)
    vencida = @decisao.status == 'vencida' || (PARADAS.include?(@decisao.status) && !parada)
    vencida ? 'vencida' : 'resolvida'
  end
end
