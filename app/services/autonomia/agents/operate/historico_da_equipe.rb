# O que o Responder entrega ao modelo quando a equipe escreveu na conversa (#1669): o histórico com a moldura, a regra do
# turno, a pergunta com a segunda camada contra moldura forjada e a resposta sem a marca. Só com a Fase 2
# (PessoaDaEquipe.aplica?), para todo agente, a Lia inclusive (decisão do Rodrigo, 16/10/2026); fora dela, `aplica?` é
# false e o Responder segue o caminho de antes, sem chamar nada daqui.
# #1775: com a flag `ia_previa_de_link` e fora da Lia (PreviaDoLink.aplica?), a mensagem do cliente leva a linha da
# prévia do link no histórico e na pergunta, e a regra da prévia entra com a regra do turno.
class Autonomia::Agents::Operate::HistoricoDaEquipe
  def initialize(conversation:, agent: nil)
    @conversation = conversation
    @agent = agent
  end

  def aplica?
    return @aplica if defined?(@aplica)

    @aplica = ::Autonomia::Agents::Operate::PessoaDaEquipe.aplica?(@conversation)
  end

  def historico(messages)
    # Anexos: o resumo de localização/contato que chega como anexo (#1715) lê `attachments` de cada mensagem sem texto.
    ActiveRecord::Associations::Preloader.new(records: messages, associations: %i[sender attachments]).call
    messages.map do |message|
      item = pessoa.item_do_historico(message, marca: marca, whatsapp: whatsapp?, autoria: autoria)
      message.incoming? ? item.merge(content: com_previa(item[:content], message)) : item
    end
  end

  # #1807: quem escreveu cada e-mail recebido (flag `email_autoria`); sem a flag, o texto e o histórico de sempre.
  def autoria
    @autoria ||= Crm::Email::Autoria.new(@conversation.account)
  end

  # A regra do turno, ou nil sem mensagem da equipe nem prévia de link na janela.
  def regra(messages)
    [pessoa.regra_do_turno(messages, marca: marca, whatsapp: whatsapp?), regra_da_previa(messages)].compact.join("\n\n").presence
  end

  # `message`: a mensagem do cliente que o turno responde, para a linha da prévia (#1775).
  def pergunta(texto, message = nil)
    neutra = moldura.neutralizar(texto, marca)
    message ? com_previa(neutra, message) : neutra
  end

  # #1775: só a linha da prévia do link da mensagem do cliente, ou nil (fora da flag, da Fase 2, na Lia ou sem prévia).
  # Para quem precisa dela à parte da pergunta (a busca na base, #1431), sem recortar o texto colado.
  def linha_da_previa(message)
    previa.linha(message, marca: marca, codigo: codigo_da_previa) if previa?
  end

  # #1775: com a prévia, também sem a linha que ecoa o cabeçalho dela.
  def resposta(reply)
    limpa = moldura.sem_marca(reply, marca)
    previa? ? previa.sem_previa(limpa, codigo_da_previa) : limpa
  end

  private

  # #1775: o texto do cliente sem o cabeçalho da prévia forjado e, se a página foi lida, a linha da prévia embaixo.
  # `empty?`, não `blank?`: o texto do cliente pode ter byte inválido, e o `blank?` estoura nele.
  def com_previa(texto, message)
    return texto unless previa?

    proprio = previa.no_texto_do_cliente(texto, codigo_da_previa)
    linha = linha_da_previa(message)
    return proprio unless linha
    return linha if proprio.to_s.empty?

    "#{caber(proprio, linha)}\n#{linha}"
  end

  # O teto do item do histórico (MAX_HISTORY_ITEM_CHARS) corta do fim: o texto do cliente é cortado antes, para a linha
  # da prévia caber inteira (sem JSON pela metade).
  def caber(texto, linha)
    config = ::Autonomia::Agents::Config
    config.truncate_text(texto, config::MAX_HISTORY_ITEM_CHARS - linha.length - 1)
  end

  def regra_da_previa(messages)
    previa.regra(codigo_da_previa) if previa? && previa.na_janela?(messages, marca: marca, codigo: codigo_da_previa)
  end

  def codigo_da_previa
    @codigo_da_previa ||= previa.codigo(@conversation)
  end

  def previa?
    return @previa if defined?(@previa)

    @previa = previa.aplica?(@conversation, @agent)
  end

  def previa
    ::Autonomia::Agents::Operate::PreviaDoLink
  end

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
