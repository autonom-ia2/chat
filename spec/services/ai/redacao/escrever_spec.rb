require 'rails_helper'

# Redator de mensagens com IA (#1354, compartilhado com a fase E da Modelos #1333). A IA é sempre simulada aqui: nenhum
# spec chama IA paga.
RSpec.describe Ai::Redacao::Escrever do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:permitidas) { %w[cliente.primeiro_nome horario.data_hora horario.link_gestao minha_empresa.nome] }
  let(:obrigatorias) { %w[horario.link_gestao horario.data_hora] }
  let(:bom) { 'Oi, {{cliente.primeiro_nome}}! Seu horário é {{horario.data_hora}}. Para mudar: {{horario.link_gestao}}. Até lá!' }
  let(:outro_bom) { 'Olá! Lembrete do seu horário em {{horario.data_hora}}. Confirme em {{horario.link_gestao}}, por favor.' }

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def opcao(texto)
    { texto: texto, chaves_usadas: [], o_que_mudou: nil, categoria_prevista: 'servico', certeza_categoria: nil, motivo_categoria: nil }
  end

  def responde(opcoes, status: 'ok', pergunta: nil)
    allow(client).to receive(:create).and_return(
      text: { status: status, pergunta: pergunta, sugestoes: [], problemas_encontrados: [], opcoes: opcoes.map { |texto| opcao(texto) } }.to_json
    )
  end

  def escrever(**extra)
    described_class.call(account: account, feature: 'aviso_redacao', canal: 'whatsapp_texto', proposito: 'lembrete 1 dia antes',
                         limites: { max_chars: 200 }, chaves: { permitidas: permitidas, obrigatorias: obrigatorias },
                         tom: 'simpatico', contexto: { empresa: 'Studio' }, **extra)
  end

  it 'devolve as opções que passam na conferência, com as chaves lidas do texto e sem categoria no texto livre' do
    responde([bom, outro_bom])

    resultado = escrever

    expect(resultado[:status]).to eq('ok')
    expect(resultado[:opcoes].pluck(:texto)).to eq([bom, outro_bom])
    expect(resultado[:opcoes].first[:chaves_usadas]).to eq(%w[cliente.primeiro_nome horario.data_hora horario.link_gestao])
    expect(resultado[:opcoes].first[:categoria_prevista]).to be_nil
    expect(resultado[:descartadas]).to eq(0)
  end

  it 'chama pelo caminho da casa: feature do chamador, sem retry, cache por feature' do
    responde([bom])

    escrever

    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(hash_including(feature: 'aviso_redacao', account: account, max_retries: 0, cache_key_scope: :feature))
  end

  it 'manda 11 s, schema estrito com as chaves permitidas, o prompt do canal e o catálogo com exemplo fictício' do
    responde([bom])

    escrever

    expect(client).to have_received(:create) do |args|
      expect(args[:timeout]).to eq(11)
      expect(args[:schema][:strict]).to be(true)
      expect(args[:schema].dig(:schema, :'$defs', :opcao, :properties, :chaves_usadas, :items, :enum)).to eq(permitidas)
      expect(args[:instructions]).to include('# Canal: mensagem de texto livre no WhatsApp')
      entrada = JSON.parse(args[:input])
      expect(entrada['chaves']['permitidas'].first).to include('chave' => 'cliente.primeiro_nome', 'exemplo' => 'Ana')
      expect(entrada['tom']).to eq('kit' => nil, 'escolha' => 'simpatico')
    end
  end

  it 'descarta a opção que quebra regra (chave fora da lista, obrigatória ausente, campo no fim, longa, {{1}})' do
    ruins = ['Oi {{cliente.nome}}! {{horario.data_hora}} {{horario.link_gestao}}. Até!',
             'Oi! Seu horário: {{horario.link_gestao}}. Até!',
             'Oi! Seu horário é {{horario.data_hora}}. Mude em {{horario.link_gestao}}',
             "Oi! #{'a' * 200} {{horario.data_hora}} {{horario.link_gestao}}. Até!",
             'Oi {{1}}! {{horario.data_hora}} {{horario.link_gestao}}. Até!']
    responde(ruins + [bom])

    resultado = escrever

    expect(resultado[:opcoes].pluck(:texto)).to eq([bom])
    expect(resultado[:descartadas]).to eq(5)
  end

  it 'devolve a pergunta quando a IA precisa de mais informação, sem opções' do
    responde([bom], status: 'precisa_mais_info', pergunta: 'Sobre o que é o aviso?')

    resultado = escrever

    expect(resultado).to include(status: 'precisa_mais_info', pergunta: 'Sobre o que é o aviso?', opcoes: [])
  end

  it 'fica indisponível sem chave de IA, sem chamar o modelo' do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))

    expect { escrever }.to raise_error(described_class::Indisponivel, 'ai_not_configured')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'fica indisponível quando a IA erra ou devolve algo que não é JSON' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')
    expect { escrever }.to raise_error(described_class::Indisponivel)

    allow(client).to receive(:create).and_return(text: 'não é json')
    expect { escrever }.to raise_error(described_class::Indisponivel)

    allow(client).to receive(:create).and_return(text: '[1, 2]')
    expect { escrever }.to raise_error(described_class::Indisponivel, 'resposta_fora_do_formato')

    allow(client).to receive(:create).and_raise(OpenSSL::SSL::SSLError)
    expect { escrever }.to raise_error(described_class::Indisponivel, 'OpenSSL::SSL::SSLError')
  end

  it 'confere o texto da resposta antes de ler o JSON' do
    allow(client).to receive(:create).and_return(text: nil)
    expect { escrever }.to raise_error(described_class::Indisponivel, 'resposta_vazia')

    allow(client).to receive(:create).and_return({})
    expect { escrever }.to raise_error(described_class::Indisponivel, 'resposta_vazia')
  end

  it 'devolve o motivo quando o pedido não se aplica, sem opções' do
    responde([bom], status: 'nao_se_aplica', pergunta: 'Isto não é uma mensagem para cliente.')

    expect(escrever).to include(status: 'nao_se_aplica', pergunta: 'Isto não é uma mensagem para cliente.', opcoes: [])
  end

  it 'com tudo descartado, fica ok sem opções e conta as descartadas' do
    responde(['{{cliente.primeiro_nome}}, seu horário é {{horario.data_hora}}: {{horario.link_gestao}}. Até!',
              'Oi! Seu horário é {{horario.data_hora}}.'])

    expect(escrever).to include(status: 'ok', opcoes: [], descartadas: 2)
  end

  it 'descarta campo no começo do texto' do
    responde(['{{cliente.primeiro_nome}}, seu horário é {{horario.data_hora}}. Mude em {{horario.link_gestao}}. Até!', bom])

    expect(escrever[:opcoes].pluck(:texto)).to eq([bom])
  end

  it 'passa timeout e tentativas da chamada, e só os limites que o canal entende' do
    responde([bom])

    escrever(timeout: 30, max_retries: 2, limites: { max_chars: 200, categoria_desejada: 'servico', sem_midia: true })

    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(max_retries: 2))
    expect(client).to have_received(:create) do |args|
      expect(args[:timeout]).to eq(30)
      expect(JSON.parse(args[:input])['limites']).to eq('max_chars' => 200)
    end
  end

  describe 'modo melhorar' do
    let(:base) { 'Oi, {{cliente.primeiro_nome}}! Seu horário é {{horario.data_hora}}. Mude em {{horario.link_gestao}}. Até!' }
    let(:sem_nome) { 'Olá! Seu horário é {{horario.data_hora}}. Mude em {{horario.link_gestao}}. Até lá!' }
    let(:com_empresa) do
      'Oi, {{cliente.primeiro_nome}}! A {{minha_empresa.nome}} te espera em {{horario.data_hora}}. Mude em {{horario.link_gestao}}. Até!'
    end

    it 'descarta a opção que tira um campo da base' do
      responde([sem_nome, bom])

      expect(escrever(base: base, pedido: { melhorias: %w[mais_claro] })[:opcoes].pluck(:texto)).to eq([bom])
    end

    it 'em "mais curto", descarta a opção que traz campo novo; sem "mais curto", aceita' do
      responde([com_empresa, bom])
      expect(escrever(base: base, pedido: { melhorias: %w[mais_curto] })[:opcoes].pluck(:texto)).to eq([bom])

      expect(escrever(base: base, pedido: { melhorias: %w[mais_claro] })[:opcoes].pluck(:texto)).to eq([com_empresa, bom])
    end

    it 'manda a base e o pedido como dado, com recusa_da_meta' do
      responde([bom])

      escrever(base: base, pedido: { melhorias: %w[corrigir_recusa], observacao: nil, recusa_da_meta: { motivo: 'INVALID_FORMAT' } })

      expect(client).to have_received(:create) do |args|
        entrada = JSON.parse(args[:input])
        expect(entrada['base']).to eq(base)
        expect(entrada['pedido']['recusa_da_meta']).to eq('motivo' => 'INVALID_FORMAT')
      end
    end
  end

  it 'erro de programação não vira "indisponível": estoura' do
    allow(client).to receive(:create).and_raise(NoMethodError)

    expect { escrever }.to raise_error(NoMethodError)
  end

  it 'no texto livre, descarta a opção com endereço escrito à mão fora dos campos' do
    responde(['Oi! Seu horário é {{horario.data_hora}}. Mude em {{horario.link_gestao}} ou www.exemplo.com. Até!',
              'Oi! Seu horário é {{horario.data_hora}}. Mude em {{horario.link_gestao}} ou bit.ly/abc. Até!', bom])

    expect(escrever[:opcoes].pluck(:texto)).to eq([bom])
  end

  it 'recusa chave fora do catálogo e limite que não veio do chamador' do
    expect { escrever(chaves: { permitidas: %w[cliente.cpf], obrigatorias: [] }) }.to raise_error(ArgumentError)
    expect { escrever(limites: {}) }.to raise_error(ArgumentError)
  end

  describe 'canais' do
    it 'registra texto livre, campanha (#1335) e modelo (#1333) do WhatsApp e diz "não suportado ainda" para e-mail' do
      expect(Ai::Redacao::Canais.para('whatsapp_texto')).to eq(Ai::Redacao::Canais::WhatsappTexto)
      expect(Ai::Redacao::Canais.para('whatsapp_campanha')).to eq(Ai::Redacao::Canais::WhatsappCampanha) # #1335
      expect(Ai::Redacao::Canais.para('whatsapp_modelo')).to eq(Ai::Redacao::Canais::WhatsappModelo)

      %w[email].each do |canal|
        expect(Ai::Redacao::Canais).to be_conhecido(canal)
        expect { escrever(canal: canal) }.to raise_error(Ai::Redacao::Canais::NaoSuportado, /ainda não suportado/)
      end
      expect { escrever(canal: 'sms') }.to raise_error(Ai::Redacao::Canais::NaoSuportado, /desconhecido/)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'monta o prompt com o bloco comum antes do canal' do
      prompt = Ai::Redacao::Canais::WhatsappTexto.prompt

      expect(prompt.index('# Papel')).to be < prompt.index('# Canal: mensagem de texto livre no WhatsApp')
    end
  end
end
