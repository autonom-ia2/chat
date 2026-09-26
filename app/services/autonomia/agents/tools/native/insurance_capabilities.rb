# Primeira ferramenta NATIVA (#312): o que a corretora consegue cotar hoje.
#
# Lê o mapa de capacidades já descoberto e guardado na conexão AGGER — não chama o portal. É de
# propósito: a pergunta "vocês vendem seguro residencial?" precisa ser respondida na hora, e o
# dado já está em casa, atualizado pela descoberta.
#
# Devolve TEXTO, não JSON: quem consome é um modelo de linguagem, e prosa curta gasta menos
# contexto e é mais difícil de citar errado do que uma estrutura aninhada.
#
# NO AGENTE DE COTAÇÃO SÃO DUAS LISTAS (conversa 7150, 26/09/2026). A pessoa perguntou por seguro de vida, e a Lia
# respondeu que a corretora trabalha com ele "com opções em 8 seguradoras" e que cotava: a lista única dava como
# cotável tudo o que a conexão traz, e só três ramos têm especialista. Agora a ferramenta separa o que a IA cota na
# hora (`Builder.ramos_que_a_ia_cota`) do que a corretora trabalha e fica com a equipe, e o manual da Lia diz o que
# fazer com cada lista. O ramo da segunda lista que a pessoa pediu fica anotado para a nota da equipe
# (`NotaDoEncaminhamento`), pelo parâmetro `ramo_pedido`, restrito aos códigos dessa lista. O agente comum segue com a
# lista única de sempre.
class Autonomia::Agents::Tools::Native::InsuranceCapabilities < Autonomia::Agents::Tools::Native::Base
  MAX_PRODUCTS = 30
  PARAMETRO_DO_RAMO = 'ramo_pedido'.freeze

  class << self
    def slug
      'consultar_produtos_cotacao'
    end

    def tool_name
      'Produtos disponíveis para cotação'
    end

    def description
      'Lista os ramos de seguro com que esta corretora trabalha hoje, quais deles a IA cota na hora e ' \
        'quantas seguradoras atendem cada um. Use quando o cliente perguntar o que a corretora vende, se um ramo ' \
        'específico está disponível, ou antes de iniciar uma cotação.'
    end

    # Sem parâmetros no catálogo. O mapa inteiro é curto (dezenas de linhas) e um filtro traria mais chance de o
    # modelo errar o nome do ramo do que economia de contexto.
    def params
      []
    end

    # NO AGENTE DE COTAÇÃO COM RAMO QUE A IA NÃO COTA, um parâmetro: o ramo que a pessoa pediu, só entre esses códigos
    # (`enum`), ou nulo. É o que leva o ramo à nota da equipe sem ler texto nenhum da pessoa. Sem esses ramos (a conta
    # que só tem o que a IA cota) e nos demais agentes, a ferramenta segue sem parâmetro. Nunca levanta: quem chama
    # monta o turno, e um erro aqui calaria o agente.
    def params_for(agent, **)
      ramos = agent && ramos_que_a_ia_nao_cota(agent)
      return params if ramos.blank?

      [{ 'name' => PARAMETRO_DO_RAMO, 'type' => 'string', 'required' => false, 'enum' => ramos,
         'description' => 'Os valores aceitos são os seguros que a corretora trabalha e a IA não cota nesta conta. ' \
                          'Se a pessoa pediu um deles, escreva o código dele já nesta consulta, para ficar anotado ' \
                          'para a equipe. Em qualquer outro caso, nulo.' }]
    rescue StandardError => e
      Rails.logger.warn("[autonomia][native_tool] capabilities params failed #{e.class}")
      params
    end

    # -> os códigos habilitados na conexão que a IA não cota, no Agente de Cotação; [] nos demais.
    def ramos_que_a_ia_nao_cota(agent)
      return [] unless agent.agent_type == 'insurance_quote'

      cota = ::Autonomia::Insurance::QuoteAgent::Builder.ramos_que_a_ia_cota(agent.account)
      connection = ::Autonomia::Insurance::Connection.for_account(agent.account).find(&:ready?)
      return [] if connection.blank?

      # Sem repetição: o `enum` repetido não é garantido no modo strict, e schema recusado cala o turno inteiro.
      habilitados(connection).pluck('product').map(&:to_s).uniq.reject { |produto| cota.include?(produto) }
    end

    def habilitados(connection)
      Array(connection.capabilities['products']).select { |product| product['enabled'] }.first(MAX_PRODUCTS)
    end

    # Não oferece a ferramenta se a conta não tem o módulo ligado ou não tem conexão pronta —
    # melhor não aparecer no prompt do que aparecer e falhar na frente do cliente.
    def available_for?(agent)
      return false unless Autonomia::Insurance::Config.enabled?(agent.account)

      Autonomia::Insurance::Connection.for_account(agent.account).any?(&:ready?)
    rescue StandardError
      false
    end
  end

  def call
    connection = Autonomia::Insurance::Connection.for_account(account).find(&:ready?)
    return 'A corretora ainda não conectou a conta do AGGER.' if connection.blank?

    products = self.class.habilitados(connection)
    return 'A conexão está ativa, mas nenhum ramo está habilitado nesta conta do AGGER.' if products.empty?

    agent.agent_type == 'insurance_quote' ? describe_split(products, connection) : describe(products, connection)
  rescue StandardError => e
    # NUNCA ecoar e.message: o payload da conexão passa perto de credencial de integração.
    Rails.logger.warn("[autonomia][native_tool] capabilities failed account=#{account.id} #{e.class}")
    error('capabilities_unavailable')
  end

  private

  def describe(products, connection)
    "Esta corretora cota hoje: #{products.map { |product| linha(product) }.join('; ')}.#{levantamento(connection)}"
  end

  # AS DUAS LISTAS DO AGENTE DE COTAÇÃO. A de quem a IA cota leva as seguradoras (é o que ela sabe fazer na hora); a do
  # que fica com a equipe vai sem contagem, porque o número de seguradoras do portal não é o que a equipe oferece.
  def describe_split(products, connection)
    cota = ::Autonomia::Insurance::QuoteAgent::Builder.ramos_que_a_ia_cota(account)
    na_hora, com_a_equipe = products.partition { |product| cota.include?(product['product'].to_s) }
    anotar_ramo_pedido(com_a_equipe)
    [cotados(na_hora), com_equipe(com_a_equipe)].compact.join(' ') + levantamento(connection)
  end

  def cotados(products)
    return 'A IA não cota nenhum ramo desta corretora na hora.' if products.empty?

    "A IA cota na hora, nesta conta: #{products.map { |product| linha(product) }.join('; ')}."
  end

  def com_equipe(products)
    return nil if products.empty?

    'A corretora também trabalha com estes, que a IA não cota e ficam com a equipe da corretora: ' \
      "#{products.map { |product| rotulo(product) }.join('; ')}."
  end

  # O ramo que o modelo escreveu em `ramo_pedido` só é anotado se estiver na lista do que fica com a equipe: o `enum`
  # já restringe, e esta conferência vale para o modelo que escrever fora dele.
  def anotar_ramo_pedido(com_a_equipe)
    ramo = params[PARAMETRO_DO_RAMO].to_s
    return unless com_a_equipe.any? { |product| product['product'].to_s == ramo }

    ::Autonomia::Agents::Tools::RecusasRecentes.anotar_ramo(::Autonomia::Agents::Tools::Recusa.conversa_de(delivery), ramo)
  end

  # Contamos só as seguradoras HABILITADAS: é o que a corretora consegue cotar de fato. As demais aparecem na tela de
  # Conexões com o motivo, mas não servem ao agente.
  def linha(product)
    ready = Array(product['insurers']).count { |insurer| insurer['enabled'] }
    ready.positive? ? "#{rotulo(product)} (#{ready} seguradoras)" : rotulo(product)
  end

  def rotulo(product)
    product['product'].to_s.tr('_', ' ').capitalize
  end

  def levantamento(connection)
    scanned = connection.last_capability_scan_at&.strftime('%d/%m/%Y')
    scanned.present? ? " Levantamento de #{scanned}." : ''
  end
end
