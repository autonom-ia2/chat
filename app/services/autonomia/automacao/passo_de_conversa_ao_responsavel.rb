# O passo "passar a conversa para o responsável do card" (G66, #2843; decisão 14 do Rodrigo, 09/11): a conversa do card
# passa para quem cuida do card agora. A troca do dono do card feita fora da automação (a Lista do CRM, o card) continua
# sem mexer na conversa; quem quer que ela acompanhe põe este passo na receita, depois da troca. Exemplo 17, passo 4: a
# Paula troca os cards da Júlia para a Renata, e "espera a Renata responder" lê quem atende a conversa.
#
# Só com gatilho de card (conferido ao salvar): o card é o alvo, e a conversa é a principal dele (ou a que a receita
# abriu, #2680). Vira o mesmo pedido do "Atribuir" da conversa, `POST conversations/:conversation_id/assignments`, pela
# porta da ação (PassoDeAcao, como o "criar retorno" do G3): como quem ligou, com a lista de ações permitidas, a chave de
# automações, a política da conversa no endpoint e o caderno do Guia (desfaz por 5 dias). Sem acesso, a automação pausa.
#
# Pula, com o motivo no histórico: sem conversa, card sem responsável, ou o responsável não enxerga a conversa (fora da
# caixa: a conversa ficaria com quem não a vê). Já com o responsável, segue sem pedir nada (`trocou: false`).
class Autonomia::Automacao::PassoDeConversaAoResponsavel
  TIPO = 'conversa_ao_responsavel'.freeze
  ACAO = 'POST conversations/:conversation_id/assignments'.freeze
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  # Ao salvar: só com gatilho de card, que tem o card de onde ler o responsável.
  def self.problemas_ao_salvar(passo, receita)
    return [] if ::Autonomia::Automacao::Gatilhos.do_card?(receita.dig('gatilho', 'tipo'))

    [I18n.t('autonomia.automacao.receita.responsavel_so_com_card', passo: passo['id'])]
  end

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
    @contexto = ::Autonomia::Automacao::Contexto.de(execucao.alvo, execucao: execucao)
  end

  def executar
    conversa = @contexto.conversa
    return pulado('sem_conversa') if conversa.nil?

    dono = @contexto.card&.owner
    return pulado('card_sem_responsavel') if dono.nil?
    return Resultado.new(tipo: :ok, dados: { 'responsavel_id' => dono.id, 'trocou' => false }) if conversa.assignee_id == dono.id
    return pulado('responsavel_nao_ve_a_conversa', 'responsavel_id' => dono.id) unless ::Autonomia::Automacao::Acesso.alcanca?(dono, conversa)

    passar(conversa, dono)
  end

  private

  def passar(conversa, dono)
    acao = ::Autonomia::Automacao::PassoDeAcao.new(execucao: @execucao, passo: passo_da_acao(conversa, dono), valores: @valores, acesso: @acesso)
    resultado = acao.executar
    return resultado unless resultado.tipo == :ok

    Resultado.new(tipo: :ok, dados: resultado.dados.merge('responsavel_id' => dono.id, 'trocou' => true))
  end

  def passo_da_acao(conversa, dono)
    { 'id' => @passo['id'], 'tipo' => 'acao', 'acao' => ACAO, 'descricao' => descricao,
      'caminho' => { 'conversation_id' => conversa.display_id }, 'corpo' => { 'assignee_id' => dono.id } }
  end

  # A frase do caderno do Guia, no idioma da conta.
  def descricao
    I18n.with_locale(@execucao.account.locale) { I18n.t('autonomia.automacao.descricoes.conversa_ao_responsavel') }
  end

  def pulado(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados)
end
