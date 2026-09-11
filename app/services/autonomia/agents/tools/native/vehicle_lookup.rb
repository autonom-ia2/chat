# A CONSULTA DE PLACA como ferramenta do especialista — entrega 2 do Agente de Cotação, termo 5.
#
# Gratuita no portal, responde em ~1 s e diz três coisas que a conversa não sabe: o nome do carro,
# o ano do modelo e o TIPO (carro, moto, caminhão) — que decide o que a cotação exige. Até
# 10/09/2026 ela rodava DENTRO do envio, depois do pedido montado: o especialista só descobria
# que era moto depois da cotação paga. Agora ele consulta quando a placa chega e AINDA FALTA DADO
# para cotar — e a cotação (`InsuranceQuote::Veiculo`) consulta por conta própria SEMPRE que há
# placa, valendo o que o portal diz: a regra é por construção, não por obediência. A rodada de
# ferramentas do especialista é UMA (`ResponsesClient#create_with_tool_executor`): consultar aqui e
# cotar na mesma resposta não cabe, e não precisa — com tudo em mãos, é cotar direto.
#
# Roda no turno, com o modelo esperando: só com a sessão que já está viva (`with_live_session`).
# Abrir sessão é login com teto de 60 s, e o turno não espera isso.
#
# Devolve TEXTO ao modelo, com os rótulos que o próprio adapter publica no schema (nada
# traduzido aqui). Nenhum dado da pessoa: o portal responde sobre o veículo.
class Autonomia::Agents::Tools::Native::VehicleLookup < Autonomia::Agents::Tools::Native::Base
  AUTO = 'auto'.freeze
  CAMPO_DO_TIPO = 'vehicle.vehicleType'.freeze
  PLACA_INVALIDA = 'Essa placa não tem o formato de uma placa. Peça ao cliente para conferir e ' \
                   'escrever de novo.'.freeze
  INDISPONIVEL = 'Não consegui consultar a placa agora. Siga com o que o cliente informou; a ' \
                 'cotação consulta de novo antes de enviar.'.freeze

  class << self
    def slug
      'consultar_placa'
    end

    def tool_name
      'Consultar placa'
    end

    def description
      'Consulta gratuita da placa no portal da corretora: devolve o modelo, o ano e o TIPO do ' \
        'veículo (carro, moto ou caminhão). Use enquanto ainda está coletando os dados da ' \
        'cotação: confirme o veículo com o cliente pelo nome e pergunte o resto já sabendo o ' \
        'tipo. Se já tem placa, CPF e CEP, chame cotar_seguro direto com o que sabe — ela ' \
        'consulta a placa sozinha e devolve o que ainda faltar.'
    end

    def params
      [{ 'name' => 'placa', 'type' => 'string', 'description' => 'Placa do veículo, como o cliente escreveu.' }]
    end

    def available_for?(agent)
      ::Autonomia::Agents::Tools::Native::InsuranceQuote.available_for?(agent)
    end
  end

  def call
    placa = params['placa'].to_s.strip
    return recusar('placa_invalida', PLACA_INVALIDA) if placa.blank?

    consulta = sessions.with_live_session do |session|
      connector.vehicle_lookup(provider: connection.provider, session: session, plate: placa)
    end
    return recusar('consulta_de_placa_indisponivel', INDISPONIVEL) if consulta.nil?

    descrever(consulta)
  rescue ::Autonomia::Insurance::Connector::Error => e
    return recusar('placa_invalida', PLACA_INVALIDA) if e.kind == :validation

    Rails.logger.warn("[autonomia][insurance] consulta de placa falhou account=#{account.id} #{e.kind}")
    recusar('consulta_de_placa_indisponivel', INDISPONIVEL)
  end

  private

  def descrever(consulta)
    tipo = consulta['vehicle_type']
    partes = ["Placa #{consulta['plate']}: #{consulta['model'].presence || 'modelo não informado pelo portal'}"]
    partes << "(#{rotulo_do_tipo(tipo)})" if tipo.present?
    partes << "ano do modelo #{consulta['model_year']}" if consulta['model_year'].present?
    partes << "código FIPE #{consulta['fipe_code']}" if consulta['fipe_code'].present?
    frase = "#{partes.join(', ')}."
    return frase if tipo.blank?

    "#{frase} Na cotação, escreva `#{CAMPO_DO_TIPO}` = #{tipo}."
  end

  # O rótulo vem do schema que o adapter entregou — a mesma lista que o formulário mostra.
  def rotulo_do_tipo(tipo)
    campo = Array(connection.quote_schema(AUTO).to_h['campos']).find { |c| c['campo'] == CAMPO_DO_TIPO }
    campo&.dig('valores', tipo) || tipo
  end

  def connection
    @connection ||= ::Autonomia::Insurance::Connection.for_account(account).find(&:ready?) ||
                    raise(::Autonomia::Insurance::Connector::Error.new(:config, 'sem conexão pronta'))
  end

  def sessions
    @sessions ||= ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector)
  end

  def connector
    @connector ||= ::Autonomia::Insurance::Connector.client
  end
end
