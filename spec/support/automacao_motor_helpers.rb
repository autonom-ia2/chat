# Montagem comum dos specs do motor da Automação livre (#2414 F3, #2459).
module AutomacaoMotorHelpers
  def ligar_motor(account)
    account.enable_features!('automacao_fundacao', 'automacao_motor')
  end

  def automacao_ligada(account, por, passos, gatilho: { 'tipo' => 'conversa.resolvida' })
    definicao = create(:autonomia_automacao, account: account, ligada_por: por)
    definicao.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => passos }, autor: por)
    definicao.update!(ativa: true)
    definicao
  end

  def comecar(definicao, alvo)
    Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: 'conversa.resolvida').call
  end

  def varrer
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
  end

  def esperar_passo(id, valor = 1, unidade = 'dias')
    { 'id' => id, 'tipo' => 'esperar', 'duracao' => { 'valor' => valor, 'unidade' => unidade } }
  end

  def ligar_mensagens(account)
    account.enable_features!('automacao_mensagens')
  end

  def mensagem_passo(id, *texto)
    { 'id' => id, 'tipo' => 'mensagem', 'texto' => texto }
  end

  def avisar_passo(id, para, *texto)
    { 'id' => id, 'tipo' => 'avisar', 'para' => para, 'texto' => texto }
  end

  def prioridade_passo(id, prioridade = 'urgent', conversa_id: { '$valor' => 'conversa.id' })
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST conversations/:id/toggle_priority', 'descricao' => 'Marcar a prioridade',
      'caminho' => { 'id' => conversa_id }, 'corpo' => { 'priority' => prioridade } }
  end
end

RSpec.configure do |config|
  config.include AutomacaoMotorHelpers, :automacao_motor
end
