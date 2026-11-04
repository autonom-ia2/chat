# IA cuida dos comentários em Agentes (#2479): os anúncios do "Qual post?" ao criar o cuidado. São os mesmos da lista
# de Anúncios (Crm::MetaAds::Panel::Report, primeiro os que trazem conversa, depois os outros), dos últimos 30 dias, e
# saem só do banco: abrir o "Qual post?" não lê a Meta nem pede leitura, para não gastar o limite que o motor dos
# comentários usa na mesma conexão. As redes e a caixa de cada anúncio só se sabem no criativo, lido ao abrir o
# cuidado dele (Anuncio): é lá que o anúncio sem post numa rede ligada, ou sem a caixa, se explica.
#
# Cada anúncio diz o estado do cuidado dele (`on`, `paused` ou nil), para o "Qual post?" mostrar o que já é cuidado.
class Crm::MetaAds::ComentariosIa::AnunciosParaCuidar
  PERIODO = '30d'.freeze

  def initialize(connection)
    @connection = connection
  end

  def lista
    linhas = report.ads + report.other_ads
    estados = estados_do_cuidado(linhas.pluck(:ad_id))
    linhas.map do |linha|
      { id: linha[:ad_id], name: linha[:name], image_url: linha[:image_url] || linha[:thumbnail_url], care: estados[linha[:ad_id]] }
    end
  end

  private

  def report
    @report ||= Crm::MetaAds::Panel::Report.new(@connection, period: PERIODO)
  end

  def estados_do_cuidado(ad_ids)
    Crm::MetaAdsCommentCare.where(account_id: @connection.account_id, target_kind: 'ad', target_id: ad_ids)
                           .pluck(:target_id, :status).to_h
  end
end
