# Só no ambiente de teste (#1718). Em produção e desenvolvimento este arquivo não faz nada.
#
# O 01_redis.rb (arquivo do Chatwoot) cria um MockRedis.new por conexão do pool: 5 bancos
# separados no $alfred e 10 no $velma. Com uma thread o pool devolve sempre a mesma conexão
# e ninguém percebe; com várias, uma thread grava num banco e a outra lê de outro. Em
# produção o Redis é um só, e o teste deve se comportar igual.
#
# Aqui cada pool passa a ter um único MockRedis, compartilhado por todas as conexões, com o
# mesmo tamanho e timeout do original e o mesmo Redis::Namespace. O MockRedis não é atômico
# entre threads (o SET NX lê e grava em dois passos), então cada comando passa por um
# Monitor. O Monitor é reentrante: dentro de watch/multi/pipelined a mesma thread continua
# chamando comandos sem travar, e as outras esperam o bloco terminar.
#
# O nome começa com "01_redis_" para carregar logo depois do 01_redis.rb e antes do
# rack_attack.rb, que guarda uma referência ao $velma no boot.
return unless Rails.env.test?

class RedisDeTesteSerializado < SimpleDelegator
  def initialize(redis)
    super
    @monitor = Monitor.new
  end

  def method_missing(...)
    @monitor.synchronize { super }
  end

  def respond_to_missing?(name, include_private = false)
    __getobj__.respond_to?(name, include_private)
  end

  # #2062: o SCAN do MockRedis pagina pela posição em `data.keys`. Se o bloco apaga chaves,
  # a lista encolhe, a página seguinte começa adiante e chaves que casam são puladas. O Redis
  # real devolve toda chave que existiu do começo ao fim da varredura, mesmo apagando nela.
  # Aqui as chaves são juntadas antes (com ou sem bloco) e entregues depois, como no Redis real.
  def scan_each(*, &)
    chaves = @monitor.synchronize { __getobj__.scan_each(*).to_a }
    return chaves.each unless block_given?

    chaves.each(&)
    nil
  end

  def self.pool_compartilhado(original, namespace)
    redis = new(MockRedis.new)
    ConnectionPool.new(size: original.size, timeout: original.instance_variable_get(:@timeout)) do
      Redis::Namespace.new(namespace, redis: redis, warning: true)
    end
  end
end

# rubocop:disable Style/GlobalVars -- os pools globais vêm do 01_redis.rb
$alfred = RedisDeTesteSerializado.pool_compartilhado($alfred, 'alfred')
$velma = RedisDeTesteSerializado.pool_compartilhado($velma, 'velma')
# rubocop:enable Style/GlobalVars
