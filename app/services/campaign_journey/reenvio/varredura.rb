# #3101: a varredura do "Mandar de novo" (CampaignJourney::ReenvioVarreduraJob, a cada 15 minutos). Para cada reenvio
# aguardando:
# 1. A primeira não existe mais (a linha ficou órfã: a tabela é polimórfica e não tem chave) ou foi cancelada:
#    cancelado.
# 2. Ainda sem hora: quando a primeira termina, grava `reenvio_em` = último envio + dias. Ninguém recebeu: sem_ninguem.
# 3. Na hora: cria a campanha da segunda mensagem só com quem sobrou (CampaignJourney::Reenvio::QuemRecebe e
#    SegundaCampanha) e grava enviado com a campanha nova; ninguém sobrou: sem_ninguem. Recusada pelo criador do canal:
#    falhou, com o motivo no log (a campanha e o público novos voltam junto).
# Cada reenvio na trava da sua linha, para duas varreduras nunca criarem duas campanhas. Um erro inesperado num reenvio
# vai para o log e não para os outros; ele continua aguardando e volta na próxima varredura.
class CampaignJourney::Reenvio::Varredura
  Reenvio = CampaignJourney::Reenvio
  RECUSAS = [CampaignJourney::CreatorError, CampaignJourney::AudienceCampaignCreator::Error, CampaignJourney::AudienceWriter::Error,
             CampaignJourney::Reenvio::Invalido].freeze

  def self.rodar(agora: Time.current)
    Autonomia::CampanhaOpcoesDeEnvio.where(reenvio_status: Reenvio::AGUARDANDO)
                                    .where('reenvio_em IS NULL OR reenvio_em <= ?', agora).find_each do |opcoes|
      new(opcoes, agora: agora).rodar
    rescue StandardError => e
      Rails.logger.error("[CampaignJourney::Reenvio] opcoes=#{opcoes.id} #{e.class.name}: #{e.message}")
    end
  end

  def initialize(opcoes, agora:)
    @opcoes = opcoes
    @agora = agora
  end

  def rodar
    @opcoes.with_lock { decidir if @opcoes.reenvio_status == Reenvio::AGUARDANDO }
  rescue *RECUSAS => e
    Rails.logger.warn("[CampaignJourney::Reenvio] opcoes=#{@opcoes.id} falhou: #{e.class.name} #{e.message}")
    fechar(Reenvio::FALHOU)
  end

  private

  def decidir
    campanha = @opcoes.campanha
    return fechar(Reenvio::CANCELADO) if campanha.nil?

    quem = Reenvio::QuemRecebe.new(campanha, @opcoes.reenvio_quem)
    return fechar(Reenvio::CANCELADO) if quem.cancelada?
    return unless na_hora?(quem)

    nova = Reenvio::SegundaCampanha.new(campanha, @opcoes).criar!(quem.contact_ids)
    return fechar(Reenvio::SEM_NINGUEM) if nova.nil?

    @opcoes.update!(reenvio_status: Reenvio::ENVIADO, reenvio_campanha: nova)
  end

  def na_hora?(quem)
    return @opcoes.reenvio_em <= @agora if @opcoes.reenvio_em
    return false unless quem.terminou?

    fim = quem.fim
    if fim.nil?
      fechar(Reenvio::SEM_NINGUEM)
      return false
    end

    @opcoes.update!(reenvio_em: fim + @opcoes.reenvio_dias.days)
    @opcoes.reenvio_em <= @agora
  end

  # Sem validar a linha: a campanha dela pode não existir mais.
  def fechar(status)
    @opcoes.update_columns(reenvio_status: status, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
