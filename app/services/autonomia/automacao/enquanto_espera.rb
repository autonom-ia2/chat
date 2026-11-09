# O que o "esperar até" faz enquanto espera (G63 #2830 e G64 #2839 do fechamento do #2414, exemplo 17, passos 4 e 5:
# "a cada mensagem do cliente, espera a Renata responder por até 2 horas" e "toda manhã [...] se a responsável original
# já está disponível de novo, devolve o card"). Dois campos opcionais do próprio passo, sem passo novo:
#
# - `a_cada_mensagem`: os passos que rodam a cada mensagem nova do cliente que chega durante a espera. Acabado o galho,
#   a execução volta ao mesmo "esperar até" (Roteiro), que segue esperando a condição. Uma espera só (decisão 11 do
#   Rodrigo, 09/11): a mensagem que chega enquanto o galho roda entra no atendimento em curso e não abre outra rodada;
#   na volta, o marco das mensagens passa a ser o instante da volta. Toda volta consome uma mensagem nova do cliente,
#   então o galho nunca gira sem ela; o teto A_CADA_TETO é contra defeito, não freio de uso.
# - `conferir_as`: a hora cheia (0 a 23, no fuso da conta, como a `hora` do gatilho recorrente) em que a espera sem
#   prazo confere a condição. Só ali: a mensagem e a mudança do card não conferem antes. A exceção é a volta do galho,
#   que confere na hora (o cliente que escreve no dia da volta não atrasa a devolução até a manhã seguinte).
#
# As conferências ao salvar (o que o esquema não sabe dizer) moram aqui; o motor, em EsperaNoExecutor.
module Autonomia::Automacao::EnquantoEspera
  A_CADA = 'a_cada_mensagem'.freeze
  # Voltas do galho numa execução. Passou: um registro "pulado" e a espera segue, só pela condição.
  A_CADA_TETO = 200

  module_function

  def a_cada?(passo) = passo.is_a?(Hash) && passo['tipo'] == 'esperar_ate' && Array(passo[A_CADA]).any?

  def conferir_as?(passo) = passo.is_a?(Hash) && passo['tipo'] == 'esperar_ate' && !passo['conferir_as'].nil?

  # `receita`: a receita inteira; `passos`: todos os passos dela, na ordem (Receita#passos).
  def problemas_ao_salvar(receita, passos)
    roteiro = ::Autonomia::Automacao::Roteiro.new(receita)
    da_conta = ::Autonomia::Automacao::Gatilhos.da_conta?(receita.dig('gatilho', 'tipo'))
    passos.flat_map do |passo|
      [*conferir_com_prazo(passo), *(a_cada?(passo) ? galho(passo, roteiro, da_conta) : []), *desde_no_galho(passo, roteiro)]
    end
  end

  def conferir_com_prazo(passo)
    return [] unless conferir_as?(passo) && !::Autonomia::Automacao::Duracao.sem_prazo?(passo['prazo'])

    [texto(:conferir_as_com_prazo, passo: passo['id'])]
  end

  # O galho sem contato (o gatilho da conta não tem cliente que escreva) e o galho dentro de outro galho.
  def galho(passo, roteiro, da_conta)
    [*(da_conta ? [texto(:a_cada_sem_contato, passo: passo['id'])] : []),
     *(roteiro.galho_de(passo['id']) ? [texto(:a_cada_aninhado, passo: passo['id'])] : [])]
  end

  # O laço dos documentos (G46) dentro do galho prenderia a execução nele, sem nunca voltar a esperar.
  def desde_no_galho(passo, roteiro)
    desde = passo.dig('de_novo', 'desde') if passo['tipo'] == 'decidir' && passo['de_novo'].is_a?(Hash)
    return [] if desde.blank? || roteiro.passo(desde).nil? || roteiro.galho_de(desde).nil?

    [texto(:de_novo_desde_no_galho, passo: passo['id'], desde: desde)]
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
  private_class_method :conferir_com_prazo, :galho, :desde_no_galho, :texto
end
