require 'rails_helper'

# #2881 — o modelo pronto de uma conversa do Construtor: o roteiro com as listas atuais no lugar dos marcadores, as
# ferramentas fixas do modelo com a frase "Use quando" do ramo (só as liberadas para a conta) e o que a tela recebe.
RSpec.describe Autonomia::Agents::ModelosDeRamo::Rascunho do
  include ModelosDeRamoHelper

  let(:account) { create(:account) }
  let(:modelo) { modelo_de_ramo('seguro_garantia') }
  let(:conversa) { conversa_com_modelo(account) }
  let(:rascunho) { described_class.do_thread(conversa) }
  let(:marca_do_modelo) { Autonomia::Agents::ModelosDeRamo::Marca }

  around { |example| com_pacotes_ligados { example.run } }

  before { liberar_modelos(account) }

  describe '.do_thread' do
    it 'devolve o modelo da conversa, com a marca copiada do arquivo' do
      expect(rascunho.modelo.chave).to eq('seguro_garantia')
      expect(rascunho.marca['perguntas'].pluck('texto')).to eq(modelo.perguntas)
      expect(rascunho.marca['perguntas'].pluck('id').first(2)).to eq(%w[p1 p2])
      expect(rascunho.marca['documentos'].first['id']).to eq('d1')
      expect(rascunho.marca['ferramentas'].pluck('fonte')).to eq(modelo.ja_vem.map(&:fonte))
    end

    it 'não existe sem modelo na conversa' do
      comum = Autonomia::Agents::BuildThread.create!(account: account)

      expect(described_class.do_thread(comum)).to be_nil
    end

    it 'some quando a flag é desligada, a conta sai do pacote seguros ou o modelo sai do ar' do
      conversa

      account.disable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)
      expect(described_class.do_thread(conversa.reload)).to be_nil

      account.enable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'false') { expect(described_class.do_thread(conversa.reload)).to be_nil }

      allow(Autonomia::Agents::ModelosDeRamo).to receive(:buscar).and_return(nil)
      expect(described_class.do_thread(conversa.reload)).to be_nil
    end

    it 'nunca vale para a Lia' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote')
      da_lia = Autonomia::Agents::BuildThread.create!(account: account, agent: lia,
                                                      state: { marca_do_modelo::CHAVE => marca_do_modelo.inicial(modelo) })

      expect(described_class.do_thread(da_lia)).to be_nil
    end
  end

  describe '#roteiro' do
    it 'troca cada marcador pela lista numerada do modelo e não deixa marcador no texto' do
      roteiro = rascunho.roteiro

      expect(roteiro).to include("1. #{modelo.perguntas.first}\n2. #{modelo.perguntas.second}")
      expect(roteiro).to include("1. #{modelo.documentos.first}\n2. #{modelo.documentos.second}")
      expect(roteiro).not_to include('{{PERGUNTAS_DA_COTACAO}}')
      expect(roteiro).not_to include('{{DOCUMENTOS}}')
      expect(roteiro).to start_with(modelo.roteiro.lines.first.chomp)
    end

    it 'usa a lista que o dono editou: o item novo entra, o tirado sai e a numeração acompanha' do
      perguntas = [{ 'id' => 'p1', 'texto' => 'Qual o CNPJ?', 'tirada' => false },
                   { 'id' => 'p2', 'texto' => 'Pergunta tirada?', 'tirada' => true },
                   { 'id' => 'p11', 'texto' => 'A obra já começou?', 'tirada' => false }]
      roteiro = rascunho.com(rascunho.marca.merge('perguntas' => perguntas)).roteiro

      expect(roteiro).to include("1. Qual o CNPJ?\n2. A obra já começou?")
      expect(roteiro).not_to include('Pergunta tirada?')
      expect(roteiro).not_to include(modelo.perguntas.last)
    end

    it 'não lê como marcador o que o dono escreveu dentro de um item' do
      perguntas = [{ 'id' => 'p1', 'texto' => 'Mande {{DOCUMENTOS}} agora', 'tirada' => false }]
      roteiro = rascunho.com(rascunho.marca.merge('perguntas' => perguntas)).roteiro

      expect(roteiro).to include('1. Mande {{DOCUMENTOS}} agora')
      expect(roteiro).to include("1. #{modelo.documentos.first}")
    end

    it 'diz que a lista está vazia quando o dono tirou tudo, sem derrubar o roteiro' do
      roteiro = rascunho.com(rascunho.marca.merge('documentos' => [])).roteiro

      expect(roteiro).to include(marca_do_modelo::LISTA_VAZIA)
      expect(roteiro).not_to include('{{DOCUMENTOS}}')
    end

    it 'aguenta as duas listas cheias no limite (20 itens de 300 letras) sem cortar nem levantar' do
      cheia = Array.new(20) { |i| { 'id' => "p#{i + 1}", 'texto' => 'á' * 300, 'tirada' => false } }
      roteiro = rascunho.com(rascunho.marca.merge('perguntas' => cheia, 'documentos' => cheia)).roteiro

      expect(roteiro.scan("20. #{'á' * 300}").size).to eq(2)
    end
  end

  describe 'as ferramentas fixas do modelo' do
    it 'não oferece nenhuma sem as prontas do Construtor ligadas na conta' do
      expect(rascunho.ferramentas).to eq([])
      expect(rascunho.tambem).to eq([])
      expect(rascunho.chaves_das_prontas).to eq('ferramentas_sugeridas' => [], 'ferramentas_tambem' => [])
    end

    it 'traz as do "Já vem com" liberadas para a conta, cada uma com a frase do ramo; a de flag desligada some' do
      ligar_prontas_do_construtor(account)
      frases = modelo.ja_vem.to_h { |ferramenta| [ferramenta.fonte, ferramenta.usar_quando] }

      # compras_governo é do lote 2 (flag desligada nesta conta).
      expect(rascunho.ferramentas.pluck('fonte')).to eq(%w[cnpj feriados cep])
      expect(rascunho.ferramentas).to all(satisfy { |ferramenta| ferramenta['usar_quando'] == frases[ferramenta['fonte']] })
      expect(rascunho.tambem.pluck('fonte')).to eq(%w[cidades banco_central])
      expect(rascunho.tambem.first['usar_quando']).to eq(modelo.tambem.first.usar_quando)
    end

    it 'volta a oferecer a fonte quando a flag dela é ligada' do
      ligar_prontas_do_construtor(account)
      account.enable_features!(Autonomia::FerramentasProntas::Fontes::ComprasGoverno::FLAG)

      expect(rascunho.ferramentas.pluck('fonte')).to eq(%w[cnpj compras_governo feriados cep])
    end

    it 'leva ao "Também combina" a ferramenta que o dono tirou e guarda a frase que ele alterou' do
      ligar_prontas_do_construtor(account)
      editado = rascunho.com(rascunho.marca.merge('ferramentas' => [{ 'fonte' => 'cnpj', 'usar_quando' => 'Use quando eu mandar.' },
                                                                    { 'fonte' => 'cidades', 'usar_quando' => 'Use para a cidade.' }]))

      expect(editado.ferramentas).to eq([{ 'fonte' => 'cnpj', 'usar_quando' => 'Use quando eu mandar.' },
                                         { 'fonte' => 'cidades', 'usar_quando' => 'Use para a cidade.' }])
      expect(editado.tambem.pluck('fonte')).to eq(%w[feriados cep banco_central])
      expect(rascunho.ferramentas.pluck('fonte')).to eq(%w[cnpj feriados cep])
    end

    it 'deixa de fora o que a pessoa já dispensou naquele agente' do
      ligar_prontas_do_construtor(account)
      agente = Autonomia::Agents::Agent.create!(account: account, name: 'Rascunho', agent_type: 'sdr',
                                                config: { 'prontas_dispensadas' => %w[cep cidades] })
      conversa.update!(agent: agente)

      expect(rascunho.ferramentas.pluck('fonte')).to eq(%w[cnpj feriados])
      expect(rascunho.tambem.pluck('fonte')).to eq(%w[banco_central])
    end

    it 'só sugere os cartões pagos que a conta vê na vitrine' do
      ligar_prontas_do_construtor(account)
      expect(rascunho.premium).to eq([])

      account.enable_features!(Autonomia::FerramentasProntas::Premium::FLAG)
      expect(rascunho.premium).to eq(modelo.premium & Autonomia::FerramentasProntas::Catalogo.premium.map(&:chave))
    end
  end

  describe '#para_tela' do
    it 'entrega o modelo para a tela, sem o roteiro' do
      ligar_prontas_do_construtor(account)
      tela = rascunho.para_tela

      expect(tela.keys).to eq(%w[chave ramo nome_padrao seguradoras_sugeridas perguntas documentos ferramentas tambem premium teste])
      expect(tela.slice('chave', 'ramo', 'nome_padrao')).to eq('chave' => 'seguro_garantia', 'ramo' => modelo.ramo,
                                                               'nome_padrao' => modelo.nome_padrao)
      expect(tela['perguntas'].first).to eq('id' => 'p1', 'texto' => modelo.perguntas.first, 'tirada' => false)
      expect(tela['ferramentas'].first.keys).to eq(%w[fonte usar_quando])
      expect(tela['teste']).to eq(modelo.teste)
      expect(tela.to_json).not_to include('ROTEIRO POR SITUAÇÃO')
    end
  end

  describe '.marca_de_inicio' do
    it 'não devolve marca para chave desconhecida nem para conta que não pode usar' do
      outra = create(:account)

      expect(described_class.marca_de_inicio(account: account, agent: nil, chave: 'seguro_de_vida')).to be_nil
      expect(described_class.marca_de_inicio(account: account, agent: nil, chave: nil)).to be_nil
      expect(described_class.marca_de_inicio(account: outra, agent: nil, chave: 'seguro_garantia')).to be_nil
    end

    it 'herda a marca do rascunho que nasceu de um modelo, com o que o dono já mudou' do
      mudada = marca_do_modelo.inicial(modelo).merge('documentos' => [])
      rascunho_do_agente = Autonomia::Agents::Agent.create!(account: account, name: 'Rascunho', agent_type: 'sdr',
                                                            config: { marca_do_modelo::CHAVE => mudada })

      expect(described_class.marca_de_inicio(account: account, agent: rascunho_do_agente, chave: nil)).to eq(mudada)
      expect(described_class.marca_de_inicio(account: account, agent: rascunho_do_agente, chave: 'seguro_auto')).to be_nil
    end

    it 'nunca dá modelo a um agente que já existe sem a marca, nem ao que já começou a atender' do
      sem_marca = Autonomia::Agents::Agent.create!(account: account, name: 'Comum', agent_type: 'sdr')
      ativo = Autonomia::Agents::Agent.create!(account: account, name: 'Ativo', agent_type: 'sdr', status: :active,
                                               config: { marca_do_modelo::CHAVE => marca_do_modelo.inicial(modelo) })

      expect(described_class.marca_de_inicio(account: account, agent: sem_marca, chave: 'seguro_garantia')).to be_nil
      expect(described_class.marca_de_inicio(account: account, agent: ativo, chave: 'seguro_garantia')).to be_nil
    end
  end
end
