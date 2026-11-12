# O TETO GLOBAL POR PROVEDOR (#2858, F1). O limite por conta (`Uso`) não basta: as APIs públicas limitam pelo IP de quem
# chama, e todas as contas saem do mesmo IP. Sem teto, uma conta movimentada esgotaria a cota da parallelum (500 por dia
# sem chave) para todas as outras.
#
# Dois tetos por pedido, os dois no Redis, por HOST (o mesmo host serve várias fontes: a BrasilAPI atende CEP, CNPJ,
# FIPE, feriados, DDD e bancos):
#   - o GLOBAL, da plataforma inteira (`TETOS`);
#   - a FATIA de cada conta (`FATIA` do global, ao menos 1): uma conta, ou um contato insistente numa conta, não gasta o
#     teto de todas.
# COM IP PRÓPRIO (#2942, `Saida`): a conta que sai pelo IP dela na Webshare não gasta a cota do IP do servidor. O pedido
# conta só no teto DAQUELE IP (`saida:`), que vale o teto global inteiro do host: a cota da fonte é por IP, e o IP é só da
# conta (índice único), então a fatia, que existe para repartir um IP entre todas as contas, não se aplica. O contador
# é do IP, não da conta: o IP que volta da quarentena para outra conta chega com o que já gastou na janela. Sem IP
# próprio (flag desligada, ou Webshare fora e sem IP livre), vale o global e a fatia, como sempre.
# EXCEÇÃO, A COTA DA CHAVE: a parallelum e a AwesomeAPI com a chave gratuita no ambiente (`por_chave?`) limitam pela
# CHAVE, que vai no cabeçalho também pelo proxy. Ali o IP próprio não dá cota nova: o pedido conta no global e na fatia
# de antes, saia por onde sair.
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
  HORA = 3_600
  DIA = 86_400
  FATIA = 0.25
  ERROS_DO_REDIS = [Redis::BaseError, RedisClient::Error, ConnectionPool::TimeoutError].freeze
  # host => [[pedidos, janela em segundos], ...]. Host fora da lista: o teto padrão.
  TETOS = {
    'photon.komoot.io' => [[60, MINUTO]],
    'parallelum.com.br' => [[450, DIA]],
    'viacep.com.br' => [[60, MINUTO]],
    # AwesomeAPI sem chave: o limite não é publicado, então o teto é conservador.
    'cep.awesomeapi.com.br' => [[30, MINUTO], [1_000, DIA]],
    'brasilapi.com.br' => [[300, MINUTO]],
    'date.nager.at' => [[30, MINUTO]],
    # F4. Sem número publicado: conservador.
    'pncp.gov.br' => [[60, MINUTO]],
    'apitempo.inmet.gov.br' => [[30, MINUTO]],
    'data.directory.opinbrasil.com.br' => [[30, MINUTO]],
    'www2.susep.gov.br' => [[30, MINUTO]],
    # Open-Meteo: 90% dos 600 por minuto, 5.000 por hora e 10.000 por dia dos termos.
    'archive-api.open-meteo.com' => [[540, MINUTO], [4_500, HORA], [9_000, DIA]]
  }.freeze
  PADRAO = [[120, MINUTO]].freeze
  # Com a chave gratuita da parallelum no ambiente, o termo sobe para 1.000 por dia.
  PARALLELUM_COM_CHAVE = [[900, DIA]].freeze
  # Com a chave gratuita da AwesomeAPI (100 mil por mês): ~90% de 100.000 / 30 por dia.
  AWESOMEAPI_COM_CHAVE = [[120, MINUTO], [3_000, DIA]].freeze
  COM_CHAVE = { 'parallelum.com.br' => PARALLELUM_COM_CHAVE, 'cep.awesomeapi.com.br' => AWESOMEAPI_COM_CHAVE }.freeze

  module_function

  def tetos(host)
    host = host.to_s.downcase
    return COM_CHAVE.fetch(host) if por_chave?(host)

    TETOS.fetch(host, PADRAO)
  end

  # O host limita pela chave da plataforma (não pelo IP de quem chama)?
  def por_chave?(host)
    case host.to_s.downcase
    when 'parallelum.com.br' then Autonomia::FerramentasProntas::Fontes::Fipe::Parallelum.chave.present?
    when 'cep.awesomeapi.com.br' then Autonomia::FerramentasProntas::Fontes::Cep::AwesomeApi.chave.present?
    else false
    end
  end

  def fatia(pedidos)
    [(pedidos * FATIA).floor, 1].max
  end

  # -> true quando o pedido cabe (e já foi contado); false quando o host passou de algum teto, global ou da conta.
  # `saida`: o IP próprio por onde o pedido sai (#2942); nil é o IP do servidor. O host da cota da chave ignora a saída.
  def reservar!(host, conta: nil, saida: nil, agora: Time.now.to_i)
    return reservar_no_ip!(host, saida, agora) if saida && !por_chave?(host)

    tetos(host).all? do |pedidos, janela|
      (conta.nil? || contar(chave(host, janela, agora, conta), janela) <= fatia(pedidos)) &&
        contar(chave(host, janela, agora), janela) <= pedidos
    end
  rescue *ERROS_DO_REDIS => e
    Rails.logger.warn("[autonomia][pronta] teto do provedor sem Redis host=#{host} #{e.class}")
    true
  end

  # O teto do host inteiro, contado só no IP próprio.
  def reservar_no_ip!(host, saida, agora)
    tetos(host).all? { |pedidos, janela| contar(chave_do_ip(host, janela, agora, saida), janela) <= pedidos }
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

  def chave_do_ip(host, janela, agora, saida)
    [CHAVE, host.to_s.downcase, "ip-#{saida}", janela, agora / janela].join(':')
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
