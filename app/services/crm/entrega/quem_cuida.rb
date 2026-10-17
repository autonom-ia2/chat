# Quem pode receber a conversa (#1454): "Quem cuida do quê" (Caixas no CRM) vira a fila do motor de entrega.
#
# Da caixa da conversa viva:
#   1. os membros que pertencem à conta, menos o usuário de integração (o n8n e o MCP nunca atendem);
#   2. menos quem o acesso por funil esconde (Crm::Access::Recipients, a mesma regra da lista e do link);
#   3. só quem cuida do assunto: com card, quem tem o funil do card; sem card, quem faz a triagem. Pessoa sem linha de
#      acesso cuida de tudo (é o que a tela grava para "Todos cuidam de tudo"), e "Só as que atende" não recebe nada;
#   4. mais os administradores da caixa, por padrão (decisão do Rodrigo em 13/10: em contas como a 16 todos da caixa
#      são administradores).
# O agente de IA em "Quem recebe" fica para depois (#1447).
#
# Leitura para as telas (#1140): `QuemCuida.na_caixa` diz quem receberia uma conversa nova da caixa, com card num funil
# (ou sem card), pela mesma regra. Conversa nova não tem atendente, participante nem dono de card: para ela o filtro do
# passo 2 é a própria regra do passo 3, e fica de fora. `acessos:` troca as linhas gravadas pelas que a tela ainda vai
# gravar (Crm::Caixas::Gravador#acessos_previstos). A lista sai na ordem da tela (Crm::OrdemDeNome): a ordem dos membros
# da caixa no banco não é fixa.
class Crm::Entrega::QuemCuida
  def self.na_caixa(inbox:, pipeline_id: nil, acessos: nil)
    conversa = Conversation.new(account_id: inbox.account_id, inbox: inbox)
    card = pipeline_id && Crm::Card.new(account_id: inbox.account_id, pipeline_id: pipeline_id)
    new(conversation: conversa, card: card, acessos: acessos).cuidam.sort_by { |user| Crm::OrdemDeNome.chave(user.available_name, user.id) }
  end

  def initialize(conversation:, card: nil, acessos: nil)
    @conversation = conversation
    @card = card
    @acessos = acessos
  end

  def pessoas
    lista = cuidam
    lista.empty? ? lista : Crm::Access::Recipients.new(@conversation).filter(lista)
  end

  # Passos 1, 3 e 4, sem o filtro do passo 2.
  def cuidam
    membros = membros_que_atendem
    return [] if membros.empty?

    acessos = acessos_por_pessoa
    membros.select { |user| @administradores.include?(user.id) || cuida?(acessos[user.id]) }
  end

  private

  def membros_que_atendem
    membros = @conversation.inbox.members.to_a
    papeis = papeis_na_conta(membros.map(&:id))
    @administradores = papeis.select { |_id, role, _integration| role == 'administrator' }.map(&:first)
    atendentes = papeis.reject { |_id, _role, integration| integration }.map(&:first)
    membros.select { |user| atendentes.include?(user.id) }
  end

  # [user_id, papel, integração] de quem é da conta: membro de caixa que saiu da conta não entra.
  def papeis_na_conta(user_ids)
    return [] if user_ids.empty?

    AccountUser.where(account_id: @conversation.account_id, user_id: user_ids).pluck(:user_id, :role, :integration)
  end

  def acessos_por_pessoa
    return @acessos if @acessos
    return {} unless Crm::Access::AccountFlag.any?(@conversation.account_id)

    Crm::InboxAgentAccess.where(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id)
                         .includes(:agent_pipelines).select(&:restricts?).index_by(&:user_id)
  end

  def cuida?(acesso)
    return true if acesso.nil?
    return false if acesso.only_own?
    return acesso.triage? if @card.nil?

    acesso.all_pipelines? || acesso.agent_pipelines.map(&:pipeline_id).include?(@card.pipeline_id)
  end
end
