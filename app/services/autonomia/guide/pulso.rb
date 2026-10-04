# O Guia olhando a conta sozinho, a cada 15 minutos (#935).
#
# Duas camadas, para o repouso custar zero:
# 1. mede as vigias da conta (no máximo 20) com a mesma leitura de `ler_da_conta`, como quem criou cada
#    uma. Se nada cruzou o gatilho, termina aqui: nenhuma chamada a modelo nenhum.
# 2. o que cruzou vai ao Jev numa ida só (`Triagem`) e vira aviso (`Entrega`).
#
# A mesma vigia avisa no máximo uma vez por janela (`ultima_janela`), e o que já avisou nesta janela
# nem chega ao Jev. Leitura que passa de 2 s é pulada neste pulso, com log: o pulso roda para muitas
# contas e não pode ficar preso numa. Um pulso por conta por vez (trava no Redis).
#
# Vigia de quem deixou de ser administrador pausa aqui, e os outros administradores ficam sabendo.
class Autonomia::Guide::Pulso
  LIMITE_DE_LEITURA = 2.0
  ATIVIDADE_DO_ADMIN = 7.days
  TRAVA = 10.minutes.to_i
  # `agora` só antecipa: vários ganchos no mesmo minuto viram um pulso.
  ANTECIPAR_NO_MAXIMO_A_CADA = 1.minute.to_i
  VIGIA = Autonomia::Guide::Vigia

  class << self
    # As contas que o pulso agendado mede: com vigia ligada e um administrador ativo nos últimos 7 dias.
    def contas
      com_vigia = VIGIA.medindo.distinct.pluck(:account_id)
      AccountUser.where(account_id: com_vigia, role: :administrator).where(active_at: ATIVIDADE_DO_ADMIN.ago..)
                 .distinct.pluck(:account_id)
    end

    # Um sinal empurrado (conexão caída, decisão em espera, saúde do WhatsApp): mede já, em vez de
    # esperar o próximo pulso. Nunca levanta: o gancho é de quem chamou.
    def agora(account)
      return if account.nil? || !VIGIA.da_conta(account).medindo.exists?
      return unless Redis::Alfred.set("autonomia:guide:pulso:agora:#{account.id}", 1, nx: true, ex: ANTECIPAR_NO_MAXIMO_A_CADA)

      Autonomia::Guide::PulsoJob.perform_later(account.id)
    rescue StandardError => e
      Rails.logger.warn("[autonomia][guide][pulso] agora account=#{account&.id} #{e.class}: #{e.message}")
    end
  end

  def initialize(account, agora: Time.current, relogio: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @account = account
    @agora = agora
    @relogio = relogio
  end

  def perform
    trava = SecureRandom.hex(8)
    return unless Redis::Alfred.set(chave_da_trava, trava, nx: true, ex: TRAVA)

    begin
      medir_e_avisar
    ensure
      Redis::Alfred.delete_if_equals(chave_da_trava, trava)
    end
  end

  private

  def medir_e_avisar
    entrega.resumir_adiados!
    pausar_orfas
    sinais = medir
    return if sinais.empty?

    veredito = Autonomia::Guide::Triagem.new(account: @account).classificar(sinais)
    sinais.each { |sinal| sinal[:vigia].avisou!(@agora) }
    entrega.avisar!(sinais, veredito) if veredito.avisar
  end

  def entrega
    @entrega ||= Autonomia::Guide::Entrega.new(@account, agora: @agora)
  end

  def chave_da_trava
    "autonomia:guide:pulso:#{@account.id}"
  end

  def administradores
    @administradores ||= @account.administrators.ids
  end

  def pausar_orfas
    VIGIA.da_conta(@account).medindo.where.not(criado_por_id: administradores).or(VIGIA.da_conta(@account).medindo.where(criado_por_id: nil))
         .find_each do |vigia|
      vigia.pausar!(@agora)
      entrega.pausada!(vigia)
    end
  end

  def medir
    VIGIA.da_conta(@account).medindo.includes(:criado_por).order(:id).limit(VIGIA::TETO_POR_CONTA).filter_map do |vigia|
      medir_uma(vigia)
    end
  end

  # O sinal da vigia quando ela cruzou o gatilho e ainda não avisou nesta janela; senão nil.
  def medir_uma(vigia)
    resultado = ler(vigia)
    return if resultado.nil?

    media = vigia.media
    cruzou = vigia.cruzou?(resultado.valor, @agora)
    vigia.medir!(resultado.valor, @agora)
    return unless cruzou && vigia.ultima_janela != vigia.janela(@agora)

    { vigia: vigia, valor: resultado.valor, media: media, item_id: resultado.item_id }
  end

  def ler(vigia)
    resposta, duracao = cronometrar { ler_cru(vigia) }
    return pulada(vigia, "lenta #{duracao.round(2)}s") if duracao > LIMITE_DE_LEITURA
    return pulada(vigia, "http=#{resposta.codigo}") unless resposta.codigo.to_s == '200'

    Autonomia::Guide::Medida.new(vigia.medida).de(JSON.parse(resposta.corpo)) || pulada(vigia, 'sem a medida')
  rescue Autonomia::Guide::Consulta::Recusada, JSON::ParserError => e
    pulada(vigia, e.class.name)
  end

  def ler_cru(vigia)
    Autonomia::Guide::Consulta.new(account: @account, user: vigia.criado_por)
                              .ler_cru(vigia.leitura['rota'], vigia.leitura['parametros'] || {})
  end

  def cronometrar
    comeco = @relogio.call
    resultado = yield
    [resultado, @relogio.call - comeco]
  end

  def pulada(vigia, motivo)
    Rails.logger.info("[autonomia][guide][pulso] account=#{@account.id} vigia=#{vigia.id} pulada: #{motivo}")
    nil
  end
end
