# Consulta às Condições Gerais das seguradoras (a "Mia") — #319.
#
# ISTO INVERTE UMA REGRA. A instrução do multicálculo que roda em produção PROÍBE o agente de
# explicar cobertura, e com razão: são seis manuais diferentes num comparativo, e qualquer resposta
# genérica vira promessa errada. A proibição existia porque não havia como consultar o contrato.
#
# Agora há. Com a CG da seguradora certa na mão, a resposta deixa de ser opinião e passa a ser
# leitura de cláusula — e o cliente não precisa esperar um humano para saber se o vidro traseiro
# está coberto. O que continua proibido é responder de memória.
#
# Devolve TEXTO, como toda ferramenta nativa. Quando a base não sustenta a resposta, o texto diz
# isso e manda escalar: melhor o agente admitir que não sabe do que entregar prosa que parece
# resposta e não se apoia em cláusula nenhuma.
class Autonomia::Agents::Tools::Native::InsuranceGeneralConditions < Autonomia::Agents::Tools::Native::Base
  DEFAULT_PRODUCT = 'Automóvel'.freeze

  class << self
    def slug
      'consultar_condicoes_gerais'
    end

    def tool_name
      'Condições gerais da seguradora'
    end

    def description
      'Consulta as condições gerais registradas na SUSEP para responder o que uma seguradora ' \
        'cobre, exclui ou condiciona. Use quando o cliente perguntar sobre cobertura, franquia, ' \
        'carro reserva, assistência, prazo ou exclusão de UMA seguradora específica. Sempre ' \
        'informe a seguradora; sem ela a consulta não tem como responder.'
    end

    def params
      [
        { 'name' => 'seguradora', 'type' => 'string',
          'description' => 'Nome da seguradora, como o cliente falou. Ex.: "Bradesco", "HDI", "Porto".' },
        { 'name' => 'pergunta', 'type' => 'string',
          'description' => 'A dúvida do cliente, em português, na forma de pergunta completa.' },
        { 'name' => 'ramo', 'type' => 'string', 'required' => false,
          'description' => 'Ramo do seguro. Padrão: Automóvel. Ex.: "Residencial", "Vida".' }
      ]
    end

    # Sem o módulo de seguros ligado a ferramenta não faz sentido no prompt. NÃO exige conexão
    # pronta com o portal: responder sobre cobertura é útil antes de existir qualquer cotação.
    def available_for?(agent)
      Autonomia::Insurance::Config.enabled?(agent.account)
    rescue StandardError
      false
    end
  end

  def call
    return 'Informe a seguradora para eu consultar as condições gerais.' if insurer.blank?
    return 'Informe a dúvida do cliente para eu consultar.' if question.blank?

    describe(client.query(question: question, insurer: insurer, product: product))
  rescue Autonomia::Insurance::GeneralConditions::Client::Error => e
    # NUNCA ecoar a mensagem crua ao cliente: o modelo lê o código e escala.
    Rails.logger.warn("[autonomia][native_tool] general_conditions failed account=#{account.id} #{e.message}")
    'A consulta às condições gerais não respondeu agora. Diga ao cliente que vai confirmar com um ' \
      'especialista em vez de responder por conta própria.'
  end

  private

  # A resposta carrega SEMPRE de qual seguradora é a regra. Sem isso o agente cita a cláusula de uma
  # e o cliente entende que vale para todas as opções do comparativo.
  def describe(answer)
    return unresolved(answer) unless answer.usable?

    "Segundo as condições gerais da #{answer.insurer}: #{answer.text}\n\n" \
      'Diga ao cliente de qual seguradora é esta regra. Não estenda para as outras do comparativo.'
  end

  # Duas causas MUITO diferentes chegam pelo mesmo caminho, e confundi-las mente para o cliente:
  #   - nome não resolveu -> a base pode ter a resposta, só não sabemos de quem;
  #   - nome resolveu e o material não cobre a pergunta -> aí sim é lacuna real.
  def unresolved(answer)
    if answer.suggestions.any?
      "Não identifiquei a seguradora \"#{insurer}\". Pergunte ao cliente se é uma destas: " \
        "#{answer.suggestions.first(3).join(', ')}."
    else
      "Não encontrei essa regra nas condições gerais da #{answer.insurer.presence || insurer}. " \
        'Diga que vai confirmar com um especialista. NÃO responda de memória.'
    end
  end

  def client
    @client ||= Autonomia::Insurance::GeneralConditions::Client.new
  end

  def insurer
    params['seguradora'].to_s.strip
  end

  def question
    params['pergunta'].to_s.strip
  end

  def product
    params['ramo'].to_s.strip.presence || DEFAULT_PRODUCT
  end
end
