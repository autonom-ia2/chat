# O salvar confere o `consulta.<id>.<chave>` (#2934) com a régua do texto da IA: o id é de um "buscar em outro sistema"
# da mesma execução, a chave é a de um dos dados que ele guarda (PassoConsultar.chave do nome), ele roda antes do passo
# que lê em algum caminho, e nunca no "Só se" do gatilho (ali nada foi buscado).
class Autonomia::Automacao::ConsultaNaReceita < Autonomia::Automacao::TextoDaIaNaReceita
  FRASES = { gatilho: :consulta_no_gatilho, sem_passo: :consulta_sem_passo, depois: :consulta_depois }.freeze

  private

  # A chave nunca tem ponto: o id do passo é tudo antes do último.
  def escritor(caminho)
    passo_id, chave = ::Autonomia::Automacao::Valores.da_consulta(caminho)
    passo = passo(passo_id)
    passo_id if passo&.dig('tipo') == 'consultar' && ::Autonomia::Automacao::PassoConsultar.chaves(passo).include?(chave)
  end
end
