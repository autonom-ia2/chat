require 'rails_helper'

# Os passos de IA de ponta a ponta (#2500, F7): a automação começa, o executor pergunta ao modelo pela chave da conta e
# entrega o resultado ali mesmo (caminho, gravação, mensagem, nota). O modelo é a OpenAI simulada no HTTP.
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:contato) { create(:contact, account: account, name: 'Bruno', email: 'contato@exemplo.com', phone_number: '+5511999990000') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:corpos) { [] }
  let(:le) { %w[mensagens_recentes contato] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Bati o carro ontem, placa ABC1D23')
  end

  after { Current.reset }

  def comecar_e_rodar(definicao, alvo = conversa)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, alvo) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def dados_do(execucao, passo) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: passo).dados

  # A OpenAI devolve, em ordem, cada item (o último se repete): um Hash vira o JSON da resposta, um número é o status do
  # erro.
  def openai_devolve(*respostas)
    fila = respostas.dup
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      atual = fila.size > 1 ? fila.shift : fila.first
      if atual.is_a?(Integer)
        next { status: atual, body: { error: { message: 'falhou' } }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      payload = { id: "resp_#{corpos.size}", output_text: atual.to_json, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def caminho(nome, chave, passos = [])
    { 'nome' => nome, 'chave' => chave, 'descricao' => "quando é #{nome}", 'passos' => passos }
  end

  def decidir(caminhos: [caminho('Sinistro', 'sinistro', [prioridade_passo('p2')]), caminho('Cotação', 'cotacao')], nenhum: [])
    { 'id' => 'p1', 'tipo' => 'decidir', 'le' => le, 'pergunta' => 'Sobre o que é?', 'caminhos' => caminhos, 'nenhum' => nenhum }
  end

  def extrair(campos, trocar: false)
    { 'id' => 'p1', 'tipo' => 'extrair', 'le' => le, 'campos' => campos, 'trocar' => trocar }
  end

  def campo(chave, destino) = { 'chave' => chave, 'descricao' => "o dado #{chave}", 'destino' => destino }

  def atributo(chave, modelo, tipo = 'text')
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_model: modelo, attribute_display_type: tipo)
  end

  def escrever(destino) = { 'id' => 'p1', 'tipo' => 'escrever', 'le' => le, 'instrucao' => 'Agradeça o contato.', 'destino' => destino }

  def resumir(destino) = { 'id' => 'p1', 'tipo' => 'resumir', 'le' => le, 'linhas' => 2, 'destino' => destino }

  # Nota 9 do PR B: antes, um tipo que o motor não conhecia devolvia nil, e a execução fechava como "concluida" sem
  # registro nenhum.
  it 'passo de tipo desconhecido falha com registro, e não fecha como concluída', :aggregate_failures do
    definicao = automacao_ligada(account, admin, [prioridade_passo('p1')])
    receita = definicao.versao_ativa.receita.merge('passos' => [{ 'id' => 'p1', 'tipo' => 'teletransportar' }])
    Autonomia::Automacao::Versao.where(id: definicao.versao_ativa_id).update_all(receita: receita) # rubocop:disable Rails/SkipsModelValidations

    execucao = comecar_e_rodar(definicao)

    expect([execucao.reload.estado, registros(execucao)]).to eq(['falhou', [%w[p1 falhou tipo_desconhecido]]])
    expect(dados_do(execucao, 'p1')).to eq('tipo' => 'teletransportar')
  end

  # Sem mensagem para ler, a resposta da IA seria vazia ou inventada: os passos pulam sem chamar.
  it 'extrair, escrever e resumir sem nada para ler pulam com nada_para_ler, sem chamar a IA', :aggregate_failures do
    atributo('placa', 'conversation_attribute')
    vazia = create(:conversation, account: account, contact: contato, status: :open)
    so_mensagens = %w[mensagens_recentes]
    passos = [extrair([campo('placa', 'conversa.atributos.placa')]).merge('id' => 'p1', 'le' => so_mensagens),
              escrever('sugestao').merge('id' => 'p2', 'le' => so_mensagens), resumir('nota').merge('id' => 'p3', 'le' => so_mensagens)]
    openai_devolve({ 'texto' => 'x' })

    execucao = comecar_e_rodar(automacao_ligada(account, admin, passos), vazia)

    expect([execucao.reload.estado, registros(execucao)]).to eq(
      ['concluida', [%w[p1 pulado nada_para_ler], %w[p2 pulado nada_para_ler], %w[p3 pulado nada_para_ler]]]
    )
    expect(corpos).to be_empty
  end

  describe 'flag e chave' do
    it 'com a flag da F7 desligada ao rodar, para sem chamar a IA (rollback)', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [decidir])
      account.disable_features!('automacao_ia')
      openai_devolve({ 'caminho' => 'sinistro', 'motivo' => 'bateu' })

      execucao = comecar_e_rodar(definicao)

      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 pulado ia_desligada]]])
      expect(corpos).to be_empty
    end

    it 'só com a chave da plataforma conta como sem chave (D2 B): falha sem repetir e sem chamar', :aggregate_failures do
      account.hooks.destroy_all
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-plataforma')
      openai_devolve({ 'caminho' => 'sinistro', 'motivo' => 'bateu' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['falhou', [%w[p1 falhou ia_nao_configurada]]])
      expect(corpos).to be_empty
    end

    it 'a IA fora do ar tenta de novo, como a ação', :aggregate_failures do
      openai_devolve(503)

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect([execucao.reload.estado, execucao.cursor, registros(execucao)]).to eq(['esperando', 'p1', [%w[p1 falhou ia_indisponivel]]])
    end

    it 'resposta fora do schema falha sem repetir' do
      openai_devolve({ 'caminho' => 'outro', 'motivo' => 'inventou' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['falhou', [%w[p1 falhou resposta_fora_do_schema]]])
    end
  end

  describe 'decidir' do
    it 'segue pelo caminho escolhido e deixa o motivo numa nota, nunca no registro', :aggregate_failures do
      openai_devolve({ 'caminho' => 'sinistro', 'motivo' => 'O cliente bateu o carro.' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil], ['p2', 'ok', nil]]])
      expect(conversa.reload.priority).to eq('urgent')
      nota = conversa.messages.where(private: true).last
      expect(nota.content).to eq('A automação escolheu *Sinistro*: O cliente bateu o carro.')
      dados = dados_do(execucao, 'p1')
      expect(dados).to include('ramo' => 'sinistro', 'nota_id' => nota.id)
      expect(dados['ia']).to include('modelo' => Crm::Ai::Config::MODEL_CLASSIFY, 'tokens_entrada' => 1000, 'tokens_saida' => 200)
      expect(dados.to_json).not_to include('bateu')
    end

    it 'a resposta é presa às chaves dos caminhos mais "nenhum", e o "nenhum" segue pelo ramo dele', :aggregate_failures do
      openai_devolve({ 'caminho' => 'nenhum', 'motivo' => 'Não dá para saber.' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir(nenhum: [prioridade_passo('p3', 'low')])]))

      expect(corpos.first.dig('text', 'format', 'schema', 'properties', 'caminho', 'enum')).to eq(%w[sinistro cotacao nenhum])
      expect(registros(execucao)).to eq([['p1', 'ok', nil], ['p3', 'ok', nil]])
      expect(conversa.reload.priority).to eq('low')
    end

    # #2578: com um gatilho de toda mensagem e o "nenhum" como o normal, a nota viraria uma por mensagem.
    it 'o "nenhum" não deixa nota na conversa: o ramo fica só no histórico', :aggregate_failures do
      openai_devolve({ 'caminho' => 'nenhum', 'motivo' => 'Mensagem normal.' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect(conversa.messages.where(private: true)).to be_empty
      expect(dados_do(execucao, 'p1')).to include('ramo' => 'nenhum')
      expect(dados_do(execucao, 'p1').keys).not_to include('nota_id', 'nota_faltou')
      expect(dados_do(execucao, 'p1').to_s).not_to include('Mensagem normal.')
    end

    it 'o que a IA lê não leva o e-mail nem o telefone do contato' do
      openai_devolve({ 'caminho' => 'cotacao', 'motivo' => 'x' })

      comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect(corpos.first['input'].to_s).to include('Bati o carro').and(include('Bruno'))
      expect(corpos.first['input'].to_s).not_to include('contato@exemplo.com', '99999')
    end

    it 'a nota do motivo que falha não para a automação: segue pelo caminho e marca nota_faltou', :aggregate_failures do
      openai_devolve({ 'caminho' => 'sinistro', 'motivo' => 'bateu' })
      allow(Autonomia::Automacao::Nota).to receive(:criar).and_raise(ActiveRecord::RecordInvalid)

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil], ['p2', 'ok', nil]]])
      expect(dados_do(execucao, 'p1')).to include('ramo' => 'sinistro', 'nota_faltou' => true)
    end
  end

  describe 'extrair' do
    before do
      atributo('placa', 'conversation_attribute')
      atributo('data_sinistro', 'contact_attribute', 'date')
      atributo('carros', 'contact_attribute', 'number')
    end

    let(:campos) do
      [campo('placa', 'conversa.atributos.placa'), campo('data', 'contato.atributos.data_sinistro'),
       campo('carros', 'contato.atributos.carros'), campo('nome', 'contato.nome')]
    end

    it 'grava como quem ligou, só preenche, e o registro leva só as chaves', :aggregate_failures do
      openai_devolve({ 'placa' => 'ABC1D23', 'data' => '2026-11-03', 'carros' => nil, 'nome' => 'Bruno Lima' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos)]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil]]])
      expect(conversa.reload.custom_attributes).to eq('placa' => 'ABC1D23')
      expect([contato.reload.custom_attributes, contato.name]).to eq([{ 'data_sinistro' => '2026-11-03' }, 'Bruno'])
      dados = dados_do(execucao, 'p1')
      expect(dados['campos']).to eq('gravados' => %w[placa data], 'ausentes' => %w[carros], 'ja_tinha' => %w[nome])
      expect(dados.to_json).not_to include('ABC1D23', '2026-11-03')
    end

    # O que a IA devolve é dado, nunca fórmula do valor calculado (G16): o PassoDeAcao do extrair recebe valores: nil, e
    # a forma {"$valor": …} nunca chega a ele, porque a resposta fora do esquema (texto, número, sim/não) para antes.
    it 'valor da IA com a forma do valor calculado: para no esquema, sem ler nem gravar', :aggregate_failures do
      openai_devolve({ 'placa' => { '$valor' => 'contato.nome' }, 'data' => nil, 'carros' => nil, 'nome' => nil })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos)]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['falhou', [%w[p1 falhou resposta_fora_do_schema]]])
      expect(conversa.reload.custom_attributes).to eq({})
    end

    # O exemplo do aceite: "bati o carro ontem à noite" só vira data quando a IA sabe o dia em que a mensagem foi escrita.
    # A mensagem é das 23h30 de 3/11 em Cuiabá (já 4/11 em UTC) e o passo roda depois da meia-noite: o "ontem" é 2/11.
    it 'data relativa: a IA recebe hoje e a data de cada mensagem, no fuso da conta', :aggregate_failures do
      account.update!(custom_attributes: { 'timezone' => 'America/Cuiaba' })
      travel_to(Time.utc(2026, 11, 4, 3, 30)) do
        create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Oi, bati o carro ontem à noite')
      end
      openai_devolve({ 'placa' => nil, 'data' => '2026-11-02', 'carros' => nil, 'nome' => nil })

      travel_to(Time.utc(2026, 11, 4, 4, 10)) { comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos)])) }

      entrada = JSON.parse(corpos.first.dig('input', 0, 'content', 0, 'text'))
      expect(entrada['hoje']).to eq('2026-11-04')
      expect(entrada.dig('conversa', 'messages').last).to eq('[2026-11-03 23:30] Oi, bati o carro ontem à noite')
      expect(corpos.first['instructions']).to include('Data relativa')
      expect(contato.reload.custom_attributes).to eq('data_sinistro' => '2026-11-02')
    end

    it 'a resposta segue o tipo do atributo: número vira número no schema' do
      openai_devolve({ 'placa' => nil, 'data' => nil, 'carros' => 2, 'nome' => nil })

      comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos)]))

      propriedades = corpos.first.dig('text', 'format', 'schema', 'properties')
      expect(propriedades.transform_values { |item| item['type'] }).to eq(
        'placa' => %w[string null], 'data' => %w[string null], 'carros' => %w[number null], 'nome' => %w[string null]
      )
      expect(contato.reload.custom_attributes).to eq('carros' => 2)
    end

    # Registro que diz "gravado" do que não foi gravado é falha silenciosa.
    it 'falha parcial: o registro diz campo a campo o que gravou e o que a plataforma recusou', :aggregate_failures do
      allow(Autonomia::Automacao::PassoDeAcao).to receive(:new).and_wrap_original do |original, **argumentos|
        next original.call(**argumentos) unless argumentos[:passo]['acao'].start_with?('POST conversations')

        instance_double(Autonomia::Automacao::PassoDeAcao,
                        executar: Autonomia::Automacao::PassoDeAcao::Resultado.new(tipo: :permanente, motivo: 'erro_permanente', dados: {}))
      end
      openai_devolve({ 'placa' => 'ABC1D23', 'data' => '2026-11-03', 'carros' => nil, 'nome' => nil })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos)]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['falhou', [%w[p1 falhou erro_permanente]]])
      expect(dados_do(execucao, 'p1')['campos']).to eq('gravados' => %w[data], 'falhou' => %w[placa], 'ausentes' => %w[carros nome],
                                                       'ja_tinha' => [])
      expect([contato.reload.custom_attributes, conversa.reload.custom_attributes]).to eq([{ 'data_sinistro' => '2026-11-03' }, {}])
    end

    it 'o nome provisório (o telefone no lugar do nome) conta como vazio e é preenchido' do
      contato.update!(name: '+5511999990000')
      openai_devolve({ 'placa' => nil, 'data' => nil, 'carros' => nil, 'nome' => 'Bruno Lima' })

      comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos)]))

      expect(contato.reload.name).to eq('Bruno Lima')
    end

    it 'com trocar: true, o valor novo entra no lugar do antigo' do
      openai_devolve({ 'placa' => nil, 'data' => nil, 'carros' => nil, 'nome' => 'Bruno Lima' })

      comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos, trocar: true)]))

      expect(contato.reload.name).to eq('Bruno Lima')
    end

    it 'nada achado: pula com dado_ausente, e a automação segue', :aggregate_failures do
      openai_devolve({ 'placa' => nil, 'data' => 'ontem', 'carros' => nil, 'nome' => nil })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [extrair(campos), prioridade_passo('p2')]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [%w[p1 pulado dado_ausente], ['p2', 'ok', nil]]])
    end

    it 'quem ligou sem permissão de gravar o contato: pausa a automação, como na ação', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: conversa.inbox)
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage])
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      openai_devolve({ 'placa' => nil, 'data' => '2026-11-03', 'carros' => nil, 'nome' => nil })
      definicao = automacao_ligada(account, agente, [extrair(campos)])

      execucao = comecar_e_rodar(definicao)

      expect(execucao.reload.estado).to eq('parada')
      expect(registros(execucao).last.first(2)).to eq(%w[p1 falhou])
      expect([definicao.reload.ativa, contato.reload.custom_attributes]).to eq([false, {}])
    end
  end

  describe 'escrever' do
    it 'manda ao cliente pelo passo "mensagem", com o custo no registro', :aggregate_failures do
      ligar_mensagens(account)
      openai_devolve({ 'texto' => 'Obrigado, Bruno! Um corretor responde em até 1 hora.' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [escrever('mensagem')]))

      mensagem = conversa.messages.outgoing.where(private: false).last
      expect([mensagem.content, mensagem.sender, mensagem.content_attributes['automacao_id']]).to eq(
        ['Obrigado, Bruno! Um corretor responde em até 1 hora.', nil, execucao.automacao_id]
      )
      expect(dados_do(execucao, 'p1')).to include('mensagem_id' => mensagem.id)
      expect(dados_do(execucao, 'p1')['ia']).to include('modelo' => Crm::Ai::Config::MODEL_SUMMARY)
    end

    it 'sem a flag da F4, o escrever ao cliente para sem chamar a IA', :aggregate_failures do
      ligar_mensagens(account)
      definicao = automacao_ligada(account, admin, [escrever('mensagem')])
      account.disable_features!('automacao_mensagens')
      openai_devolve({ 'texto' => 'oi' })

      execucao = comecar_e_rodar(definicao)

      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 pulado mensagens_desligadas]]])
      expect(corpos).to be_empty
    end

    it 'o contato que pediu para não receber pula antes de pagar a IA', :aggregate_failures do
      ligar_mensagens(account)
      allow(Contact).to receive(:opted_out).and_return(Contact.where(id: contato.id))
      openai_devolve({ 'texto' => 'oi' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [escrever('mensagem')]))

      expect(registros(execucao)).to eq([%w[p1 pulado contato_nao_recebe]])
      expect(corpos).to be_empty
    end

    it 'destino sugestão: uma nota privada para a equipe revisar, sem a flag da F4', :aggregate_failures do
      openai_devolve({ 'texto' => 'Obrigado pelo contato!' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [escrever('sugestao')]))

      nota = conversa.messages.where(private: true).last
      expect(nota.content).to eq("Sugestão da automação (revise antes de mandar):\n\nObrigado pelo contato!")
      expect(dados_do(execucao, 'p1')).to include('nota_id' => nota.id)
      expect(conversa.messages.outgoing.where(private: false)).to be_empty
    end
  end

  # A nota do passo de IA é mensagem `nota`, e outra automação pode reagir a ela e pagar IA de novo. Quem segura é a
  # cadeia comum (proteção contra defeito, não teto de uso).
  describe 'nota que dispara outra automação' do
    let(:nota_criada) do
      { 'tipo' => 'mensagem.criada', 'filtros' => [{ 'campo' => { '$valor' => 'mensagem.tipo' }, 'op' => 'igual', 'valor' => 'nota' }] }
    end

    # A nota da equipe dispara A e B. A nota de A dispara B (cadeia [A, B]) e a de B dispara A (cadeia [B, A]). A nota
    # dessas segundas rodadas voltaria a quem já está na cadeia e é cortada: quatro rodadas, nunca um laço.
    it 'A gera nota que dispara B, B gera nota que dispararia A, e a volta é cortada', :aggregate_failures do
      a = automacao_ligada(account, admin, [resumir('nota')], gatilho: nota_criada)
      b = automacao_ligada(account, admin, [resumir('nota')], gatilho: nota_criada)
      openai_devolve({ 'resumo' => 'Quer acionar o seguro.' })

      perform_enqueued_jobs(only: [EventDispatcherJob, Autonomia::Automacao::AvancarJob]) do
        create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing, private: true,
                         sender: admin, content: 'Cliente ligou.')
      end

      execucoes = Autonomia::Automacao::Execucao.where(automacao: [a, b])
      expect(execucoes.map(&:cadeia)).to contain_exactly(
        ["automacao:#{a.id}"], ["automacao:#{b.id}"], ["automacao:#{a.id}", "automacao:#{b.id}"], ["automacao:#{b.id}", "automacao:#{a.id}"]
      )
      expect(execucoes.pluck(:estado).uniq).to eq(['concluida'])
      expect(corpos.size).to eq(4)
    end
  end

  describe 'resumir' do
    it 'destino nota: uma nota privada sem menção', :aggregate_failures do
      openai_devolve({ 'resumo' => 'Cliente bateu o carro e quer acionar o seguro.' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [resumir('nota')]))

      nota = conversa.messages.where(private: true).last
      expect(nota.content).to eq("Resumo da automação:\n\nCliente bateu o carro e quer acionar o seguro.")
      expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      expect(corpos.first['instructions']).to include('até 2 linhas')
    end

    # G41 (#2752, exemplo 10, passo 4): a instrução vai junto do texto fixo, sem trocá-lo.
    it 'com instrução, a IA recebe o texto fixo e a instrução', :aggregate_failures do
      openai_devolve({ 'resumo' => 'Quer o reembolso; o Rafael prometeu ligar hoje.' })
      passo = resumir('nota').merge('instrucao' => 'Inclua o que a equipe já prometeu ao cliente.')

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [passo]))

      expect(registros(execucao)).to eq([['p1', 'ok', nil]])
      expect(corpos.first['instructions']).to include('até 2 linhas', 'nunca invente', 'Inclua o que a equipe já prometeu ao cliente.')
    end

    it 'sem instrução, a IA recebe só o texto fixo' do
      openai_devolve({ 'resumo' => 'Quer acionar o seguro.' })

      comecar_e_rodar(automacao_ligada(account, admin, [resumir('nota')]))

      expect(corpos.first['instructions']).not_to include('Instrução')
    end

    it 'em aviso, ninguém para avisar pula antes de pagar a IA', :aggregate_failures do
      ligar_mensagens(account)
      openai_devolve({ 'resumo' => 'x' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [resumir({ 'avisar' => { 'responsavel' => true } })]))

      expect(registros(execucao)).to eq([%w[p1 pulado ninguem_para_avisar]])
      expect(corpos).to be_empty
    end

    it 'em aviso, menciona o responsável que vê a conversa', :aggregate_failures do
      ligar_mensagens(account)
      conversa.update!(assignee: admin)
      openai_devolve({ 'resumo' => 'Quer acionar o seguro.' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [resumir({ 'avisar' => { 'responsavel' => true } })]))

      nota = conversa.messages.where(private: true).last
      expect(nota.content).to start_with("Resumo da automação:\n\nQuer acionar o seguro.").and(include("mention://user/#{admin.id}/"))
      expect(dados_do(execucao, 'p1')).to include('pessoas' => [admin.id])
    end
  end

  # O #2508: no card, o passo age na conversa principal (NaConversa). Card sem ela não tem o que ler: pula sem pagar a IA.
  describe 'alvo card' do
    let(:funil) { create_crm_pipeline(account: account, user: admin) }

    let(:dois_caminhos) { [caminho('Sinistro', 'sinistro'), caminho('Cotação', 'cotacao')] }

    def card(principal)
      Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Pedido', currency: 'BRL',
                        primary_conversation: principal)
    end

    it 'sem conversa principal: os quatro passos pulam com sem_conversa, sem chamar a IA', :aggregate_failures do
      atributo('placa', 'conversation_attribute')
      openai_devolve({ 'caminho' => 'sinistro', 'motivo' => 'x' })
      passos = [decidir(caminhos: dois_caminhos).merge('id' => 'p1'),
                extrair([campo('placa', 'conversa.atributos.placa')]).merge('id' => 'p2'),
                escrever('sugestao').merge('id' => 'p3'), resumir('nota').merge('id' => 'p4')]

      execucao = comecar_e_rodar(automacao_ligada(account, admin, passos), card(nil))

      expect(registros(execucao)).to eq(%w[p1 p2 p3 p4].map { |id| [id, 'pulado', 'sem_conversa'] })
      expect([execucao.reload.estado, corpos]).to eq(['concluida', []])
    end

    it 'com conversa principal: decide lendo a conversa e deixa a nota nela', :aggregate_failures do
      openai_devolve({ 'caminho' => 'sinistro', 'motivo' => 'Bateu o carro' })

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [decidir(caminhos: dois_caminhos)]), card(conversa))

      expect([execucao.reload.estado, registros(execucao).first]).to eq(['concluida', ['p1', 'ok', nil]])
      expect(corpos.first.dig('input', 0, 'content', 0, 'text')).to include('Bati o carro ontem')
      expect(conversa.messages.where(private: true).last.content).to include('Sinistro', 'Bateu o carro')
    end
  end
end
