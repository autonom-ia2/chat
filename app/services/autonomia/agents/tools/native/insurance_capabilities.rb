# Primeira ferramenta NATIVA (#312): o que a corretora consegue cotar hoje.
#
# Lê o mapa de capacidades já descoberto e guardado na conexão AGGER — não chama o portal. É de
# propósito: a pergunta "vocês vendem seguro residencial?" precisa ser respondida na hora, e o
# dado já está em casa, atualizado pela descoberta.
#
# Devolve TEXTO, não JSON: quem consome é um modelo de linguagem, e prosa curta gasta menos
# contexto e é mais difícil de citar errado do que uma estrutura aninhada.
class Autonomia::Agents::Tools::Native::InsuranceCapabilities < Autonomia::Agents::Tools::Native::Base
  MAX_PRODUCTS = 30

  class << self
    def slug
      'consultar_produtos_cotacao'
    end

    def tool_name
      'Produtos disponíveis para cotação'
    end

    def description
      'Lista os ramos de seguro que esta corretora consegue cotar hoje e quantas seguradoras ' \
        'atendem cada um. Use quando o cliente perguntar o que a corretora vende, se um ramo ' \
        'específico está disponível, ou antes de iniciar uma cotação.'
    end

    # Sem parâmetros. O mapa inteiro é curto (dezenas de linhas) e um filtro traria mais chance de
    # o modelo errar o nome do ramo do que economia de contexto.
    def params
      []
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

    products = enabled_products(connection)
    return 'A conexão está ativa, mas nenhum ramo está habilitado nesta conta do AGGER.' if products.empty?

    describe(products, connection)
  rescue StandardError => e
    # NUNCA ecoar e.message: o payload da conexão passa perto de credencial de integração.
    Rails.logger.warn("[autonomia][native_tool] capabilities failed account=#{account.id} #{e.class}")
    error('capabilities_unavailable')
  end

  private

  def enabled_products(connection)
    Array(connection.capabilities['products']).select { |product| product['enabled'] }.first(MAX_PRODUCTS)
  end

  def describe(products, connection)
    lines = products.map do |product|
      # Contamos só as seguradoras HABILITADAS: é o que a corretora consegue cotar de fato. As
      # demais aparecem na tela de Conexões com o motivo, mas não servem ao agente.
      ready = Array(product['insurers']).count { |insurer| insurer['enabled'] }
      label = product['product'].to_s.tr('_', ' ').capitalize
      ready.positive? ? "#{label} (#{ready} seguradoras)" : label
    end
    scanned = connection.last_capability_scan_at&.strftime('%d/%m/%Y')
    suffix = scanned.present? ? " Levantamento de #{scanned}." : ''
    "Esta corretora cota hoje: #{lines.join('; ')}.#{suffix}"
  end
end
