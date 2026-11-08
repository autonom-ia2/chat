# Por cima do ConversationFinder do Chatwoot (Números F2, #1883): os botões do Números abrem a caixa já filtrada.
# - `da_ia=1`: só as conversas que um agente de IA passou para uma pessoa da equipe (Crm::Passagem.da_ia_para_equipe).
# - `esperando_min=N` (1 a 1440): só as que esperam alguém há mais de N minutos (waiting_since). Outro valor é ignorado.
# - `no_funil=1` (Números F5, #1992): só as de cliente com card num funil que a pessoa vê no Números
#   (Crm::Access::VisiblePipelines#apply_to_reports), pelo card principal ou pelo vínculo (crm_card_conversations). É o
#   escopo da visão "Equipe": a conversa de um funil que o gestor não vê, em que ele só participa, não entra.
# Entram no `set_up`, depois do filtro de sempre e da visibilidade: as contagens das abas seguem a mesma regra, e o link
# não mostra nada que a pessoa já não veria. No Spam e na Lixeira do e-mail, a pasta manda e estes filtros não valem.
# Sem os parâmetros, nada muda: só quem abre o link vê a lista filtrada (por isso sem chave de recurso).
module Crm::ConversationFinderComFiltrosDoLink
  ESPERANDO_MIN = 1..1440

  private

  def set_up
    super
    return if pasta_do_email_manda?

    filtrar_recebidas_da_ia if params[:da_ia] == '1'
    filtrar_esperando if minutos_esperando
    filtrar_no_funil if params[:no_funil] == '1'
  end

  # A passagem gravada, ou a marca de espera de pessoa: o robô passou e ninguém estava online, então a Entrega não
  # gravou passagem ainda (ConversationBotHandoff, #1377). A marca sai quando uma pessoa entra ou a conversa é resolvida.
  def filtrar_recebidas_da_ia
    passagens = Crm::Passagem.da_ia_para_equipe.where(account_id: current_account.id)
                             .where(Crm::Passagem.arel_table[:conversation_id].eq(Conversation.arel_table[:id]))
    @conversations = @conversations.where(passagens.arel.exists.or(Arel.sql(marca_de_espera_de_pessoa_sql)))
  end

  # additional_attributes às vezes chega gravado como JSON dentro de string; nesse formato, `->>` dá NULL e a chave só
  # aparece no texto. No formato de objeto vale a mesma regra do AWAITING_PERSON_SQL (chave com valor).
  def marca_de_espera_de_pessoa_sql
    chave = Conversation::BOT_HANDOFF_WAITING_SINCE_KEY
    Conversation.sanitize_sql_array([
                                      '(conversations.additional_attributes ->> :chave IS NOT NULL OR ' \
                                      "(jsonb_typeof(conversations.additional_attributes) = 'string' AND " \
                                      'conversations.additional_attributes::text LIKE :no_texto))',
                                      { chave: chave, no_texto: "%#{chave}%" }
                                    ])
  end

  def filtrar_no_funil
    funis = Crm::Access::VisiblePipelines.new(user: current_user, account: current_account)
                                         .apply_to_reports(current_account.crm_pipelines).select(:id)
    cards = Crm::Card.where(account_id: current_account.id, pipeline_id: funis)
    principais = cards.where.not(conversation_id: nil).select(:conversation_id)
    vinculadas = Crm::CardConversation.where(account_id: current_account.id, card_id: cards.select(:id)).select(:conversation_id)
    @conversations = @conversations.where(id: Conversation.where(id: principais).or(Conversation.where(id: vinculadas)).select(:id))
  end

  def filtrar_esperando
    @conversations = @conversations.where(waiting_since: ..minutos_esperando.minutes.ago)
  end

  # Só dígitos (o Integer aceitaria " 30", "+30" e "1_0"), a mesma regra do painel.
  def minutos_esperando
    valor = params[:esperando_min].to_s
    return if valor.empty? || valor.count('0-9') != valor.length

    minutos = valor.to_i
    minutos if ESPERANDO_MIN.cover?(minutos)
  end

  # O ConversaCanal::ConversationFinderComPastas também está por cima do finder (config/initializers/conversa_canal_email.rb).
  def pasta_do_email_manda?
    pastas_do_email_ligadas? && pasta_pedida.present?
  end
end
