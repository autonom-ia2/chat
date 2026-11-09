# A campanha da vez num gatilho recorrente de card ou contato (#2414 G55, exemplo 16, passo 2: "para cada card perdido"
# põe a etiqueta, e a campanha sai uma vez "para todos com essa etiqueta").
#
# O card.recorrente abre uma execução por card, e cada uma passa pelo passo campanha. A campanha não é do card, é da
# ocorrência (a "vez": todo dia 1º, toda segunda): a primeira execução que chega cria a campanha da tela, agendada para
# daqui a JUNTAR; cada execução seguinte da mesma vez entra nela e empurra a saída para JUNTAR depois de si. A campanha
# sai pelo agendador das campanhas (TriggerScheduledItemsJob, o mesmo da tela) quando a vez para de juntar gente, e o
# envio lê o público (as etiquetas) nessa hora: entram todos os cards da vez que já passaram pelo passo de etiqueta.
#
# Uma só por automação, passo e vez, mesmo com as execuções correndo juntas em vários processos: a trava de transação do
# Postgres na chave da vez serializa quem procura e quem cria; a marca no Redis cobre o instante entre criar e o
# Executor gravar o registro do passo, e o registro (durável) cobre o Redis que perdeu a marca.
#
# A execução que chega depois de a campanha sair (a vez ficou mais de JUNTAR parada no meio) não cria outra: a nova iria
# de novo para todos com a etiqueta, inclusive quem já recebeu. Ela pula com `campanha_da_vez_ja_saiu`, no histórico.
class Autonomia::Automacao::CampanhaDaOcorrencia
  JUNTAR = 15.minutes
  VALIDADE_DA_MARCA = 2.days

  # `ocorrencia`: a marca da vez (Gatilhos.ocorrencia_da_marca).
  def initialize(execucao:, passo_id:, ocorrencia:)
    @execucao = execucao
    @conta = execucao.account
    @passo_id = passo_id
    @ocorrencia = ocorrencia
  end

  # [campanha, :nova | :junta | :ja_saiu]. `criar` recebe a hora da saída e devolve a campanha criada (create!).
  def juntar(&criar)
    ::Campaign.transaction do
      travar
      campanha = existente
      next [nova(criar), :nova] if campanha.nil?
      next [campanha, :ja_saiu] unless campanha.active?

      campanha.update!(scheduled_at: saida)
      [campanha, :junta]
    end
  end

  private

  def chave = "automacao:campanha_da_vez:#{@execucao.automacao_id}:#{@passo_id}:#{@ocorrencia}"

  def saida = Time.current + JUNTAR

  def travar
    sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', chave])
    ActiveRecord::Base.connection.execute(sql)
  end

  def nova(criar)
    criar.call(saida).tap { |campanha| Redis::Alfred.set(chave, campanha.id, ex: VALIDADE_DA_MARCA.to_i) }
  end

  def existente
    id = Redis::Alfred.get(chave)
    (id && @conta.campaigns.find_by(id: id)) || da_vez_no_registro
  end

  # A campanha que outra execução desta vez já gravou no registro do passo.
  def da_vez_no_registro
    padrao = "#{ActiveRecord::Base.sanitize_sql_like(@ocorrencia)}:%"
    display_id = ::Autonomia::Automacao::Registro.joins(:execucao)
                                                 .where(automacao_id: @execucao.automacao_id, passo: @passo_id, resultado: 'ok')
                                                 .where('autonomia_automacao_execucoes.evento LIKE ?', padrao)
                                                 .pick(Arel.sql("autonomia_automacao_registros.dados ->> 'campanha_id'"))
    display_id && @conta.campaigns.find_by(display_id: display_id)
  end
end
