# A CHAMADA PAGA, e a fronteira de incerteza em volta dela (entrega 5).
#
# `quote_start` é a única chamada da cotação que custa dinheiro e deixa registro no portal do
# corretor. O que falha ANTES dela (login, conexão ausente, validação) ou COM o portal dizendo que
# recusou (credencial, entrada) é falha comum: nada foi cotado. O que falha DEPOIS de ela sair sem o
# portal dizer nada — timeout, 502/503, resposta que não se lê — é outra coisa: a cotação pode
# existir lá. Até 10/09/2026 o job lia as duas como "não fez" e apagava a intenção de submeter; a
# passada seguinte cotava de novo, sem marca. Era a janela #337 por outra porta.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Envio
  extend ActiveSupport::Concern

  # As categorias em que o portal DISSE que não cotou, ou nem foi chamado: credencial recusada (401,
  # antes de processar), entrada recusada, conexão sem configuração, ramo que o adapter não tem.
  # `auth_required` sobe como está porque `with_fresh_session` a reconhece: renova a sessão e chama
  # de novo. Tudo o que não está aqui vira `Native::EnvioIncerto`.
  NAO_ENVIOU = %i[auth_required validation config not_implemented].freeze

  # A ENTRADA QUE O ADAPTER RECUSOU no `quote/start` (#470). Ele confere a entrada com o Zod ANTES do
  # `calcularV2` (`quote.ts#start`), então nada foi cotado nem cobrado. O caso real: a consulta de CPF
  # não achou a pessoa, e faltaram nascimento e sexo — dados que o cliente tem e o agente pergunta.
  # Tratado como falha passageira, virava 15 tentativas em 7 minutos e "um atendente vai continuar".
  #
  # Classe própria, e não o `Connector::Error` de `validation`, para o `start` só transformar em
  # recusa o que veio DESTA chamada: um `validation` do login não é dado que falta ao cliente.
  # E só com a lista de campos (`details.issues`): `validation` sem ela é o portal recusando o
  # `calcularV2` ou a corretora sem seguradora no ramo, e nada disso é pergunta ao cliente.
  class EntradaRecusada < StandardError
    # -> "campo: motivo", como o adapter escreve (`quote.ts`, `path.join('.')` do Zod).
    attr_reader :issues

    def initialize(issues)
      @issues = Array(issues).map(&:to_s)
      super('entrada recusada pelo adapter')
    end
  end

  private

  # -> o id da cotação no portal. Levanta `EnvioIncerto` quando a chamada saiu e não se sabe o que o
  # portal fez com ela — inclusive quando ele respondeu algo sem id.
  def enviar(open_session, pedido)
    resposta = chamar_portal(open_session, pedido)
    quote_id = resposta.is_a?(Hash) ? resposta['quote_id'].presence : nil
    quote_id || raise(::Autonomia::Agents::Tools::Native::EnvioIncerto, 'resposta sem quote_id')
  end

  def chamar_portal(open_session, pedido)
    connector.quote_start(session: open_session, **pedido)
  rescue ::Autonomia::Insurance::Connector::Error => e
    ausentes = campos_ausentes(e)
    raise EntradaRecusada, ausentes if ausentes.present?
    raise if NAO_ENVIOU.include?(e.kind)
    # A INVOCAÇÃO RECUSADA NÃO É INCERTEZA. Quando o próprio serviço recusa a chamada (throttle,
    # permissão, 5xx dele), o adapter não chega a rodar e o portal não é tocado: nada foi cotado.
    # Tratar isso como "pode ter cotado" queimava as duas tentativas em segundos e mandava o
    # cliente para a fila — foi o que aconteceu em 20/09/2026, com o adapter registrando zero
    # erros no mesmo minuto. Aqui a exceção sobe como falha comum, a intenção volta atrás, e a
    # execução tenta de novo com o intervalo normal.
    raise if e.nao_chegou_a_rodar?

    raise ::Autonomia::Agents::Tools::Native::EnvioIncerto, e.etiqueta
  rescue StandardError => e
    raise ::Autonomia::Agents::Tools::Native::EnvioIncerto, e.class.name
  end

  # SÓ CAMPO AUSENTE vira pergunta ao cliente (achado da revisão da PR #472). Um erro de FORMATO ("placa com
  # 7 caracteres") pediria de novo um dado que o cliente já deu, e o modelo tende a reenviar igual: laço.
  # Esses seguem o caminho de antes.
  def campos_ausentes(erro)
    return [] unless erro.kind == :validation

    Array(erro.details.to_h.stringify_keys['issues']).map(&:to_s).select { |issue| issue.split(':', 2)[1].to_s.strip == 'Required' }
  end

  # A MESMA RECUSA DA CONFERÊNCIA (`validar`), com o que falta e sem nova tentativa.
  # "insured.birthDate: Required" vira { 'campo' => 'insured.birthDate', 'motivo' => 'Required' }, o
  # formato que `campos` e os fatos do evento (`Eventos`) leem.
  def recusa_da_entrada(erro)
    faltantes = erro.issues.map do |issue|
      campo, motivo = issue.split(':', 2).map(&:strip)
      { 'campo' => campo, 'motivo' => motivo }
    end
    recusa('faltam_dados', faltando: campos(faltantes), problemas: faltantes)
  end
end
