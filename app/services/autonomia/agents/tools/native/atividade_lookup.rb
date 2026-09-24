# A BUSCA DA ATIVIDADE DA EMPRESA, POR SEGURADORA — empresarial (chat#641), no molde da consulta de CEP.
#
# No empresarial cada seguradora tem a sua lista de atividades, com códigos que não conversam entre si, e a
# seguradora sem a atividade escolhida na lista dela não calcula (colheita de 04/09/2026, provado em 24/09). A
# busca é grátis e por texto: o especialista manda de 1 a 3 termos tirados do que o cliente disse que a empresa
# faz (o nome específico, um sinônimo, o genérico), recebe as opções de cada seguradora e ESCOLHE uma por
# seguradora na cotação. Casar a fala da pessoa com a lista de uma seguradora é interpretar linguagem: quem
# decide é o modelo, e aqui não há lista de palavras. Seguradora sem opção segura fica de fora (opção C do
# Rodrigo, 24/09/2026), depois de o modelo tentar outro termo.
#
# Síncrona e só com a sessão viva (`with_live_session`), como a de CEP. Devolve TEXTO ao MODELO; nenhuma frase
# aqui é para o cliente.
class Autonomia::Agents::Tools::Native::AtividadeLookup < Autonomia::Agents::Tools::Native::Base
  PRODUTO = 'empresarial'.freeze
  SEM_TERMOS = 'Mande de 1 a 3 termos de busca tirados do que o cliente disse que a empresa faz. Se ele ainda não ' \
               'disse, pergunte o que a empresa faz antes de buscar.'.freeze
  INDISPONIVEL = 'Não deu para buscar as atividades agora. Não invente atividade nem código: tente de novo em ' \
                 'seguida, e se continuar, siga sem cotar e diga que vai encaminhar para alguém da equipe.'.freeze
  # O que o especialista faz com as opções. É a regra da opção C, resolvida ao máximo.
  COMO_ESCOLHER = 'Para cada seguradora, escolha a opção que descreve a mesma atividade que o cliente contou, e mande ' \
                  'a escolhida em atividades na cotação (seguradora, key e value exatamente como estão aqui). Onde a ' \
                  'lista separa térreo de andar superior, escolha pelo que o cliente disse do local; se ele não disse, ' \
                  'pergunte uma vez se é térreo ou andar. Seguradora sem opção que corresponda com segurança: busque ' \
                  'de novo com outro termo (um sinônimo, o nome mais genérico da atividade); se ainda assim nenhuma ' \
                  'corresponder, deixe essa seguradora de fora. Nunca escolha uma atividade diferente da do cliente ' \
                  'só para a seguradora cotar. Se nenhuma seguradora ficar com opção, não cote: diga que vai ' \
                  'encaminhar para alguém da equipe.'.freeze
  # A SAÍDA DO BECO (revisão da chat#654): sem ela, a atividade que nenhuma seguradora lista virava pergunta ao cliente
  # em laço. Uma segunda busca, e depois a equipe, como na busca indisponível.
  NADA_ACHADO = 'Nenhuma seguradora tem opção para estes termos. Busque de novo com outro termo, mais genérico. Se ' \
                'já buscou com outro termo e ainda nenhuma seguradora tem a atividade do cliente, não cote e não ' \
                'pergunte de novo o que a empresa faz: diga que vai encaminhar para alguém da equipe.'.freeze

  class << self
    def slug
      'buscar_atividade'
    end

    def tool_name
      'Buscar atividade'
    end

    def description
      'Busca gratuita, no portal da corretora, das opções de atividade da empresa em cada seguradora. Use antes de ' \
        'cotar empresarial, assim que souber o que a empresa faz: a cotação só vai às seguradoras cuja atividade ' \
        'você escolher.'
    end

    def params
      [{ 'name' => 'termos', 'type' => 'array', 'items' => 'string',
         'description' => 'De 1 a 3 termos de busca, com pelo menos 3 letras cada, tirados do que o cliente disse ' \
                          'que a empresa faz: o nome específico, um sinônimo e o genérico.' }]
    end

    def available_for?(agent)
      ::Autonomia::Agents::Tools::Native::InsuranceQuote.available_for?(agent)
    end
  end

  def call
    termos = Array(params['termos']).map { |termo| termo.to_s.strip }.compact_blank.uniq
    return recusar('atividade_sem_termos', SEM_TERMOS) if termos.empty?

    busca = buscar(termos)
    return recusar('busca_de_atividade_indisponivel', INDISPONIVEL) if busca.nil?

    descrever(busca)
  rescue ::Autonomia::Insurance::Connector::Error => e
    # SÓ É TERMO RUIM O QUE O ADAPTER DECLARA COMO PERGUNTA (`details.perguntas`), como na consulta de CEP. Uma
    # `validation` sem ela (o 401 do portal com envelope de erro chega assim) não é culpa do termo, e pedir outro
    # faria o cliente ouvir de novo a pergunta sobre a empresa.
    return recusar('atividade_sem_termos', SEM_TERMOS) if termo_recusado?(e)

    Rails.logger.warn("[autonomia][insurance] busca de atividade falhou account=#{account.id} #{e.etiqueta}")
    recusar('busca_de_atividade_indisponivel', INDISPONIVEL)
  end

  private

  def termo_recusado?(erro)
    erro.kind == :validation && Array(erro.details.to_h['perguntas']).any?
  end

  def buscar(termos)
    sessions.with_live_session do |session|
      connector.atividade_lookup(provider: connection.provider, session: session, product: PRODUTO, termos: termos)
    end
  end

  def descrever(busca)
    blocos = Array(busca.to_h['por_termo']).filter_map { |termo| bloco(termo) }
    return NADA_ACHADO if blocos.empty?

    [*blocos, COMO_ESCOLHER].join("\n\n")
  end

  # Um termo: as seguradoras com opção, uma linha por opção. Seguradora sem opção não aparece.
  def bloco(termo)
    com_opcao = Array(termo['por_seguradora']).select { |seg| Array(seg['opcoes']).any? }
    return nil if com_opcao.empty?

    linhas = com_opcao.flat_map do |seg|
      Array(seg['opcoes']).map { |op| "- #{seg['insurer_name']} (seguradora #{seg['insurer_code']}): key #{op['key']}, value #{op['value']}" }
    end
    ["Termo \"#{termo['termo']}\":", *linhas].join("\n")
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
