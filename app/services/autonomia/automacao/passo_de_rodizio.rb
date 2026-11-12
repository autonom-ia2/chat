# O passo "atribuir em rodízio" (#2502, receita "Dividir os clientes entre o time"): a conversa sem responsável vai para a
# próxima pessoa da caixa dela, ou do time escolhido (`time_id`, só quem também está na caixa), que está online.
#
# Quem escolhe é o rodízio da própria plataforma, sem reescrever a regra: AutoAssignment::AgentAssignmentService, o mesmo
# da atribuição automática da caixa. Ele só olha quem está online, tira quem o acesso por funil esconde e gira a fila da
# caixa. A lista de partida é a mesma que a atribuição automática usa (Inbox#member_ids_with_assignment_capacity, que no
# EE já tira quem passou do limite de conversas); com o time, só quem é do time. O time escolhido na automação vale
# mesmo sem o "atribuir automaticamente" do time: quem pediu foi a receita.
#
# A troca vira o mesmo pedido do "Atribuir" da conversa, `POST conversations/:conversation_id/assignments`, pela porta
# da ação (PassoDeAcao, como o G66): como quem ligou, com a lista de ações permitidas, a chave de automações, a política
# da conversa no endpoint e o caderno do Guia (desfaz por 5 dias). Sem acesso, a automação pausa.
#
# Pula, com o motivo no histórico: sem conversa (card sem conversa principal), conversa resolvida, conversa que já tem
# responsável ou está com robô ou agente de IA (a atribuição automática também não mexe nelas), ninguém da caixa (ou do
# time) para o rodízio, ou ninguém dele online agora.
class Autonomia::Automacao::PassoDeRodizio
  TIPO = 'rodizio'.freeze
  ACAO = 'POST conversations/:conversation_id/assignments'.freeze
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  SEM_CONVERSA = [::Autonomia::Automacao::Gatilhos::CONTATO, ::Autonomia::Automacao::Gatilhos::CONTA].freeze

  # Ao salvar: só onde há conversa (`alvo`, Receita#alvo) e o time da própria conta.
  def self.problemas_ao_salvar(conta, passo, alvo)
    id = passo['id']
    time = passo['time_id']
    [(texto(:rodizio_sem_conversa, passo: id) if SEM_CONVERSA.include?(alvo)),
     (texto(:time_de_fora, passo: id, id: time) if time && conta && !conta.teams.exists?(id: time))].compact
  end

  # O ensaio (#2498) só lê: nunca chama o rodízio, que gira a fila da caixa. Diz entre quem seria (a caixa ou o time), ou
  # por que pularia; quem está online só se sabe na hora.
  def self.ensaiar(passo, conversa)
    motivo = antes_do_rodizio(conversa) || ('ninguem_no_rodizio' if candidatos(passo, conversa).empty?)
    return [motivo] if motivo

    ['rodizio', { time: (conversa.account.teams.find_by(id: passo['time_id'])&.name if passo['time_id']) }.compact]
  end

  def self.antes_do_rodizio(conversa)
    return 'conversa_resolvida' if conversa.resolved?
    return 'conversa_ja_atribuida' if conversa.assignee_id.present?

    'robo_atende' if conversa.assignee_agent_bot_id.present? || conversa.ai_assignee.present?
  end

  # A mesma lista da atribuição automática da caixa; com o time, só quem é dele.
  def self.candidatos(passo, conversa)
    ids = conversa.inbox.member_ids_with_assignment_capacity
    return ids unless passo['time_id']

    ids & ::TeamMember.joins(:team).where(teams: { account_id: conversa.account_id, id: passo['time_id'] }).pluck(:user_id)
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  # `alvo`: o alvo relido pelo executor (Executor#alvo): a conversa, ou o card e a conversa principal dele.
  def initialize(execucao:, passo:, valores:, acesso:, alvo:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
    @alvo = alvo
  end

  def executar
    conversa = ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao).conversa
    return pulado('sem_conversa') if conversa.nil?

    motivo = self.class.antes_do_rodizio(conversa)
    return pulado(motivo) if motivo

    candidatos = self.class.candidatos(@passo, conversa)
    return pulado('ninguem_no_rodizio') if candidatos.empty?

    pessoa = ::AutoAssignment::AgentAssignmentService.new(conversation: conversa, allowed_agent_ids: candidatos).find_assignee
    pessoa ? passar(conversa, pessoa) : pulado('ninguem_online')
  end

  private

  def passar(conversa, pessoa)
    acao = ::Autonomia::Automacao::PassoDeAcao.new(execucao: @execucao, passo: passo_da_acao(conversa, pessoa), valores: @valores,
                                                   acesso: @acesso)
    resultado = acao.executar
    return resultado unless resultado.tipo == :ok

    Resultado.new(tipo: :ok, dados: resultado.dados.merge('responsavel_id' => pessoa.id))
  end

  def passo_da_acao(conversa, pessoa)
    { 'id' => @passo['id'], 'tipo' => 'acao', 'acao' => ACAO, 'descricao' => descricao,
      'caminho' => { 'conversation_id' => conversa.display_id }, 'corpo' => { 'assignee_id' => pessoa.id } }
  end

  # A frase do caderno do Guia, no idioma da conta.
  def descricao
    I18n.with_locale(@execucao.account.locale) { I18n.t('autonomia.automacao.descricoes.rodizio') }
  end

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})
end
