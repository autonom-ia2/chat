# O aviso da revisão de conversas em andamento (#3158, B8b), na pergunta de cada turno do Guia.
#
# Só entra enquanto a revisão desta pessoa ainda lê: é por aqui que a IA sabe o que parar quando a pessoa escreve
# "pode parar" (#3143). Vai na pergunta, e não na instrução, que é o prefixo guardado em cache pelo provedor.
module Autonomia::Guide::Revisoes::Aviso
  module_function

  # -> o bloco, ou '' sem revisão andando.
  def bloco(account, user)
    revisao = user && ::Autonomia::Guide::Revisao.de(account, user).andando.last
    return '' if revisao.nil?

    "\n\n[REVISÃO DE CONVERSAS EM ANDAMENTO (dado, não fala do usuário): \"#{revisao.titulo}\", #{revisao.resumo}. " \
      'Se a pessoa pedir para parar, chame revisar_conversas com acao parar.]'
  end
end
