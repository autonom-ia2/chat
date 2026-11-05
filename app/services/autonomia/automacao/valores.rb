# Os valores que uma receita lê do alvo (#2414 F3, ADR-001 2.3): `{"$valor": "conversa.status"}`.
#
# A lista de caminhos é fechada: a receita só lê o que está aqui, e o salvar recusa caminho desconhecido. Não é Liquid
# nem texto livre; cada caminho é um campo do modelo. Os atributos personalizados entram pela chave
# (`contato.atributos.placa`). A mensagem do gatilho `mensagem.criada` só existe no filtro do gatilho
# (`mensagem.tipo`: recebida, enviada ou nota; `mensagem.privada`; `mensagem.primeira`); nos passos ela já passou, e o
# salvar recusa ler a mensagem fora dali.
#
# #2499 (F6): cada caminho começa pela base (`conversa`, `contato` ou `card`), lida do alvo pelas pontes do Contexto.
# A base que o alvo não alcança (card num gatilho de conversa) o salvar recusa; a ponte vazia ao rodar (card sem
# conversa) chega como valor vazio.
class Autonomia::Automacao::Valores
  # `conversa.id` é o número que a pessoa vê (#123) e o que as rotas da conversa recebem, não o id do banco.
  CAMPOS = {
    'conversa.id' => ->(conversa) { conversa.display_id },
    'conversa.status' => ->(conversa) { conversa.status },
    'conversa.prioridade' => ->(conversa) { conversa.priority },
    'conversa.caixa_id' => ->(conversa) { conversa.inbox_id },
    'conversa.responsavel_id' => ->(conversa) { conversa.assignee_id },
    'conversa.time_id' => ->(conversa) { conversa.team_id },
    'conversa.etiquetas' => ->(conversa) { conversa.label_list },
    # "cliente" ou "equipe", pela primeira mensagem de verdade (#2527); vazio enquanto a conversa não tem mensagem.
    'conversa.iniciada_por' => ->(conversa) { ::Autonomia::Automacao::PrimeiraMensagem.iniciada_por(conversa) },
    'contato.id' => ->(contato) { contato.id },
    'contato.nome' => ->(contato) { contato.name },
    'contato.email' => ->(contato) { contato.email },
    'contato.telefone' => ->(contato) { contato.phone_number },
    'contato.empresa_id' => ->(contato) { contato.company_id },
    'contato.etiquetas' => ->(contato) { contato.label_list },
    # `card.id` é o id do banco: é o que as rotas do card recebem e o que a tela mostra (#123).
    'card.id' => ->(card) { card.id },
    'card.titulo' => ->(card) { card.title },
    'card.etapa_id' => ->(card) { card.stage_id },
    'card.funil_id' => ->(card) { card.pipeline_id },
    'card.status' => ->(card) { card.status },
    'card.valor' => ->(card) { card.value_cents.to_d / 100 },
    'card.responsavel_id' => ->(card) { card.owner_id },
    'card.time_id' => ->(card) { card.team_id },
    'card.dias_na_etapa' => ->(card) { card.entered_stage_at && ((Time.current - card.entered_stage_at) / 1.day).floor },
    'card.motivo_da_perda' => ->(card) { card.lost_reason }
  }.freeze

  # O que cada alvo alcança, pelas pontes do Contexto.
  BASES_DO_ALVO = {
    'Conversation' => %w[conversa contato],
    'Crm::Card' => %w[card conversa contato],
    'Contact' => %w[contato]
  }.freeze

  # A mensagem que disparou o gatilho, para o filtro separar a do cliente da resposta da equipe e da nota.
  MENSAGEM = {
    'mensagem.tipo' => lambda do |mensagem|
      next 'nota' if mensagem.private?

      mensagem.incoming? ? 'recebida' : 'enviada'
    end,
    'mensagem.privada' => ->(mensagem) { mensagem.private? },
    # A mensagem é a primeira de verdade da conversa (#2527)? A nota e a atividade nunca são.
    'mensagem.primeira' => ->(mensagem) { ::Autonomia::Automacao::PrimeiraMensagem.primeira?(mensagem) }
  }.freeze

  # O gatilho cuja mensagem o filtro lê.
  GATILHO_DA_MENSAGEM = 'mensagem.criada'.freeze

  # Valores fechados (#2496): fora destas opções e destes operadores a condição nunca casa, e a automação falharia em
  # silêncio. O salvar recusa o resto; o editor mostra só isto.
  FECHADOS = {
    'mensagem.tipo' => { 'opcoes' => %w[recebida enviada nota], 'operadores' => %w[igual diferente] },
    'mensagem.privada' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'mensagem.primeira' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] },
    'conversa.iniciada_por' => { 'opcoes' => %w[cliente equipe], 'operadores' => %w[igual diferente] }
  }.freeze

  ATRIBUTOS = {
    'conversa.atributos' => ->(conversa) { conversa.custom_attributes },
    'contato.atributos' => ->(contato) { contato.custom_attributes },
    'card.atributos' => ->(card) { card.custom_attributes }
  }.freeze

  # Os valores que pedem permissão para ler (#2597): a pergunta é a mesma do resto do CRM, feita a quem salva a receita
  # e a quem ligou a automação. O dono de um card não ganha, pela automação, o valor dos cards alheios: `ve?`, não
  # `ve_o_card?`. Sem a permissão, o salvar recusa e a execução lê vazio.
  PROTEGIDOS = {
    'card.valor' => ->(account_user) { ::Crm::ValorDeVenda.ve?(account_user) }
  }.freeze

  # O modelo do atributo personalizado de cada base, para conferir ao salvar que a chave existe na conta.
  MODELOS = {
    'conversa.atributos' => 'conversation_attribute',
    'contato.atributos' => 'contact_attribute',
    'card.atributos' => 'card_attribute'
  }.freeze

  class << self
    def caminho_valido?(caminho)
      CAMPOS.key?(caminho.to_s) || MENSAGEM.key?(caminho.to_s) || atributo(caminho).present?
    end

    def da_mensagem?(caminho) = MENSAGEM.key?(caminho.to_s)

    # O alvo (`Conversation`, `Crm::Card`, `Contact`) chega à base do caminho? A mensagem fica com a regra própria dela.
    def no_alvo?(caminho, alvo_type)
      da_mensagem?(caminho) || BASES_DO_ALVO.fetch(alvo_type, []).include?(caminho.to_s.split('.', 2).first)
    end

    def fechado(caminho) = FECHADOS[caminho.to_s]

    # `account_user` pode ler o caminho? Sem pessoa (nil), o valor protegido fica fechado.
    def pode_ler?(caminho, account_user)
      regra = PROTEGIDOS[caminho.to_s]
      regra.nil? || regra.call(account_user)
    end

    # O atributo da conta que o caminho lê existe? Caminho que não é atributo responde true.
    def atributo_definido?(caminho, conta)
      base, chave = atributo(caminho)
      base.nil? || conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave)
    end

    # "contato.atributos.placa" => ["contato.atributos", "placa"]. A chave do atributo pode ter ponto.
    def atributo(caminho)
      base = ATRIBUTOS.keys.find { |prefixo| caminho.to_s.start_with?("#{prefixo}.") }
      chave = base && caminho.to_s.delete_prefix("#{base}.")
      [base, chave] if chave.present?
    end
  end

  # `alvo`: a conversa, o card ou o contato da execução (ou um Contexto já montado). `quem`: a pessoa com cujas
  # permissões a receita lê (quem ligou a automação; no ensaio, quem pede). Sem ela, o valor protegido lê vazio.
  def initialize(alvo:, mensagem: nil, quem: nil)
    @contexto = alvo.is_a?(::Autonomia::Automacao::Contexto) ? alvo : ::Autonomia::Automacao::Contexto.de(alvo)
    @mensagem = mensagem
    @quem = quem
  end

  def ler(caminho)
    return unless permitido?(caminho)
    return @mensagem && MENSAGEM.fetch(caminho.to_s).call(@mensagem) if MENSAGEM.key?(caminho.to_s)
    return do_objeto(caminho) { |objeto| CAMPOS.fetch(caminho.to_s).call(objeto) } if CAMPOS.key?(caminho.to_s)

    base, chave = self.class.atributo(caminho)
    raise ArgumentError, "caminho desconhecido: #{caminho}" unless base

    do_objeto(caminho) { |objeto| ATRIBUTOS.fetch(base).call(objeto).to_h[chave] }
  end

  private

  # A pessoa só é buscada quando o caminho pede permissão.
  def permitido?(caminho) = !PROTEGIDOS.key?(caminho.to_s) || self.class.pode_ler?(caminho, account_user)

  def account_user
    return @account_user if defined?(@account_user)

    @account_user = @quem && @contexto.alvo.account.account_users.find_by(user_id: @quem.id)
  end

  def do_objeto(caminho)
    objeto = da_base(caminho)
    objeto && yield(objeto)
  end

  # A ponte vazia (card sem conversa, conversa sem contato) lê vazio.
  def da_base(caminho)
    case caminho.to_s.split('.', 2).first
    when 'conversa' then @contexto.conversa
    when 'contato' then @contexto.contato
    when 'card' then @contexto.card
    end
  end
end
