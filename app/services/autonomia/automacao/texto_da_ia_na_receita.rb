# O salvar confere o `ia.<id>` (#2679): o texto de um passo que escreve ("escrever", "resumir") desta receita, nunca no
# "Só se" do gatilho (ali nenhum passo rodou, e o valor estaria sempre vazio). Pelo mesmo motivo, o passo que escreve
# roda antes do que lê em algum caminho: depois dele, ou noutro galho do mesmo passo, o leitor pularia sempre com
# faltou_valor. O "para cada item" (G24, #2771) deixa `ia.<id>.quantos` e `ia.<id>.nomes` (PassoParaCada::VALORES);
# outro sufixo, ou o `ia.<id>` dele sem sufixo, não existe.
class Autonomia::Automacao::TextoDaIaNaReceita
  def initialize(receita, conteudo)
    @receita = receita
    @conteudo = conteudo
  end

  def problemas(id, caminho, no_gatilho:)
    return [texto(:texto_da_ia_no_gatilho, id, caminho)] if no_gatilho

    escritor = escritor(caminho)
    return [texto(:texto_da_ia_sem_passo, id, caminho)] unless escritor
    return [] if Array(rodam_antes(id)).any? { |passo| passo['id'] == escritor }

    [texto(:texto_da_ia_depois, id, caminho)]
  end

  private

  # O id do passo que escreve o que o caminho lê, ou nil. O id inteiro vale primeiro, porque o id de um passo pode ter
  # ponto; senão, o que vem antes do último ponto é o "para cada item" e o resto, o valor dele.
  def escritor(caminho)
    resto = ::Autonomia::Automacao::Valores.passo_da_ia(caminho)
    return resto if ::Autonomia::Automacao::Valores::PASSOS_QUE_ESCREVEM.include?(tipo(resto))

    passo_id, _ponto, valor = resto.rpartition('.')
    passo_id if tipo(passo_id) == 'para_cada' && ::Autonomia::Automacao::PassoParaCada::VALORES.include?(valor)
  end

  def tipo(passo_id) = @receita.passos.find { |passo| passo['id'] == passo_id }&.dig('tipo')

  # Os passos que podem ter rodado antes do passo `id`, em algum caminho: os anteriores da mesma lista, o passo que abre
  # o galho dele, e o que veio antes desse passo, com tudo o que estava dentro dos galhos dele. Os galhos de um mesmo
  # passo (então e senão, os caminhos do decidir, o "se vencer") nunca rodam juntos. nil quando o id não está na receita.
  def rodam_antes(id, lista = @conteudo['passos'], antes = [])
    Array(lista).each do |passo|
      return antes if passo['id'] == id

      ::Autonomia::Automacao::Receita.ramos(passo).each do |ramo|
        achou = rodam_antes(id, ramo, antes + [passo])
        return achou if achou
      end
      antes += @receita.passos([passo])
    end
    nil
  end

  def texto(chave, id, caminho) = I18n.t("autonomia.automacao.receita.#{chave}", passo: id, caminho: caminho)
end
