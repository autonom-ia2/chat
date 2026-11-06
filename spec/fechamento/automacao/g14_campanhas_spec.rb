require 'rails_helper'

# Fechamento do épico #2414, lacuna G14 (#2630): campanhas como passo da Automação livre. É a prova que a sonda da G14
# lê (FechamentoAutomacao::Lacunas): montado pela API da tela, como o dono montaria, e o que sai para o cliente parando
# no receptor de teste (F9.7).
#
# - "Não receber" (exemplo 7, passo 6: "tira a pessoa de todas as campanhas"): o cliente escreve, a automação marca.
# - "Disparar" (exemplos 7, 9 e 16): a campanha da tela, para quem tem a etiqueta, com o modelo aprovado. Só em gatilho
#   sem alvo (recorrente, G7, ainda fora da main): num gatilho de conversa a API recusa ao salvar. O disparo em si é
#   provado no passo, até o pedido na Graph, pelo Whatsapp::OneoffCampaignService, que pula quem pediu para não receber.
# - Pôr e tirar da campanha (exemplos 2, 3, 6, 12) é a etiqueta do público, com o passo de etiqueta que já existe.
RSpec.describe 'Fechamento #2414 · G14: campanhas como passo', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Carla Dona') }
  let!(:ja_comprou) { create(:label, account: account, title: 'ja_comprou', description: 'Já comprou com a loja') }
  let(:pre_black) do
    { 'name' => 'pre_black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi! A Black começa {{1}}.' }] }
  end
  let(:disparar) do
    { id: 'pre_black', tipo: 'campanha', faz: 'disparar', titulo: 'Pré-Black', caixa_id: inbox.id,
      modelo: { nome: 'pre_black', idioma: 'pt_BR', variaveis: [['na quinta']] }, etiquetas: [ja_comprou.id] }
  end

  def cliente(nome, telefone, etiquetas: [])
    create(:contact, account: account, name: nome, phone_number: telefone).tap { |contato| contato.update!(label_list: etiquetas) }
  end

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('whatsapp_campaign')
    canal.update!(message_templates: [pre_black])
    receptor_whatsapp_cloud
  end

  after { Current.reset }

  it 'quem pede para não receber sai de todas as campanhas, marcado pela automação' do
    ana = cliente('Ana', '+5511900000011')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: ana, source_id: '5511900000011')
    conversa = create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox, status: :open)
    receita = {
      gatilho: { tipo: 'mensagem.criada', filtros: [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }] },
      passos: [{ id: 'nao_quer', tipo: 'campanha', faz: 'nao_receber' }]
    }
    automacao = montar_automacao(dona, account, nome: 'Não quer receber', receita: receita)
    ligar_automacao(dona, account, automacao)
    clear_enqueued_jobs

    cliente_escreve(conversa, 'Não quero mais receber promoção')

    expect(ana.reload).to have_attributes(opt_out_source: 'manual', opted_out_by_id: dona.id)
    expect(Autonomia::Automacao::Registro.where(automacao_id: automacao['id']).pluck(:passo, :resultado, :dados))
      .to eq([['nao_quer', 'ok', { 'contato_id' => ana.id }]])
  end

  it 'mandar campanha num gatilho de conversa é recusado ao salvar, com o motivo' do
    receita = { gatilho: { tipo: 'conversa.criada' }, passos: [disparar] }

    post api_automacoes(account), params: { nome: 'Pré-Black', receita: receita }, headers: dona.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t('autonomia.automacao.receita.campanha_so_sem_alvo', passo: 'pre_black', locale: :pt_BR))
  end

  it 'a campanha sai pela Campanha da tela, com o modelo, só para quem tem a etiqueta e não pediu para parar' do
    cliente('Bia', '+5511900000021', etiquetas: ['ja_comprou'])
    cliente('Caio', '+5511900000022', etiquetas: ['ja_comprou']).opt_out!(source: 'manual')
    cliente('Duda', '+5511900000023')
    # Salva como no recorrente (G7): o gatilho sem alvo ainda não está na main.
    allow(Autonomia::Automacao::PassoDeCampanha).to receive(:gatilho_sem_alvo?).and_return(true)
    # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [pre_black.merge('id' => '9001')] }.to_json, headers: { 'Content-Type' => 'application/json' })
    automacao = montar_automacao(dona, account, nome: 'Pré-Black', receita: { gatilho: { tipo: 'conversa.criada' }, passos: [disparar] })
    definicao = Autonomia::Automacao::Definicao.find(automacao['id'])
    definicao.update!(ligada_por: dona)
    execucao = Autonomia::Automacao::Execucao.new(automacao: definicao, account: account)

    resultado = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: disparar.deep_stringify_keys, alvo: nil).executar
    perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob)

    expect(resultado.tipo).to eq(:ok)
    expect(account.campaigns.last).to have_attributes(title: 'Pré-Black', campaign_status: 'completed')
    enviados = chamadas_para('graph.facebook.com').map(&:corpo)
    expect(enviados.pluck('to')).to eq(['+5511900000021'])
    expect(enviados.first['template']).to include('name' => 'pre_black')
    expect(enviados.first.dig('template', 'components', 0, 'parameters', 0, 'text')).to eq('na quinta')
  end
end
