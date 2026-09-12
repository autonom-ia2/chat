# A CHAMADA AO PORTAL, UMA SEGURADORA POR PASSADA — e o que fica registrado dela (rodada de correção
# da entrega 8).
#
# ATÉ 12/09/2026 o `start` chamava o portal para as duas seguradoras numa expressão só, e uma falha
# na segunda descartava a URL da primeira: o job refazia as duas (Codex, P2). A ferramenta não tem a
# linha da execução para gravar no meio do `start` — quem persiste é o job, com o handle devolvido
# (é assim que a cotação anota o `quote_id`, entrega 5). Então CADA PASSADA FAZ UMA CHAMADA e devolve
# o handle: o `start` pede a PRIMEIRA seguradora e volta; o `poll` pede a próxima pendente, uma por
# vez, e só depois entrega. Uma URL gerada está no banco antes de a chamada seguinte sair, e um
# deploy entre passadas não perde nada. É também o que mantém cada passada dentro de UMA chamada de
# até 60 s (`Connector::Http::READ_TIMEOUT`) — o `start` da cotação tem o mesmo teto.
#
# FALHA NUMA SEGURADORA NÃO LEVANTA. O portal recusar o código (422, `validation`) ou falhar
# (indisponível, tempo, resposta ilegível) fica registrado por seguradora, e a proposta das outras
# sai. A recusa é definitiva; a falha ganha até `MAX_TENTATIVAS` chamadas (uma por passada) antes de
# ser desistida. O que falha ANTES da chamada — código em branco, conexão sem configuração,
# credencial ausente, login recusado — é problema NOSSO e sobe como sempre: o job tenta de novo e,
# no limite, desiste com a nossa frase (verificador cego, B2: o `rescue` só envolve a chamada ao
# portal, nunca o `with_fresh_session`).
module Autonomia::Agents::Tools::Native::InsuranceProposal::Geracao
  extend ActiveSupport::Concern

  # As chaves do handle DESTA execução. Não se chamam `propostas` de propósito: esse nome é o da
  # chave que fica na LINHA DA COTAÇÃO (`InsuranceQuote::PROPOSTAS_KEY`, só códigos), e dois formatos
  # sob o mesmo nome em duas linhas é como uma medida passa a somar a linha errada sem ninguém notar.
  #   GERADAS    — `[{code, name, url}]`, na ordem em que o portal as gerou;
  #   PENDENTES  — códigos ainda por pedir, na ordem em que foram falados;
  #   TENTATIVAS — código -> quantas chamadas já saíram para ele;
  #   NAO_SAIU   — código -> motivo (a categoria do conector: `validation`, `unavailable`, `timeout`,
  #                `protocol`), das que o portal não gerou e não vão ser pedidas de novo;
  #   ENVIADAS   — códigos cujo arquivo já foi entregue (não é `entregues`: esse nome é da cotação).
  GERADAS = 'geradas'.freeze
  PENDENTES = 'pendentes'.freeze
  TENTATIVAS = 'tentativas'.freeze
  NAO_SAIU = 'nao_saiu'.freeze
  ENVIADAS = 'enviadas'.freeze
  # Quantas chamadas uma seguradora ganha antes de ser desistida: a primeira e UMA repetição. A
  # proposta não consome cotação (repetir não custa dinheiro), mas cada chamada é uma passada de até
  # 60 s com o cliente esperando — e o portal que falhou duas vezes seguidas não vai gerar na terceira.
  MAX_TENTATIVAS = 2
  # A recusa do portal (422) é definitiva: repetir a mesma pergunta traria a mesma resposta.
  DEFINITIVO = 'validation'.freeze

  # O PORTAL NÃO GEROU a proposta desta seguradora: recusou ou falhou. `motivo` é a categoria do
  # conector (`Connector::Error#kind`), nunca a mensagem — ela pode carregar texto do portal.
  class NaoGerada < StandardError
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo.to_s
      super("portal nao gerou a proposta: #{@motivo}")
    end
  end

  private

  # -> o handle do `start`: a PRIMEIRA seguradora pedida, as demais pendentes. Se ela foi a única e o
  # portal a recusou, é recusa nomeada (`proposta_nao_gerada`): nada saiu e nada mais vai sair.
  def iniciar(codigos)
    handle = tentar(handle_inicial(codigos), codigos.first)
    return handle if handle[GERADAS].any? || handle[PENDENTES].any?

    recusa('proposta_nao_gerada', nao_gerada(nomes_de(handle[NAO_SAIU].keys)), faltando: [])
  end

  def handle_inicial(codigos)
    { 'quote_id' => quote_id, 'sufixo' => sufixo_do_arquivo, GERADAS => [], PENDENTES => codigos,
      TENTATIVAS => {}, NAO_SAIU => {}, ENVIADAS => [] }.merge(origem_no_handle)
  end

  # UMA chamada ao portal, para UM código; -> o handle seguinte (novo objeto, nunca o mesmo mutado).
  def tentar(handle, codigo)
    url = proposta(codigo)
    handle.merge(GERADAS => Array(handle[GERADAS]) + [{ 'code' => codigo, 'name' => mapa[codigo].to_s, 'url' => url }],
                 PENDENTES => Array(handle[PENDENTES]) - [codigo])
  rescue NaoGerada => e
    nao_gerou(handle, codigo, e.motivo)
  end

  # Conta a tentativa; recusa definitiva ou tentativas esgotadas tiram o código de `pendentes` e o
  # põem em `nao_saiu`, com o motivo. A divergência (o portal cotou e agora não gera) vai ao log.
  def nao_gerou(handle, codigo, motivo)
    tentativas = handle[TENTATIVAS].to_h[codigo].to_i + 1
    Rails.logger.warn("[autonomia][insurance] portal nao gerou proposta account=#{account.id} seguradora=#{codigo} " \
                      "motivo=#{motivo} tentativa=#{tentativas}")
    proximo = handle.merge(TENTATIVAS => handle[TENTATIVAS].to_h.merge(codigo => tentativas))
    return proximo if motivo != DEFINITIVO && tentativas < MAX_TENTATIVAS

    proximo.merge(PENDENTES => Array(handle[PENDENTES]) - [codigo], NAO_SAIU => handle[NAO_SAIU].to_h.merge(codigo => motivo))
  end

  # -> a URL do PDF daquela seguradora. Levanta `NaoGerada` quando o PORTAL não gerou. O que falha
  # antes da chamada sobe como está: código em branco é defeito nosso (`:protocol`, e nunca vira
  # pedido de comparativo — o adapter sem `insurerCode` devolveria o PDF de TODAS com nome de
  # proposta; verificador cego, A), e a sessão é do `with_fresh_session`, fora do `rescue`.
  def proposta(codigo)
    raise ::Autonomia::Insurance::Connector::Error.new(:protocol, 'codigo de seguradora em branco') if codigo.blank?

    sessions.with_fresh_session { |open_session| pedir_ao_portal(open_session, codigo) }
  end

  # SÓ A CHAMADA AO PORTAL fica sob o `rescue`. `auth_required` sobe como está porque
  # `with_fresh_session` a reconhece: renova a sessão e chama de novo.
  def pedir_ao_portal(open_session, codigo)
    resposta = connector.quote_proposal(provider: connection.provider, session: open_session, quote_id: quote_id,
                                        insurer_code: codigo)
    resposta.to_h['url'].presence || raise(NaoGerada, 'protocol')
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise if e.kind == :auth_required

    raise NaoGerada, e.kind
  end

  # A sessão é a da conexão, reusada (#330); `with_fresh_session` renova se o portal a recusar.
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
end
