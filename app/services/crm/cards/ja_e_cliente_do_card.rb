# #2710: o selo "Já é cliente" de um card só, para uma ou várias pessoas (card aberto e tempo real). As compras do contato
# saem numa consulta por evento, e só quando o card leva o selo; cada pessoa filtra pelo que vê (Crm::Cards::JaECliente#entre).
class Crm::Cards::JaEClienteDoCard
  def initialize(card)
    @card = card
  end

  def para(user:, account_user:)
    return if ganho_ids.empty?

    Crm::Cards::JaECliente.new(user: user, account: @card.account, account_user: account_user).entre(@card, ganho_ids)
  end

  private

  # Todas as compras do contato na conta; quem pode ver qual delas, cada pessoa decide em `entre`.
  def ganho_ids
    @ganho_ids ||= if Crm::Cards::JaECliente.candidato?(@card)
                     Crm::Card.won.where(account_id: @card.account_id, contact_id: @card.contact_id).pluck(:id)
                   else
                     []
                   end
  end
end
