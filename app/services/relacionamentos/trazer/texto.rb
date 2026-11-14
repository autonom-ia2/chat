# "Trazer minha lista" (#2896): o texto que a pessoa digita na conferência (o valor de um conserto, o nome e o "para que
# serve" de uma informação) nunca leva caractere de controle. O byte nulo, em especial, o banco recusa: num jsonb a
# rota quebraria.
module Relacionamentos::Trazer::Texto
  # Do byte nulo ao último caractere de controle, e o DEL: a lista de caracteres que String#delete tira.
  CONTROLE = "\u0000-\u001F\u007F".freeze

  module_function

  def sem_controle(texto)
    texto.to_s.delete(CONTROLE)
  end
end
