# Quem tem a carteira de seguros (E4, #2897): toda conta corretora de seguros. Desde a E9 (#2902) não há chave: as
# flags `carteira_seguros` e `relacionamentos_novo` viraram padrão e saíram do código. O segmento sai do nicho da conta
# (Autonomia::Agents::Nicho), não do `autonomia_pacote`: o pacote vem nulo na stack que não liga os pacotes, e a
# corretora de lá ficaria sem carteira. Conta que não escolheu nicho segue o padrão da instalação, como o resto da
# plataforma. Sem acesso, as rotas da carteira respondem 404 e o payload da conta diz `carteira_seguros: false`. As chaves
# por conta da leitura de PDF e da cotação (pagas) continuam à parte: Carteira::Leitor::Liberado e
# Carteira::Cotacao::Liberada.
module Carteira::Acesso
  PERFIL = 'corretora'.freeze

  def self.liberada?(account)
    escolha = Autonomia::Agents::Nicho.for(account)
    escolha.nicho == Autonomia::Agents::Nicho::SEGUROS && escolha.perfil == PERFIL
  end
end
