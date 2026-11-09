# A resposta que chegou durante um "esperar até" (G11 do fechamento do #2414): "até o cliente responder" e "até a
# equipe responder". `espera` é a janela da espera (Range: do começo até o prazo, ou sem fim na primeira conferência);
# só conta o que chegou depois do começo e até o prazo.
#
# - Cliente: mensagem recebida em qualquer conversa do contato na conta que quem ligou vê (#2680).
# - Equipe: a mesma régua da IA que responde (Autonomia::Agents::Operate::PessoaDaEquipe): pessoa da equipe escrevendo
#   ao cliente, ou o eco do que ela mandou pelo app do celular. Não contam a nota, o robô, o envio automático em nome
#   de alguém (follow-up, campanha, regra), a mensagem da própria automação nem a que falhou: o cliente não a recebeu.
#
# O eco de uma mensagem NOSSA (IA, automação, robô) não é a equipe respondendo. Normalmente ele nem vira mensagem: o
# reconciliador o junta à bolha que já existe (WhatsappHybrid::EchoReconcilerExtension; na Cloud, o mesmo source_id).
# Quando o eco chega antes de a bolha ter o id gravado, nasce uma mensagem a mais, com a marca do celular e sem
# remetente (PessoaDaEquipe, "ECO DO CELULAR"). A raiz para separar: o eco leva o id da mensagem que saiu (o wamid; no
# Híbrido, o id físico dentro dele, WhatsappHybrid::Wamid). Se outra mensagem de saída da caixa tem esse id, o eco é
# dela e não conta. O eco do que a pessoa mandou pelo celular não tem par aqui.
#
# A corrida: o eco vira mensagem nova justamente porque a bolha ainda não tem o id, e a espera acorda nesse mesmo
# instante. Por isso, eco sem par com uma mensagem NOSSA de saída da conversa ainda sem id, anterior a ele, é ambíguo e
# não conta agora. A espera segue; no prazo, a varredura confere de novo a janela inteira, com o id já gravado: o eco
# da bolha é descartado, e o de uma pessoa conta (atrasado, no prazo).
module Autonomia::Automacao::Resposta
  module_function

  # Os valores que a condição do "esperar até" lê (Valores::RESPOSTA). Cada um recebe o Contexto da execução, a janela
  # da espera e quem ligou, e trata o vazio (sem contato, sem conversa) como "não respondeu".
  VALORES = {
    'conversa.cliente_respondeu' => ->(contexto, espera, quem) { cliente?(contexto.contato, espera, quem) },
    'conversa.equipe_respondeu' => ->(contexto, espera, _quem) { equipe_na?(contexto.conversa, espera) }
  }.freeze

  # Em qualquer conversa do contato na conta que `quem` (quem ligou) vê, pelo filtro da lista de conversas (#2680): o
  # e-mail da automação abre uma conversa nova, e a resposta chega nela. A resposta numa caixa que quem ligou não abre
  # não decide o ramo (parecer da Funções). Sem contato, ou sem quem ligou, nunca respondeu.
  def cliente?(contato, espera, quem)
    recebidas = do_cliente(contato, quem)
    !recebidas.nil? && na_janela(recebidas, espera).exists?
  end

  # O "decidir" que decide de novo (G31): a resposta depois da mensagem `depois_de` (id) e até `ate` (sem fim na
  # primeira conferência). Pelo id, não pela hora: a mensagem gravada depois da leitura tem id maior, mesmo com
  # `created_at` de antes.
  def cliente_depois?(contato, depois_de, ate, quem)
    recebidas = do_cliente(contato, quem)
    return false if recebidas.nil?

    novas = recebidas.where('messages.id > ?', depois_de)
    (ate ? novas.where('messages.created_at <= ?', ate) : novas).exists?
  end

  # O marco da leitura do G31: o id da última mensagem do cliente que existe agora (0 sem nenhuma).
  def ultima_do_cliente_id(contato, quem) = do_cliente(contato, quem)&.maximum(:id).to_i

  # As mensagens recebidas do contato nas conversas que quem ligou vê; nil sem contato ou sem quem ligou.
  def do_cliente(contato, quem)
    return if contato.nil? || quem.nil?

    conta = contato.account
    do_contato = ::Conversation.where(account_id: conta.id, contact_id: contato.id)
    conversas = ::Conversations::PermissionFilterService.new(do_contato, quem, conta, for_reading: true).perform.select(:id)
    ::Message.incoming.where(account_id: conta.id, conversation_id: conversas)
  end

  # Sem conversa (o card sem conversa principal, o contato antes da conversa nova), a equipe nunca respondeu.
  def equipe_na?(conversa, espera) = conversa.present? && equipe?(conversa, espera)

  # O SQL já deixa só o que pode ser pessoa ou eco (público, que não falhou, remetente pessoa ou nenhum); a régua decide.
  def equipe?(conversa, espera)
    equipe = ::Autonomia::Agents::Operate::PessoaDaEquipe
    candidatas = conversa.messages.chat.outgoing.where(sender_type: ['User', nil]).where.not(status: :failed)
    na_janela(candidatas, espera).find_each.any? do |mensagem|
      equipe.da_pessoa?(mensagem) || (equipe.eco_do_celular?(mensagem) && eco_de_pessoa?(mensagem))
    end
  end

  def eco_de_pessoa?(eco) = !eco_do_que_saiu_daqui?(eco) && !saida_nossa_sem_id_antes?(eco)

  # Nossa: robô, automação ou envio automático em nome de alguém (PessoaDaEquipe.envio_automatico?). O eco sempre tem
  # source_id (o wamid), então nunca entra aqui.
  def saida_nossa_sem_id_antes?(eco)
    equipe = ::Autonomia::Agents::Operate::PessoaDaEquipe
    eco.conversation.messages.chat.outgoing.where(source_id: nil).where.not(status: :failed).where('messages.id < ?', eco.id)
       .find_each.any? { |mensagem| mensagem.sender_type != 'User' || equipe.envio_automatico?(mensagem) }
  end

  def eco_do_que_saiu_daqui?(eco)
    ids = [eco.source_id, ::WhatsappHybrid::Wamid.message_id(eco.source_id.to_s)].compact_blank.uniq
    ids.any? && ::Message.where(inbox_id: eco.inbox_id, message_type: :outgoing, source_id: ids).where.not(id: eco.id).exists?
  end

  def na_janela(mensagens, espera)
    depois = mensagens.where('messages.created_at > ?', espera.begin)
    espera.end ? depois.where('messages.created_at <= ?', espera.end) : depois
  end
end
