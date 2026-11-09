# O salvar confere o `ia.<id>` (#2679): o texto de um passo que escreve ("escrever", "resumir") desta receita, nunca no
# "Só se" do gatilho (ali nenhum passo rodou, e o valor estaria sempre vazio). Pelo mesmo motivo, o passo que escreve
# roda antes do que lê em algum caminho: depois dele, ou noutro galho do mesmo passo, o leitor pularia sempre com
# faltou_valor. G18: o ramo do "em outro registro" roda numa execução filha, que não vê os textos da mãe nem a mãe os
# dela; só contam os passos da mesma execução (Receita#do_alvo).
# G49 (RegistroCriadoNaReceita) usa a mesma régua para o `criado.<id>`, com as frases e o passo que produz dela.
class Autonomia::Automacao::TextoDaIaNaReceita
  FRASES = { gatilho: :texto_da_ia_no_gatilho, sem_passo: :texto_da_ia_sem_passo, depois: :texto_da_ia_depois }.freeze

  def initialize(receita, conteudo)
    @receita = receita
    @conteudo = conteudo
  end

  def problemas(id, caminho, no_gatilho:)
    return [texto(self.class::FRASES[:gatilho], id, caminho)] if no_gatilho

    escritor = passo_do(caminho)
    return [texto(self.class::FRASES[:sem_passo], id, caminho)] unless produz?(@receita.do_alvo.find { |passo| passo['id'] == escritor })
    return [] if Array(rodam_antes(id)).any? { |passo| passo['id'] == escritor }

    [texto(self.class::FRASES[:depois], id, caminho)]
  end

  private

  def passo_do(caminho) = ::Autonomia::Automacao::Valores.passo_da_ia(caminho)

  # O passo (da mesma execução) produz o valor que o caminho lê?
  def produz?(passo) = ::Autonomia::Automacao::Valores::PASSOS_QUE_ESCREVEM.include?(passo&.dig('tipo'))

  # Os passos que podem ter rodado antes do passo `id`, em algum caminho: os anteriores da mesma lista, o passo que abre
  # o galho dele, e o que veio antes desse passo, com tudo o que estava dentro dos galhos dele. Os galhos de um mesmo
  # passo (então e senão, os caminhos do decidir, o "se vencer") nunca rodam juntos. nil quando o id não está na receita.
  def rodam_antes(id, lista = @conteudo['passos'], antes = [])
    Array(lista).each do |passo|
      return antes if passo['id'] == id

      @receita.ramos_do_alvo(passo).each do |ramo|
        achou = rodam_antes(id, ramo, antes + [passo])
        return achou if achou
      end
      antes += @receita.do_alvo([passo])
    end
    nil
  end

  def texto(chave, id, caminho) = I18n.t("autonomia.automacao.receita.#{chave}", passo: id, caminho: caminho)
end
