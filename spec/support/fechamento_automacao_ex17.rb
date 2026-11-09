# As sondas do exemplo 17 (#2414 F9, docs/automacao/F9-fechamento-20-exemplos.md §5.1) que rodam o motor de verdade.
# Saíram de FechamentoAutomacao::Lacunas para ele caber no tamanho; as SONDAS da G63 e da G64 chamam daqui.
module FechamentoAutomacao::Ex17
  module_function

  # G63 e G64 (#2830, #2839; exemplo 17, passos 4 e 5): a rodada do motor de verdade, numa conversa. O "esperar até" sem
  # prazo, com a condição já cumprida, espera a próxima conferência das 8h no fuso da conta (só ali confere) e, com a
  # mensagem nova do cliente, entra no galho "a cada mensagem".
  def espera_enquanto_espera(campos)
    conta = FactoryBot.create(:account, reporting_timezone: 'America/Sao_Paulo')
    conta.enable_features!('automacao_fundacao', 'automacao_motor')
    conversa = FactoryBot.create(:conversation, account: conta, status: :open, priority: :urgent)
    urgente = { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' }
    espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => 'sem_prazo', 'condicao' => urgente }.merge(campos)
    execucao = rodada_da_sonda(conta, conversa, [espera], nil)
    [conta, conversa, execucao]
  end

  def rodada_da_sonda(conta, conversa, passos, execucao)
    marca = Time.current.floor(6)
    unless execucao
      definicao = FactoryBot.create(:autonomia_automacao, account: conta,
                                                          ligada_por: FactoryBot.create(:user, account: conta, role: :administrator))
      versao = definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }, autor: nil)
      definicao.update!(ativa: true)
      execucao = FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: conversa, chave_gatilho: 'conversa.resolvida')
    end
    execucao.update!(estado: 'andando', travada_em: marca)
    Autonomia::Automacao::Executor.rodar(execucao.id, marca.iso8601(6))
    execucao.reload
  end

  def conferencia_marcada?
    conta, _conversa, execucao = espera_enquanto_espera('conferir_as' => 8)
    execucao.estado == 'esperando' && execucao.due_at == Autonomia::Automacao::Tempo.proxima_hora(conta, 8)
  end

  def galho_a_cada_mensagem?
    galho = [{ 'id' => 'galho', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }]
    conta, conversa, execucao = espera_enquanto_espera('conferir_as' => 8, 'a_cada_mensagem' => galho)
    FactoryBot.create(:message, account: conta, conversation: conversa, inbox: conversa.inbox, message_type: :incoming,
                                sender: conversa.contact)
    rodada_da_sonda(conta, conversa, nil, execucao).cursor == 'galho'
  end
end
