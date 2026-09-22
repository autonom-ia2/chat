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
  attr_reader :account, :user, :account_user, :proposta, :tela

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

  # UMA tela por turno, pelo mesmo motivo: a resposta tem um botão só. Fica a
  # última que o modelo escolheu (#590).
  def mostrar(destino)
    @tela = destino
  end

  # O que as leituras deste turno devolveram. O botão de UM registro só leva a
  # um id que veio daqui: na bateria real de 22/09/2026, "abre a conversa 999"
  # ganhou botão para uma conversa que não existe, com o número que a pessoa
  # digitou (#590).
  def lido(texto)
    (@leituras ||= []) << texto.to_s
  end

  # O id como a leitura o escreve: `"id":12,` ou `"id":"12"}`. O que vem depois
  # do número faz parte da conferência, senão o 5 casaria com o 55.
  FIM_DO_VALOR = [',', '}'].freeze

  def leu?(valor)
    marcas = FIM_DO_VALOR.flat_map { |fim| ["\"id\":#{valor}#{fim}", "\"id\":\"#{valor}\"#{fim}"] }
    Array(@leituras).any? { |texto| marcas.any? { |marca| texto.include?(marca) } }
  end

  # Os ids de `parametros` que nenhuma leitura deste turno trouxe. Vale para o
  # botão de tela (#590) e para a proposta de ação (#593): apagar "a caixa do
  # Instagram" precisa do id que a leitura achou, nunca de um número chutado.
  # `:inboxId`, `:conversation_id`, `:id` apontam registro; `:tab` e `:label`
  # não. É o nome que o roteador dá ao parâmetro, não texto de gente.
  def nao_lidos(parametros)
    parametros.to_h.select do |nome, valor|
      nome = nome.to_s
      (nome == 'id' || nome.end_with?('Id') || nome.end_with?('_id')) && !leu?(valor)
    end
  end

  # O Guia leu dados da conta neste turno. É o que ancora "não encontrei o
  # contato Pedro": não é falta de conhecimento, é o que a conta tem (#593).
  def leu_a_conta?
    Array(@leituras).any?
  end
end
