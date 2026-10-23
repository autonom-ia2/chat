# Varredura da mídia pendente (#2109): a cada 15 minutos, relê pelo job da chegada (Crm::Ai::LerMidiaJob) o áudio e a
# foto sem texto das mensagens dos últimos 2 dias (Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA). Decisão do Rodrigo
# (23/10/2026): mais velho que isso fica de fora, salvo quando chega mensagem nova na conversa (aí a leitura em linha
# relê).
#
# Pega o anexo sem motivo de falha (`crm_ai_midia_falha`) e com a nova tentativa já vencida:
#   - falha passageira à espera da próxima tentativa (depois das duas do próprio job da chegada);
#   - marcado sem texto antes do #2109, quando toda falha marcava (entra uma vez: a releitura grava o motivo);
#   - conta que passou do teto do dia, ou que ganhou a credencial de IA depois que a mídia chegou.
# Nunca relê o que tem falha definitiva, `expirado` ou texto. O teto do dia vale como sempre: quem conta é o leitor.
#
# Limites: contas com a flag, credencial e caixa com CRM; mensagens não privadas entre JANELA_DE_RELEITURA + MARGEM e
# CARENCIA atrás (o job da chegada ainda pode estar tentando: arquivo subindo, ~4 min; falha passageira, 1 + 5 min). A
# MARGEM dá a última tentativa a quem teve a próxima agendada para o fim da janela: falhou de novo, o leitor marca
# `expirado`. Até MAX_MENSAGENS_POR_CONTA por rodada, as mais novas primeiro.
class Crm::Ai::RelerMidiaPendenteJob < ApplicationJob
  CARENCIA = 15.minutes
  MARGEM = 1.hour
  MAX_MENSAGENS_POR_CONTA = 50
  LOTE = 200
  # Teto de mensagens olhadas por conta numa rodada (a mensagem com mídia além do teto por mensagem nunca é lida e
  # continua candidata até sair da janela).
  MAX_LOTES = 5

  queue_as :scheduled_jobs

  def perform
    Account.where(id: Crm::InboxSetting.where(crm_enabled: true).select(:account_id)).find_each do |account|
      next unless Crm::Ai::LeitorDeMidia.ligada?(account) && Crm::Ai::CredentialResolver.new(account: account).configured?

      ids = pendentes(account)
      Rails.logger.info("[crm][midia] varredura conta=#{account.id} mensagens=#{ids.size}") if ids.any?
      ids.each { |id| Crm::Ai::LerMidiaJob.perform_later(id, 'varredura') }
    end
  end

  private

  # As mais novas primeiro. O filtro final é o `escolhidos` (o teto por mensagem e por tipo): a mensagem cujo anexo sem
  # texto passa do teto (o 4º áudio, a 5ª foto) nunca é lida e não pode ocupar vaga, então o teto da rodada vale depois
  # dele, lote a lote.
  def pendentes(account)
    ids = []
    candidatas(account).in_batches(of: LOTE, order: :desc).each_with_index do |lote, indice|
      # O default_scope de Message ordena por created_at crescente: sem o reorder, o lote volta das mais velhas.
      lote.reorder(id: :desc).each { |mensagem| ids << mensagem.id if Crm::Ai::LeitorDeMidia.new(mensagem, releitura: :varredura).escolhidos.any? }
      break if ids.size >= MAX_MENSAGENS_POR_CONTA || indice + 1 >= MAX_LOTES
    end
    ids.first(MAX_MENSAGENS_POR_CONTA)
  end

  def candidatas(account)
    caixas = Crm::InboxSetting.where(account_id: account.id, crm_enabled: true).select(:inbox_id)
    desde = (Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA + MARGEM).ago
    account.messages.where(private: false, inbox_id: caixas, created_at: desde..CARENCIA.ago)
           .where(Crm::Ai::LeitorDeMidia.com_midia_para_reler)
  end
end
