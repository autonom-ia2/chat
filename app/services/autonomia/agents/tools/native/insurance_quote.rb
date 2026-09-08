# Cotação de seguro em QUALQUER ramo que a corretora atende — a tool que não precisa ser reescrita
# a cada produto novo (#350, e o par autonom-ia2/autonomia-adapters#34 / #35).
#
# POR QUE ELA EXISTE. A cotação de auto tem uma tool própria com sete parâmetros digitados à mão em
# Ruby, e ela é SÓ de auto. Um ramo novo era outro arquivo, com os campos daquele ramo digitados de
# novo — dezessete para bike, onze para condomínio — e cada lista envelhecia sozinha. O
# `previousInsurerCode` é o preço disso: o adapter monta o campo, ninguém o coletava, e em renovação
# ele viajava nulo porque não havia parâmetro para ele.
#
# COMO ELA FAZ DIFERENTE. Não sabe nada sobre ramo nenhum. Pergunta ao adapter o que o ramo pede
# (`quote/schema`), confere a entrada antes de cotar (`quote/validate`), e quando falta algo devolve
# ao agente A LISTA DO QUE FALTA em vez de cotar errado.
#
# NÃO SUBSTITUI A DE AUTO. `insurance_auto_quote` está em produção com entrega parcial, comparativo
# em PDF e o aviso de renovação sem bônus — comportamento maduro que esta não tem. Auto continua
# lá; esta atende os outros dez ramos, que hoje não têm ferramenta nenhuma.
class Autonomia::Agents::Tools::Native::InsuranceQuote < Autonomia::Agents::Tools::Native::Base
  # O ramo com ferramenta própria. Fica de fora para não haver duas ferramentas competindo pelo
  # mesmo pedido — o modelo escolheria por descrição, e a desta é necessariamente mais genérica.
  PRODUTO_COM_FERRAMENTA_PROPRIA = 'auto'.freeze
  MAX_OFFERS = 3
  # Teto do JSON que o modelo escreve. O ramo que mais pede é a bike, com dezessete campos — alguns
  # milhares de caracteres com folga. Um valor muito maior não é entrada legítima, e parsear antes
  # de olhar o tamanho é trabalho que ninguém pediu.
  MAX_DADOS_BYTES = 20_000
  DELIVERED_KEY = 'entregues'.freeze
  DEFAULT_COMMISSION = 10.0

  class << self
    def slug
      'cotar_seguro'
    end

    def tool_name
      'Cotar seguro (qualquer ramo)'
    end

    def async?
      true
    end

    def description
      'Cota seguro de RESIDENCIAL, CONDOMÍNIO, EMPRESARIAL, ALUGUEL/FIANÇA, VIAGEM, ACIDENTES ' \
        'PESSOAIS, VIDA, VIDA EM GRUPO, CELULAR ou BICICLETA nas seguradoras que esta corretora ' \
        'atende. Para seguro de AUTOMÓVEL use a ferramenta específica de auto. Informe o produto e ' \
        'os dados que o cliente já deu; se faltar algo, a ferramenta responde exatamente o que ' \
        'perguntar, sem consumir cotação.'
    end

    # `dados` viaja como TEXTO JSON, e não como objeto. O schema de função exige `strict` com
    # `additionalProperties: false`, e um objeto de forma livre não tem como ser declarado ali —
    # cada ramo tem os seus campos, que é o ponto desta ferramenta. Texto é o único tipo que
    # atravessa; a ferramenta parseia e diz com clareza quando o JSON não presta.
    def params
      [
        { 'name' => 'produto', 'type' => 'string',
          'description' => 'Ramo a cotar: residencial, condominio, empresarial, fianca_locaticia, ' \
                           'viagem, acidentes_pessoais, vida, vida_global, celular ou bike.' },
        { 'name' => 'dados', 'type' => 'string',
          'description' => 'JSON com o que o cliente informou, usando os nomes de campo que a ' \
                           'ferramenta pedir. Exemplo para bike: ' \
                           '{"marca":"Caloi","modelo":"Elite","valorMercado":8000}. ' \
                           'Mande {} na primeira vez para descobrir o que perguntar.' },
        { 'name' => 'cpf', 'type' => 'string', 'required' => false,
          'description' => 'CPF ou CNPJ do segurado, se o cliente já informou.' },
        { 'name' => 'nome', 'type' => 'string', 'required' => false,
          'description' => 'Nome do segurado, se o cliente já informou.' }
      ]
    end

    def available_for?(agent)
      return false unless ::Autonomia::Insurance::Config.enabled?(agent.account)

      ::Autonomia::Insurance::Connection.for_account(agent.account).any?(&:ready?)
    rescue StandardError
      false
    end

    def accepted_message
      'Cotação enviada às seguradoras. Avise o cliente que está consultando e que manda os preços ' \
        'aqui assim que chegarem. Não invente valores, prazos nem nomes de seguradora.'
    end

    def waiting_message
      'Estou consultando as seguradoras agora. Assim que os primeiros preços chegarem, mando aqui.'
    end

    def failure_message
      'Não consegui concluir a cotação agora. Um atendente vai retomar daqui.'
    end
  end

  # -> Hash serializável, ou o pedido do que falta. NÃO cota antes de validar: cada cotação no AGGER
  # consome consulta paga, e a validação custa uma chamada sem sessão.
  def start
    return recusa('produto_nao_informado', PEDIDO_DE_PRODUTO) if produto.blank?
    return recusa('json_invalido', PEDIDO_DE_JSON) if dados.nil?

    faltantes = validar
    return recusa('faltam_dados', pedido_do_que_falta(faltantes)) if faltantes.any?

    submeter
  end

  # -> Tools::Progress. Uma consulta por vez; só entrega quem ainda não foi entregue.
  def poll(handle:, attempt:)
    return progress_class.done(deliveries: [handle['pedido']], handle: handle) if handle['pedido']

    quote_id = handle['quote_id']
    return progress_class.failed('sem_id_de_cotacao') if quote_id.blank?

    result = sessions.with_fresh_session do |open_session|
      connector.quote_result(provider: connection.provider, session: open_session, quote_id: quote_id)
    end
    build_progress(result, handle, attempt)
  end

  private

  PEDIDO_DE_PRODUTO = 'Não entendi qual seguro cotar. Pergunte ao cliente qual é o produto ' \
                      '(residencial, viagem, vida, celular, bicicleta…) e chame de novo.'.freeze
  PEDIDO_DE_JSON = 'O campo `dados` não era um JSON válido. Reenvie como objeto JSON, por ' \
                   'exemplo {"marca":"Caloi"}.'.freeze

  # O QUE FALTA, PERGUNTADO DE GRAÇA. Sem sessão e sem tocar no portal — é o que permite errar a
  # entrada sem gastar cotação. Só `erro` vira pedido: `aviso` fala de tabela possivelmente velha do
  # nosso lado, e mandar o agente perguntar por causa disso seria atrito sem causa.
  def validar
    resultado = connector.quote_validate(provider: connection.provider, product: produto,
                                         input: entrada)
    Array(resultado['problemas']).select { |p| p['severidade'] == 'erro' }
  end

  def submeter
    handle = sessions.with_fresh_session do |open_session|
      connector.quote_start(provider: connection.provider, session: open_session,
                            product: produto, input: entrada)
    end
    { 'quote_id' => handle['quote_id'], DELIVERED_KEY => [], 'produto' => produto }
  end

  # A recusa VIRA ENTREGA, e não falha. O agente precisa receber o texto para perguntar ao cliente;
  # `failed` mandaria a mensagem genérica de erro e a conversa morreria sem ninguém saber o que
  # faltava. O `poll` reconhece o handle com `pedido` e entrega na primeira passada.
  def recusa(motivo, texto)
    Rails.logger.info("[autonomia][insurance] cotacao recusada antes do portal account=#{account.id} motivo=#{motivo}")
    { 'pedido' => texto, 'motivo' => motivo }
  end

  # O texto que o agente lê para saber o que perguntar. Nomes de campo crus de propósito: quem
  # traduz para o cliente é o especialista, que conhece o vocabulário do ramo — inventar rótulo em
  # português aqui seria adivinhar o que o portal chama de quê.
  def pedido_do_que_falta(faltantes)
    campos = faltantes.pluck('campo').join(', ')
    "Para cotar #{produto} ainda faltam estes dados: #{campos}. Pergunte ao cliente e chame a " \
      'ferramenta de novo com eles preenchidos. Nenhuma cotação foi consumida.'
  end

  def build_progress(result, handle, _attempt)
    already = Array(handle[DELIVERED_KEY]).map(&:to_s)
    fresh = quoted_offers(result).reject { |offer| already.include?(insurer_code(offer)) }
    next_handle = handle.merge(DELIVERED_KEY => already + fresh.map { |offer| insurer_code(offer) })
    deliveries = fresh.empty? ? [] : [describe(fresh, first: already.empty?)]

    return progress_class.running(deliveries: deliveries, handle: next_handle) unless finished?(result)

    progress_class.done(deliveries: deliveries, handle: next_handle)
  end

  def finished?(result)
    %w[completed failed].include?(result['status'])
  end

  # SÓ quem cotou, e no máximo três. Recusa de risco e problema de credencial não viram texto ao
  # cliente — a primeira fala do bem dele, a segunda é problema nosso e vai para a tela de Conexões.
  def quoted_offers(result)
    Array(result['offers'])
      .select { |offer| offer['status'] == 'quoted' && offer.dig('premium', 'amount').present? }
      .sort_by { |offer| offer.dig('premium', 'amount').to_f }
      .first(MAX_OFFERS)
  end

  def insurer_code(offer)
    offer.dig('insurer', 'code').to_s
  end

  def describe(offers, first:)
    linhas = offers.map do |offer|
      "#{offer.dig('insurer', 'name')}: #{::Autonomia::Insurance::PremiumText.new(offer['premium'])}"
    end
    abertura = first ? 'Primeiros preços que chegaram:' : 'Chegaram mais opções:'
    corpo = "#{abertura}\n#{linhas.join("\n")}"
    return corpo unless offers.any? { |o| ::Autonomia::Insurance::PremiumText.new(o['premium']).indefinido? }

    "#{corpo}\n\n#{::Autonomia::Insurance::PremiumText::SEM_SIGNIFICADO}"
  end

  def produto
    @produto ||= params['produto'].to_s.strip.presence
  end

  # `nil` quando o JSON não presta — diferente de `{}`, que é "o cliente ainda não disse nada" e é
  # entrada legítima na primeira chamada.
  def dados
    return @dados if defined?(@dados)

    bruto = params['dados'].to_s.strip
    return @dados = nil if bruto.bytesize > MAX_DADOS_BYTES

    @dados = bruto.empty? ? {} : parse_json(bruto)
  end

  def parse_json(bruto)
    valor = JSON.parse(bruto)
    valor.is_a?(Hash) ? valor : nil
  rescue JSON::ParserError
    nil
  end

  # O segurado vem por parâmetro próprio porque é o único dado comum a TODOS os ramos, e pedi-lo
  # dentro do JSON faria o agente errar a grafia da chave a cada ramo.
  #
  # VAZIO NUNCA SOBRESCREVE. O JSON vence o parâmetro quando traz valor — é o mais específico, e o
  # modelo o escreveu de propósito —, mas `{"segurado":{"cpfCnpj":""}}` apagaria o CPF que veio no
  # parâmetro, e o portal recusaria uma cotação que tinha tudo. `compact_blank` é o que separa
  # "informou outro valor" de "mandou a chave vazia".
  def entrada
    base = dados.to_h
    informado = segurado_dos_parametros.merge(base['segurado'].to_h.compact_blank)
    base = base.merge('segurado' => informado) if informado.any?
    base.merge('commissionPercent' => commission_percent)
  end

  def segurado_dos_parametros
    { 'cpfCnpj' => params['cpf'].to_s.gsub(/\D/, '').presence,
      'nome' => params['nome'].to_s.presence }.compact
  end

  def commission_percent
    value = connection.metadata.to_h['commission_percent']
    value.present? ? value.to_f : DEFAULT_COMMISSION
  end

  def sessions
    @sessions ||= ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector)
  end

  def connection
    @connection ||= ::Autonomia::Insurance::Connection.for_account(account).find(&:ready?) ||
                    raise(::Autonomia::Insurance::Connector::Error.new(:config, 'sem conexão pronta'))
  end

  def connector
    @connector ||= ::Autonomia::Insurance::Connector.client
  end

  def progress_class
    ::Autonomia::Agents::Tools::Progress
  end
end
