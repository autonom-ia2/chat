# Memória das IAs (#1601): a última passagem da conversa com o bilhete e a tarefa de retomar aberta, para a faixa do
# bilhete (a tela vem depois do mockup). Quem vê a conversa vê o bilhete. Sem a flag, 404.
class Api::V1::Accounts::Crm::MemoriaPassagensController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_memoria

  def show
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize_crm_conversation!(conversation)
    passagem = ::Crm::Passagem.where(account_id: Current.account.id, conversation_id: conversation.id).em_ordem.first
    tarefa = ::Crm::Memoria::Compromissos.abertas(conversation).first
    render json: { passagem: passagem && passagem_payload(passagem), tarefa: tarefa && tarefa_payload(tarefa) }
  end

  private

  def ensure_memoria
    render json: { error: 'crm.memoria.disabled' }, status: :not_found unless ::Crm::Memoria.ligada?(Current.account)
  end

  def passagem_payload(passagem)
    {
      id: passagem.id, em: passagem.em, motivo: passagem.motivo, de_nome: passagem.de_nome, de_tipo: passagem.de&.tipo,
      para_nome: passagem.para_nome, para_tipo: passagem.para&.tipo, bilhete: passagem.bilhete,
      bilhete_status: passagem.bilhete_status, bilhete_gerado_em: passagem.bilhete_gerado_em
    }
  end

  def tarefa_payload(tarefa)
    memoria = tarefa.metadata.to_h['memoria'].to_h
    { id: tarefa.id, desde: tarefa.created_at, status: tarefa.status, recipient_user_ids: tarefa.recipient_user_ids,
      sem_dono_agora: memoria['sem_dono_agora'] == true, confirmar: memoria['confirmar'] == true, origem: memoria['origem'] }
  end
end
