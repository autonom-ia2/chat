# Os números do relatório baixado de Anúncios (#1960), os mesmos da tela no mesmo período: o painel (Panel::Report),
# o tempo de resposta, a lista de quem chegou e as pessoas de cada anúncio (Panel::PathList) e as conversas por dia.
# Com `visible` (Crm::MetaAds::VisibleConversations, #1794) as listas trazem só as conversas que a pessoa já vê; os
# totais são da conta toda, como na tela. Serve à conta conectada (com gasto) e à sem login (só WhatsApp).
class Crm::MetaAds::Relatorio::Dados
  # Linhas da lista de conversas na planilha; o resto fica de fora e a planilha diz quantas.
  LIMITE = 5_000
  # Foto no PDF: no máximo isto de lado, em PNG (o Prawn só lê PNG e JPEG).
  LADO_DA_FOTO = 800
  FOTO_DIRETA = %w[image/png image/jpeg].freeze

  attr_reader :account, :report

  def initialize(connection, days:, account:, visible: nil)
    @account = account
    @visible = visible
    @report = Crm::MetaAds::Panel::Report.new(connection, days: days, account: account)
  end

  def painel
    @painel ||= @report.payload
  end

  def totais
    painel[:totals]
  end

  def anuncios
    painel[:ads]
  end

  def moeda
    painel[:currency]
  end

  def sem_gasto?
    @report.whatsapp_only?
  end

  def zona
    @report.zone
  end

  def dias
    (@report.first_day..@report.today).to_a
  end

  def tempo_de_resposta
    return if @report.cohort.conversation_ads.empty?

    @tempo_de_resposta ||= Crm::MetaAds::Panel::ResponseTime.new(
      account_id: @report.account_id, range: @report.range, starts: @report.cohort.starts
    ).payload
  end

  # { step:, days:, total:, items: [...] } de todas as conversas de anúncio do período.
  def conversas
    @conversas ||= lista(limit: LIMITE)
  end

  def pessoas(ad_id, limite)
    lista(ad_id: ad_id, limit: limite)
  end

  # Quem chegou e ainda não teve resposta, a espera mais longa primeiro: { total:, items: (até `limite`) }.
  def sem_resposta(limite)
    @sem_resposta ||= Crm::MetaAds::Panel::PathList.new(nil, step: 'slow_replies', days: @report.days, visible: @visible,
                                                             report: @report, limit: LIMITE).payload[:items]
                                                   .select { |item| item[:answered] == false }
    { total: @sem_resposta.size, items: @sem_resposta.first(limite) }
  end

  # Conversas de cada dia do período, de um anúncio, no fuso da conta.
  def por_dia(ad_id)
    contagem = @report.cohort.touches.values.select { |ad, _at| ad == ad_id }.map { |_ad, at| at.in_time_zone(zona).to_date }.tally
    dias.map { |dia| contagem.fetch(dia, 0) }
  end

  # PNG ou JPEG da foto guardada do anúncio, ou nil.
  def foto(ad_id)
    objeto = objetos[ad_id]
    return unless objeto&.image&.attached?

    blob = objeto.image.blob
    return blob.download if FOTO_DIRETA.include?(blob.content_type) && blob.byte_size <= Crm::MetaAds::ReferralImageJob::MAX_BYTES

    objeto.image.variant(format: :png, resize_to_limit: [LADO_DA_FOTO, LADO_DA_FOTO]).processed.download
  rescue ActiveStorage::Error, ImageProcessing::Error, Vips::Error => e
    Rails.logger.info("Crm::MetaAds::Relatorio::Dados sem foto account=#{@account.id} ad=#{ad_id}: #{e.class.name}")
    nil
  end

  private

  def lista(**scope)
    Crm::MetaAds::Panel::PathList.new(nil, step: 'conversations', days: @report.days, visible: @visible, report: @report,
                                           **scope).payload
  end

  def objetos
    @objetos ||= Crm::MetaAdObject.where(account_id: @account.id, meta_object_id: anuncios.pluck(:ad_id))
                                  .with_attached_image.index_by(&:meta_object_id)
  end
end
