# UMA LISTA POR PEDIDO, NUNCA A MESMA DUAS VEZES, E UMA FALHA NUNCA PERDE DUAS (terceira a sétima rodadas de revisão
# da fatia 2 do #420).
#
# A passada que publica monta a lista desta execução (`emitir_lista`, sob o lock da conversa, o mesmo sob o qual o
# publicador confere `publicacao_vale?` e cria a mensagem):
#   - os códigos do pedido, gravados na abertura;
#   - mais os das execuções anteriores desta ferramenta, na mesma conversa e sobre a mesma cotação, cuja lista foi
#     prometida numa fala (`prometida?`) e não é mensagem entregue, com o que elas mesmas já levavam;
#   - menos os das anteriores cuja lista virou mensagem entregue DEPOIS de esta execução abrir: o cliente a recebeu
#     depois de pedir de novo.
# e grava na linha, em `LISTA_KEY`, os códigos, as execuções levadas e a identidade da entrega (`ToolRun#delivery_token`).
#
# A LISTA ANTERIOR SÓ CONTA COMO LEVADA DEPOIS DE A NOVA SER ACEITA (decisão do CEO, sétima rodada). `lista_levada?`
# exige que a execução que a levou tenha a lista aceita pelo publicador (`Tools::EntregaAceita`) ou já publicada; antes
# disso a anterior continua valendo, e uma falha na publicação da nova não perde as duas.
#
# "Mensagem entregue" é `lista_entregue?`: `sequence` positivo (o publicador o avança na mesma transação em que cria a
# mensagem) e nenhuma mensagem da execução com pendência de envio.
#
# Separado da ferramenta pelo mesmo motivo de `InsuranceQuote::Resultado`: a classe está no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceQuoteResult::Listas
  extend ActiveSupport::Concern

  # No handle da execução, gravada pela passada que publica: { 'codigos', 'levadas' (ids), 'token' }.
  LISTA_KEY = 'lista'.freeze
  # Os status de uma anterior cuja lista foi prometida numa fala: a que terminou (despachada) e a supersedida que foi
  # despachada ou é do mesmo turno (`prometida?`).
  TERMINADAS = %w[done failed].freeze
  # Quantas execuções anteriores a passada lê, no máximo.
  ANTERIORES_LIDAS = 20

  class_methods do
    # -> a lista desta execução é mensagem entregue: a `sequence` avançou, e nenhuma mensagem com a identidade de
    # entrega desta execução tem pendência de envio (`Tools::PendenciaDeEnvio`).
    def lista_entregue?(run)
      run.sequence.positive? && mensagens_da_lista(run).none? { |mensagem| ::Autonomia::Agents::Tools::PendenciaDeEnvio.pendente?(mensagem) }
    end

    # -> a lista desta execução foi aceita pelo publicador (publicada ou adiada) ou já é mensagem.
    def lista_aceita?(run)
      token = run.handle.to_h.dig(LISTA_KEY, 'token')
      return false if token.blank?

      ::Autonomia::Agents::Tools::EntregaAceita.aceita?(run, token) ||
        ::Autonomia::Agents::Tools::EntregaPublicada.para(run.conversation, token).present?
    end

    # -> uma execução mais nova desta ferramenta na conversa levou a lista de `run`, e a dela já foi aceita.
    def lista_levada?(run)
      ::Autonomia::Agents::ToolRun.for_conversation(run.conversation_id).where(slug: slug).where('id > ?', run.id)
                                  .any? { |outra| levou?(outra, run) && lista_aceita?(outra) }
    end

    # -> a lista gravada por `outra` levou a de `run`?
    def levou?(outra, run)
      Array(outra.handle.to_h.dig(LISTA_KEY, 'levadas')).map(&:to_i).include?(run.id)
    end

    # -> as mensagens publicadas com a identidade de entrega desta execução.
    def mensagens_da_lista(run)
      run.conversation.messages.where(sender_type: 'AgentBot').where('content_attributes::text LIKE ?', "%#{run.execution_key}:%")
    end
  end

  private

  # -> a lista desta execução ainda tem de sair: a cotação lida no turno é a mais nova da conversa, a lista não foi
  # aceita nem publicada, e nenhuma execução mais nova a levou.
  def lista_vale?(execucao)
    resultado&.run&.id == execucao && !self.class.lista_aceita?(run) && !self.class.lista_levada?(run)
  end

  # -> o texto da lista desta execução, montado e gravado sob o lock da conversa, ou nil quando não sobrou código.
  def emitir_lista(handle, execucao)
    run.conversation.with_lock do
      levadas, descontadas = composicao(execucao)
      codigos = (levadas.flat_map { |outra| codigos_da_lista(outra) } + Array(handle[self.class::CODIGOS_KEY])).uniq -
                descontadas.flat_map { |outra| codigos_da_lista(outra) }
      texto = resultado.itens(codigos)
      gravar_lista(texto, codigos, levadas) if texto
    end
  end

  # -> [anteriores levadas, anteriores descontadas], lidas da mais nova para a mais antiga até a primeira entregue antes
  # de esta execução abrir.
  def composicao(execucao)
    anteriores.each_with_object([[], []]) do |outra, (levadas, descontadas)|
      next unless outra.handle.to_h[self.class::EXECUCAO_KEY].to_i == execucao

      if self.class.lista_entregue?(outra)
        break [levadas, descontadas] unless entregue_depois_da_abertura?(outra)

        descontadas << outra
      elsif prometida?(outra)
        levadas << outra
      end
    end
  end

  def gravar_lista(texto, codigos, levadas)
    texto = progress_class.entregavel(texto)
    token = ::Autonomia::Agents::Tools::EntregaPublicada.token_de(run, texto)
    run.merge_handle!({ LISTA_KEY => { 'codigos' => codigos, 'levadas' => levadas.map(&:id), 'token' => token } })
    texto
  end

  # -> os códigos da lista de `outra`: os que ela gravou ao publicar, ou os do pedido dela.
  def codigos_da_lista(outra)
    Array(outra.handle.to_h.dig(LISTA_KEY, 'codigos').presence || outra.handle.to_h[self.class::CODIGOS_KEY])
  end

  def entregue_depois_da_abertura?(outra)
    self.class.mensagens_da_lista(outra).exists?(['created_at >= ?', run.created_at])
  end

  # -> a lista de `outra` foi prometida numa fala que chegou ao cliente: a que terminou (despachada), e a supersedida
  # que foi despachada (`expires_at`, gravado na promoção) ou que é do mesmo turno desta (a segunda chamada da mesma
  # rodada). A supersedida de outro turno que nunca foi despachada é de um turno que não falou.
  def prometida?(outra)
    return true if TERMINADAS.include?(outra.status)

    outra.status == 'superseded' && (outra.expires_at.present? || outra.origin_message_id == run.origin_message_id)
  end

  # -> até `ANTERIORES_LIDAS` execuções desta ferramenta na conversa, anteriores a esta, da mais nova para a mais antiga.
  def anteriores
    ::Autonomia::Agents::ToolRun.for_conversation(run.conversation_id).where(slug: self.class.slug).where('id < ?', run.id)
                                .order(id: :desc).limit(ANTERIORES_LIDAS).to_a
  end
end
