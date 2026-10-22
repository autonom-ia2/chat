# Toda mensagem do cliente avalia o card em foco (#1675, épico #1140), atrás da flag de conta `crm_avaliar_toda_mensagem`.
#
# Na caixa sem card ao chegar (2+ funis, ou 1 funil em modo manual), a mensagem não fazia nada no card: só a troca de foco
# (Crm::Cards::Focus) e o card novo da IA de assunto agendavam a IA do CRM. O cliente que seguia no mesmo assunto
# ("fechado, quero contratar") não movia o card. Com a flag e a IA do CRM ligada, a mensagem do cliente:
#   1. agenda a avaliação do card em foco (Crm::Ai::Observer, com o debounce de sempre: uma rajada, uma avaliação); e
#   2. conta como atividade dele (last_message_at e last_activity_at com a hora da mensagem, só para a frente).
#
# Quem chama: o CardSyncer, com a IA de assunto desligada na caixa; o Crm::Subjects::IdentifyJob, depois da decisão do
# assunto, com ela ligada (o card em foco já é o do assunto decidido). Com ela ligada, vale também para a caixa de 1 funil
# com card ao chegar: o CardSyncer não agenda nem conta atividade no card da chegada (o foco de antes da mensagem), e
# um cliente com dois assuntos no mesmo funil tem lido o card do assunto da mensagem. Não agenda de novo quando a troca
# de foco ou o card novo já agendaram depois que a mensagem chegou, ou depois que o WhatsApp Híbrido trouxe o texto real
# dela (#1638).
#
# A atividade avança junto com a avaliação de propósito: o StaleCardsJob só reavalia card cuja última avaliação é anterior
# à última atividade, então a mensagem avaliada não volta a ser avaliada por estar parada.
#
# MENSAGEM DA EQUIPE (#1923, flag da conta `crm_ia_avalia_mensagem_equipe`, além da de cima; sem ela, aqui só a
# mensagem do cliente agenda, como antes; a caixa com card ao chegar segue pelo CardSyncer#sync_card, que não muda):
# a pessoa da equipe que escreve ao cliente também relê o card em foco: a cotação enviada
# depois da última mensagem do cliente deixava o card parado até ele voltar. Conta a pessoa que escreve pelo painel e o
# eco (`external_echo`, sem remetente) do que foi enviado fora da plataforma, em todo canal que grava eco: o app do
# celular no WhatsApp, e também a página no Facebook/Instagram e o TikTok. Nesses, o eco pode ser de uma ferramenta de
# terceiros ou da resposta automática do próprio app (ausência, saudação), e conta como da equipe: o mesmo papel que o
# ContextBuilder já dá ao eco (`human_agent`).
# Sem decisão de assunto (ela é só da mensagem do cliente): o card é o que está em foco. Não conta: robô, nota privada,
# mensagem de sistema, envio automático em nome de alguém (regra de automação, follow-up, Agendamento, campanha) e envio
# que falhou (Autonomia::Agents::Operate::PessoaDaEquipe, a mesma régua da IA que responde). A falha costuma chegar
# depois (message_updated), com a avaliação já agendada: o ContextBuilder tira o envio falho do que o modelo lê.
# A espera é maior que a do cliente (ESPERA_DA_EQUIPE) e não é adiada pela mensagem seguinte: a equipe manda a cotação em
# várias mensagens, e o cliente que responde nesse meio-tempo agenda a avaliação dele, que lê as duas e deixa esta velha
# (conversa ao vivo não paga avaliação a mais). Com uma avaliação já esperando a vez (a do cliente ou a da equipe), a
# mensagem não agenda outra: aquela vai lê-la. A decisão é tomada sob a trava do card (Crm::Ai::Observer). A avaliação
# leva o gatilho `mensagem_da_equipe` (sugestão e log). O respeito à etapa escolhida por uma pessoa (#1918) vale como em
# todo gatilho automático (Crm::Ai::Evaluator#pessoa_mexeu_na_etapa?).
# Só a mensagem do cliente e a da equipe avançam last_message_at aqui; a do robô e a automática, não (no caminho do
# CardSyncer com card na chegada, LastRealMessageAt conta toda mensagem `chat`). Diferença conhecida e aceita.
#
# FALA DO NOSSO ROBÔ (IA entende a conversa F1, flag `crm_ia_fatos_da_conversa`, além da `crm_avaliar_toda_mensagem`):
# a fala pública do nosso agente de IA (opções enviadas, "vou passar para uma pessoa") também relê o card em foco, com a
# espera da equipe e até Crm::Ai::FatosDaConversa::MAX_AVALIACOES_DO_ROBO_POR_DIA por card (Crm::Ai::Observer). Fica de
# fora o que Crm::Ai::FatosDaConversa.fala_do_nosso_robo? não aceita (follow-up, Agendamento, robô de fora, envio que
# falhou, agente protegido). Não conta como atividade do card: o StaleCardsJob não reavalia por causa dela.
class Crm::Conversations::CardEmFoco
  FLAG = 'crm_avaliar_toda_mensagem'.freeze
  FLAG_DA_EQUIPE = 'crm_ia_avalia_mensagem_equipe'.freeze
  # Teto de uma avaliação por este tempo enquanto só a equipe escreve.
  ESPERA_DA_EQUIPE = 2.minutes

  def self.ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @account = conversation.account
  end

  def perform
    autor = autor_que_conta
    return if autor.nil?

    card = Crm::Assunto.funil_atual(@conversation)
    return if card.nil?
    return card.tap { Crm::Ai::Observer.new(card: card).schedule_evaluation_do_robo(ESPERA_DA_EQUIPE) } if autor == :robo

    agendar_avaliacao(card)
    Crm::Cards::Broadcaster.broadcast(card.reload, Events::Types::CRM_CARD_UPDATED) if registrar_atividade(card)
    card
  end

  private

  # Quem escreveu, entre os que relêem o card: :cliente, :equipe, :robo (o nosso agente de IA, F1) ou nil.
  def autor_que_conta
    return :cliente if mensagem_do_cliente?
    return :equipe if mensagem_da_equipe?

    :robo if fala_do_nosso_robo?
  end

  def mensagem_do_cliente?
    @message&.incoming? && avaliar_toda_mensagem?
  end

  def mensagem_da_equipe?
    return false if @message.blank? || @message.failed? || !@account.feature_enabled?(FLAG_DA_EQUIPE)

    equipe = Autonomia::Agents::Operate::PessoaDaEquipe
    (equipe.da_pessoa?(@message) || equipe.eco_do_celular?(@message)) && avaliar_toda_mensagem?
  end

  def fala_do_nosso_robo?
    return false if @message.blank? || !Crm::Ai::FatosDaConversa.ligada?(@account)

    Crm::Ai::FatosDaConversa.fala_do_nosso_robo?(@message) && avaliar_toda_mensagem?
  end

  def avaliar_toda_mensagem?
    self.class.ligada?(@account) && Crm::Ai::Config.enabled? && crm_da_caixa?
  end

  # A decisão (já há avaliação que serve?) e o agendamento acontecem sob a trava do card, no Observer: o job da mensagem
  # do cliente e o da equipe que rodam juntos não agendam os dois, nem a da equipe atrasa a do cliente.
  def agendar_avaliacao(card)
    observer = Crm::Ai::Observer.new(card: card)
    return observer.schedule_evaluation_do_cliente(chegada) if @message.incoming?

    observer.schedule_evaluation_da_equipe(ESPERA_DA_EQUIPE)
  end

  # O mesmo critério do CardSyncer: caixa sem configuração do CRM conta como ligada.
  def crm_da_caixa?
    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    setting.nil? || setting.crm_enabled?
  end

  # Quando o texto da mensagem ficou disponível: a chegada, ou a recuperação pelo Híbrido (#1638), se veio depois.
  def chegada
    recuperada = @message.content_attributes.to_h['hybrid_recovered_at']
    return @message.created_at if recuperada.blank?

    [@message.created_at, Time.iso8601(recuperada.to_s)].max
  rescue ArgumentError
    @message.created_at
  end

  # Uma escrita condicional, só para a frente: mover de etapa grava a atividade com a hora de agora, e a hora desta
  # mensagem não pode voltá-la, nem a de outro job que rodou junto.
  def registrar_atividade(card)
    momento = @message.created_at
    cards = Crm::Card.where(id: card.id)
    atividade = cards.where(last_activity_at: nil).or(cards.where(last_activity_at: ...momento))
                     .update_all(last_activity_at: momento, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    mensagem = cards.where(last_message_at: nil).or(cards.where(last_message_at: ...momento))
                    .update_all(last_message_at: momento) # rubocop:disable Rails/SkipsModelValidations
    (atividade + mensagem).positive?
  end
end
