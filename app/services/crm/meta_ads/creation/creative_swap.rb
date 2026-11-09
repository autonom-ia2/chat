# Trocar a foto ou o texto no próprio anúncio criado aqui (#2778, Fluxo 5). A Meta não muda o criativo: cria um novo
# (Crm::MetaAds::Creation::CreativeChange) e põe no anúncio (`POST /{ad_id}` com `creative`). A Meta analisa de novo, e
# a resposta traz a situação relida (`effective_status`, em geral PENDING_REVIEW).
#
# `CONFIRMED` fica false até a chamada real confirmar o `POST /{ad_id}` com `creative` (item 3 de "Confirmar na chamada
# real", docs/crm/anuncios-meta-criar-2198.md). Enquanto isso a gestão diz `can_swap_creative: false`, a tela oferece
# "Trocar a foto (cria uma cópia)" (Crm::MetaAds::Creation::Copy) e esta troca recusa (`cannot_swap`).
#
# A mesma chave troca uma vez só: a resposta fica guardada por um dia, e um segundo toque durante a troca recebe
# `in_progress`. Se a Meta recusar pôr o criativo novo no anúncio, ele é apagado e o anúncio fica como estava.
class Crm::MetaAds::Creation::CreativeSwap
  CONFIRMED = false
  KEEP = 1.day
  LOCK_FOR = 2.minutes

  def self.confirmed?
    CONFIRMED
  end

  def initialize(connection)
    @connection = connection
    @access = Crm::MetaAds::Creation::Access.new(connection)
  end

  # → { effective_status }. `swapped_now`: esta chamada trocou.
  attr_reader :swapped_now

  def swap!(ad_id, params)
    raise Crm::MetaAds::Creation::Error, 'cannot_swap' unless self.class.confirmed?

    params = params.to_h.with_indifferent_access
    record = Crm::MetaAds::Creation::Activation.new(@connection).created_here(ad_id) || raise(Crm::MetaAds::Creation::Error, 'ad_not_found')
    key = Crm::MetaAds::Creation::Draft.key!(params[:idempotency_key])
    done = Redis::Alfred.get(done_key(ad_id, key))
    return JSON.parse(done).symbolize_keys if done
    raise unsure_error if Redis::Alfred.exists?(unsure_key(ad_id, key))

    change = Crm::MetaAds::Creation::CreativeChange.from_params(params)
    locked(ad_id, key) { swap_creative!(record, change, done_key(ad_id, key)) }
  end

  private

  def client
    @access.client
  end

  # Por anúncio: a mesma chave em outro anúncio não devolve a troca deste.
  def done_key(ad_id, key)
    "meta_ads:creative_swap:#{@connection.account_id}:#{ad_id}:#{key}"
  end

  # A Meta não respondeu ao pôr o criativo: a mesma chave não troca de novo (podia ser a segunda troca e a segunda
  # análise). A tela pede para abrir o anúncio de novo e conferir.
  def unsure_key(ad_id, key)
    "#{done_key(ad_id, key)}:unsure"
  end

  def unsure_error
    Crm::MetaAds::Creation::Error.new('unconfirmed', nothing_created: false)
  end

  def locked(ad_id, key)
    lock = "#{done_key(ad_id, key)}:lock"
    raise Crm::MetaAds::Creation::Error, 'in_progress' unless Redis::Alfred.set(lock, 1, nx: true, ex: LOCK_FOR.to_i)

    begin
      yield
    ensure
      Redis::Alfred.delete(lock)
    end
  end

  def swap_creative!(record, change, stored_key)
    raise Crm::MetaAds::Creation::Error, 'cannot_change' unless @access.can_change_ads?

    read = client.creative_spec(record.creative_id)
    raise Crm::MetaAds::Creation::Error.from_result(read) unless read.ok

    creative_id = create_creative!(change.creative_params(read.data, name: record.name))
    put_on_ad!(record, creative_id, stored_key)
    swapped = { effective_status: reread_status(record.ad_id) }
    Redis::Alfred.setex(stored_key, swapped.to_json, KEEP)
    @swapped_now = true
    swapped
  end

  def create_creative!(params)
    result = client.create_creative(@connection.ad_account_id, params)
    id = result.data['id'].presence if result.ok
    raise Crm::MetaAds::Creation::Error.from_result(result) if id.nil?

    id.to_s
  end

  # Recusa clara: o criativo novo, que ninguém usa, é apagado (sem conseguir, fica solto na conta, sem gastar nada).
  # Sem resposta (tempo esgotado, 5xx): a Meta pode ter trocado, então o criativo fica e a tela não diz "segue como
  # estava" (`nothing_created: false`).
  def put_on_ad!(record, creative_id, stored_key)
    result = client.update_object(record.ad_id, creative: { creative_id: creative_id }.to_json)
    if result.transient?
      Redis::Alfred.setex("#{stored_key}:unsure", 1, KEEP)
      raise unsure_error
    end

    unless result.ok
      client.delete_object(creative_id)
      raise Crm::MetaAds::Creation::Error.from_result(result)
    end

    record.update!(creative_id: creative_id)
    Crm::MetaAds::Creation::CareState.forget(@connection.account_id, record.ad_id)
  end

  # A troca já aconteceu e criativo novo sempre passa pela análise da Meta: sem conseguir reler, PENDING_REVIEW.
  def reread_status(ad_id)
    result = client.object_status(ad_id)
    (result.data['effective_status'] if result.ok).presence || 'PENDING_REVIEW'
  end
end
