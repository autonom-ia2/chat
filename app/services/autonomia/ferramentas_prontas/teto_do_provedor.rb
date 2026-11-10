# O TETO GLOBAL POR PROVEDOR (#2858, F1). O limite por conta (`Uso`) não basta: as APIs públicas limitam pelo IP de quem
# chama, e todas as contas saem do mesmo IP. Sem teto, uma conta movimentada esgotaria a cota da parallelum (500 por dia
# sem chave) para todas as outras.
#
# Dois tetos por pedido, os dois no Redis, por HOST (o mesmo host serve várias fontes: a BrasilAPI atende CEP, CNPJ,
# FIPE, feriados, DDD e bancos):
#   - o GLOBAL, da plataforma inteira (`TETOS`);
#   - a FATIA de cada conta (`FATIA` do global, ao menos 1): uma conta, ou um contato insistente numa conta, não gasta o
#     teto de todas.
# Conta só o que sai para a rede: o que vem do cache não gasta. Passou de qualquer um: o provedor é pulado com o motivo
# `teto_do_provedor`, e a reserva tenta. Os números e de onde vêm estão em `docs/ferramentas-prontas/termos-das-fontes.md`;
# mudou o termo de uma fonte, muda aqui e lá. Vale também para CEP, CNPJ e FIPE (F0), de propósito: a cota é a mesma.
#
# Janela fixa: INCR e EXPIRE juntos (MULTI), uma chave por host, conta, janela e período. Redis fora do ar: o pedido segue
# (o teto protege a cota, não o dado), com aviso no log. Nenhum host do catálogo exige teto por segundo.
#
# DESLIGAR UM PROVEDOR SEM DEPLOY: o host na configuração `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS` (lista separada por
# vírgula; configuração da instalação no Super Admin, ou a variável de ambiente). Desligado, o provedor é pulado com
# `provedor_desligado`.
module Autonomia::FerramentasProntas::TetoDoProvedor
  CHAVE = 'autonomia:prontas:teto'.freeze
  DESLIGADOS = 'AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS'.freeze
  MINUTO = 60
  DIA = 86_400
  FATIA = 0.25
  ERROS_DO_REDIS = [Redis::BaseError, RedisClient::Error, ConnectionPool::TimeoutError].freeze
  # host => [[pedidos, janela em segundos], ...]. Host fora da lista: o teto padrão.
  TETOS = {
    'photon.komoot.io' => [[60, MINUTO]],
    'parallelum.com.br' => [[450, DIA]],
    'viacep.com.br' => [[60, MINUTO]],
    'brasilapi.com.br' => [[300, MINUTO]],
    'date.nager.at' => [[30, MINUTO]]
  }.freeze
  PADRAO = [[120, MINUTO]].freeze

  module_function

  def tetos(host)
    TETOS.fetch(host.to_s.downcase, PADRAO)
  end

  def fatia(pedidos)
    [(pedidos * FATIA).floor, 1].max
  end

  # -> true quando o pedido cabe (e já foi contado); false quando o host passou de algum teto, global ou da conta.
  def reservar!(host, conta: nil, agora: Time.now.to_i)
    tetos(host).all? do |pedidos, janela|
      (conta.nil? || contar(chave(host, janela, agora, conta), janela) <= fatia(pedidos)) &&
        contar(chave(host, janela, agora), janela) <= pedidos
    end
  rescue *ERROS_DO_REDIS => e
    Rails.logger.warn("[autonomia][pronta] teto do provedor sem Redis host=#{host} #{e.class}")
    true
  end

  def desligado?(host)
    lista = configurado.presence || ENV.fetch(DESLIGADOS, '')
    lista.to_s.split(',').map { |item| item.strip.downcase }.include?(host.to_s.downcase)
  end

  # A configuração da instalação passa pelo Redis e pelo banco: fora do ar, vale a variável de ambiente.
  def configurado
    GlobalConfig.get(DESLIGADOS)[DESLIGADOS]
  rescue *ERROS_DO_REDIS, ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][pronta] configuração dos hosts desligados indisponível #{e.class}")
    nil
  end

  def chave(host, janela, agora, conta = nil)
    [CHAVE, host.to_s.downcase, conta && "conta-#{conta.to_i}", janela, agora / janela].compact.join(':')
  end

  def contar(chave, janela)
    Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.incr(chave)
        transacao.expire(chave, janela + 1)
      end
    end.first
  end
end
