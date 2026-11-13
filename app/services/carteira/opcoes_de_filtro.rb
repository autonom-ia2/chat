# O que a gaveta "Mais filtros" da aba Seguros oferece (E4, #2897): só os tipos e as seguradoras que existem na carteira
# da conta. Cada seguradora aparece uma vez, mesmo escrita de dois jeitos (a forma de comparação junta). "Quem cuida"
# chega com a renovação (E5): vem vazio.
class Carteira::OpcoesDeFiltro
  # O nome que representa cada seguradora, entre os jeitos em que ela foi escrita: o primeiro na ordem do texto puro
  # (COLLATE "C"), que não muda com a collation do banco de cada ambiente.
  NOME = Arel.sql('seguradora COLLATE "C"')

  def initialize(account)
    @account = account
  end

  def call
    { tipos: seguros.distinct.pluck(:tipo).sort, seguradoras: seguros.group(:seguradora_chave).minimum(NOME).values.sort, cuida: [] }
  end

  private

  def seguros
    Carteira::Apolice.where(account_id: @account.id)
  end
end
