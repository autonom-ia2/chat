# O gatilho "mensagem que falhou" (G8, #2637). Quem chama é o AutomacaoListener: a mensagem nova que já nasce recusada
# (`criada`) e a que o canal recusa depois (`atualizada`, o status passou a `failed`). Só a mensagem que saiu para o
# cliente: a recebida, a nota privada e a atividade não falham para ele.
#
# A marca do evento é a própria mensagem ("mensagem.falhou:<id>"): o evento repetido não abre outra execução, e a
# rajada de recusas abre uma por mensagem.
#
# A falha de uma mensagem que uma automação mandou chega depois, pelo webhook do canal, fora da cadeia de quem a
# mandou. A marca da mensagem (NaConversa#marca) diz qual execução foi; a partida retoma a cadeia dela. Assim a mesma
# automação não se redispara (auto-disparo), e duas que se mandam mensagem que falha param no laço da cadeia, como
# qualquer outra mudança feita por automação.
module Autonomia::Automacao::MensagemQueFalhou
  TIPO = 'mensagem.falhou'.freeze
  FALHOU = 'failed'.freeze

  module_function

  def criada(mensagem)
    comecar(mensagem) if mensagem&.failed?
  end

  def atualizada(mensagem, mudancas)
    status = mudancas.to_h.with_indifferent_access[:status]
    comecar(mensagem) if mensagem && status.present? && status.last.to_s == FALHOU
  end

  def comecar(mensagem)
    return unless mensagem.outgoing? && !mensagem.private? && ::Autonomia::Automacao::Motor.ligado?(mensagem.account)

    execucao = execucao_que_mandou(mensagem)
    ::Autonomia::Automacao::Cadeia.retomar(execucao&.cadeia, mensagem.account) do
      ::Autonomia::Automacao::Escuta.comecar(mensagem.conversation, TIPO, mensagem: mensagem, evento: "#{TIPO}:#{mensagem.id}")
    end
  rescue StandardError => e
    Rails.logger.error("[Automacao::MensagemQueFalhou] não ouviu mensagem=#{mensagem&.id} #{e.class}")
  end

  # G53: o id da mensagem que falhou, lido da marca do evento ("mensagem.falhou:<id>"). Outra marca, nil.
  def id_da_marca(marca)
    tipo, id = marca.to_s.split(':', 2)
    Integer(id, 10, exception: false) if tipo == TIPO && id
  end

  def execucao_que_mandou(mensagem)
    id = mensagem.content_attributes.to_h.with_indifferent_access[:execucao_id]
    ::Autonomia::Automacao::Execucao.find_by(id: id, account_id: mensagem.account_id) if id
  end
end
