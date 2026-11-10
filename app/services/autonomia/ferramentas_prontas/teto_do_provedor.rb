# O TETO GLOBAL POR PROVEDOR (#2858, F1). O limite por conta (`Uso`) não basta: as APIs públicas limitam pelo IP de quem
# chama, e todas as contas saem do mesmo IP. Sem teto, uma conta movimentada esgotaria a cota da parallelum (500 por dia
# sem chave) para todas as outras, ou passaria do 1 pedido por segundo do Nominatim e bloquearia a plataforma inteira.
#
# O teto é por HOST (o mesmo host serve várias fontes: a BrasilAPI atende CEP, CNPJ, FIPE, feriados, DDD e bancos) e
# conta só o que sai para a rede: o que vem do cache não gasta. Os números e de onde vêm estão em
# `docs/ferramentas-prontas/termos-das-fontes.md`; mudou o termo de uma fonte, muda aqui e lá.
#
# Janela fixa no Redis: INCR e EXPIRE juntos (MULTI), uma chave por host, janela e período. Passou do teto: o provedor
# é pulado com o motivo `teto_do_provedor`, e a reserva tenta. Redis fora do ar: o pedido segue (o teto é proteção da
# cota, não do dado), com aviso no log.
#
# DESLIGAR UM PROVEDOR SEM DEPLOY (o Nominatim exige poder parar a pedido da OSMF sem atualizar o software): o host na
# configuração `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS` (lista separada por vírgula; Super Admin > configurações da
# instalação, ou a variável de ambiente). Desligado, o provedor é pulado com `provedor_desligado`.
module Autonomia::FerramentasProntas::TetoDoProvedor
  CHAVE = 'autonomia:prontas:teto'.freeze
  DESLIGADOS = 'AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS'.freeze
  MINUTO = 60
  DIA = 86_400
  # host => [[pedidos, janela em segundos], ...]. Host fora da lista: o teto padrão.
  TETOS = {
    'nominatim.openstreetmap.org' => [[1, 1], [40, MINUTO]],
    'photon.komoot.io' => [[60, MINUTO]],
    'parallelum.com.br' => [[450, DIA]],
    'viacep.com.br' => [[60, MINUTO]],
    'brasilapi.com.br' => [[120, MINUTO]],
    'date.nager.at' => [[30, MINUTO]]
  }.freeze
  PADRAO = [[120, MINUTO]].freeze

  module_function

  def tetos(host)
    TETOS.fetch(host.to_s.downcase, PADRAO)
  end

  # -> true quando o pedido cabe (e já foi contado); false quando o host passou de algum teto.
  def reservar!(host, agora: Time.now.to_i)
    tetos(host).all? { |pedidos, janela| contar(host, pedidos, janela, agora) <= pedidos }
  rescue StandardError => e
    Rails.logger.warn("[autonomia][pronta] teto do provedor sem Redis host=#{host} #{e.class}")
    true
  end

  def desligado?(host)
    lista = GlobalConfig.get(DESLIGADOS)[DESLIGADOS].presence || ENV.fetch(DESLIGADOS, '')
    lista.to_s.split(',').map { |item| item.strip.downcase }.include?(host.to_s.downcase)
  end

  def contar(host, _pedidos, janela, agora)
    chave = "#{CHAVE}:#{host.to_s.downcase}:#{janela}:#{agora / janela}"
    Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.incr(chave)
        transacao.expire(chave, janela + 1)
      end
    end.first
  end
end
