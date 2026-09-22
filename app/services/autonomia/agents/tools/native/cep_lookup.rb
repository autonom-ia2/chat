# A CONSULTA DE CEP como ferramenta do especialista, no molde da consulta de placa (`VehicleLookup`)
# — piloto de residencial (chat#323, autonomia-adapters#87).
#
# O especialista de ramo com imóvel precisa saber se o imóvel fica em zona rural ou em área de risco,
# e perguntar isso a quem mora na Av. Faria Lima é perguntar à toa. Até 22/09/2026 só o adapter via o
# endereço, dentro do envio da cotação: o especialista cotava sem saber a rua. Agora ele consulta o
# CEP que o cliente deu, recebe rua, bairro, cidade e UF, e deduz pelo endereço e pela conversa; só
# pergunta quando o endereço indica (estrada, sítio, beira de rio). Cidade pequena NÃO é sinal: costuma ter CEP
# único, e o modelo perguntaria "mora num sítio?" a quem mora no centro (revisão da adapters#86).
#
# Gratuita no portal e síncrona: roda no turno, com o modelo esperando, e por isso só com a sessão que
# já está viva (`with_live_session`), como a de placa. O que a consulta não responde inteiro (CEP que
# não existe, cidade de CEP único sem rua) o adapter devolve como PERGUNTA ao cliente (`perguntas`, o
# contrato do adapters#77), e ela chega ao modelo como o que perguntar, nunca como endereço inventado.
#
# LGPD: o endereço é o do CEP que o próprio cliente informou, dado público do CEP. Não vem da busca por
# CPF, e pode ir ao modelo.
#
# Devolve TEXTO ao MODELO. Nenhuma frase aqui é para o cliente ler: o modelo fala com a voz dele.
class Autonomia::Agents::Tools::Native::CepLookup < Autonomia::Agents::Tools::Native::Base
  CEP_VAZIO = 'O CEP veio vazio. Peça ao cliente o CEP do imóvel antes de consultar.'.freeze
  INDISPONIVEL = 'Não deu para consultar este CEP agora. Não invente rua, bairro nem cidade: siga com o que o ' \
                 'cliente informou, e a cotação consulta o CEP de novo antes de enviar.'.freeze
  # O que o especialista faz com o endereço. É a regra do piloto: deduzir, e perguntar só com indício.
  DEDUCAO = 'Com este endereço e com o que o cliente já contou, deduza se o imóvel fica em zona rural ou em ' \
            'área de risco (beira de rio, encosta, morro). Só pergunte isso ao cliente quando houver indício: ' \
            'estrada, sítio, chácara, fazenda ou zona rural no endereço, imóvel perto de rio, encosta ou morro. ' \
            'Endereço urbano comum não pede essa pergunta, nem o de cidade pequena, que costuma ter CEP único.'.freeze
  SEM_ENDERECO = 'A consulta deste CEP não trouxe o endereço completo, e sem ele não há como deduzir zona rural ' \
                 'nem área de risco. Não invente o endereço. O que perguntar ao cliente antes de seguir:'.freeze
  # Recusa de validação sem a lista de perguntas (o adapter sempre a manda; isto é o que o modelo lê se
  # um dia ela faltar): o único dado que se pode pedir é o próprio CEP.
  PERGUNTA_PADRAO = 'Confirme o CEP do imóvel com o cliente.'.freeze

  class << self
    def slug
      'consultar_cep'
    end

    def tool_name
      'Consultar CEP'
    end

    def description
      'Consulta gratuita do CEP do imóvel no portal da corretora: devolve rua, bairro, cidade e UF. Use ' \
        'assim que o cliente informar o CEP do imóvel, antes de decidir se precisa perguntar sobre zona ' \
        'rural ou área de risco: é o endereço que diz se vale perguntar.'
    end

    def params
      [{ 'name' => 'cep', 'type' => 'string', 'description' => 'CEP do imóvel, como o cliente escreveu.' }]
    end

    def available_for?(agent)
      ::Autonomia::Agents::Tools::Native::InsuranceQuote.available_for?(agent)
    end
  end

  def call
    cep = params['cep'].to_s.strip
    return recusar('cep_invalido', CEP_VAZIO) if cep.blank?

    consulta = sessions.with_live_session do |session|
      connector.cep_lookup(provider: connection.provider, session: session, cep: cep)
    end
    return recusar('consulta_de_cep_indisponivel', INDISPONIVEL) if consulta.nil?

    descrever(consulta)
  rescue ::Autonomia::Insurance::Connector::Error => e
    return perguntar(e.details) if e.kind == :validation

    Rails.logger.warn("[autonomia][insurance] consulta de CEP falhou account=#{account.id} #{e.etiqueta}")
    recusar('consulta_de_cep_indisponivel', INDISPONIVEL)
  end

  private

  def descrever(consulta)
    "Endereço do CEP #{consulta['cep']}: #{consulta['logradouro']}, bairro #{consulta['bairro']}, " \
      "#{consulta['cidade']}, #{consulta['uf']}. #{DEDUCAO}"
  end

  # As perguntas do adapter, com o motivo que ele escreveu para o modelo. O registro leva só os NOMES dos
  # campos (`cep`, `logradouro`, `bairro`), nunca o CEP.
  def perguntar(detalhes)
    perguntas = Array(detalhes.to_h['perguntas']).select { |p| p.is_a?(Hash) }
    motivos = perguntas.map { |p| p['motivo'].to_s.strip.upcase_first }.compact_blank
    texto = [SEM_ENDERECO, *(motivos.presence || [PERGUNTA_PADRAO])].join(' ')
    recusar('cep_sem_endereco', texto, faltando: perguntas.map { |p| p['campo'].to_s })
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
