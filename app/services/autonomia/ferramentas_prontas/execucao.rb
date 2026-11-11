# A EXECUÇÃO DE UMA FERRAMENTA PRONTA (#2858, F0): o lugar do `HttpExecutor` quando a ferramenta aponta para uma fonte
# do catálogo. Roda no turno (síncrona) ou no `HttpAssincronaJob` (consulta em segundo plano, #2749), com o mesmo
# contrato: `call` devolve o texto que o modelo lê.
#
# A ordem, e o que cada passo grava no contador do dia (`Uso`):
#   1. flag e fonte: sem a flag, "não consegui" e nada gravado (a conta volta ao que era);
#   2. o acesso da conta (a chave do "Incluir") e o corte individual -> `recusadas`;
#   3. a consulta e os parâmetros, normalizados; o que não serve -> `recusadas`, e nenhuma fonte é chamada;
#   4. o limite do dia, por SQL atômico -> conta a consulta, ou `recusadas` (`limite_diario`);
#   4b. o dado que o cliente diz trocado pelo que a fonte pede (`Consulta#resolver`, regra "QI 70": a marca da FIPE pelo
#      nome), com outras consultas da mesma fonte (`Apoio`); o que não resolve devolve a reserva do limite e vai a
#      `recusadas`, com os candidatos;
#   5. o cache (validade da consulta; o "não encontrado" por 1 hora) -> `do_cache`;
#   6. os provedores em ordem, com o prazo total da consulta: o principal, depois a reserva. Cada falha vira motivo
#      (`brasilapi.tempo_esgotado`). Responde quem vier primeiro; vindo da reserva -> `pela_reserva`. Sem resposta de
#      ninguém, ou uma dizendo "não tem" e outra fora -> `sem_resposta`, e o modelo lê "não consegui consultar agora".
#   A consulta conta no limite do dia mesmo quando vem do cache ou quando a fonte falha: o limite é do uso da conta.
#
# NUNCA LEVANTA: um defeito nosso vai ao rastreador e vira o mesmo "não consegui". A consulta é leitura de dado público,
# sem efeito do lado de lá: repetir não registra nada duas vezes, por isso não existe a consulta "incerta" aqui.
# O log leva conta, agente, fonte, consulta, desfecho, provedor, tempos e motivos; nunca o valor consultado nem o
# endereço (que traz o CEP ou o CNPJ), nem a chave da conta.
class Autonomia::FerramentasProntas::Execucao
  Acesso = Autonomia::FerramentasProntas::Acesso
  Uso = Autonomia::FerramentasProntas::Uso
  Resposta = Autonomia::FerramentasProntas::Resposta
  Provedor = Autonomia::FerramentasProntas::Provedor
  ClienteHttp = Autonomia::FerramentasProntas::ClienteHttp
  Cache = Autonomia::FerramentasProntas::Cache

  PREFIXO = '[autonomia][pronta]'.freeze

  def initialize(tool:, params: {})
    @tool = tool
    @argumentos = params.to_h.deep_stringify_keys
    @fonte = Autonomia::FerramentasProntas::Catalogo.buscar(tool.fonte_pronta)
    @inicio = ClienteHttp.agora
  end

  # O "hoje" das consultas (dias úteis, o ano dos feriados e do Focus, o dia do contador) é o do fuso da conta.
  def call
    Time.use_zone(fuso) do
      executar
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: @tool.account).capture_exception
      terminar(Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: ['defeito'])
    end
  end

  # O desfecho de falha, para o registro da consulta em segundo plano (`pronta_sem_resposta`, `pronta_recusadas`); nil
  # quando a fonte respondeu (encontrado ou não encontrado).
  attr_reader :codigo

  # O pedido saiu para alguma fonte? (O contrato do `HttpExecutor`, que o job da consulta em segundo plano lê.)
  def enviada?
    @cliente.present? && @cliente.chamadas.positive?
  end

  private

  # O fuso da conta; sem ele (defeito ao ler a conta), o da plataforma: a execução nunca levanta.
  def fuso
    ActiveSupport::TimeZone[Crm::Timezone::Resolver.new(account: @tool.account).name_or_default.to_s] || Time.zone
  rescue StandardError => e
    Rails.logger.warn("#{PREFIXO} fuso da conta indisponível conta=#{@tool.account_id} #{e.class}")
    Time.zone
  end

  def executar
    return desligada unless Autonomia::FerramentasProntas.disponivel?(@tool.account, @fonte)

    acesso = Acesso.find_by(account_id: @tool.account_id, fonte: @fonte.chave)
    return recusar('sem_acesso') if acesso.nil?
    return recusar('cortada') if acesso.cortada?

    pedido(acesso)
  end

  # A consulta e os parâmetros (nada é contado no limite quando o pedido não serve, nem quando o resolver o recusa), o
  # limite, o cache e as fontes.
  def pedido(acesso)
    @consulta = @fonte.consulta(@argumentos[Autonomia::FerramentasProntas::Fonte::PARAMETRO_DA_CONSULTA])
    return recusar('pedido_invalido', Resposta.pedido_invalido('consulta', @fonte.parametro_da_consulta)) if @consulta.nil?

    params, falta = @consulta.conferir(@argumentos)
    return recusar_pedido(falta) if params.nil?
    return recusar('limite_diario') unless Uso.reservar!(account_id: @tool.account_id, fonte: @fonte.chave, limite: acesso.limite_do_dia)

    resolvido(params)
  end

  # Depois do limite: o dado do cliente trocado pelo da fonte (o nome da marca pelo código), o cache e as fontes.
  def resolvido(params)
    params, falta = resolver(params)
    return devolver_e_recusar(falta) if falta

    @cache = Autonomia::FerramentasProntas::Cache.new(@fonte, @consulta, params)
    do_cache(params) || consultar(params)
  rescue Autonomia::FerramentasProntas::Apoio::SemResposta => e
    terminar(Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: e.motivos)
  end

  # O resolver olhou só listas (do cache, quase sempre) e recusou: a reserva do limite volta.
  def devolver_e_recusar(falta)
    Uso.devolver!(account_id: @tool.account_id, fonte: @fonte.chave)
    recusar_pedido(falta)
  end

  def recusar_pedido(falta)
    recusar('pedido_invalido', Resposta.pedido_invalido(falta, @consulta.parametro(falta.campo)))
  end

  def resolver(params)
    return [params, nil] unless @consulta.resolve?

    @consulta.resolver(params, Autonomia::FerramentasProntas::Apoio.new(@fonte, cliente))
  end

  def cliente
    @cliente ||= ClienteHttp.new(hosts: @fonte.hosts, prazo_final: @inicio + @consulta.prazo_total, conta: @tool.account_id)
  end

  def do_cache(params)
    guardado = @cache.ler
    return if guardado.nil?

    @provedor = 'cache'
    return terminar(Resposta.nao_encontrado(@fonte, @consulta), desfecho: 'do_cache') if guardado['situacao'] == Cache::NAO_ENCONTRADO

    entregar(guardado['dados'], params, desfecho: 'do_cache')
  end

  def consultar(params)
    aplicaveis = @consulta.provedores.select { |provedor| provedor.aplica?(@consulta, params) }
    falhas = []
    nao_encontrado = false
    aplicaveis.each do |provedor|
      next if pular?(provedor, falhas, nao_encontrado)

      dados = provedor.new(cliente, prazo: @consulta.prazo_por_fonte).consultar(@consulta, @consulta.para_a_fonte(params))
      return achado(params, dados, provedor, reserva: provedor != aplicaveis.first, falhas: falhas)
    rescue Provedor::NaoEncontrado
      nao_encontrado = true
    rescue Provedor::Falha => e
      falhas << "#{provedor.nome}.#{e.motivo}"
    end
    nada(nao_encontrado, falhas)
  end

  # Sem prazo para a rede, só o provedor calculado aqui (o calendário, o plano do DDD, as sedes) ainda responde; e a
  # reserva aproximada não responde depois de um "não tem".
  def pular?(provedor, falhas, nao_encontrado)
    return true if nao_encontrado && !provedor.depois_de_nao_encontrado?

    provedor.host.present? && falhas.any? { |falha| falha.end_with?('.prazo_total') }
  end

  def achado(params, dados, provedor, reserva:, falhas:)
    @cache.encontrado(dados, validade: provedor.validade_da_resposta(dados))
    @provedor = provedor.nome
    entregar(dados, params, desfecho: reserva ? 'pela_reserva' : nil, motivos: falhas)
  end

  # O filtro local roda sobre o que veio da fonte ou do cache. Nada sobrou: não encontrado (sem cache: a lista guardada
  # continua servindo a outras buscas). Se uma fonte falhou antes, a que respondeu pode estar incompleta: "não consegui".
  def entregar(dados, params, desfecho:, motivos: [])
    refinados = @consulta.refinar(dados, params)
    return terminar(Resposta.encontrado(@fonte, @consulta, refinados), desfecho: desfecho, motivos: motivos) if refinados
    return terminar(Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: motivos) if motivos.any?

    terminar(Resposta.nao_encontrado(@fonte, @consulta), desfecho: 'nao_encontradas', motivos: motivos)
  end

  # "Não encontrado" só quando nenhuma fonte falhou: com uma que disse "não tem" e outra fora do ar, o certo é "não
  # consegui consultar" (a que falhou podia ter o registro), e o agente não afirma ao cliente que o CEP não existe.
  def nada(nao_encontrado, falhas)
    if nao_encontrado && falhas.empty?
      @cache.nao_encontrado
      return terminar(Resposta.nao_encontrado(@fonte, @consulta), desfecho: 'nao_encontradas')
    end

    terminar(Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: falhas.presence || ['sem_provedor'])
  end

  # Sem a flag (desligada depois de a consulta abrir) ou com a fonte fora do catálogo: nada é gravado.
  def desligada
    @codigo = 'pronta_desligada'
    registrar('desligada', [])
    Resposta.nao_consegui
  end

  def recusar(motivo, texto = Resposta.nao_consegui)
    terminar(texto, desfecho: 'recusadas', motivos: [motivo])
  end

  def terminar(texto, desfecho:, motivos: [])
    @codigo = "pronta_#{desfecho}" if %w[sem_resposta recusadas].include?(desfecho)
    anotar(desfecho, motivos)
    registrar(desfecho || 'encontrado', motivos)
    texto
  end

  # O contador é cortesia sobre a resposta: falhar aqui não tira o resultado do modelo.
  def anotar(desfecho, motivos)
    return if @fonte.nil?

    Uso.anotar!(account_id: @tool.account_id, fonte: @fonte.chave, desfecho: desfecho, motivos: motivos)
  rescue StandardError => e
    Rails.logger.warn("#{PREFIXO} contador falhou conta=#{@tool.account_id} fonte=#{@fonte&.chave} #{e.class}")
    ChatwootExceptionTracker.new(e, account: @tool.account).capture_exception
  end

  def registrar(desfecho, motivos)
    campos = { conta: @tool.account_id, agente: @tool.autonomia_agent_id, ferramenta: @tool.id, fonte: @fonte&.chave,
               consulta: @consulta&.nome, desfecho: desfecho, provedor: @provedor, chamadas: @cliente&.chamadas.to_i,
               ms: ((ClienteHttp.agora - @inicio) * 1000).round, motivos: motivos.presence&.join(',') }
    Rails.logger.info("#{PREFIXO} #{campos.map { |nome, valor| "#{nome}=#{valor.nil? ? '-' : valor}" }.join(' ')}")
  end
end
