# O que o Responder entrega ao modelo quando a equipe escreveu na conversa (#1669): o histórico com a moldura, a regra do
# turno, a pergunta com a segunda camada contra moldura forjada e a resposta sem a marca. Só com a Fase 2
# (PessoaDaEquipe.aplica?), para todo agente, a Lia inclusive (decisão do Rodrigo, 16/10/2026); fora dela, `aplica?` é
# false e o Responder segue o caminho de antes, sem chamar nada daqui.
class Autonomia::Agents::Operate::HistoricoDaEquipe
  def initialize(conversation:)
    @conversation = conversation
  end

  def aplica?
    return @aplica if defined?(@aplica)

    @aplica = ::Autonomia::Agents::Operate::PessoaDaEquipe.aplica?(@conversation)
  end

  def historico(messages)
    # Anexos: o resumo de localização/contato que chega como anexo (#1715) lê `attachments` de cada mensagem sem texto.
    ActiveRecord::Associations::Preloader.new(records: messages, associations: %i[sender attachments]).call
    messages.map { |message| pessoa.item_do_historico(message, marca: marca, whatsapp: whatsapp?) }
  end

  # A regra do turno, ou nil sem mensagem da equipe na janela.
  def regra(messages)
    pessoa.regra_do_turno(messages, marca: marca, whatsapp: whatsapp?)
  end

  def pergunta(texto)
    moldura.neutralizar(texto, marca)
  end

  def resposta(reply)
    moldura.sem_marca(reply, marca)
  end

  private

  def marca
    @marca ||= moldura.marca(@conversation)
  end

  def whatsapp?
    @conversation.inbox.whatsapp?
  end

  def pessoa
    ::Autonomia::Agents::Operate::PessoaDaEquipe
  end

  def moldura
    ::Autonomia::Agents::Operate::MolduraDaEquipe
  end
end
