# A busca dos seguros no conector (E7, #2900). A busca é uma leitura de origem `conector` (Carteira::Leitura), e cada
# registro que volta é um item dela.
#
# Começar:
# - `primeira(account, user:)`: os últimos MESES_DA_PRIMEIRA meses. Termina no Conferir: a pessoa confere e traz, como
#   nos PDFs;
# - `diaria(account)`: os últimos DIAS_DA_DIARIA dias. Entra sozinha (Carteira::Conector::Gravar) e aparece no histórico,
#   com Desfazer;
# - `de_novo(leitura)`: a busca que parou num erro continua de onde estava; a que terminou com alguma seguradora sem
#   vir pede de novo o mesmo período (os registros que já chegaram não se repetem).
# Enquanto uma busca da conta anda, pedir outra DO MESMO TIPO devolve a mesma (a primeira nunca devolve uma de todo dia, e
# vice-versa). A que não anda há PARADA (o processo morreu, o job se perdeu) é retomada ali: a rotina de todo dia não fica
# presa numa busca parada. Sem conexão pronta: `agger_desligado`.
#
# Andar (`passo`, no Carteira::Conector::BuscaJob, que se reagenda com a espera que o passo devolve): UMA chamada ao
# conector por passo, nunca em rajada.
# 1. sem pedido: pede o período (`portfolio_sync_start`);
# 2. pedido buscando: pergunta o andamento (`portfolio_sync_status`) e guarda como cada seguradora está;
# 3. pedido pronto: lê uma página (`portfolio_policies`) e passa para a seguinte;
# 4. sem página seguinte: decide o tipo de cada seguro e termina (`lida`, com os números do Conferir já calculados:
#    Carteira::Conector::Conferir#calcular!; a de todo dia já vai para a gravação).
# O pedido que falhou inteiro (nenhuma seguradora pronta) também termina, sem seguro: a tela diz o que fazer em cada uma.
#
# Erros: o login do Agger recusado (depois da renovação da sessão, que é uma só por operação) para a busca com o motivo
# `agger_pede_login`; o Agger fora do ar ou lento é tentado de novo até TENTATIVAS vezes, e depois para com `agger_falhou`.
# A busca parada (`parou`) volta pelo `de_novo`. No registro, só o id da leitura e a categoria do erro.
class Carteira::Conector::Sincronizar
  MESES_DA_PRIMEIRA = 36
  DIAS_DA_DIARIA = 7
  ESPERA_DO_ANDAMENTO = 1.minute
  ESPERA_DA_PAGINA = 2.seconds
  TENTATIVAS = 3
  PEDE_LOGIN = 'agger_pede_login'.freeze
  FALHOU = 'agger_falhou'.freeze
  DESLIGADO = 'agger_desligado'.freeze
  # A busca que não anda há este tanto (o processo morreu, o job se perdeu) pode ser pedida de novo.
  PARADA = 10.minutes
  # O que a lista de um pedido conta (Carteira::Conector::Ler e o total que o conector informa).
  CONTAS_DA_LISTA = %w[recebidos repetidos ja_lidos ignorados total].freeze

  class << self
    def primeira(account, user:)
      comecar(account, user: user, tipo: Carteira::Leitura::PRIMEIRA)
    end

    def diaria(account)
      comecar(account, user: nil, tipo: Carteira::Leitura::DIARIA)
    end

    def de_novo(leitura)
      recusar(DESLIGADO) unless Carteira::Conector.ligado?(leitura.account)
      pedir = leitura.with_lock do
        recusar('leitura_fechada') unless %w[parou lida lendo].include?(leitura.estado)
        next false if leitura.estado == 'lendo' && leitura.updated_at > PARADA.ago

        totais = totais_de_novo(leitura)
        pedir_o_periodo_de_novo(leitura) if leitura.estado == 'lida'
        leitura.update!(estado: 'lendo', totais: totais)
      end
      Carteira::Conector::BuscaJob.perform_later(leitura.id) if pedir
      leitura
    end

    private

    # A busca parada (ou que não anda há PARADA) continua de onde estava. A que terminou pede o período de novo, e as contas
    # da lista e os números do Conferir recomeçam: cada pedido tem o seu total.
    def totais_de_novo(leitura)
      totais = leitura.totais.to_h.except('parou', 'tentativas').reject { |chave, _| chave.start_with?('motivo_agger') }
      return totais unless leitura.estado == 'lida'

      totais.except(*CONTAS_DA_LISTA).reject { |chave, _| chave.start_with?(Carteira::Conector::Conferir::CHAVE) }
    end

    # Os registros que não deram para trazer voltam na lista nova (o sem referência não tem como ser reconhecido como
    # repetido): saem antes, para não contarem duas vezes.
    def pedir_o_periodo_de_novo(leitura)
      leitura.itens.where(estado: Carteira::Conector::Ler::FALHOU).delete_all
      Carteira::Conector::Pedido.new(leitura).de_novo!
    end

    def comecar(account, user:, tipo:)
      recusar(DESLIGADO) unless Carteira::Conector.ligado?(account)

      andando = Carteira::Leitura.do_conector.where(account_id: account.id, estado: 'lendo')
                                 .where('carteira_leituras.totais ->> ? IS NOT NULL', tipo).order(:id).last
      return retomar(andando) if andando

      leitura = Carteira::Leitura.transaction { criar(account, user, tipo) }
      Carteira::Conector::BuscaJob.perform_later(leitura.id)
      leitura
    end

    # A busca do mesmo tipo que ainda anda é devolvida como está; a que não anda há PARADA volta para a fila.
    def retomar(leitura)
      parada = leitura.with_lock do
        next false unless leitura.estado == 'lendo' && leitura.updated_at <= PARADA.ago

        leitura.update!(updated_at: Time.current)
      end
      Carteira::Conector::BuscaJob.perform_later(leitura.id) if parada
      leitura
    end

    def criar(account, user, tipo)
      hoje = Carteira::Selo.hoje(account)
      desde = tipo == Carteira::Leitura::PRIMEIRA ? hoje - MESES_DA_PRIMEIRA.months : hoje - DIAS_DA_DIARIA.days
      leitura = Carteira::Leitura.create!(account: account, user: user, origem: 'conector', estado: 'lendo', totais: { tipo => 1 })
      Carteira::Conector::Pedido.criar!(leitura, desde: desde, ate: hoje)
      leitura
    end

    def recusar(codigo)
      raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
    end
  end

  def initialize(leitura, portal: nil)
    @leitura = leitura
    @portal = portal || Carteira::Conector::Portal.new(leitura.account)
    @pedido = Carteira::Conector::Pedido.new(leitura)
  end

  # Um passo da busca. Devolve quanto esperar até o próximo, ou nil quando a busca terminou ou parou.
  def passo
    return unless @leitura.estado == 'lendo'

    espera = andar
    zerar_tentativas
    espera
  rescue Autonomia::Insurance::Connector::Error => e
    falhou(e.kind == :auth_required ? PEDE_LOGIN : nil, e.kind)
  rescue Carteira::Conector::Portal::SemConexao
    parar(PEDE_LOGIN)
  end

  private

  def andar
    return pedir unless @pedido.sync_id
    return acompanhar if @pedido.status == 'buscando'
    return ler_pagina if @pedido.status == 'pronta'

    terminar
  end

  def pedir
    resposta = @portal.pedir(desde: @pedido.desde, ate: @pedido.ate)
    sync_id = resposta['sync_id']
    raise Autonomia::Insurance::Connector::Error.new(:protocol, 'pedido sem identificador') if sync_id.blank?

    @pedido.pedido!(sync_id.to_s, status_de(resposta['status']))
    ESPERA_DO_ANDAMENTO
  end

  def acompanhar
    resposta = @portal.andamento(@pedido.sync_id)
    @pedido.andamento!(status_de(resposta['status']), resposta['por_seguradora'])
    tocar
    @pedido.status == 'buscando' ? ESPERA_DO_ANDAMENTO : 0.seconds
  end

  def ler_pagina
    resposta = @portal.apolices(@pedido.sync_id, @pedido.cursor)
    Carteira::Conector::Ler.new(@leitura).pagina(resposta['itens'], ignorados: resposta['ignorados'])
    guardar_total(resposta['total'])
    proximo = resposta['proximo_cursor'].presence
    return terminar unless proximo

    @pedido.proxima_pagina!(proximo.to_s)
    ESPERA_DA_PAGINA
  end

  def terminar
    Carteira::Conector::Ler.new(@leitura).tipos!
    @leitura.reload
    if @leitura.totais.to_h.key?(Carteira::Leitura::DIARIA)
      @leitura.update!(estado: 'trazendo', totais: @leitura.totais.to_h.merge('para_trazer' => lidos))
      Carteira::Conector::GravarJob.perform_later(@leitura.id)
    else
      Carteira::Conector::Conferir.new(@leitura).calcular!
      @leitura.update!(estado: 'lida')
    end
    nil
  end

  # buscando | pronta | falhou. O status que não conhecemos é tratado como falhou: a busca termina e a tela diz o que fazer.
  def status_de(status)
    %w[buscando pronta falhou].include?(status.to_s) ? status.to_s : 'falhou'
  end

  def guardar_total(total)
    return unless total.is_a?(Integer)

    @leitura.reload.update!(totais: @leitura.totais.to_h.merge('total' => total))
  end

  def lidos
    @leitura.itens.where(estado: Carteira::Conector::Ler::LIDO).count
  end

  def tocar
    @leitura.update!(updated_at: Time.current)
  end

  def falhou(motivo, kind)
    Rails.logger.warn("[carteira][conector] leitura=#{@leitura.id} erro=#{kind}")
    return parar(motivo) if motivo

    tentativas = @leitura.reload.totais.to_h['tentativas'].to_i + 1
    return parar(FALHOU) if tentativas >= TENTATIVAS

    @leitura.update!(totais: @leitura.totais.to_h.merge('tentativas' => tentativas))
    ESPERA_DO_ANDAMENTO * tentativas
  end

  def zerar_tentativas
    totais = @leitura.reload.totais.to_h
    @leitura.update!(totais: totais.except('tentativas')) if totais.key?('tentativas')
  end

  # O motivo vai como contagem (`motivo_<código>`), porque `totais` só guarda números.
  def parar(motivo)
    totais = @leitura.reload.totais.to_h.except('tentativas').reject { |chave, _| chave.start_with?('motivo_agger') }
    @leitura.update!(estado: 'parou', totais: totais.merge('parou' => 1, "motivo_#{motivo}" => 1))
    nil
  end
end
