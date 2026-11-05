# IA cuida dos comentários em Agentes (#2479): os anúncios do "Qual post?" ao criar o cuidado. São os mesmos da lista
# de Anúncios (Crm::MetaAds::Panel::Report, primeiro os que trazem conversa, depois os outros), dos últimos 30 dias, e
# saem só do banco: abrir o "Qual post?" não lê a Meta nem pede leitura, para não gastar o limite que o motor dos
# comentários usa na mesma conexão. As redes e a caixa de cada anúncio só se sabem no criativo, lido ao abrir o
# cuidado dele (Anuncio): é lá que o anúncio sem post numa rede ligada, ou sem a caixa, se explica.
#
# Cada anúncio diz o estado do cuidado dele (`on`, `paused` ou nil), para o "Qual post?" mostrar o que já é cuidado.
#
# #2519 (3A): e quantos comentários dele esperam o dono (`waiting`, Esperando). Os que esperam vêm primeiro, na ordem de
# Anúncios entre eles; o anúncio que saiu dos 30 dias mas ainda tem comentário esperando entra também, com o nome e a
# miniatura guardados no banco (crm_meta_ad_objects), depois dos de Anúncios que esperam.
class Crm::MetaAds::ComentariosIa::AnunciosParaCuidar
  PERIODO = '30d'.freeze

  def initialize(connection)
    @connection = connection
  end

  def lista
    esperando = Crm::MetaAds::ComentariosIa::Esperando.anuncios_com_espera(@connection.account_id)
    linhas = do_periodo + fora_do_periodo(esperando.keys)
    estados = estados_do_cuidado(linhas.pluck(:id))
    itens = linhas.map { |linha| linha.merge(care: estados[linha[:id]], waiting: esperando.fetch(linha[:id], 0)) }
    esperam, sem_espera = itens.partition { |item| item[:waiting].positive? }
    esperam + sem_espera
  end

  private

  def do_periodo
    @do_periodo ||= (report.ads + report.other_ads).map do |linha|
      { id: linha[:ad_id], name: linha[:name], image_url: linha[:image_url] || linha[:thumbnail_url] }
    end
  end

  def fora_do_periodo(ad_ids)
    ids = ad_ids - do_periodo.pluck(:id)
    return [] if ids.empty?

    guardados = Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: ids).with_attached_image.index_by(&:meta_object_id)
    ids.sort.map do |id|
      guardado = guardados[id]
      { id: id, name: guardado&.name, image_url: guardado&.image_path || guardado&.thumbnail_url }
    end
  end

  def report
    @report ||= Crm::MetaAds::Panel::Report.new(@connection, period: PERIODO)
  end

  def estados_do_cuidado(ad_ids)
    Crm::MetaAdsCommentCare.where(account_id: @connection.account_id, target_kind: 'ad', target_id: ad_ids)
                           .pluck(:target_id, :status).to_h
  end
end
