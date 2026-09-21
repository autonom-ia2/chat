# QUEM está pedindo, num turno do Guia (issue #568).
#
# A ferramenta nativa recebe o AGENTE na construção, e o agente é da conta — não
# da pessoa. O Guia precisa da pessoa: a leitura e a ação saem com a permissão de
# quem está logado, e é isso que faz valer o critério do Rodrigo — o que ela vê
# na tela, a IA vê; o que ela não vê, a IA não vê.
#
# Desce POR CHAMADA, como o `Tools::Delivery` do atendimento, e pelo mesmo
# motivo: `Tools::Bound.for_agent` memoiza catálogo, então pendurar contexto na
# construção da ferramenta vazaria a pessoa de um turno para o turno seguinte.
#
# Também é aqui que a PROPOSTA de ação fica guardada. A ferramenta não executa
# nada: ela descreve, deixa a proposta neste objeto, e quem monta a resposta lê
# daqui para a tela mostrar o Confirmar. Nada toca o banco antes do clique.
class Autonomia::Guide::Contexto
  attr_reader :account, :user, :account_user, :proposta

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  def consulta
    @consulta ||= ::Autonomia::Guide::Consulta.new(account: @account, user: @user, account_user: @account_user)
  end

  def acoes
    @acoes ||= ::Autonomia::Guide::Acoes.new(account: @account, user: @user, account_user: @account_user)
  end

  # UMA proposta por turno. O modelo pode chamar a ferramenta mais de uma vez
  # enquanto pensa; a tela tem um par de botões só, e dois pedidos empilhados
  # fariam a pessoa confirmar um e achar que confirmou o outro. Fica a última,
  # que é a que a resposta dele descreve.
  def propor(nome:, dados:, descricao:)
    @proposta = { nome: nome, dados: dados, descricao: descricao }
  end
end
