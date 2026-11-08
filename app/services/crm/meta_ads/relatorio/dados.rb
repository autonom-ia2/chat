# Os números do relatório baixado de Anúncios (#1960), os mesmos da tela no mesmo período: o painel (Panel::Report),
# o tempo de resposta, a lista de quem chegou e as pessoas de cada anúncio (Panel::PathList) e as conversas por dia.
# Com `visible` (Crm::MetaAds::VisibleConversations, #1794) as listas trazem só as conversas que a pessoa já vê; os
# totais são da conta toda, como na tela. Serve à conta conectada (com gasto) e à sem login (só WhatsApp).
# Sem `com_pessoas` (quem não pode exportar o CRM, crm_export: dado pessoal em lote) o arquivo leva só os números,
# sem as listas de pessoas. Os valores de venda em R$ seguem a mesma pessoa (#2075): sem `sales_value_view`, o painel
# vem sem o dinheiro dos cards (Panel::SalesValue) e o arquivo tira as colunas e linhas de valor (`valores?`).
class Crm::MetaAds::Relatorio::Dados
  # Linhas da lista de conversas na planilha; o resto fica de fora e a planilha diz quantas.
  LIMITE = 5_000
  # Foto no PDF: no máximo isto de lado, em PNG (o Prawn só lê PNG e JPEG).
  LADO_DA_FOTO = 800

  attr_reader :account, :report

  def initialize(connection, account:, period: nil, visible: nil, com_pessoas: true)
    @account = account
    @visible = visible
    @com_pessoas = com_pessoas
    @report = Crm::MetaAds::Panel::Report.new(connection, period: period, account: account, visible: visible)
  end

  def com_pessoas?
    @com_pessoas
  end

  def valores?
    Crm::MetaAds::Panel::SalesValue.visible?(@visible)
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
    (@report.first_day..@report.last_day).to_a
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
    @sem_resposta ||= Crm::MetaAds::Panel::PathList.new(nil, step: 'slow_replies', visible: @visible, report: @report,
                                                             limit: LIMITE).payload[:items]
                                                   .select { |item| item[:answered] == false }
    { total: @sem_resposta.size, items: @sem_resposta.first(limite) }
  end

  # Conversas de cada dia do período, de um anúncio, no fuso da conta.
  def por_dia(ad_id)
    contagem = contagem_por_anuncio.fetch(ad_id, {})
    dias.map { |dia| contagem.fetch(dia, 0) }
  end

  # PNG da foto guardada do anúncio, ou nil. Toda foto passa pelo libvips (mesmo PNG e JPEG): ele decodifica a
  # imagem inteira, então arquivo corrompido falha aqui, onde vira "sem foto", e não no meio do PDF.
  # A mesma foto sai na capa e na página do anúncio: processa uma vez.
  def foto(ad_id)
    @fotos ||= {}
    @fotos.fetch(ad_id) { @fotos[ad_id] = foto_processada(ad_id) }
  end

  private

  # { ad_id => { dia => conversas } }, contado uma vez para todos os anúncios (o período inteiro pode ter meses).
  def contagem_por_anuncio
    @contagem_por_anuncio ||= @report.cohort.touches.values.group_by(&:first).transform_values do |toques|
      toques.map { |_ad, at| at.in_time_zone(zona).to_date }.tally
    end
  end

  def foto_processada(ad_id)
    objeto = objetos[ad_id]
    return unless objeto&.image&.attached?

    objeto.image.variant(format: :png, resize_to_limit: [LADO_DA_FOTO, LADO_DA_FOTO]).processed.download
  rescue LoadError => e
    sem_libvips(ad_id, e)
  rescue ActiveStorage::Error, ImageProcessing::Error, Vips::Error => e # depois do LoadError: sem a libvips, Vips nem existe
    sem_foto(ad_id, e)
  end

  def sem_foto(ad_id, erro)
    Rails.logger.info("Crm::MetaAds::Relatorio::Dados sem foto account=#{@account.id} ad=#{ad_id}: #{erro.class.name}")
    nil
  end

  # A imagem de produção e o CI têm a libvips; faltar em produção é defeito de imagem (avisa), fora dela o PDF sai
  # com o bloco de cor no lugar da foto.
  def sem_libvips(ad_id, erro)
    ChatwootExceptionTracker.new(erro).capture_exception if Rails.env.production?
    sem_foto(ad_id, erro)
  end

  def lista(**scope)
    Crm::MetaAds::Panel::PathList.new(nil, step: 'conversations', visible: @visible, report: @report, **scope).payload
  end

  def objetos
    @objetos ||= Crm::MetaAdObject.where(account_id: @account.id, meta_object_id: anuncios.pluck(:ad_id))
                                  .with_attached_image.index_by(&:meta_object_id)
  end
end
