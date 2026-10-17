# Configuração da memória das IAs por conta (#1601), declarada pelo administrador:
# - usuarios_robo_ids: logins de pessoa que um robô de fora usa para responder (o "Ana Maciel" do garimpo). O que eles
#   mandam é `robo_externo`, nunca pessoa: não cumpre a tarefa de retomar e não prova fato como equipe.
# - caixas_excluidas: caixas cujas mensagens não geram memória nem tarefa (chats internos, parceiros B2B).
class Crm::MemoriaConfig < ApplicationRecord
  self.table_name = 'crm_memoria_configs'

  belongs_to :account

  validate :usuarios_da_conta
  validate :caixas_da_conta

  def robo?(user_id)
    user_id.present? && usuarios_robo_ids.include?(user_id.to_i)
  end

  def caixa_excluida?(inbox_id)
    inbox_id.present? && caixas_excluidas.include?(inbox_id.to_i)
  end

  private

  def usuarios_da_conta
    ids = Array(usuarios_robo_ids).uniq
    return if ids.empty? || AccountUser.where(account_id: account_id, user_id: ids).distinct.count(:user_id) == ids.size

    errors.add(:usuarios_robo_ids, 'must belong to the same account')
  end

  def caixas_da_conta
    ids = Array(caixas_excluidas).uniq
    return if ids.empty? || Inbox.where(account_id: account_id, id: ids).count == ids.size

    errors.add(:caixas_excluidas, 'must belong to the same account')
  end
end
