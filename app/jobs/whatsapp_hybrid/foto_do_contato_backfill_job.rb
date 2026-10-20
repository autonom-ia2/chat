# A foto dos contatos que já conversavam antes da foto do Híbrido existir (#1934, backfill). OK do Rodrigo em 20/10 para
# as caixas 2 e 61 da stack Hub2You; por isso só roda nas caixas listadas em WHATSAPP_HYBRID_FOTO_BACKFILL_INBOX_IDS
# (ex.: "2,61"; vazio = desligado). Caixa híbrida nova não entra sozinha: entra quando alguém a põe na lista.
# - Roda a cada 15 minutos (config/schedule.yml). Por caixa: a sessão em uso pelo Híbrido
#   (WhatsappHybrid::FotoDoContato.sessao_pronta?), a conta com a flag e o motor dizendo que a sessão está funcionando
#   AGORA (uma consulta de estado por rodada). Sessão caída ou instável espera a próxima rodada.
# - Percorre os contatos com conversa na caixa, sem foto e com telefone, do mais novo para o mais antigo, com um cursor
#   no Redis: cada rodada continua de onde a anterior parou, e quem já tem marca da busca ao vivo é pulado sem travar a
#   fila. São duas voltas; ao fim da segunda, a caixa fica marcada como feita (para refazer: apagar as chaves da caixa,
#   FEITO, VOLTA e CURSOR).
# - Devagar, para o número não ser bloqueado (pedido do Rodrigo, 20/10): no máximo LOTE por rodada, com 1 a 2 minutos
#   entre uma consulta e outra (intervalo irregular), e só enquanto a sessão fez menos de TETO_DO_BACKFILL consultas no
#   dia, somando o ao vivo. São até 12 por hora e 80 por dia: a caixa 2 (~470 contatos) leva uma semana. Erro do motor
#   pausa a sessão por 1 hora (WhatsappHybrid::FotoDoContato), e o backfill respeita a pausa.
class WhatsappHybrid::FotoDoContatoBackfillJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 3
  ESPACO = 90.seconds
  FOLGA = 30
  TETO_DO_BACKFILL = 80
  VARREDURA = 500
  FEITO = 'whatsapp_hybrid:foto_do_contato:backfill_feito:'.freeze
  CURSOR = 'whatsapp_hybrid:foto_do_contato:backfill_cursor:'.freeze
  VOLTA = 'whatsapp_hybrid:foto_do_contato:backfill_segunda_volta:'.freeze

  def self.caixas
    ENV.fetch('WHATSAPP_HYBRID_FOTO_BACKFILL_INBOX_IDS', '').split(',').map(&:strip).reject(&:empty?).map(&:to_i)
  end

  def perform
    return if self.class.caixas.empty?

    WhatsappHybrid::Connection.where(inbox_id: self.class.caixas, status: 'connected').find_each do |connection|
      rodada(connection)
    rescue StandardError => e
      Rails.logger.error("[whatsapp_hybrid] foto do contato (backfill) inbox=#{connection.inbox_id} #{e.class}")
    end
  end

  private

  def rodada(connection)
    vagas = vagas_hoje(connection)
    return unless vagas.positive? && pronta?(connection)

    contatos, fim = proximos(connection, [vagas, LOTE].min)
    contatos.each_with_index do |contact_id, indice|
      WhatsappHybrid::FotoDoContatoJob.set(wait: (ESPACO * indice) + rand(FOLGA).seconds).perform_later(contact_id, connection.inbox_id)
    end
    fim_da_volta(connection) if fim
  end

  # Duas voltas: a segunda pega quem ficou sem consulta na primeira (sem vaga na sessão, contato adiado que já venceu).
  def fim_da_volta(connection)
    volta = "#{VOLTA}#{connection.inbox_id}"
    return ::Redis::Alfred.set("#{FEITO}#{connection.inbox_id}", 1) if ::Redis::Alfred.exists?(volta)

    ::Redis::Alfred.set(volta, 1)
    ::Redis::Alfred.delete("#{CURSOR}#{connection.inbox_id}")
  end

  def vagas_hoje(connection)
    return 0 if ::Redis::Alfred.exists?("#{FEITO}#{connection.inbox_id}")

    TETO_DO_BACKFILL - WhatsappHybrid::FotoDoContato.consultas_hoje(connection.session_name)
  end

  def pronta?(connection)
    connection.account.feature_enabled?(WhatsappHybrid::FotoDoContato::FLAG) &&
      WhatsappHybrid::FotoDoContato.sessao_pronta?(connection) && sessao_funcionando?(connection)
  end

  def sessao_funcionando?(connection)
    Waha::Client.new.get_session(connection.session_name, timeout: WhatsappHybrid::FotoDoContato::TIMEOUT).to_h['status'] == 'WORKING'
  end

  # Até `quantos` contatos sem marca, a partir do cursor (ids decrescentes). Devolve [ids, chegou_ao_fim].
  def proximos(connection, quantos)
    chave = "#{CURSOR}#{connection.inbox_id}"
    ids = candidatos(connection, ::Redis::Alfred.get(chave))
    escolhidos = []
    ultimo = ids.find do |id|
      escolhidos << id unless ::Redis::Alfred.exists?(WhatsappHybrid::FotoDoContato.chave_do_contato(id))
      escolhidos.size >= quantos
    end
    ::Redis::Alfred.set(chave, ultimo || ids.last) if ids.any?
    [escolhidos, ultimo.nil? && ids.size < VARREDURA]
  end

  def candidatos(connection, cursor)
    da_caixa = Conversation.where(inbox_id: connection.inbox_id).where('conversations.contact_id = contacts.id')
    escopo = Contact.where(account_id: connection.account_id).where.not(phone_number: [nil, ''])
                    .where.missing(:avatar_attachment).where(da_caixa.arel.exists)
    escopo = escopo.where('contacts.id < ?', cursor.to_i) if cursor.present?
    escopo.order(id: :desc).limit(VARREDURA).pluck(:id)
  end
end
