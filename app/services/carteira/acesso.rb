# Quem tem a carteira de seguros (E4, #2897): toda conta do nicho seguros, qualquer perfil (corretora, seguradora,
# insurtech, saúde e benefícios), por decisão do Rodrigo em 19/11 (#3053). Desde a E9 (#2902) não há chave: as flags
# `carteira_seguros` e `relacionamentos_novo` viraram padrão e saíram do código. O segmento sai do nicho da conta
# (Autonomia::Agents::Nicho), não do `autonomia_pacote`: o pacote vem nulo na stack que não liga os pacotes, e a conta
# de seguros de lá ficaria sem carteira. Conta que não escolheu nicho segue o padrão da instalação, como o resto da
# plataforma. Sem acesso, as rotas da carteira respondem 404 e o payload da conta diz `carteira_seguros: false`. As chaves
# por conta da leitura de PDF e da cotação (pagas) continuam à parte: Carteira::Leitor::Liberado e
# Carteira::Cotacao::Liberada.
module Carteira::Acesso
  def self.liberada?(account)
    Autonomia::Agents::Nicho.for(account).nicho == Autonomia::Agents::Nicho::SEGUROS
  end
end
