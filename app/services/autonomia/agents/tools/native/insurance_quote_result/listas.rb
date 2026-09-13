# UMA LISTA POR PEDIDO, E NUNCA A MESMA DUAS VEZES (terceira a quinta rodadas de revisão da fatia 2 do #420).
#
# A lista de uma execução da ferramenta da Lia leva também os códigos das execuções anteriores dela, na mesma
# conversa e sobre a mesma cotação, cuja lista não é mensagem entregue (`codigos_a_publicar`), e grava na própria
# linha quais levou (`ABSORVIDAS_KEY`), sob o lock da conversa. A lista ainda não entregue de uma execução levada por
# outra não sai mais (`InsuranceQuoteResult.publicacao_vale?`, com `absorvida_depois?`).
#
# "Mensagem entregue" é `lista_entregue?`: `sequence` positivo (o publicador o avança na mesma transação, sob o
# lock da conversa, em que cria a mensagem) e nenhuma mensagem da execução com pendência de envio.
#
# Separado da ferramenta pelo mesmo motivo de `InsuranceQuote::Resultado`: a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuoteResult::Listas
  extend ActiveSupport::Concern

  # No handle da execução: os ids das execuções anteriores cuja lista a desta leva.
  ABSORVIDAS_KEY = 'listas_absorvidas'.freeze
  # Quantas execuções anteriores a passada lê, no máximo.
  ANTERIORES_LIDAS = 20

  class_methods do
    # -> a lista desta execução é mensagem entregue: a `sequence` avançou, e nenhuma mensagem com a identidade de
    # entrega desta execução (`ToolRun#delivery_token`) tem pendência de envio (`Tools::PendenciaDeEnvio`).
    def lista_entregue?(run)
      return false unless run.sequence.positive?

      mensagens = run.conversation&.messages&.where(sender_type: 'AgentBot')
                     &.where('content_attributes::text LIKE ?', "%#{run.execution_key}:%")
      Array(mensagens).none? { |mensagem| ::Autonomia::Agents::Tools::PendenciaDeEnvio.pendente?(mensagem) }
    end

    # -> alguma execução desta ferramenta na conversa, mais nova que `run`, levou a lista de `run` na sua?
    def absorvida_depois?(run)
      ::Autonomia::Agents::ToolRun.for_conversation(run.conversation_id).where(slug: slug).where('id > ?', run.id)
                                  .any? { |outra| Array(outra.handle.to_h[ABSORVIDAS_KEY]).map(&:to_i).include?(run.id) }
    end
  end

  private

  # -> os códigos desta execução e os das anteriores desta ferramenta na conversa que `prometida?` aceita, lidas da
  # mais nova para a mais antiga até a primeira com a lista entregue. A leitura e a gravação de quais foram levadas
  # (`absorver`) são feitas sob o lock da conversa, o mesmo sob o qual o publicador confere `publicacao_vale?` e
  # cria a mensagem.
  def codigos_a_publicar(handle, execucao)
    proprios = Array(handle[self.class::CODIGOS_KEY])
    return proprios if run&.conversation.nil?

    levadas = run.conversation.with_lock { absorver(prometidas_antes(execucao)) }
    (levadas.flat_map { |outra| Array(outra.handle.to_h[self.class::CODIGOS_KEY]) } + proprios).uniq
  end

  # Grava na linha desta execução quais anteriores ela leva. `merge_handle!` só grava com a execução viva: a que foi
  # supersedida no meio da passada não barra ninguém, e a publicação dela é recusada por estar morta.
  def absorver(anteriores)
    run.merge_handle!({ ABSORVIDAS_KEY => anteriores.map(&:id) }) if anteriores.any?
    anteriores
  end

  def prometidas_antes(execucao)
    anteriores.take_while { |outra| !self.class.lista_entregue?(outra) }.select { |outra| prometida?(outra, execucao) }
  end

  # -> a lista de `outra`, sobre a mesma cotação, foi prometida numa fala que chegou ao cliente e ainda pode sair
  # nesta: a encerrada (`done`, despachada), e a supersedida que foi despachada (`expires_at`, gravado na promoção)
  # ou que é do mesmo turno desta (a segunda chamada da mesma rodada). A supersedida de outro turno que nunca foi
  # despachada é de um turno que não falou.
  def prometida?(outra, execucao)
    return false unless outra.handle.to_h[self.class::EXECUCAO_KEY].to_i == execucao
    return true if outra.status == 'done'

    outra.status == 'superseded' && (outra.expires_at.present? || outra.origin_message_id == run.origin_message_id)
  end

  # -> até `ANTERIORES_LIDAS` execuções desta ferramenta na conversa, anteriores a esta, da mais nova para a mais antiga.
  def anteriores
    ::Autonomia::Agents::ToolRun.for_conversation(run.conversation_id).where(slug: self.class.slug).where('id < ?', run.id)
                                .order(id: :desc).limit(ANTERIORES_LIDAS).to_a
  end
end
