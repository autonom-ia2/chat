require 'rails_helper'

# #2881 — o dono muda o modelo pronto antes de começar (pedido do Rodrigo): tira, edita e inclui perguntas e
# documentos; tira ferramenta, inclui as do "Também combina" e altera a frase "Use quando". Fica no state da conversa
# e na marca do rascunho do agente, sem chamada de IA. Validação estrita: o que falha não grava nada.
RSpec.describe Autonomia::Agents::ModelosDeRamo::Edicao do
  include ModelosDeRamoHelper

  let(:account) { create(:account) }
  let(:modelo) { modelo_de_ramo('seguro_garantia') }
  let(:conversa) { conversa_com_modelo(account) }
  let(:chave_da_marca) { Autonomia::Agents::ModelosDeRamo::Marca::CHAVE }

  around { |example| com_pacotes_ligados { example.run } }

  before do
    liberar_modelos(account)
    ligar_prontas_do_construtor(account)
  end

  # Sem parâmetro nomeado de propósito: `editar(perguntas: [...])` chega como o hash das mudanças.
  def editar(mudancas, alvo = conversa)
    described_class.new(thread: alvo, mudancas: mudancas).call
  end

  def recusa(mudancas, alvo = conversa)
    editar(mudancas, alvo)
    nil
  rescue described_class::Recusada => e
    [e.motivo, e.campo]
  end

  def marca
    conversa.reload.state[chave_da_marca]
  end

  # O agente já atendendo, direto no banco: o caminho de verdade ("Começar") exige um canal, que não é o assunto aqui.
  def comecar!(alvo)
    alvo.update_columns(status: Autonomia::Agents::Agent.statuses[:active], enabled: true) # rubocop:disable Rails/SkipsModelValidations
  end

  describe 'perguntas e documentos' do
    it 'edita o texto, tira um item e inclui um novo, com id novo só para o que é novo' do
      editar(perguntas: [{ id: 'p1', texto: '  Para que é a   garantia?  ' },
                         { id: 'p2', texto: modelo.perguntas.second, tirada: true },
                         { texto: 'A obra já começou?' }])

      expect(marca['perguntas']).to eq([{ 'id' => 'p1', 'texto' => 'Para que é a garantia?', 'tirada' => false },
                                        { 'id' => 'p2', 'texto' => modelo.perguntas.second, 'tirada' => true },
                                        { 'id' => "p#{modelo.perguntas.size + 1}", 'texto' => 'A obra já começou?', 'tirada' => false }])
    end

    it 'só troca a lista que veio: as outras ficam como estavam' do
      antes = marca

      editar(documentos: [{ texto: 'Contrato social.' }])

      expect(marca['documentos'].pluck('texto')).to eq(['Contrato social.'])
      expect(marca.slice('chave', 'perguntas', 'ferramentas')).to eq(antes.slice('chave', 'perguntas', 'ferramentas'))
    end

    it 'não perde a edição de outra aba: cada pedido parte do que o anterior gravou, não da cópia que tinha' do
      outra_aba = Autonomia::Agents::BuildThread.find(conversa.id)

      editar(perguntas: [{ texto: 'A obra já começou?' }])
      editar({ documentos: [{ texto: 'Contrato social.' }] }, outra_aba)

      expect(marca['perguntas'].pluck('texto')).to eq(['A obra já começou?'])
      expect(marca['documentos'].pluck('texto')).to eq(['Contrato social.'])
    end

    it 'aceita a lista vazia (o dono tirou tudo) e o id desconhecido como item novo' do
      editar(documentos: [], perguntas: [{ id: 'inventado', texto: 'Qual o CNPJ?' }, { id: 'p9', texto: 'Qual o prazo?' }])

      expect(marca['documentos']).to eq([])
      expect(marca['perguntas'].pluck('id')).to eq(["p#{modelo.perguntas.size + 1}", 'p9'])
    end

    it 'recusa o que não é lista de objetos, a lista com mais de 20 itens e o id repetido' do
      muitos = Array.new(21) { |i| { texto: "Pergunta #{i}?" } }

      expect(recusa(perguntas: 'Qual o CNPJ?')).to eq(%w[lista_invalida perguntas])
      expect(recusa(documentos: ['Contrato social.'])).to eq(%w[lista_invalida documentos])
      expect(recusa(perguntas: muitos)).to eq(%w[lista_invalida perguntas])
      expect(recusa(perguntas: [{ id: 'p1', texto: 'Uma?' }, { id: 'p1', texto: 'Outra?' }])).to eq(%w[id_repetido perguntas])
    end

    it 'recusa texto vazio, que não é texto ou com mais de 300 letras, e tirada que não é verdadeiro ou falso' do
      expect(recusa(perguntas: [{ texto: '   ' }])).to eq(%w[texto_invalido perguntas])
      expect(recusa(perguntas: [{ texto: 123 }])).to eq(%w[texto_invalido perguntas])
      expect(recusa(perguntas: [{ texto: { 'a' => 'b' } }])).to eq(%w[texto_invalido perguntas])
      expect(recusa(documentos: [{ texto: 'a' * 301 }])).to eq(%w[texto_invalido documentos])
      expect(recusa(documentos: [{ texto: 'Contrato.', tirada: 'talvez' }])).to eq(%w[tirada_invalida documentos])
    end

    it 'não grava nada quando uma das listas é recusada' do
      antes = marca

      expect(recusa(perguntas: [{ texto: 'Pergunta boa?' }], documentos: [{ texto: '' }])).to eq(%w[texto_invalido documentos])
      expect(marca).to eq(antes)
    end
  end

  describe 'ferramentas' do
    it 'tira uma, inclui uma do "Também combina" e altera a frase; sem frase vale a do ramo' do
      resultado = editar(ferramentas: [{ fonte: 'cnpj', usar_quando: '  Use quando o cliente   mandar o CNPJ. ' },
                                       { fonte: 'cidades' }, { fonte: 'cep', usar_quando: '' }])

      expect(marca['ferramentas']).to eq([{ 'fonte' => 'cnpj', 'usar_quando' => 'Use quando o cliente mandar o CNPJ.' },
                                          { 'fonte' => 'cidades', 'usar_quando' => modelo.tambem.first.usar_quando },
                                          { 'fonte' => 'cep', 'usar_quando' => modelo.ja_vem.last.usar_quando },
                                          { 'fonte' => 'compras_governo', 'usar_quando' => modelo.ja_vem.second.usar_quando }])
      expect(resultado.ferramentas.pluck('fonte')).to eq(%w[cnpj cidades cep])
      expect(resultado.tambem.pluck('fonte')).to eq(%w[feriados banco_central])
    end

    # compras_governo é do modelo, mas de uma fase desligada nesta conta: a tela não a recebe e nunca a manda de volta.
    it 'mantém na marca a ferramenta que a tela não recebe: ela não some por não vir na lista' do
      resultado = editar(ferramentas: [{ fonte: 'cep' }])

      expect(marca['ferramentas'].pluck('fonte')).to eq(%w[cep compras_governo])
      expect(resultado.ferramentas.pluck('fonte')).to eq(%w[cep])
      expect(resultado.tambem.pluck('fonte')).not_to include('compras_governo')
    end

    it 'não repete a ferramenta fora da tela quando a lista a traz' do
      editar(ferramentas: [{ fonte: 'compras_governo' }, { fonte: 'cep' }])

      expect(marca['ferramentas'].pluck('fonte')).to eq(%w[compras_governo cep])
    end

    it 'mantém em dia as chaves que a Confira já lê' do
      editar(ferramentas: [{ fonte: 'cep' }])

      expect(conversa.reload.state.slice('ferramentas_sugeridas', 'ferramentas_tambem'))
        .to eq('ferramentas_sugeridas' => %w[cep], 'ferramentas_tambem' => %w[cnpj feriados cidades banco_central])
    end

    it 'recusa fonte que não é do modelo (mesmo sendo do catálogo), Premium, repetida ou que não é texto' do
      expect(recusa(ferramentas: [{ fonte: 'fipe' }])).to eq(%w[fonte_invalida ferramentas])
      expect(recusa(ferramentas: [{ fonte: 'raio_x_empresa' }])).to eq(%w[fonte_invalida ferramentas])
      expect(recusa(ferramentas: [{ fonte: 'cnpj' }, { fonte: 'cnpj' }])).to eq(%w[fonte_invalida ferramentas])
      expect(recusa(ferramentas: [{ usar_quando: 'Use sempre.' }])).to eq(%w[fonte_invalida ferramentas])
      expect(recusa(ferramentas: [{ fonte: %w[cnpj] }])).to eq(%w[fonte_invalida ferramentas])
    end

    it 'recusa a frase que não é texto ou passa do limite do "Incluir"' do
      expect(recusa(ferramentas: [{ fonte: 'cnpj', usar_quando: 42 }])).to eq(%w[usar_quando_invalido ferramentas])
      expect(recusa(ferramentas: [{ fonte: 'cnpj', usar_quando: 'a' * 501 }])).to eq(%w[usar_quando_invalido ferramentas])
      expect(recusa(ferramentas: (1..21).map { { fonte: 'cnpj' } })).to eq(%w[lista_invalida ferramentas])
    end
  end

  describe 'o rascunho do agente' do
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Novo agente', agent_type: 'sdr', instruction: 'Instrução fechada.',
                                       config: { chave_da_marca => conversa.state[chave_da_marca], 'guardrails' => ['regra'] })
    end

    before { conversa.update!(agent: agente) }

    it 'leva a mudança para a marca do rascunho, sem tocar na instrução nem no resto do config' do
      editar(documentos: [{ texto: 'Contrato social.' }], ferramentas: [{ fonte: 'cnpj' }])
      config = agente.reload.config

      expect(config[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
      expect(config['ferramentas_sugeridas']).to eq(%w[cnpj])
      expect(config['guardrails']).to eq(['regra'])
      expect(agente.instruction).to eq('Instrução fechada.')
      expect(Autonomia::Agents::ModelosDeRamo::Instrucao.do_agente(agente)).to include("DOCUMENTOS:\n1. Contrato social.")
    end

    it 'não mexe na data de alteração do agente: mudar uma lista não cancela o Desfazer nem um ajuste em andamento' do
      antes = agente.reload.updated_at

      editar(documentos: [{ texto: 'Contrato social.' }])

      expect(agente.reload.updated_at).to eq(antes)
      expect(agente.config[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
    end

    it 'não chama o Construtor nem modelo de IA nenhum' do
      allow(Crm::Ai::ResponsesClient).to receive(:new)

      editar(perguntas: [{ texto: 'Qual o CNPJ?' }])

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'recusa quando o agente já começou a atender' do
      comecar!(agente)
      antes = agente.reload.config

      expect(recusa(documentos: [])).to eq(['agente_ja_comecou', nil])
      expect(agente.reload.config).to eq(antes)
    end

    it 'confere com o agente travado, não pela cópia que a conversa tinha, e a recusa não grava nada na conversa' do
      antes = marca
      expect(conversa.agent).to be_draft
      comecar!(Autonomia::Agents::Agent.find(agente.id))

      expect(recusa(documentos: [])).to eq(['agente_ja_comecou', nil])
      expect(marca).to eq(antes)
    end
  end

  describe 'pelo rascunho do agente, sem a conversa (a tela reaberta)' do
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Novo agente', agent_type: 'sdr',
                                       config: { chave_da_marca => conversa.state[chave_da_marca], 'guardrails' => ['regra'] })
    end

    # O conhecimento do ramo não é editável: a edição das listas tem de deixá-lo como nasceu, na conversa e no rascunho.
    it 'mantém o conhecimento do ramo na marca, pela conversa e pelo agente' do
      saber = Autonomia::Agents::ModelosDeRamo::Marca.inicial(modelo)['conhecimento']
      expect(saber).to be_present

      editar(documentos: [{ texto: 'Contrato social.' }])
      expect(agente.reload.config[chave_da_marca]['conhecimento']).to eq(saber)
      expect(conversa.reload.state[chave_da_marca]['conhecimento']).to eq(saber)

      described_class.new(agent: agente, mudancas: { perguntas: [{ texto: 'A obra já começou?' }] }).call
      expect(agente.reload.config[chave_da_marca]['conhecimento']).to eq(saber)
    end

    def editar_pelo_agente(mudancas, alvo = agente)
      described_class.new(agent: alvo, mudancas: mudancas).call
    end

    it 'grava na marca do agente, sem tocar no resto do config nem na conversa' do
      antes = marca

      editar_pelo_agente(documentos: [{ texto: 'Contrato social.' }], ferramentas: [{ fonte: 'cnpj' }])
      config = agente.reload.config

      expect(config[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
      expect(config['ferramentas_sugeridas']).to eq(%w[cnpj])
      expect(config['guardrails']).to eq(['regra'])
      expect(marca).to eq(antes)
    end

    it 'não perde a edição de outra aba' do
      outra_aba = Autonomia::Agents::Agent.find(agente.id)

      editar_pelo_agente(perguntas: [{ texto: 'A obra já começou?' }])
      editar_pelo_agente({ documentos: [{ texto: 'Contrato social.' }] }, outra_aba)

      listas = agente.reload.config[chave_da_marca]
      expect(listas['perguntas'].pluck('texto')).to eq(['A obra já começou?'])
      expect(listas['documentos'].pluck('texto')).to eq(['Contrato social.'])
    end

    it 'recusa o agente que não nasceu de um modelo' do
      comum = Autonomia::Agents::Agent.create!(account: account, name: 'Comum', agent_type: 'support', instruction: 'Atenda.')
      expect { editar_pelo_agente({ perguntas: [] }, comum) }.to raise_error(described_class::Recusada, 'sem_modelo')
    end

    # #2976 — depois do "Começar" as duas listas continuam mudando pela página do agente.
    it 'muda perguntas e documentos do agente que já começou a atender, sem tocar no resto do config' do
      comecar!(agente)
      antes = agente.reload.config

      editar_pelo_agente(perguntas: [{ texto: 'A obra já começou?' }], documentos: [{ texto: 'Contrato social.' }])

      depois = agente.reload.config
      expect(depois[chave_da_marca]['perguntas'].pluck('texto')).to eq(['A obra já começou?'])
      expect(depois[chave_da_marca]['documentos'].pluck('texto')).to eq(['Contrato social.'])
      expect(depois[chave_da_marca].except('perguntas', 'documentos')).to eq(antes[chave_da_marca].except('perguntas', 'documentos'))
      expect(depois.except(chave_da_marca)).to eq(antes.except(chave_da_marca))
    end

    it 'entrega a lista nova ao agente que atende já no turno seguinte' do
      comecar!(agente)

      editar_pelo_agente(perguntas: [{ texto: 'A obra já começou?' }])

      expect(Autonomia::Agents::ModelosDeRamo::Instrucao.do_agente(agente.reload)).to include("PERGUNTAS DA COTAÇÃO:\n1. A obra já começou?")
    end

    it 'recusa mexer nas ferramentas do agente que já começou a atender, dizendo o campo, sem gravar nem registrar' do
      comecar!(agente)
      antes = agente.reload.config
      allow(Autonomia::Agents::ModelosDeRamo::RegistroDaMudanca).to receive(:gravar!)

      expect { editar_pelo_agente(perguntas: [], ferramentas: [{ fonte: 'cnpj' }]) }.to raise_error(described_class::Recusada) do |erro|
        expect([erro.motivo, erro.campo]).to eq(%w[agente_ja_comecou ferramentas])
      end
      expect(agente.reload.config).to eq(antes)
      expect(Autonomia::Agents::ModelosDeRamo::RegistroDaMudanca).not_to have_received(:gravar!)
    end
  end

  describe 'isolamento' do
    it 'recusa a conversa sem modelo pronto' do
      comum = Autonomia::Agents::BuildThread.create!(account: account)

      expect(recusa({ perguntas: [] }, comum)).to eq(['sem_modelo', nil])
      expect(comum.reload.state).not_to have_key(chave_da_marca)
    end

    it 'recusa com a flag desligada e com a conta fora do pacote seguros, sem gravar' do
      antes = marca

      account.disable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)
      expect(recusa(perguntas: [])).to eq(['sem_modelo', nil])

      account.enable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)
      account.update!(internal_attributes: account.internal_attributes.merge(Autonomia::Agents::Nicho::NICHO_KEY => 'geral'))
      expect(recusa(perguntas: [])).to eq(['sem_modelo', nil])
      expect(marca).to eq(antes)
    end

    it 'recusa a Lia' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote')
      da_lia = Autonomia::Agents::BuildThread.create!(account: account, agent: lia,
                                                      state: { chave_da_marca => conversa.state[chave_da_marca] })

      expect(recusa({ perguntas: [] }, da_lia)).to eq(['sem_modelo', nil])
      expect(lia.reload.config).not_to have_key(chave_da_marca)
    end

    it 'recusa o agente de sistema, mesmo com uma conversa ligada a ele' do
      de_sistema = Autonomia::Agents::Agent.create!(account: account, name: 'Guia', agent_type: 'custom',
                                                    config: { chave_da_marca => conversa.state[chave_da_marca], 'system_key' => 'guia' })
      da_conversa = Autonomia::Agents::BuildThread.create!(account: account, agent: de_sistema,
                                                           state: { chave_da_marca => conversa.state[chave_da_marca] })
      antes = de_sistema.config

      expect(recusa({ perguntas: [] }, da_conversa)).to eq(['sem_modelo', nil])
      expect(de_sistema.reload.config).to eq(antes)
      expect(Autonomia::Agents::ModelosDeRamo::Rascunho.para_a_criacao(da_conversa)).to be_nil
    end

    it 'só mexe na conversa e no agente que recebeu: a de outra conta fica como estava' do
      outra_conta = create(:account)
      liberar_modelos(outra_conta)
      alheia = conversa_com_modelo(outra_conta)
      antes = alheia.state[chave_da_marca]

      editar(perguntas: [])

      expect(alheia.reload.state[chave_da_marca]).to eq(antes)
    end
  end
end
