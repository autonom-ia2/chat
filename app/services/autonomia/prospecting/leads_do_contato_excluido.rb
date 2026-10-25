# Contato excluído (#2143, LGPD): os leads da Prospecção ligados a ele saem de vez. Sem isto, a chave estrangeira só
# soltava o lead do contato e do card, e ficavam nome, telefone, e-mail e WhatsApp achados, o decisor e as redes dele.
#
# Ligado ao contato é o lead que aponta para ele (contact_id) ou para um card dele (crm_card_id). O lead pode ter sido
# importado antes de o contato existir: a busca o achou no Google, e a conversão o ligou a um contato novo ou a um
# que já existia pelo telefone ou e-mail. Ligado, ele é a mesma pessoa, e sai junto. Lead que nunca foi ligado ao
# contato (só tem o mesmo telefone) não é tocado: é um resultado de busca, não o registro desta pessoa.
#
# A linha inteira sai, e não só as colunas com dado pessoal: o lead não entra em número de venda nem de meta (o total de
# cada busca fica gravado nela, em results_count), e uma coluna nova não escapa da limpeza por esquecimento. As
# listas perdem o lead pela cascata do banco. Enriquecimento, pesquisa e verificação de WhatsApp que estejam rodando
# já tratam o lead apagado no meio: gravam em zero linhas.
#
# Fica o lead que recusou contato (consent_refused): a recusa é a prova de que a pessoa pediu para não receber
# mensagem, e o telefone, o WhatsApp e o e-mail dele são o que veta a campanha a quem tem o mesmo número
# (Autonomia::Prospecting::ConsentVeto). Ele só perde o contato e o card, pela chave estrangeira, como na main.
#
# Roda dentro da transação de quem exclui o contato, com as linhas travadas: um lead que recusa no mesmo instante
# (Autonomia::Prospecting::ContactOptOutSync) ou é lido já recusado e fica, ou espera esta exclusão terminar.
class Autonomia::Prospecting::LeadsDoContatoExcluido
  # pluck devolve o status como o nome do enum.
  RECUSA = 'no_consent'.freeze

  attr_reader :apagados, :mantidos_por_recusa

  # Criado antes de os cards do contato saírem ou serem anonimizados, que soltam o lead deles (crm_card_id). O perform
  # roda depois, já com os cards travados: a mesma ordem de travas do resto do CRM (card, depois lead).
  def initialize(contact:)
    @contact = contact
    @pelos_cards = Autonomia::Prospecting::Lead.where(account_id: contact.account_id, crm_card_id: contact.crm_cards.select(:id)).pluck(:id)
    @apagados = []
    @mantidos_por_recusa = []
  end

  def perform
    leads = ligados.order(:id).lock.pluck(:id, :consent_refused_at, :status)
    @mantidos_por_recusa = leads.select { |_id, recusado_em, status| recusado_em.present? || status == RECUSA }.map(&:first)
    @apagados = leads.map(&:first) - @mantidos_por_recusa
    Autonomia::Prospecting::Lead.where(id: @apagados).delete_all if @apagados.any?
    self
  end

  private

  def ligados
    da_conta = Autonomia::Prospecting::Lead.where(account_id: @contact.account_id)
    da_conta.where(contact_id: @contact.id).or(da_conta.where(id: @pelos_cards))
  end
end
