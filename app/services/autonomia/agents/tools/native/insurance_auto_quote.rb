# Cotação de seguro de AUTO — a primeira ferramenta ASSÍNCRONA (#313 + #291).
#
# Duas fases, porque cotar leva minutos: `start` submete e volta com o id; `poll` consulta. Medido no
# AGGER real em 04/09/2026: o primeiro preço apareceu aos ~15s, e o portal só declarou a cotação
# encerrada aos 392s. Por isso a entrega é PARCIAL — manda quem já respondeu e complementa depois.
#
# O QUE VAI PARA O CLIENTE, e o que não vai (decisão do PO):
#   - preço de seguradora que cotou: vai;
#   - seguradora que recusou o risco: NÃO vai por iniciativa nossa. O cliente pediu preço, não
#     auditoria, e a recusa fala do veículo e da região dele. Só se ele perguntar — e aí quem
#     responde é a instrução do especialista, não esta ferramenta;
#   - credencial da corretora inválida numa seguradora: NUNCA vai, nem se perguntado. É problema
#     nosso, constrangedor e inútil para quem quer comprar. Vai para a tela de Conexões.
class Autonomia::Agents::Tools::Native::InsuranceAutoQuote < Autonomia::Agents::Tools::Native::Base
  PRODUCT = 'auto'.freeze
  # Quantas opções o cliente vê. O fluxo de referência mostra as 3 mais baratas; mais que isso vira
  # tabela e para de ajudar a decidir.
  MAX_OFFERS = 3
  # Chave nossa dentro do handle: quem já foi entregue. É o que faz a segunda mensagem ser
  # "chegaram mais opções" em vez de repetir as que o cliente já leu.
  DELIVERED_KEY = 'entregues'.freeze
  DEFAULT_COMMISSION = 10.0
  # Sai UMA vez, junto do primeiro preço, e só em renovação sem classe de bônus. Não promete
  # desconto nem percentual: o quanto o bônus abate é decisão de cada seguradora, e prometer número
  # aqui vira preço que a emissão desmente. Diz o que é verdade — existe preço melhor, e ele depende
  # de um dado que está na apólice do cliente.
  AVISO_SEM_BONUS = 'Importante: cotei sem a classe de bônus da sua apólice atual, então estes ' \
                    'preços são os de quem está fazendo o primeiro seguro. Se você conferir a ' \
                    'classe de bônus na apólice (é um número de 0 a 10) e me disser, eu refaço a ' \
                    'cotação — com bônus costuma sair melhor.'.freeze
  # O PDF já foi entregue? O comparativo sai UMA vez, no fim — não a cada entrega parcial.
  PDF_SENT_KEY = 'comparativo_enviado'.freeze
  # Renovação cotada sem a classe de bônus. Viaja no handle porque quem decide isso é o `start`, e
  # quem precisa contar ao cliente é a primeira entrega de preços, minutos depois.
  SEM_BONUS_KEY = 'renovacao_sem_bonus'.freeze
  # O aviso JÁ SAIU. Sentinela própria, no mesmo molde do `PDF_SENT_KEY`, e não inferência a partir
  # de `already.empty?`: `deliver` roda ANTES de `record_attempt!`, então uma entrega bloqueada
  # (conversa encerrada, erro transitório do publisher) avançava o handle com os códigos das ofertas
  # mesmo assim — e o aviso, que vale por sair UMA vez, não sairia nunca mais.
  AVISO_SENT_KEY = 'aviso_sem_bonus_enviado'.freeze

  class << self
    def slug
      'cotar_seguro_auto'
    end

    def tool_name
      'Cotar seguro de automóvel'
    end

    def async?
      true
    end

    def description
      'Cota seguro de AUTOMÓVEL nas seguradoras que esta corretora atende. Precisa do CPF do ' \
        'segurado, da placa do veículo e do CEP de pernoite. Use quando o cliente pedir preço de ' \
        'seguro de carro e você já tiver esses três dados.'
    end

    def params
      [
        { 'name' => 'cpf', 'type' => 'string',
          'description' => 'CPF do segurado, só números ou formatado.' },
        { 'name' => 'placa', 'type' => 'string', 'description' => 'Placa do veículo (7 caracteres).' },
        { 'name' => 'cep', 'type' => 'string', 'description' => 'CEP onde o carro dorme.' },
        { 'name' => 'numero', 'type' => 'string', 'required' => false,
          'description' => 'Número do endereço, se o cliente informou.' },
        # RENOVAÇÃO. O portal cobra menos de quem já tem seguro, e a conta é feita com estes três
        # campos — sem eles a renovação sai cotada como se fosse a primeira apólice do cliente, mais
        # cara, e o comparativo perde para o preço que ele já paga hoje.
        { 'name' => 'renovacao', 'type' => 'boolean', 'required' => false,
          'description' => 'true quando o cliente JÁ TEM seguro e está renovando. Só marque com ' \
                           'confirmação dele; na dúvida, deixe em branco.' },
        { 'name' => 'bonus', 'type' => 'integer', 'required' => false,
          'description' => 'Classe de bônus que consta na apólice atual, de 0 a 10. Só em ' \
                           'renovação. ZERO é resposta válida: quem teve sinistro volta para a ' \
                           'classe 0. Se o cliente NÃO SOUBER, deixe em branco — não converta ' \
                           'percentual em classe e não chute. A cotação sai assim mesmo.' },
        { 'name' => 'sinistros', 'type' => 'integer', 'required' => false,
          'description' => 'Quantos sinistros o cliente teve na vigência atual. Só em renovação. ' \
                           'Zero é resposta válida e comum; não confunda com "não sei".' }
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
        'aqui assim que chegarem. Os primeiros costumam levar menos de um minuto. Não invente ' \
        'valores, prazos nem nomes de seguradora.'
    end

    def waiting_message
      'Estou consultando as seguradoras agora. Assim que os primeiros preços chegarem, mando aqui.'
    end

    def failure_message
      'Não consegui concluir a cotação agora. Um atendente vai retomar daqui.'
    end
  end

  # -> Hash serializável guardado na execução. Volta rápido: quem espera é o job.
  #
  # `with_fresh_session` porque uma cotação dura minutos e consulta de poucos em poucos segundos:
  # é o caminho com MAIS chance de a sessão morrer no meio — basta alguém abrir o portal no
  # navegador, e o AGGER derruba a nossa. Sem renovar, a cotação inteira morre em 403.
  def start
    sessions.with_fresh_session do |open_session|
      handle = connector.quote_start(provider: connection.provider, session: open_session,
                                     product: PRODUCT, input: quote_input)
      { 'quote_id' => handle['quote_id'], DELIVERED_KEY => [],
        SEM_BONUS_KEY => renewal.sem_bonus? }
    end
  end

  # -> Tools::Progress. Uma consulta. Só entrega quem AINDA NÃO foi entregue.
  def poll(handle:, attempt:)
    quote_id = handle['quote_id']
    return progress_class.failed('sem_id_de_cotacao') if quote_id.blank?

    result = sessions.with_fresh_session do |open_session|
      connector.quote_result(provider: connection.provider, session: open_session, quote_id: quote_id)
    end
    build_progress(result, handle, attempt)
  end

  private

  def build_progress(result, handle, _attempt)
    already = Array(handle[DELIVERED_KEY]).map(&:to_s)
    fresh = quoted_offers(result).reject { |offer| already.include?(insurer_code(offer)) }
    next_handle = handle.merge(DELIVERED_KEY => already + fresh.map { |offer| insurer_code(offer) })
    deliveries, next_handle = precos(fresh, already, next_handle)

    return progress_class.running(deliveries: deliveries, handle: next_handle) unless finished?(result)

    # O comparativo em PDF fecha a conversa, e sai UMA vez. É o que o portal entrega e o que o
    # cliente guarda — a lista de preços no chat serve para decidir, o PDF serve para levar adiante.
    # Individual só quando ele escolher uma seguradora; aí é outro pedido.
    pdf = comparison_pdf(next_handle)
    if pdf
      deliveries += [pdf]
      next_handle = next_handle.merge(PDF_SENT_KEY => true)
    end
    progress_class.done(deliveries: deliveries, handle: next_handle)
  end

  # -> [deliveries, handle]. O aviso de renovação sem bônus tem SENTINELA própria, no mesmo molde do
  # PDF, e não é inferido de "esta é a primeira entrega": `deliver` roda antes de `record_attempt!`,
  # então uma entrega bloqueada avançaria o handle e o aviso — que vale por sair uma vez — não sairia
  # nunca mais.
  def precos(fresh, already, handle)
    return [[], handle] if fresh.empty?

    avisar = handle[SEM_BONUS_KEY].present? && handle[AVISO_SENT_KEY].blank?
    texto = describe(fresh, first: already.empty?, sem_bonus: avisar)
    [[texto], avisar ? handle.merge(AVISO_SENT_KEY => true) : handle]
  end

  def finished?(result)
    %w[completed failed].include?(result['status'])
  end

  # nil quando não há o que imprimir, quando já foi enviado, ou quando a geração falha. Nunca
  # derruba a cotação: os preços já chegaram, e um PDF que não sai não pode apagá-los.
  def comparison_pdf(handle)
    return if handle[PDF_SENT_KEY]
    return if Array(handle[DELIVERED_KEY]).empty?

    proposal = sessions.with_fresh_session do |open_session|
      connector.quote_proposal(provider: connection.provider, session: open_session,
                               quote_id: handle['quote_id'])
    end
    url = proposal.to_h['url'].presence
    url && "Comparativo com todas as opções:\n#{url}"
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] comparativo falhou account=#{account.id} #{e.class}")
    nil
  end

  # SÓ quem cotou. `declined` e `auth_required` não viram texto ao cliente — ver o cabeçalho.
  def quoted_offers(result)
    Array(result['offers'])
      .select { |offer| offer['status'] == 'quoted' && offer.dig('premium', 'amount').present? }
      .sort_by { |offer| offer.dig('premium', 'amount').to_f }
      .first(MAX_OFFERS)
  end

  def insurer_code(offer)
    offer.dig('insurer', 'code').to_s
  end

  # Texto pronto para o cliente. A segunda mensagem se anuncia como complemento — sem isso ela
  # parece uma cotação nova e o cliente não sabe qual vale.
  def describe(offers, first:, sem_bonus: false)
    linhas = offers.map do |offer|
      "#{offer.dig('insurer', 'name')}: #{money(offer.dig('premium', 'amount'))}"
    end
    abertura = first ? 'Primeiros preços que chegaram:' : 'Chegaram mais opções:'
    corpo = "#{abertura}\n#{linhas.join("\n")}"
    sem_bonus ? "#{corpo}\n\n#{AVISO_SEM_BONUS}" : corpo
  end

  def money(amount)
    "R$ #{format('%.2f', amount.to_f).tr('.', ',')}"
  end

  def quote_input
    address = { 'zipCode' => params['cep'].to_s.gsub(/\D/, ''),
                'number' => params['numero'].to_s.presence }.compact
    {
      'insured' => { 'document' => params['cpf'].to_s.gsub(/\D/, '') },
      'address' => address,
      'vehicle' => { 'plate' => params['placa'].to_s },
      'commissionPercent' => commission_percent
    }.merge(renewal.to_input)
  end

  # Tudo o que muda quando o cliente já tem seguro mora aqui — inclusive as armadilhas do bônus.
  def renewal
    @renewal ||= ::Autonomia::Insurance::AutoRenewal.new(params)
  end

  # Comissão da conexão; sem valor definido, o padrão combinado com o PO.
  def commission_percent
    value = connection.metadata.to_h['commission_percent']
    value.present? ? value.to_f : DEFAULT_COMMISSION
  end

  # A sessão é ÚNICA por conexão (#330): reusada, nunca aberta por chamada. É o que permite duas
  # cotações simultâneas da mesma corretora sem uma atrapalhar a outra.
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
