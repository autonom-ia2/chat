require 'rails_helper'

# "Criar com IA" e "Melhorar com IA" da tela de Modelos (#1333). A IA é sempre simulada: nenhum spec chama IA paga.
# O POST confere o pedido e enfileira (202 + poll_url, padrão `DeferInteractiveAi`); o job escreve com 25 s e 1 nova
# tentativa, e o resultado sai em GET ai_requests/:id.
RSpec.describe 'Api::V1::Accounts::WhatsappTemplateSuggestions', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/whatsapp_template_suggestions" }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:bom) { 'Oi, {{cliente.primeiro_nome}}! Seu horário é em {{publico.data}} às {{publico.horario}}. Se precisar mudar, é só responder.' }
  let(:whatsapp) do
    { cabecalho: nil, rodape: nil, nome_sugerido: 'lembrete_horario',
      botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar', chave: nil }] }
  end

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    account.enable_features!('whatsapp_templates_journey')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def responde(textos, status: 'ok', pergunta: nil, sugestoes: [])
    opcoes = textos.map do |texto|
      { texto: texto, chaves_usadas: [], o_que_mudou: 'Ficou mais curto.', categoria_prevista: 'servico', certeza_categoria: 'alta',
        motivo_categoria: 'Fala do horário do cliente.', whatsapp: whatsapp }
    end
    allow(client).to receive(:create).and_return(
      text: { status: status, pergunta: pergunta, sugestoes: sugestoes, problemas_encontrados: [], opcoes: opcoes }.to_json
    )
  end

  def pedir(user: admin, **params)
    post path, params: params, headers: user.create_new_auth_token, as: :json
  end

  # O que a tela recebe depois do job: o `result` do GET ai_requests/:id.
  def resultado(user: admin)
    expect(response).to have_http_status(:accepted)
    aceito = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(aceito['id'])
    get aceito['poll_url'], headers: user.create_new_auth_token, as: :json
    expect(response.parsed_body['status']).to eq('done')
    response.parsed_body['result']
  end

  it 'criar: devolve as opções, pela feature modelo_redacao, com o tom e o tipo desejado indo como limites' do
    responde([bom])

    pedir(mode: 'create', goal: 'lembrar do horário de amanhã', tone: 'curto', category: 'aviso')

    option = resultado.dig('payload', 'options', 0)
    expect(option).to include('text' => bom, 'category' => 'servico', 'name' => 'lembrete_horario',
                              'buttons' => [{ 'tipo' => 'resposta_rapida', 'texto' => 'Confirmar', 'chave' => nil }])
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'modelo_redacao', max_retries: 1))
    expect(client).to have_received(:create) do |args|
      expect(args[:timeout]).to eq(25)
      entrada = JSON.parse(args[:input])
      expect(entrada['pedido']).to eq('lembrar do horário de amanhã')
      expect(entrada['limites']).to eq('max_chars' => 200, 'categoria_desejada' => 'servico', 'sem_midia' => true)
      expect(entrada['canal']).to eq('whatsapp_modelo')
    end
  end

  it 'melhorar: manda o texto como base e as melhorias como dado; campo do catálogo do texto vale' do
    texto = 'Oi, {{cliente.primeiro_nome}}! Seu horário é {{horario.data_hora}}. Qualquer dúvida, responda.'
    melhor = 'Oi, {{cliente.primeiro_nome}}! Lembrete: {{horario.data_hora}}. Qualquer dúvida, responda aqui.'
    responde([melhor])

    pedir(mode: 'improve', text: texto, improvements: %w[mais_claro], category: 'aviso', meta_reason: 'INVALID_FORMAT')

    expect(resultado.dig('payload', 'options', 0, 'text')).to eq(melhor)
    expect(client).to have_received(:create) do |args|
      entrada = JSON.parse(args[:input])
      expect(entrada['base']).to eq(texto)
      expect(entrada['pedido']).to eq('melhorias' => %w[mais_claro], 'observacao' => nil,
                                      'recusa_da_meta' => { 'motivo' => 'INVALID_FORMAT' })
      expect(entrada['chaves']['permitidas'].pluck('chave')).to include('horario.data_hora', 'publico.valor')
    end
  end

  it 'pedido vago: devolve a pergunta e as sugestões, sem opções' do
    responde([], status: 'precisa_mais_info', pergunta: 'Sobre o que é a mensagem?', sugestoes: ['Lembrar horário'])

    pedir(mode: 'create', goal: 'mandar mensagem')

    expect(resultado['payload']).to include('status' => 'precisa_mais_info', 'question' => 'Sobre o que é a mensagem?',
                                            'suggestions' => ['Lembrar horário'], 'options' => [])
  end

  it 'sem opção que passe na conferência, sem IA ou com a IA fora do ar: o resultado traz a frase simples' do
    frase = I18n.t('whatsapp_templates.errors.suggestion_unavailable', locale: :pt_BR)
    responde(['{{cliente.primeiro_nome}}, seu horário é amanhã.'])
    pedir(mode: 'create', goal: 'lembrar do horário')
    expect(resultado).to eq('error' => 'suggestion_unavailable', 'message' => frase)

    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')
    pedir(mode: 'create', goal: 'lembrar do horário')
    expect(resultado).to eq('error' => 'suggestion_unavailable', 'message' => frase)

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))
    pedir(mode: 'create', goal: 'lembrar do horário')
    expect(resultado).to eq('error' => 'suggestion_unavailable', 'message' => frase)
  end

  it 'guarda no pedido só o que o modo usa, já conferido' do
    pedir(mode: 'create', goal: '  lembrar do horário  ', tone: 'gritando', category: 'aviso', text: 'sobra', meta_reason: 'x')
    criar = Crm::Ai::InteractiveRequest.read(response.parsed_body['id'])['inputs']
    expect(criar).to eq('mode' => 'create', 'goal' => 'lembrar do horário', 'tone' => '', 'category' => 'aviso')

    pedir(mode: 'improve', text: 'Oi, {{cliente.primeiro_nome}}! Até.', improvements: %w[mais_claro mais_claro], tone: 'curto',
          category: 'outra', meta_reason: 'm' * 300)
    melhorar = Crm::Ai::InteractiveRequest.read(response.parsed_body['id'])['inputs']
    expect(melhorar).to include('improvements' => %w[mais_claro], 'tone' => 'curto', 'category' => '')
    expect(melhorar['meta_reason'].length).to eq(120)
    expect(melhorar.keys).not_to include('goal')
  end

  it 'o resultado é só de quem pediu' do
    responde([bom])
    pedir(mode: 'create', goal: 'lembrar do horário')
    aceito = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(aceito['id'])
    outro = create(:user, account: account, role: :administrator)

    get aceito['poll_url'], headers: outro.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'flag desligada depois do pedido: o job não chama a IA' do
    responde([bom])
    pedir(mode: 'create', goal: 'lembrar do horário')
    aceito = response.parsed_body
    account.disable_features!('whatsapp_templates_journey')

    Crm::Ai::InteractiveJob.perform_now(aceito['id'])

    expect(Crm::Ai::InteractiveRequest.read(aceito['id'])['status']).to eq('failed')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'recusa pedido fora do formato sem chamar a IA' do
    [{ mode: 'create', goal: '' }, { mode: 'create', goal: 'a' * 301 }, { mode: 'outro', goal: 'x' },
     { mode: 'improve', text: 'Oi', improvements: %w[virar_servico] }, { mode: 'improve', text: 'Oi', improvements: [] },
     { mode: 'improve', text: 'Oi {{cliente.cpf}} tudo bem', improvements: %w[mais_claro] },
     { mode: 'improve', text: 'Oi {{1}} tudo bem', improvements: %w[mais_claro] },
     { mode: 'improve', text: 'a' * 1025, improvements: %w[mais_claro] }].each do |params|
      expect { pedir(**params) }.not_to have_enqueued_job(Crm::Ai::InteractiveJob)
      expect(response).to have_http_status(:unprocessable_entity), params.to_s
      expect(response.parsed_body['error']).to eq('suggestion_invalid')
    end
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'sem a flag da conta, 404 sem chamar a IA' do
    account.disable_features!('whatsapp_templates_journey')

    pedir(mode: 'create', goal: 'lembrar do horário')

    expect(response).to have_http_status(:not_found)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'agente sem whatsapp_templates_manage não usa' do
    pedir(mode: 'create', goal: 'lembrar do horário', user: agent)

    expect(response).to have_http_status(:unauthorized)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end
end
