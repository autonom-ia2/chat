# Por cima do ConversationFinder do Chatwoot (Números F2, #1883): os botões do Números abrem a caixa já filtrada.
# - `da_ia=1`: só as conversas que um agente de IA passou para uma pessoa da equipe (Crm::Passagem.da_ia_para_equipe).
# - `esperando_min=N` (1 a 1440): só as que esperam alguém há mais de N minutos (waiting_since). Outro valor é ignorado.
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
  end

  def filtrar_recebidas_da_ia
    passagens = Crm::Passagem.da_ia_para_equipe.where(account_id: current_account.id)
                             .where(Crm::Passagem.arel_table[:conversation_id].eq(Conversation.arel_table[:id]))
    @conversations = @conversations.where(passagens.arel.exists)
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
