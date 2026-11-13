# O selo de seguro de cada pessoa de uma página da lista de pessoas (E4, #2897): quantos seguros ela tem e, do que mais
# pede atenção, o selo, o tipo e os dias que faltam. "Mais pede atenção" é a ordem do bloco Seguros da ficha
# (Carteira::Selo.por_urgencia): o vencido, depois o ativo que termina antes, o cancelado por último.
#
# Recebe só os ids da página que a tela mostrou e faz uma consulta para todos eles. Pessoa sem seguro não vem na
# resposta, e id de outra conta não acha nada: a leitura é sempre dentro da conta de quem pede.
class Carteira::ResumoPorPessoa
  # Uma página da lista tem 25 pessoas. O teto existe para o pedido (e a consulta) não crescer sem limite.
  LIMITE = 100
  # O maior id que cabe na coluna (bigint): além disso o pedido não é de ninguém.
  MAIOR_ID = (2**63) - 1
  DA_APOLICE = %i[id contact_id tipo fim_vigencia cancelado_em].freeze

  def initialize(account, pessoa_ids)
    @account = account
    @pessoa_ids = conferidos(pessoa_ids)
  end

  # { id da pessoa => { quantos, selo, tipo, dias } }
  def call
    hoje = Carteira::Selo.hoje(@account)
    Carteira::Apolice.where(account_id: @account.id, contact_id: @pessoa_ids).select(*DA_APOLICE).group_by(&:contact_id)
                     .transform_values { |apolices| da_pessoa(apolices, hoje) }
  end

  private

  def da_pessoa(apolices, hoje)
    urgente = Carteira::Selo.por_urgencia(apolices, hoje: hoje).first
    { quantos: apolices.size, selo: Carteira::Selo.de(urgente, hoje: hoje), tipo: urgente.tipo,
      dias: Carteira::Selo.dias(urgente, hoje: hoje) }
  end

  # A mensagem não repete o que foi mandado: o controller da carteira responde só `pedido_invalido`.
  def conferidos(recebidos)
    recusar('pessoa_ids em formato inválido') unless recebidos.is_a?(Array) && recebidos.size.between?(1, LIMITE)
    recebidos.map { |recebido| id_de(recebido) || recusar('pessoa_ids com id inválido') }
  end

  def id_de(recebido)
    id = Integer(recebido.to_s, 10, exception: false)
    id if id&.between?(1, MAIOR_ID)
  end

  def recusar(mensagem)
    raise Relacionamentos::PedidoInvalido, mensagem
  end
end
