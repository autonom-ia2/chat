# O MOTIVO DE QUEM NÃO COTOU, EM CATEGORIA (fatia 2 do #420).
#
# A LIA NÃO FALA DE RECUSA DO RISCO (decisão do CEO de 23/09/2026, chat#612). Até aqui uma lista fechada de palavras lia
# o texto do portal e devolvia `veiculo` ou `regiao`, e a Lia contava ao cliente que a seguradora não aceitou o veículo
# ou a região. Agora ela diz só que a seguradora não trouxe proposta desta vez; o que a seguradora escreveu vai para a
# equipe, numa nota interna (`InsuranceQuote::NotaDaEquipe`). A lista de palavras saiu junto.
#
# A INSTABILIDADE CONTINUA (chat#323, 22/09/2026). Quem classifica é o conector: `kind` `passageiro` é a seguradora
# fora do ar ou instável. Não é recusa do risco. Desde a chat#638 nem ela vai ao cliente: só à nota da equipe.
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PASSAGEIRO = 'passageiro'.freeze
  INSTABILIDADE = 'instabilidade'.freeze
  CATEGORIAS = [INSTABILIDADE].freeze

  module_function

  # -> `INSTABILIDADE`, ou nil (o genérico).
  def categoria(reason)
    INSTABILIDADE if reason.is_a?(Hash) && reason['kind'] == KIND_PASSAGEIRO
  end
end
