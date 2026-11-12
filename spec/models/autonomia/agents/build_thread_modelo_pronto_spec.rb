require 'rails_helper'

# #2881 — a abertura da conversa do Construtor com um modelo pronto de ramo. A chave só vale quando existe e a conta
# pode usar (pacote seguros e a flag): aí a conversa guarda a marca do modelo e o tipo passa a ser o dele. Fora disso,
# a conversa abre como antes, sem erro.
RSpec.describe Autonomia::Agents::BuildThread do
  include ModelosDeRamoHelper

  let(:account) { create(:account) }
  let(:modelo) { modelo_de_ramo('seguro_garantia') }
  let(:chave_da_marca) { Autonomia::Agents::ModelosDeRamo::Marca::CHAVE }

  around { |example| com_pacotes_ligados { example.run } }

  def abrir(conta: account, modelo: 'seguro_garantia', type: 'support', **opcoes)
    described_class.new(account: conta, **opcoes).tap do |conversa|
      conversa.persist_start_options!(type: type, actuation: 'external', with_knowledge: false, modelo: modelo)
      conversa.save!
    end
  end

  describe '#persist_start_options! com modelo' do
    before { liberar_modelos(account) }

    it 'guarda a marca do modelo e usa o tipo dele, não o que veio no pedido' do
      conversa = abrir(type: 'support')
      marca = conversa.reload.state[chave_da_marca]

      expect(conversa.state['agent_type']).to eq('sdr')
      expect(marca['chave']).to eq('seguro_garantia')
      expect(marca['perguntas'].pluck('texto')).to eq(modelo.perguntas)
      expect(marca['perguntas']).to all(include('tirada' => false))
      expect(marca['documentos'].pluck('texto')).to eq(modelo.documentos)
      expect(marca['ferramentas']).to eq(modelo.ja_vem.map { |f| { 'fonte' => f.fonte, 'usar_quando' => f.usar_quando } })
    end

    it 'mantém as outras escolhas da abertura' do
      conversa = abrir

      expect(conversa.state.slice('actuation', 'with_knowledge')).to eq('actuation' => 'external', 'with_knowledge' => false)
    end

    it 'abre os três modelos do piloto' do
      %w[seguro_auto seguro_garantia transporte_carga].each do |chave|
        expect(abrir(modelo: chave).state.dig(chave_da_marca, 'chave')).to eq(chave)
      end
    end

    it 'ignora chave desconhecida, vazia ou ausente, sem erro e com o tipo pedido' do
      ['seguro_de_vida', '', nil].each do |chave|
        conversa = abrir(modelo: chave, type: 'support')

        expect(conversa.state).not_to have_key(chave_da_marca)
        expect(conversa.state['agent_type']).to eq('support')
      end
    end

    it 'herda a marca do rascunho que nasceu de um modelo, com o que o dono já mudou' do
      mudada = Autonomia::Agents::ModelosDeRamo::Marca.inicial(modelo).merge('documentos' => [])
      rascunho = Autonomia::Agents::Agent.create!(account: account, name: 'Novo agente', agent_type: 'sdr',
                                                  config: { chave_da_marca => mudada })

      expect(abrir(modelo: nil, agent: rascunho).state[chave_da_marca]).to eq(mudada)
    end

    it 'não dá modelo ao agente que já existe sem a marca' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Comum', agent_type: 'support', instruction: 'Atenda.')

      expect(abrir(agent: comum).state).not_to have_key(chave_da_marca)
    end
  end

  describe 'quem não pode usar' do
    it 'abre como antes com a flag desligada' do
      conta_de_seguros(account)

      conversa = abrir(type: 'support')

      expect(conversa.state).not_to have_key(chave_da_marca)
      expect(conversa.state['agent_type']).to eq('support')
    end

    it 'abre como antes em conta sem o pacote seguros, mesmo com a flag' do
      account.enable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)

      expect(abrir.state).not_to have_key(chave_da_marca)
    end

    it 'deixa o state igual ao de uma abertura sem modelo' do
      sem_modelo = described_class.new(account: account)
      sem_modelo.persist_start_options!(type: 'sdr', actuation: 'both', with_knowledge: true)

      expect(abrir(type: 'sdr', modelo: nil).state.except('actuation', 'with_knowledge'))
        .to eq(sem_modelo.state.except('actuation', 'with_knowledge'))
      expect(sem_modelo.state.keys).to match_array(%w[agent_type actuation with_knowledge])
    end
  end

  describe '#juntar_ao_estado!' do
    let(:conversa) { described_class.create!(account: account, state: { 'agent_type' => 'sdr' }) }

    it 'junta as chaves no banco sem perder o que outro caminho gravou no meio' do
      copia_velha = described_class.find(conversa.id)
      conversa.update!(state: conversa.state.merge('canal_pedido' => 'whatsapp'))

      copia_velha.juntar_ao_estado!(chave_da_marca => { 'chave' => 'seguro_garantia' })

      expect(copia_velha.state).to eq('agent_type' => 'sdr', 'canal_pedido' => 'whatsapp',
                                      chave_da_marca => { 'chave' => 'seguro_garantia' })
    end

    it 'vale com a geração em andamento e não muda o status nem o token' do
      token = conversa.begin_build!

      conversa.juntar_ao_estado!('ferramentas_sugeridas' => %w[cnpj])

      expect(conversa.reload).to be_processing
      expect(conversa.build_token).to eq(token)
      expect(conversa.state['ferramentas_sugeridas']).to eq(%w[cnpj])
    end
  end
end
