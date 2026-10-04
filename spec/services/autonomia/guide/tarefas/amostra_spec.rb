require 'rails_helper'

# `planejar_tarefa` (#936): a amostra mostra o que vai mudar e NÃO muda nada. Recusa o que não pode
# virar tarefa, com o motivo em pt-BR.
RSpec.describe Autonomia::Guide::Tarefas::Amostra do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  before { simular_ia_do_cliente! }

  # AC-TL1 — com 60 contatos, a tarefa nasce `amostra_pronta` com total 60 e 10 pares, e nem o diário
  # nem os contatos recebem escrita.
  describe 'a amostra' do
    let!(:contatos) { contatos_em_maiusculas!(conta, 60) }

    it 'monta 10 pares de antes e depois, sem escrever nada', :aggregate_failures do
      carimbos = Contact.where(id: contatos.map(&:id)).pluck(:id, :updated_at)

      tarefa = nil
      expect { tarefa = planejar!(conta, admin, receita_de_nomes) }
        .not_to change(Autonomia::Guide::Mudanca, :count)

      expect(tarefa.status).to eq('amostra_pronta')
      expect(tarefa.total).to eq(60)
      expect(tarefa.itens.count).to eq(60)
      expect(tarefa.amostra.size).to eq(10)
      # A listagem de contatos não tem ordem garantida: confere a forma de cada par, não qual veio primeiro.
      expect(tarefa.amostra).to all(satisfy do |par|
        par['antes']['name'].start_with?('CLIENTE NUMERO') && par['depois'] == { 'name' => par['antes']['name'].titleize } &&
          par['ref'] == par['antes']['name']
      end)
      expect(Autonomia::Guide::Execucao.count).to eq(0)
      expect(Contact.where(id: contatos.map(&:id)).pluck(:id, :updated_at)).to match_array(carimbos)
      expect(Contact.where(id: contatos.map(&:id)).pluck(:name)).to all(start_with('CLIENTE'))
    end

    # LGPD: o item guarda só a referência.
    it 'guarda nos itens só o recurso e o id' do
      tarefa = planejar!(conta, admin, receita_de_nomes)

      expect(Autonomia::Guide::TarefaItem.column_names).not_to include('dados', 'antes', 'depois')
      expect(tarefa.itens.order(:posicao).first.attributes.slice('record_type', 'record_id'))
        .to eq('record_type' => 'contacts', 'record_id' => contatos.first.id)
    end

    # AC-TL13 — estimativa pelo custo real da amostra, teto 2× e a IA do cliente com a feature própria.
    it 'estima o custo e o tempo, com teto de 2× e a feature guia_tarefa', :aggregate_failures do
      expect(Crm::Ai::ResponsesClient).to receive(:new).with(hash_including(feature: 'guia_tarefa')).and_call_original

      tarefa = planejar!(conta, admin, receita_de_nomes)

      tokens = Crm::Ai::UsageRecorder.extract_tokens('input_tokens' => 1_000, 'output_tokens' => 200)
      por_item = Crm::Ai::UsageRecorder.cost_for(Autonomia::Guide::Tarefas::Gerador::MODELO, tokens).to_f / 10
      expect(tarefa.custo_estimado.to_f).to be_within(0.000001).of(por_item * 60)
      expect(tarefa.teto_custo.to_f).to be_within(0.000001).of(tarefa.custo_estimado.to_f * 2)
      expect(tarefa.tempo_estimado).to be >= 6
    end
  end

  # AC-TL13 — a amostra diz quantas classificações do Jev vai usar e recusa quando a cota não cabe.
  describe 'com classificação' do
    let(:receita) do
      receita_de_nomes('classificar' => { 'pergunta' => 'O nome está todo em maiúsculas?',
                                          'opcoes' => [{ 'chave' => 'sim', 'descricao' => 'todo em maiúsculas' },
                                                       { 'chave' => 'nao', 'descricao' => 'já está certo' }],
                                          'agir_quando' => ['sim'], 'certeza_minima' => 0.8 })
    end

    before do
      contatos_em_maiusculas!(conta, 12)
      allow_any_instance_of(TypesafeAi::Decisor).to receive(:decidir) # rubocop:disable RSpec/AnyInstance
        .and_return(TypesafeAi::Decisor::Resultado.new(resposta: 'sim', certeza: 0.9, modelo: 'jev'))
    end

    it 'mostra quantas classificações vai usar e quantas restam', :aggregate_failures do
      tarefa = planejar!(conta, admin, receita)

      expect(tarefa.jev_estimado).to eq(12)
      expect(tarefa.para_tela['jev_restante']).to eq(Autonomia::Decisores::LIMITE_MENSAL)
    end

    it 'recusa quando a cota do mês não cabe' do
      stub_const('Autonomia::Decisores::LIMITE_MENSAL', 5)

      expect { planejar!(conta, admin, receita) }
        .to raise_error(Autonomia::Guide::Tarefas::Recusada, /12 perguntas ao Jev.*5 neste mês/)
    end

    it 'pula na amostra o que a classificação manda pular, com o motivo' do
      allow_any_instance_of(TypesafeAi::Decisor).to receive(:decidir) # rubocop:disable RSpec/AnyInstance
        .and_return(TypesafeAi::Decisor::Resultado.new(resposta: 'nao', certeza: 0.95, modelo: 'jev'))

      expect(planejar!(conta, admin, receita).amostra.first).to eq('ref' => 'CLIENTE NUMERO 1', 'pulado' => 'fora_da_classificacao')
    end
  end

  # AC-TL2 — as recusas, sem criar tarefa.
  describe 'as recusas' do
    before { contatos_em_maiusculas!(conta, 3) }

    def recusa(quem, receita)
      mensagem = nil
      expect { planejar!(conta, quem, receita) }.to raise_error(Autonomia::Guide::Tarefas::Recusada) { |erro| mensagem = erro.message }
      expect(Autonomia::Guide::Tarefa.count).to eq(0)
      mensagem
    end

    it 'recusa ação sem desfazer (mensagem em massa)' do
      receita = receita_de_nomes('alvo' => { 'recurso' => 'conversations' }, 'acao' => 'POST conversations/:conversation_id/messages',
                                 'caminho' => { 'conversation_id' => { '$item' => 'id' } }, 'corpo' => { 'content' => 'Feliz aniversário!' })

      expect(recusa(admin, receita)).to include('não tem desfazer')
    end

    it 'recusa quem não administra' do
      agente = create(:user, account: conta, role: :agent)

      expect(recusa(agente, receita_de_nomes)).to eq(I18n.t('autonomia.guide.admin_only'))
    end

    it 'recusa mais de 5.000 itens' do
      stub_const('Autonomia::Guide::Tarefa::MAX_ITENS', 2)

      expect(recusa(admin, receita_de_nomes)).to include('2')
    end

    it 'recusa o corpo que a conferência reprova, com o caminho' do
      receita = receita_de_nomes('corpo' => { 'apelido_inventado' => 'x' })

      expect(recusa(admin, receita)).to include('não passou na conferência', 'apelido_inventado')
    end

    it 'recusa o corpo que cai num nó x-sem-volta' do
      allow_any_instance_of(Autonomia::Guide::Formatos::Conferencia).to receive(:sem_volta?).and_return(true) # rubocop:disable RSpec/AnyInstance

      expect(recusa(admin, receita_de_nomes)).to include('sem desfazer')
    end

    it 'recusa a receita incompleta, dizendo o que falta' do
      expect(recusa(admin, receita_de_nomes('acao' => '', 'corpo' => { 'name' => { '$jev' => true } })))
        .to include("falta 'acao'", "'$jev' precisa de 'classificar'")
    end
  end
end
