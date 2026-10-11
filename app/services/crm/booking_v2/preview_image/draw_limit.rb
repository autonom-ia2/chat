# Teto global de desenhos da imagem de prévia (#1303): no máximo `limit` desenhos ao mesmo tempo na instalação
# inteira, somando os processos web e os jobs, e no máximo UM por conta. A trava do `Store` é por página; sem este
# teto, um robô pedindo páginas diferentes punha um desenho (libvips, CPU e memória) em cada thread do web. A vaga por
# conta é a divisão justa: uma conta mudando a marca sem parar (ou pedindo as imagens dos próprios links) não ocupa
# todas as vagas e não deixa as outras contas com a imagem neutra.
#
# São `limit` vagas numeradas no Redis, mais uma chave por conta. Pegar é um `SET NX EX` (atômico): primeiro a da conta,
# depois a primeira vaga global livre; sem vaga global, a da conta é devolvida na hora. Soltar é apagar a chave só se o
# valor ainda for o de quem pegou (`delete_if_equals`), no `ensure`. Chave de processo que morreu expira sozinha em
# `SLOT_SECONDS`. Nada de `KEYS` nem varredura: são no máximo `limit + 1` comandos por tentativa.
#
# `SLOT_SECONDS` fica bem acima do tempo de um desenho (segundos; a fonte tem teto de pixels no `Canvas`), da trava
# por página (`Store::LOCK_SECONDS`) e do tempo-limite do pedido web (`RACK_TIMEOUT_SERVICE_TIMEOUT`, 15 s por padrão).
# Um desenho que passe disso perde a vaga e o teto pode ser furado por ele até terminar: preferimos isso a uma vaga presa
# para sempre. Processo morto no meio (deploy) deixa a vaga presa por até `SLOT_SECONDS`.
#
# `CRM_BOOKING_PREVIEW_MAX_DRAWS` precisa ter o mesmo valor no web e no Sidekiq: cada processo lê o seu, e o teto real
# é o maior deles.
#
# Servir a imagem já guardada não passa por aqui.
class Crm::BookingV2::PreviewImage::DrawLimit
  LIMIT_ENV = 'CRM_BOOKING_PREVIEW_MAX_DRAWS'.freeze
  DEFAULT_LIMIT = 2
  MAX_LIMIT = 16
  SLOT_SECONDS = 120
  SLOT_PREFIX = 'CRM_BOOKING_PREVIEW_IMAGE_DRAW_SLOT'.freeze
  ACCOUNT_PREFIX = 'CRM_BOOKING_PREVIEW_IMAGE_DRAW_ACCOUNT'.freeze

  class Full < StandardError; end

  # Valor inválido, zero ou negativo na variável de ambiente: vale o padrão. Nunca passa de `MAX_LIMIT`.
  def self.limit
    configured = Integer(ENV.fetch(LIMIT_ENV, DEFAULT_LIMIT).to_s, exception: false)
    configured&.positive? ? [configured, MAX_LIMIT].min : DEFAULT_LIMIT
  end

  def self.slot_key(index)
    "#{SLOT_PREFIX}::#{index}"
  end

  def self.account_key(account_id)
    "#{ACCOUNT_PREFIX}::#{account_id}"
  end

  # Roda o bloco segurando a vaga da conta e uma vaga global, e devolve o que ele devolver. Sem uma das duas: `Full`,
  # sem rodar o bloco.
  def self.with_slot(account_id)
    owner = SecureRandom.hex(8)
    keys = take(owner, account_id)
    raise Full if keys.nil?

    begin
      yield
    ensure
      keys.each { |key| ::Redis::Alfred.delete_if_equals(key, owner) }
    end
  end

  def self.take(owner, account_id)
    account = account_key(account_id)
    return unless ::Redis::Alfred.set(account, owner, nx: true, ex: SLOT_SECONDS)

    slot = Array.new(limit) { |index| slot_key(index) }.find { |key| ::Redis::Alfred.set(key, owner, nx: true, ex: SLOT_SECONDS) }
    return [account, slot] if slot

    ::Redis::Alfred.delete_if_equals(account, owner)
    nil
  rescue StandardError
    # Erro do Redis no meio: a chave da conta, se já era nossa, volta antes de o erro subir (senão a conta ficaria sem
    # desenhar até ela expirar). Só apaga se o valor ainda for o deste pedido.
    ::Redis::Alfred.delete_if_equals(account, owner)
    raise
  end
  private_class_method :take
end
