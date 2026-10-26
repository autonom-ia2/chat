# #2216 — Prepend em Api::V1::Accounts::ConversationsController (config/initializers/reabrir_ao_escrever.rb).
# Começar conversa numa caixa com "Reabrir a mesma conversa" (lock_to_single_conversation) cai na última conversa do
# contato, mesmo resolvida ou adiada (ConversationBuilder#look_up_exising_conversation). A mensagem do atendente não
# reabre (Message#reopen_conversation só olha a do cliente), e a conversa ficava fora das Abertas.
# Aqui, com mensagem, a conversa achada reabre antes de a mensagem entrar, sem mudar quem cuida (#2067: atendente
# responde, não assume): nem o atendente que escreveu, nem o rodízio da caixa.
# Só a criação da API da conta (painel, gaveta Nova conversa). O ConversationBuilder fica igual: o widget, a API pública,
# as campanhas e os avisos de agendamento também passam por ele e não reabrem. A conversa visível vai pela API de
# mensagem, com o sinal da gaveta (Conversations::ReabrirAoEscreverNaMensagem).
# Na mesma transação da criação: se a mensagem não sai, a conversa não reabre. A transação fecha dentro do `create`,
# antes da resposta, como no original: o número da conversa (display_id) só é lido depois do commit.
module Conversations::ReabrirAoEscrever
  def create
    ActiveRecord::Base.transaction do
      reabrir_conversa_achada
      super
    end
  end

  private

  # A mesma regra do ConversationBuilder#look_up_exising_conversation: com a caixa em "Reabrir a mesma conversa", a
  # última do contato (Conversation#reabrir_ao_escrever! confere a caixa e a situação).
  def reabrir_conversa_achada
    return if params[:message].blank?

    @contact_inbox.conversations.last&.reabrir_ao_escrever!
  end
end
