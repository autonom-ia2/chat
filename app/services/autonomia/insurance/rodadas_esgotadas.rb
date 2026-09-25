# O ESPECIALISTA DE COTAÇÃO GASTOU AS SEIS RODADAS SEM ABRIR A COTAÇÃO (decisão 3 do Rodrigo, 25/09/2026, chat#718).
#
# O teto das rodadas é do cliente de IA (`Crm::Ai::ResponsesClient#create_with_tool_executor`, núcleo do CRM), que não
# conta a ninguém que acabou. Quem sabe é o `Specialists::Runner`, que executa cada rodada: ele passa aqui cada rodada
# e o que as ferramentas assíncronas (a cotação) devolveram, e no fim pergunta se esgotou. O núcleo não muda.
#
# SÓ O ESPECIALISTA QUE A AUTONOM.IA MANTÉM NO AGENTE DE COTAÇÃO (`QuoteAgent::Builder.ramo_do_especialista`): para
# qualquer outro especialista esta classe não faz nada, e o Runner segue como sempre.
#
# ESGOTOU: as seis rodadas rodaram, alguma chamou a cotação, e nenhuma cotação abriu nem já existia. A equipe recebe
# nota privada na hora (`NotaNaHora`), com a última recusa da conferência; quando a recusa se repetiu, a nota diz que
# a conferência ficou em laço. O cliente não recebe nada daqui: a Lia fala pela SITUAÇÃO DA COTAÇÃO do Runner.
class Autonomia::Insurance::RodadasEsgotadas
  RODADAS = 'A IA gastou as %<rodadas>d rodadas de ferramenta deste turno e não conseguiu abrir a cotação de %<ramo>s. ' \
            'A pessoa não recebeu a cotação; confira os dados na conversa e cote, se for o caso.'.freeze
  EM_LACO = 'A conferência recusou o mesmo pedido %<vezes>d vezes seguidas (em laço).'.freeze
  ULTIMA = 'Última recusa da conferência: %<recusa>s'.freeze
  TETO_DA_RECUSA = 500

  def initialize(specialist:, delivery:, rodadas:)
    @ramo = ::Autonomia::Insurance::QuoteAgent::Builder.ramo_do_especialista(specialist)
    @slug = specialist&.slug
    @delivery = delivery
    @rodadas = rodadas
    @feitas = 0
    @recusas = []
  end

  # Uma rodada do especialista. `recusas`: o que a cotação devolveu nesta rodada sem abrir execução.
  def rodada!(recusas)
    @feitas += 1
    @recusas.concat(Array(recusas).map(&:to_s))
  end

  # No fim do turno do especialista. `abriu`: alguma cotação abriu ou já existia. -> a nota, ou nil.
  def avisar!(tentou_cotar:, abriu:)
    return unless @ramo && tentou_cotar && !abriu && @feitas >= @rodadas

    ::Autonomia::Insurance::NotaNaHora.postar(@delivery&.conversation, texto,
                                              chave: "rodadas:#{@delivery&.origin_message_id}:#{@slug}")
  end

  private

  def texto
    [format(RODADAS, rodadas: @rodadas, ramo: @ramo), laco, ultima].compact.join("\n")
  end

  def laco
    vezes = @recusas.reverse.take_while { |recusa| recusa == @recusas.last }.size
    format(EM_LACO, vezes: vezes) if vezes > 1
  end

  def ultima
    format(ULTIMA, recusa: @recusas.last.truncate(TETO_DA_RECUSA)) if @recusas.any?
  end
end
