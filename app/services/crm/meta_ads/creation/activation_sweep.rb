# "Teve anúncio" em Seus posts (#2804, parte B da #2739): o post impulsionado por aqui e ligado no Gerenciador da Meta
# ganha a marca sem depender de alguém abrir Anúncios (a lista de pausados, Crm::MetaAds::Creation::PausedAds, só lê os
# LIMIT mais novos). Roda num job de hora em hora (Crm::MetaAds::ActivationSweepJob), nunca na abertura da tela.
#
# Lê na Meta, um a um, os anúncios criados aqui a partir de um post, da conta de anúncios conectada agora, dos últimos
# WINDOW (post mais velho não aparece em Seus posts, e o anúncio nasce depois do post):
# - os que ainda esperam ativar: `status` ACTIVE grava `activated_at`, como o Ativar daqui e a lista de pausados;
# - os do Instagram já ativados sem a mídia guardada (Crm::MetaAds::Creation::AdMedia), para o "Esperando você" contar
#   os comentários do anúncio. Com a mídia guardada, não são lidos de novo.
# Rodízio: anúncio lido fica um tempo sem ser lido de novo (RECENT_EVERY nos primeiros RECENT dias, quando a pessoa
# costuma ligar o anúncio; OLD_EVERY depois), e cada rodada lê no máximo LIMIT, os mais novos primeiro. Meta fora ou
# token recusado param a rodada; a próxima tenta de novo.
class Crm::MetaAds::Creation::ActivationSweep
  WINDOW = SeusPosts::Posts::HISTORICO_DIAS.days
  LIMIT = 200
  RECENT = 2.days
  RECENT_EVERY = 50.minutes
  OLD_EVERY = 6.hours

  def initialize(connection)
    @connection = connection
  end

  def perform
    candidates.each do |record|
      result = client.ad_management(record.ad_id)
      break if result.transient? || result.token_invalid?

      read!(record)
      apply(record, result.data) if result.ok
    end
  end

  private

  def candidates
    (waiting + without_media).reject { |record| read_recently?(record) }.first(LIMIT)
  end

  def apply(record, meta_ad)
    Crm::MetaAds::Creation::AdMedia.remember(record, meta_ad)
    activated!(record) if record.activated_at.nil? && meta_ad['status'] == 'ACTIVE'
  end

  # Com um clique de Ativar ou Pausar em andamento (Crm::MetaAds::Creation::Activation trava a linha), quem grava é ele.
  def waiting
    scope = boosted.where(activated_at: nil)
    scope.where(switching_at: nil).or(scope.where(switching_at: ...Crm::MetaAds::Creation::Activation::SWITCH_STALE_AFTER.ago)).to_a
  end

  def without_media
    boosted.where.not(activated_at: nil).where(source_post_network: Crm::MetaAds::Creation::AdMedia::NETWORK)
           .reject { |record| Crm::MetaAds::Creation::AdMedia.known?(record.account_id, record.ad_id) }
  end

  def boosted
    Crm::MetaAdsCreatedObject.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, status: 'created')
                             .where.not(ad_id: nil).where.not(source_post_id: nil).where(created_at: WINDOW.ago..)
                             .order(created_at: :desc)
  end

  def read_key(record)
    "crm_meta_ads:activation_sweep:v1:#{record.account_id}:#{record.ad_id}"
  end

  def read_recently?(record)
    Rails.cache.exist?(read_key(record))
  end

  def read!(record)
    Rails.cache.write(read_key(record), true, expires_in: record.created_at > RECENT.ago ? RECENT_EVERY : OLD_EVERY)
  end

  # Sem gravar, a próxima rodada tenta de novo.
  def activated!(record)
    record.update!(activated_at: Time.current)
  rescue ActiveRecord::ActiveRecordError => e
    ChatwootExceptionTracker.new(e, account: @connection.account).capture_exception
  end

  def client
    @client ||= Crm::MetaAds::Creation::Access.new(@connection).client
  end
end
