# CRIA O AGENTE DE COTAÇÃO PRONTO — o botão "Criar Agente de Cotação" (PRD §18-19).
#
# POR QUE ISTO EXISTE. O agente de cotação não é um agente comum com uma ferramenta ligada: ele tem
# uma instrução que a Autonom.ia mantém e a corretora não edita, um especialista por ramo, e a
# ferramenta de cotação obrigatória. Montar isso pelo construtor conversacional daria um agente
# diferente a cada vez — e a instrução, que é o produto, ficaria por conta de quem clicou.
#
# O QUE A CORRETORA DECIDE, e é só isto: o nome do agente, o nome dela, o horário de atendimento e o
# comportamento. Tudo o mais vem daqui. O que ela quiser acrescentar entra em `custom_instruction`
# do especialista, que o `effective_instruction` junta DEPOIS do texto duro — complementa, nunca
# sobrescreve.
class Autonomia::Insurance::QuoteAgent::Builder
  INSTRUCOES = Rails.root.join('app/services/autonomia/insurance/quote_agent/instrucoes').freeze
  # O comportamento que a corretora escolhe. Não é formal/informal: a instrução já trava o tom. É
  # QUANDO o agente usa o que sabe — explica antes de cotar, ou cota e explica se perguntarem.
  COMPORTAMENTOS = %w[consultivo objetivo].freeze
  COMPORTAMENTO_PADRAO = 'consultivo'.freeze
  HORARIO_PADRAO = 'de segunda a sexta, das 09h às 18h'.freeze
  # A ferramenta de cotação é do ESPECIALISTA, e some da visão do principal (Answerer#enabled_agent_
  # _tools). O principal fica com as duas que valem para toda conversa.
  TOOLS_DO_PRINCIPAL = %w[consultar_produtos_disponiveis consultar_condicoes_gerais].freeze
  TOOLS_DO_ESPECIALISTA = %w[cotar_seguro].freeze

  # O primeiro (e por enquanto único) especialista. Cada ramo novo entra aqui com o seu arquivo de
  # instrução — e nada mais precisa mudar.
  ESPECIALISTAS = [
    { slug: 'cotacao_auto', nome: 'Cotação de automóvel', arquivo: 'especialista_auto.md',
      descricao: 'Cota seguro de automóvel, moto e caminhão para pessoa física. Use quando o ' \
                 'cliente pedir preço de seguro de carro, moto ou caminhão.' }
  ].freeze

  # Teto do que a corretora escreve. `nome_agente` já é limitado pela coluna (string, 255), mas
  # `nome_corretora` NÃO VAI PARA COLUNA NENHUMA — ele só é colado dentro da instrução. Sem teto
  # aqui, um valor grande o bastante estoura o limite de 50.000 do `instruction` e a criação falha
  # com erro de validação que não explica nada a quem clicou.
  MAX_NOME = 120

  class ComportamentoInvalido < StandardError; end
  class NomeInvalido < StandardError; end
  class JaExiste < StandardError; end

  def initialize(account:, nome_agente:, nome_corretora:, horario: nil, comportamento: nil)
    @account = account
    @nome_agente = nome_agente.to_s.strip
    @nome_corretora = nome_corretora.to_s.strip
    @horario = horario.presence || HORARIO_PADRAO
    @comportamento = (comportamento.presence || COMPORTAMENTO_PADRAO).to_s
  end

  # -> Agent criado, com o especialista e as ferramentas já ligados. Tudo ou nada: um especialista
  # que falha não pode deixar um agente meio-pronto no banco, que responderia sem saber cotar.
  def call
    raise ComportamentoInvalido, @comportamento unless COMPORTAMENTOS.include?(@comportamento)

    validar_nomes!
    # UM AGENTE DE COTAÇÃO POR CONTA. Dois seriam ligados às mesmas caixas de entrada e disputariam
    # a mesma conversa, cada um com o seu especialista e a sua sessão AGGER — e o corretor não teria
    # como saber qual respondeu. Quem quer trocar o nome ou o comportamento edita o que existe.
    raise JaExiste, existente.id.to_s if existente

    ::Autonomia::Agents::Agent.transaction do
      agente = criar_agente
      ESPECIALISTAS.each { |dados| criar_especialista(agente, dados) }
      agente
    end
  end

  private

  # O agente de cotação desta conta, se já houver.
  def existente
    ::Autonomia::Agents::Agent.find_by(account: @account, agent_type: 'insurance_quote')
  end

  def validar_nomes!
    { 'nome do agente' => @nome_agente, 'nome da corretora' => @nome_corretora }.each do |campo, valor|
      raise NomeInvalido, "#{campo} vazio" if valor.blank?
      raise NomeInvalido, "#{campo} acima de #{MAX_NOME} caracteres" if valor.length > MAX_NOME
    end
  end

  def criar_agente
    ::Autonomia::Agents::Agent.create!(
      account: @account, name: @nome_agente, agent_type: 'insurance_quote',
      status: :active, enabled: true, instruction: texto('principal.md'),
      config: { 'native_tool_slugs' => TOOLS_DO_PRINCIPAL, 'with_knowledge' => true }
    )
  end

  def criar_especialista(agente, dados)
    ::Autonomia::Agents::Specialist.create!(
      agent: agente, account: @account, slug: dados[:slug], name: dados[:nome],
      description: dados[:descricao], instruction: texto(dados[:arquivo]),
      tool_slugs: TOOLS_DO_ESPECIALISTA, enabled: true
    )
  end

  # As variáveis são substituídas AQUI, na criação, e não a cada turno: o que vai para o banco é o
  # texto final. Um agente cujo nome mudasse a cada leitura seria impossível de auditar depois.
  # O BLOCO NO `gsub` NÃO É ESTILO. Com o valor como segundo argumento, o Ruby interpreta `\\0` no
  # texto de substituição — um nome de corretora contendo essa sequência passaria a inserir o
  # próprio marcador de volta. O bloco entrega a string literal, sem interpretar nada.
  def texto(arquivo)
    VARIAVEIS.reduce(INSTRUCOES.join(arquivo).read) do |texto, (marcador, campo)|
      texto.gsub(marcador) { valores.fetch(campo) }
    end
  end

  VARIAVEIS = { '$nomeAgente' => :nome_agente, '$nomeCorretora' => :nome_corretora,
                '$horarioAtendimento' => :horario, '$comportamento' => :comportamento }.freeze

  def valores
    { nome_agente: @nome_agente, nome_corretora: @nome_corretora,
      horario: @horario, comportamento: @comportamento }
  end
end
