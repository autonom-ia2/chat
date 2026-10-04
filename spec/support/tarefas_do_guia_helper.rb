# O cenário das tarefas longas do Guia (#936): contatos com o nome em maiúsculas e a receita que os
# arruma com `$gerar`. A IA do cliente é simulada (devolve o nome com só a inicial maiúscula) e conta
# as chamadas; o Jev também, quando a receita classifica.
module TarefasDoGuiaHelper
  def receita_de_nomes(extra = {})
    { 'descricao' => 'Arrumar o nome dos contatos', 'alvo' => { 'recurso' => 'contacts' },
      'acao' => 'PATCH contacts/:id', 'caminho' => { 'id' => { '$item' => 'id' } },
      'corpo' => { 'name' => { '$gerar' => { 'campo' => 'name', 'instrucao' => 'Só a inicial de cada nome em maiúscula' } } } }
      .merge(extra)
  end

  # Com e-mail: a lista de contatos só mostra quem tem e-mail, telefone ou identificador.
  def contatos_em_maiusculas!(conta, quantos)
    Array.new(quantos) do |indice|
      create(:contact, account: conta, name: "CLIENTE NUMERO #{indice + 1}", email: "cliente#{indice + 1}@exemplo.com")
    end
  end

  def simular_ia_do_cliente!
    credencial = { api_key: 'chave', api_base: 'https://api.openai.com/v1' }
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
    allow_any_instance_of(Crm::Ai::ResponsesClient).to receive(:create) do |_cliente, **argumentos| # rubocop:disable RSpec/AnyInstance
      itens = JSON.parse(argumentos[:input])['itens'].map { |item| { 'ref' => item['ref'], 'valor' => item['valor'].titleize } }
      { text: { 'itens' => itens }.to_json, usage: { 'input_tokens' => 1_000, 'output_tokens' => 200 } }
    end
  end

  def planejar!(conta, quem, receita)
    contexto = Autonomia::Guide::Contexto.new(account: conta, user: quem)
    Autonomia::Guide::Tarefas::Amostra.new(contexto: contexto, receita: receita).planejar
  end

  # O lote como o job o roda: com a vaga e o status `rodando`.
  def rodar_lote!(tarefa)
    tarefa.update!(status: Autonomia::Guide::Tarefa::RODANDO)
    Autonomia::Guide::Tarefas::Lote.new(tarefa.reload).rodar
  end

  # A vaga do semáforo mora no Redis, que não volta com a transação do exemplo.
  def limpar_semaforo!
    Redis::Alfred.delete(Autonomia::Guide::Tarefas::Semaforo::RODANDO)
  end

  def comecar!(tarefa)
    tarefa.mudar!('comecar', receita_digest: Autonomia::Guide::Tarefa.digest_de(tarefa.receita))
    tarefa
  end
end

RSpec.configure do |config|
  config.include TarefasDoGuiaHelper
end
