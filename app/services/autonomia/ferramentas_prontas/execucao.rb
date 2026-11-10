# A EXECUÇÃO DE UMA FERRAMENTA PRONTA (#2858, F0): o lugar do `HttpExecutor` quando a ferramenta aponta para uma fonte
# do catálogo. Roda no turno (síncrona) ou no `HttpAssincronaJob` (consulta em segundo plano, #2749), com o mesmo
# contrato: `call` devolve o texto que o modelo lê.
#
# A ordem, e o que cada passo grava no contador do dia (`Uso`):
#   1. flag e fonte: sem a flag, "não consegui" e nada gravado (a conta volta ao que era);
#   2. o acesso da conta (a chave do "Incluir") e o corte individual -> `recusadas`;
#   3. a consulta e os parâmetros, normalizados; o que não serve -> `recusadas`, e nenhuma fonte é chamada;
#   4. o limite do dia, por SQL atômico -> conta a consulta, ou `recusadas` (`limite_diario`);
#   5. o cache (validade da consulta) -> `do_cache`;
#   6. os provedores em ordem, com o prazo total da consulta: o principal, depois a reserva. Cada falha vira motivo
#      (`brasilapi.tempo_esgotado`). Responde quem vier primeiro; vindo da reserva -> `pela_reserva`. Sem resposta de
#      ninguém -> `sem_resposta`, e o modelo lê "não consegui consultar agora".
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

  PREFIXO = '[autonomia][pronta]'.freeze
  VERSAO_DO_CACHE = 'v1'.freeze

  def initialize(tool:, params: {})
    @tool = tool
    @argumentos = params.to_h.deep_stringify_keys
    @fonte = Autonomia::FerramentasProntas::Catalogo.buscar(tool.fonte_pronta)
    @inicio = ClienteHttp.agora
  end

  def call
    executar
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @tool.account).capture_exception
    terminar(Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: ['defeito'])
  end

  # O pedido saiu para alguma fonte? (O contrato do `HttpExecutor`, que o job da consulta em segundo plano lê.)
  def enviada?
    @cliente.present? && @cliente.chamadas.positive?
  end

  private

  def executar
    return desligada unless @fonte && Autonomia::FerramentasProntas.ligada?(@tool.account)

    acesso = Acesso.find_by(account_id: @tool.account_id, fonte: @fonte.chave)
    return recusar('sem_acesso') if acesso.nil?
    return recusar('cortada') if acesso.cortada?

    pedido(acesso)
  end

  # A consulta e os parâmetros (nada é contado no limite quando o pedido não serve), o limite, o cache e as fontes.
  def pedido(acesso)
    @consulta = @fonte.consulta(@argumentos[Autonomia::FerramentasProntas::Fonte::PARAMETRO_DA_CONSULTA])
    return recusar('pedido_invalido', Resposta.pedido_invalido('consulta')) if @consulta.nil?

    params, campo = @consulta.conferir(@argumentos)
    return recusar('pedido_invalido', Resposta.pedido_invalido(campo)) if params.nil?
    return recusar('limite_diario') unless Uso.reservar!(account_id: @tool.account_id, fonte: @fonte.chave, limite: acesso.limite_do_dia)

    do_cache(params) || consultar(params)
  end

  def do_cache(params)
    dados = Rails.cache.read(chave_do_cache(params))
    return if dados.nil?

    @provedor = 'cache'
    terminar(Resposta.encontrado(@fonte, @consulta, dados), desfecho: 'do_cache')
  end

  def consultar(params)
    @cliente = ClienteHttp.new(hosts: @fonte.hosts, prazo_final: @inicio + @consulta.prazo_total)
    aplicaveis = @consulta.provedores.select { |provedor| provedor.aplica?(@consulta, params) }
    falhas = []
    nao_encontrado = false
    aplicaveis.each do |provedor|
      dados = provedor.new(@cliente, prazo: @consulta.prazo_por_fonte).consultar(@consulta, params)
      return achado(params, dados, provedor, reserva: provedor != aplicaveis.first, falhas: falhas)
    rescue Provedor::NaoEncontrado
      nao_encontrado = true
    rescue Provedor::Falha => e
      falhas << "#{provedor.nome}.#{e.motivo}"
      break if e.motivo == 'prazo_total'
    end
    nada(nao_encontrado, falhas)
  end

  def achado(params, dados, provedor, reserva:, falhas:)
    Rails.cache.write(chave_do_cache(params), dados, expires_in: @consulta.validade)
    @provedor = provedor.nome
    terminar(Resposta.encontrado(@fonte, @consulta, dados), desfecho: reserva ? 'pela_reserva' : nil, motivos: falhas)
  end

  def nada(nao_encontrado, falhas)
    return terminar(Resposta.nao_encontrado(@fonte, @consulta), desfecho: 'nao_encontradas', motivos: falhas) if nao_encontrado

    terminar(Resposta.nao_consegui, desfecho: 'sem_resposta', motivos: falhas.presence || ['sem_provedor'])
  end

  # Sem a flag (desligada depois de a consulta abrir) ou com a fonte fora do catálogo: nada é gravado.
  def desligada
    registrar('desligada', [])
    Resposta.nao_consegui
  end

  def recusar(motivo, texto = Resposta.nao_consegui)
    terminar(texto, desfecho: 'recusadas', motivos: [motivo])
  end

  def terminar(texto, desfecho:, motivos: [])
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
  end

  def registrar(desfecho, motivos)
    campos = { conta: @tool.account_id, agente: @tool.autonomia_agent_id, ferramenta: @tool.id, fonte: @fonte&.chave,
               consulta: @consulta&.nome, desfecho: desfecho, provedor: @provedor, chamadas: @cliente&.chamadas.to_i,
               ms: ((ClienteHttp.agora - @inicio) * 1000).round, motivos: motivos.presence&.join(',') }
    Rails.logger.info("#{PREFIXO} #{campos.map { |nome, valor| "#{nome}=#{valor.nil? ? '-' : valor}" }.join(' ')}")
  end

  # O cache é da fonte, não da conta: o dado é público e igual para todas (o mesmo CEP tem o mesmo endereço). A chave
  # leva o resumo dos parâmetros, não o CEP ou o CNPJ em claro.
  def chave_do_cache(params)
    resumo = Digest::SHA256.hexdigest(@consulta.chave_do_cache(params).to_json)
    "autonomia:prontas:#{VERSAO_DO_CACHE}:#{@fonte.chave}:#{@consulta.nome}:#{resumo}"
  end
end
