# #2520: o cuidado dos comentários no Facebook só recebe o comentário se a Página manda o `feed` ao app e se a conta
# está em crm_meta_ads_pages (é por ela que o Crm::MetaAds::FacebookFeed acha a conta). Antes, só abrir a aba Facebook
# de um anúncio, com a chave de mudar, fazia as duas coisas; o cuidado ligado pelo Seus posts ou por Agentes ficava sem
# receber nada. Ligar (salvar ou voltar a cuidar) um cuidado de Facebook enfileira este job para cada Página dele.
#
# Usa o token da caixa da Página nesta conta (Channel::FacebookPage). Só soma o campo: os outros da Página ficam como
# estão (Crm::MetaAds::PageSubscription). A Página já assinada não chama a Meta de novo. Erro passageiro tenta de novo
# mais tarde; recusa (token sem permissão) vai ao log e ao rastreador de erros, e o cuidado segue ligado (a aba do
# anúncio ainda assina).
class Crm::MetaAds::ComentariosIa::AssinarFeedJob < ApplicationJob
  queue_as :low

  FEED = %w[feed].freeze
  ATTEMPTS = 3

  # As Páginas de um cuidado de Facebook: a da caixa do post e as dos posts do criativo (o id é `<página>_<post>`). Só
  # com a flag dos comentários do Facebook: sem ela, nada escreve na Página (o anúncio nas duas redes com só a do IG).
  def self.para!(care)
    return unless care&.status == 'on' && %w[facebook both].include?(care.network)
    return unless care.account.feature_enabled?(Crm::MetaAds::FacebookFeed::FLAG)

    paginas(care).each { |page_id| perform_later(care.account_id, page_id) }
  end

  def self.paginas(care)
    dos_posts = Array(care.post_ids).filter_map { |id| id.to_s.split('_').first if id.to_s.include?('_') }
    canal = care.inbox&.channel
    da_caixa = canal.is_a?(Channel::FacebookPage) ? [canal.page_id.to_s] : []
    (dos_posts + da_caixa).uniq
  end

  def perform(account_id, page_id, attempt = 1)
    return if Crm::MetaAdsPage.feed_receiving.exists?(account_id: account_id, page_id: page_id)

    channel = caixa(account_id, page_id)
    return Rails.logger.warn("[#{self.class.name}] account=#{account_id} page=#{page_id} sem caixa com token") if channel.nil?

    assinar!(channel)
  rescue Crm::MetaAds::PageSubscription::Error => e
    return desistir!(e, account_id, page_id) if !e.transient? || attempt >= ATTEMPTS

    self.class.set(wait: (attempt * 30).seconds).perform_later(account_id, page_id, attempt + 1)
  end

  private

  # Recusa (token sem permissão) ou erro passageiro que não passou: o cuidado fica sem receber da Página. Vai ao
  # rastreador de erros, além do log, para alguém ver.
  def desistir!(error, account_id, page_id)
    Rails.logger.warn("[#{self.class.name}] account=#{account_id} page=#{page_id} desistiu: #{error.message}")
    ChatwootExceptionTracker.new(error, account: Account.find_by(id: account_id)).capture_exception
  end

  def caixa(account_id, page_id)
    Channel::FacebookPage.where(account_id: account_id, page_id: page_id).order(:id).reject(&:reauthorization_required?).first
  end

  def assinar!(channel)
    Crm::MetaAds::PageSubscription.new(page_id: channel.page_id, access_token: channel.page_access_token).add!(FEED)
    Crm::MetaAdsPage.remember!(channel.account, [{ 'id' => channel.page_id }]) # sem nome: não troca o já guardado
    Crm::MetaAdsPage.where(account_id: channel.account_id, page_id: channel.page_id)
                    .update_all(feed_receiving: true, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
