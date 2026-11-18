# Quem tem a carteira de seguros (E4, #2897): a conta com a chave `carteira_seguros` ligada e que é corretora de
# seguros. As telas novas de Relacionamentos, onde a carteira mora, são de todas as contas desde a E9 (#2902). O
# segmento sai do nicho da conta (Autonomia::Agents::Nicho), não do `autonomia_pacote`: o pacote vem nulo na stack que
# não liga os pacotes, e a corretora de lá ficaria sem carteira. Conta que não escolheu nicho segue o padrão da instalação, como o resto da
# plataforma. Sem acesso, as rotas da carteira respondem 404 e o payload da conta diz `carteira_seguros: false`.
module Carteira::Acesso
  CHAVES = %w[carteira_seguros].freeze
  PERFIL = 'corretora'.freeze

  def self.liberada?(account)
    return false unless CHAVES.all? { |chave| account.feature_enabled?(chave) }

    escolha = Autonomia::Agents::Nicho.for(account)
    escolha.nicho == Autonomia::Agents::Nicho::SEGUROS && escolha.perfil == PERFIL
  end
end
