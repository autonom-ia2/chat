# Varredura da mídia pendente (#2109): a cada 15 minutos, relê pelo job da chegada (Crm::Ai::LerMidiaJob.reler, fila
# low) o áudio e a foto sem texto das mensagens dos últimos 2 dias (Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA). Decisão
# do Rodrigo (23/10/2026): mais velho que isso fica de fora, salvo quando chega mensagem nova na conversa (aí a leitura
# em linha relê).
#
# Pega o anexo sem motivo de falha (`crm_ai_midia_falha`) e com a nova tentativa já vencida:
#   - falha passageira à espera da próxima tentativa (depois das duas do próprio job da chegada);
#   - marcado sem texto antes do #2109, quando toda falha marcava (entra uma vez: a releitura grava o motivo);
#   - conta que passou do teto do dia, ou que ganhou a credencial de IA depois que a mídia chegou.
# Nunca relê o que tem falha definitiva, `expirado` ou texto.
#
# Limites (revisão de banco):
#   - a consulta começa pelas mensagens da conta na janela, pelo índice (account_id, created_at), em lotes de LOTE, e
#     só depois procura a mídia sem texto nos anexos DESSES ids (índice de message_id). Nunca varre attachments inteira
#     nem messages inteira; no máximo MAX_LOTES lotes por conta numa rodada;
#   - até MAX_MENSAGENS_POR_CONTA por rodada, e só enquanto a conta gastou menos que FRACAO_DO_TETO do teto do dia: a
#     releitura de mídia antiga não tira a vez da mídia nova;
#   - a mesma mensagem não é enfileirada de novo enquanto a anterior pode estar na fila (LerMidiaJob.reler);
#   - só as mensagens de entrada (as do cliente): o índice (account_id, created_at, message_type) já cobre o filtro;
#   - os MAX_LOTES lotes acabaram antes do fim da janela (conta com muita mensagem): aviso no log com a data até onde
#     chegou, para medir; a mídia mais velha fica para a mensagem nova da conversa;
#   - uma conta que falha (consulta que estoura o statement_timeout, banco ou Redis fora do ar) é pulada com
#     aviso no log (classe do erro e id da conta, sem dado de cliente) e no rastreador de erros; a rodada segue nas outras.
# CARENCIA: o job da chegada ainda pode estar tentando (arquivo subindo, ~4 min; falha passageira, 1 + 5 min). MARGEM:
# a última tentativa de quem teve a próxima agendada para o fim da janela (falhou de novo: o leitor marca `expirado`).
class Crm::Ai::RelerMidiaPendenteJob < ApplicationJob
  CARENCIA = 15.minutes
  MARGEM = 1.hour
  MAX_MENSAGENS_POR_CONTA = 25
  FRACAO_DO_TETO = 0.5
  LOTE = 500
  MAX_LOTES = 10
  # O que derruba a varredura de UMA conta: tempo esgotado e infraestrutura fora do ar. Lista fechada: erro de programação
  # (SQL inválido, registro que sumiu, NoMethodError) sobe e aparece.
  FALHAS_DA_CONTA = [ActiveRecord::QueryCanceled, ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError,
                     Redis::BaseError, RedisClient::Error, ConnectionPool::TimeoutError].freeze

  queue_as :scheduled_jobs

  def perform
    Account.where(id: Crm::InboxSetting.where(crm_enabled: true).select(:account_id)).find_each { |account| varrer(account) }
  end

  private

  def varrer(account)
    return unless Crm::Ai::LeitorDeMidia.ligada?(account) && Crm::Ai::CredentialResolver.new(account: account).configured?

    vagas = [MAX_MENSAGENS_POR_CONTA, cota_do_dia(account)].min
    return if vagas <= 0

    ids = pendentes(account, vagas).select { |id| Crm::Ai::LerMidiaJob.reler(id, 'varredura') }
    Rails.logger.info("[crm][midia] varredura conta=#{account.id} mensagens=#{ids.size}") if ids.any?
  rescue *FALHAS_DA_CONTA => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    Rails.logger.warn("[crm][midia] varredura_pulou conta=#{account.id} erro=#{e.class}")
  end

  def cota_do_dia(account)
    (Crm::Ai::LeitorDeMidia::MAX_LEITURAS_POR_DIA * FRACAO_DO_TETO).floor - Crm::Ai::TetoDaMidia.new(account).usado
  end

  # As mais novas primeiro, lote a lote. O filtro final é o `escolhidos` (o teto por mensagem e por tipo): a mensagem
  # cujo anexo sem texto passa do teto (o 4º áudio, a 5ª foto) nunca é lida e não ocupa vaga.
  def pendentes(account, vagas)
    ids = []
    lotes(account) do |lote|
      com_midia = Attachment.where(message_id: lote).merge(Crm::Ai::LeitorDeMidia.midia_para_reler).distinct.pluck(:message_id)
      Message.where(id: com_midia).includes(attachments: { file_attachment: :blob }).reorder(id: :desc).each do |mensagem|
        ids << mensagem.id if Crm::Ai::LeitorDeMidia.new(mensagem, releitura: :varredura).escolhidos.any?
      end
      ids.size >= vagas
    end
    ids.first(vagas)
  end

  # Ids das mensagens da conta na janela, do mais novo para o mais velho, LOTE por vez (cursor por created_at e id).
  # O bloco devolve true para parar.
  def lotes(account)
    cursor = nil
    MAX_LOTES.times do
      pagina = candidatas(account, cursor).limit(LOTE).pluck(:id, :created_at)
      return if pagina.empty? || yield(pagina.map(&:first)) || pagina.size < LOTE

      cursor = pagina.last.reverse
    end
    return unless candidatas(account, cursor).exists?

    Rails.logger.warn("[crm][midia] varredura_cortada conta=#{account.id} lotes=#{MAX_LOTES} ate=#{cursor.first.utc.iso8601}")
  end

  def candidatas(account, cursor)
    caixas = Crm::InboxSetting.where(account_id: account.id, crm_enabled: true).select(:inbox_id)
    janela = (Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA + MARGEM).ago..CARENCIA.ago
    escopo = account.messages.incoming.where(private: false, inbox_id: caixas, created_at: janela)
                    .reorder(created_at: :desc, id: :desc)
    cursor ? escopo.where('(messages.created_at, messages.id) < (?, ?)', *cursor) : escopo
  end
end
