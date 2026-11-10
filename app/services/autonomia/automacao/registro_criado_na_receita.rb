# O salvar confere o `criado.<id>` (G49) com a régua do texto da IA: o id é de um passo da mesma execução que cria
# registro (o "criar card", a ação que cria contato: RegistroCriado), roda antes do passo que lê em algum caminho, e
# nunca no "Só se" do gatilho. `tipo`: onde só cabe um tipo de registro (o contato do "criar card", o campo do contato
# no "em outro registro"), o passo tem de criar esse tipo.
class Autonomia::Automacao::RegistroCriadoNaReceita < Autonomia::Automacao::TextoDaIaNaReceita
  FRASES = { gatilho: :criado_no_gatilho, sem_passo: :criado_sem_passo, depois: :criado_depois }.freeze

  def initialize(receita, conteudo, tipo: nil)
    super(receita, conteudo)
    @tipo = tipo
  end

  private

  def passo_do(caminho) = ::Autonomia::Automacao::RegistroCriado.passo_do(caminho)

  def produz?(passo)
    criado = ::Autonomia::Automacao::RegistroCriado.tipo_do_passo(passo)
    criado.present? && (@tipo.nil? || criado == @tipo)
  end

  def do_para_cada(_resto) = nil
end
