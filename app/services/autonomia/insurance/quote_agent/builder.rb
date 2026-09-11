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
  # `native_tool_slugs` NÃO É A LISTA DO PRINCIPAL: é o que o agente TEM. Quem esconde do principal
  # o que pertence ao especialista é o `Answerer#enabled_agent_tools`, em runtime. Deixar a de
  # cotação fora daqui não a reserva — APAGA: o catálogo do turno vem de `Tools::Bound.for_agent`,
  # e o `Specialist#tools` filtra ESSE catálogo. Fora dele o especialista roda sem ferramenta.
  TOOLS_DO_PRINCIPAL = %w[consultar_produtos_cotacao consultar_condicoes_gerais].freeze
  TOOLS_DO_ESPECIALISTA = %w[consultar_placa cotar_seguro].freeze
  TODAS_AS_TOOLS = (TOOLS_DO_PRINCIPAL + TOOLS_DO_ESPECIALISTA).freeze

  # O primeiro (e por enquanto único) especialista. Cada ramo novo entra aqui com o seu arquivo de
  # instrução — e nada mais precisa mudar.
  ESPECIALISTAS = [
    { slug: 'cotacao_auto', nome: 'Cotação de automóvel', arquivo: 'especialista_auto.md',
      descricao: 'Cota seguro de automóvel, moto e caminhão, para pessoa física e para empresa. Use ' \
                 'quando o cliente pedir preço de seguro de carro, moto ou caminhão.' }
  ].freeze

  # Teto do que a corretora escreve. `nome_agente` já é limitado pela coluna (string, 255), mas
  # `nome_corretora` NÃO VAI PARA COLUNA NENHUMA — ele só é colado dentro da instrução. Sem teto
  # aqui, um valor grande o bastante estoura o limite de 50.000 do `instruction` e a criação falha
  # com erro de validação que não explica nada a quem clicou.
  MAX_NOME = 120

  # O MANUAL QUE VALE É O DO DEPLOY, não a cópia gravada no nascimento (entrega 3, termo 5). Até
  # 11/09/2026 a instrução do especialista era copiada para a linha na criação e nunca mais lida do
  # arquivo: o agente 24 rodou três dias com um manual que o repositório já não tinha (a versão com
  # teto de três ofertas, retirada em #362, seguia em produção — medido pelo md5 da coluna).
  # Corrigir o modelo não corrigia quem já existia. Agora quem roda (`Specialist#effective_instruction`)
  # lê daqui; a coluna fica como retrato do nascimento. Só para os especialistas que a Autonom.ia
  # mantém — os do agente de cotação —: um especialista que a corretora criou com instrução própria
  # continua lendo a dele. O arquivo é lido cru: `builder_instrucao_do_especialista_spec` garante que ele
  # não tem variável para substituir.
  # -> texto do arquivo, ou nil quando não é um especialista mantido.
  def self.instrucao_mantida(specialist)
    dados = mantido(specialist)
    dados && INSTRUCOES.join(dados[:arquivo]).read
  end

  # A DESCRIÇÃO também: é o que o principal lê para decidir chamar o especialista (`openai_schema`),
  # e a gravada no nascimento dizia "para pessoa física" enquanto o manual passou a cotar empresa.
  def self.descricao_mantida(specialist)
    mantido(specialist)&.dig(:descricao)
  end

  # A entrada de `ESPECIALISTAS` deste especialista, quando é um que a Autonom.ia mantém.
  def self.mantido(specialist)
    return nil unless specialist.agent&.agent_type == 'insurance_quote'

    ESPECIALISTAS.find { |e| e[:slug] == specialist.slug }
  end

  # O PRINCIPAL TAMBÉM LÊ O ARQUIVO DO DEPLOY (#380). A instrução da Lia (`principal.md`) tinha o mesmo
  # defeito do manual do especialista: copiada para `autonomia_agents.instruction` no nascimento, com as
  # variáveis substituídas, e nunca relida — toda edição do texto só valia para agente criado depois.
  # O que o principal tem a mais são as quatro escolhas da corretora, que até aqui só existiam DENTRO
  # do texto gravado. Agora elas ficam no `config` do agente, na chave `ESCOLHAS_DA_CORRETORA`, e quem
  # monta o prompt (`Agent#instrucao_do_sistema` <- `PromptBuilder#instructions`) lê o arquivo e
  # substitui com elas a cada montagem. A coluna fica como retrato do nascimento.
  #
  # AUDITABILIDADE: o que foi ao modelo é função de duas coisas só — o arquivo no SHA deployado e as
  # escolhas guardadas. Com os dois, este método devolve o mesmo texto; nada mais entra na conta.
  #
  # -> texto do arquivo com as escolhas, ou nil quando não é o agente de cotação ou quando ele nasceu
  # antes de as escolhas serem guardadas (aí a coluna é a única fonte, e quem chama a usa). A chave
  # PRESENTE e incompleta não cai em silêncio no arquivo cru nem na coluna: `EscolhasIncompletas`, com
  # o nome do campo — uma variável nunca pode chegar ao modelo como `$nomeAgente`.
  def self.instrucao_do_principal(agent)
    return nil unless agent&.agent_type == 'insurance_quote'

    escolhas = agent.config.to_h[ESCOLHAS_DA_CORRETORA]
    return nil if escolhas.nil?

    substituir(texto_do_principal, escolhas)
  end

  # Lido a cada montagem, e não fotografado no boot: é o que faz o deploy seguinte valer.
  def self.texto_do_principal
    INSTRUCOES.join(ARQUIVO_DO_PRINCIPAL).read
  end

  # O BLOCO NO `gsub` NÃO É ESTILO. Com o valor como segundo argumento, o Ruby interpreta `\\0` no
  # texto de substituição — um nome de corretora contendo essa sequência passaria a inserir o
  # próprio marcador de volta. O bloco entrega a string literal, sem interpretar nada.
  def self.substituir(texto, escolhas)
    VARIAVEIS.reduce(texto) do |parcial, (marcador, campo)|
      parcial.gsub(marcador) { escolha(escolhas, campo) }
    end
  end

  # Só o nome do campo na mensagem, nunca o valor de outra escolha: o erro vai para log.
  def self.escolha(escolhas, campo)
    valor = escolhas[campo] if escolhas.is_a?(Hash)
    raise EscolhasIncompletas, campo if valor.blank?

    valor.to_s
  end

  # A chave do `config` onde as escolhas da corretora vivem: `nome_agente`, `nome_corretora`,
  # `horario` e `comportamento`, sempre as quatro, escritas só por `criar_agente` (a API do agente a
  # protege em `PROTECTED_CONFIG_KEYS`). O rollout de #380 preenche a dos agentes criados antes.
  ESCOLHAS_DA_CORRETORA = 'agente_de_cotacao'.freeze
  ARQUIVO_DO_PRINCIPAL = 'principal.md'.freeze
  # Marcador no arquivo -> campo das escolhas.
  VARIAVEIS = { '$nomeAgente' => 'nome_agente', '$nomeCorretora' => 'nome_corretora',
                '$horarioAtendimento' => 'horario', '$comportamento' => 'comportamento' }.freeze

  class SlugDesconhecido < StandardError; end
  class ComportamentoInvalido < StandardError; end
  class NomeInvalido < StandardError; end
  class JaExiste < StandardError; end
  class EscolhasIncompletas < StandardError; end

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

    validar_slugs!
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

  # SLUG QUE NÃO EXISTE É DESCARTADO EM SILÊNCIO por quem monta o turno: `Registry.for_agent` faz
  # `filter_map` e `Specialist#tools` também. Esse silêncio está certo para configuração velha, mas
  # transforma um erro de digitação AQUI num agente que nasce sem a ferramenta e nunca reclama —
  # foi assim que a Lia coletou os dados do cliente e anunciou uma cotação que nunca saiu. O nome
  # do slug entra no erro porque quem lê é quem vai corrigir a constante.
  def validar_slugs!
    catalogo = ::Autonomia::Agents::Tools::Registry.slugs
    desconhecidos = TODAS_AS_TOOLS - catalogo
    return if desconhecidos.empty?

    raise SlugDesconhecido, "#{desconhecidos.join(', ')} (catálogo: #{catalogo.join(', ')})"
  end

  def validar_nomes!
    { 'nome do agente' => @nome_agente, 'nome da corretora' => @nome_corretora }.each do |campo, valor|
      raise NomeInvalido, "#{campo} vazio" if valor.blank?
      raise NomeInvalido, "#{campo} acima de #{MAX_NOME} caracteres" if valor.length > MAX_NOME
    end
  end

  # A coluna recebe o texto de hoje (retrato do nascimento); o que roda lê o arquivo do deploy com as
  # escolhas guardadas em `config` (ver `instrucao_do_principal`).
  def criar_agente
    ::Autonomia::Agents::Agent.create!(
      account: @account, name: @nome_agente, agent_type: 'insurance_quote',
      status: :active, enabled: true, instruction: texto(ARQUIVO_DO_PRINCIPAL),
      config: { 'native_tool_slugs' => TODAS_AS_TOOLS, 'with_knowledge' => true, ESCOLHAS_DA_CORRETORA => escolhas }
    )
  end

  def criar_especialista(agente, dados)
    ::Autonomia::Agents::Specialist.create!(
      agent: agente, account: @account, slug: dados[:slug], name: dados[:nome],
      description: dados[:descricao], instruction: texto(dados[:arquivo]),
      tool_slugs: TOOLS_DO_ESPECIALISTA, enabled: true
    )
  end

  # A MESMA substituição do runtime (`substituir`): o que a coluna guarda no nascimento é, no dia da
  # criação, exatamente o que o modelo recebe. A auditoria não depende disso — depende das escolhas
  # guardadas e do arquivo no deploy —, mas o retrato de nascimento fica fiel.
  def texto(arquivo)
    self.class.substituir(INSTRUCOES.join(arquivo).read, escolhas)
  end

  # As quatro escolhas, com as chaves que o jsonb devolve (string), para o Builder e o runtime lerem
  # o mesmo formato.
  def escolhas
    { 'nome_agente' => @nome_agente, 'nome_corretora' => @nome_corretora,
      'horario' => @horario, 'comportamento' => @comportamento }
  end
end
