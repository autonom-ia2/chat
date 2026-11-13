# O que a gaveta "Mais filtros" da aba Seguros oferece (E4, #2897): só os tipos e as seguradoras que existem na carteira
# da conta. Cada seguradora aparece uma vez, mesmo escrita de dois jeitos (a forma de comparação junta). "Quem cuida"
# são os donos dos cards de renovação que os seguros da conta mostram (E5, #2898), pelo nome; o filtro manda o id.
class Carteira::OpcoesDeFiltro
  # O nome que representa cada seguradora, entre os jeitos em que ela foi escrita: o primeiro na ordem do texto puro
  # (COLLATE "C"), que não muda com a collation do banco de cada ambiente.
  NOME = Arel.sql('seguradora COLLATE "C"')

  def initialize(account)
    @account = account
  end

  def call
    { tipos: seguros.distinct.pluck(:tipo).sort, seguradoras: seguros.group(:seguradora_chave).minimum(NOME).values.sort, cuida: cuida }
  end

  private

  def cuida
    cards = seguros.where(renovacao_card_removido_em: nil).where.not(crm_card_id: nil).select(:crm_card_id)
    donos = Crm::Card.where(account_id: @account.id, id: cards).where.not(owner_id: nil).select(:owner_id)
    User.where(id: donos).order(:name, :id).map { |pessoa| { id: pessoa.id, nome: pessoa.name } }
  end

  def seguros
    Carteira::Apolice.where(account_id: @account.id)
  end
end
