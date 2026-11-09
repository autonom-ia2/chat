require 'rails_helper'

# Fechamento do épico #2414, lacuna G58 (#2779): o público "só quem esta automação criou nesta vez" no passo campanha
# (exemplo 9, passo 4: "Monta a campanha com o modelo aprovado e manda", logo depois de criar um card por empresa). É a
# prova que a sonda da G58 lê (FechamentoAutomacao::Lacunas).
#
# - Ao salvar, pela API da tela: sem um passo antes que crie card ou contato, a receita é recusada.
# - O envio: os contatos dos cards que a execução criou viram um Público (source 'automacao'), a Campanha sai ligada a
#   ele pela Campanha da tela, e o modelo para no receptor de teste (F9.7) só para esses números. Na segunda seguinte,
#   quem já tinha card (card_ja_existe) não recebe de novo, embora tenha a mesma etiqueta do mês.
#
# Limite desta prova, até a G21 (#2706): na main nenhum passo de um gatilho da conta grava card_ids (o "card" pede
# alvo e o "prospeccao" ainda não entrou). O registro do passo que cria os cards é gravado aqui como o executor o
# grava, com o contrato `card_ids` combinado com a G21, e a receita da versão vai direto ao banco, como fica com o passo
# da G21. O exemplo 9 de ponta a ponta fica no pendentes_spec até lá.
#
# Pendente: o contrato `card_ids`/`contato_ids` com a G21 (#2706) só está provado com o registro montado aqui. Quando a
# G21 entrar, um teste real precisa rodar o passo dela e ler o registro que ele grava de verdade.
RSpec.describe 'Fechamento #2414 · G58: campanha só para quem a execução criou', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:andre) { create(:user, account: account, role: :administrator, name: 'André Sócio') }
  let!(:mes) { create(:label, account: account, title: 'prospeccao_novembro') }
  let(:funil) { create_crm_pipeline(account: account, user: andre) }
  let(:apresentacao) do
    { 'name' => 'apresentacao_do_escritorio', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá! Somos o escritório {{1}}.' }] }
  end
  let(:segunda_8h) { { tipo: 'conta.recorrente', frequencia: 'semanal', dia_da_semana: 1, hora: 8 } }
  let(:criar_cards) { { id: 'cards', tipo: 'prospeccao' } }
  let(:campanha) do
    { id: 'apresentar', tipo: 'campanha', faz: 'disparar', publico: 'desta_execucao', titulo: 'Apresentação do escritório',
      caixa_id: inbox.id, modelo: { nome: 'apresentacao_do_escritorio', idioma: 'pt_BR', variaveis: [['Conta Certa']] } }
  end

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('whatsapp_campaign', 'automacao_gatilhos')
    canal.update!(message_templates: [apresentacao])
    receptor_whatsapp_cloud
    # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [apresentacao.merge('id' => '9001')] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  after { Current.reset }

  def empresa(nome, telefone)
    contato = create(:contact, account: account, name: nome, phone_number: telefone)
    contato.update!(label_list: ['prospeccao_novembro'])
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, contact: contato, owner: andre, title: nome, currency: 'BRL')
  end

  # Até a G21, o passo que cria os cards não salva num gatilho da conta: a versão ganha a receita direto no banco, como
  # ela fica com o passo da G21.
  def automacao_da_prospeccao
    receita = { gatilho: segunda_8h, passos: [criar_cards, campanha] }.deep_stringify_keys
    esperar = { 'id' => 'antes', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'minutos' } }
    automacao_ligada(account, andre, [esperar], gatilho: segunda_8h.deep_stringify_keys).tap do |automacao|
      Autonomia::Automacao::Versao.where(id: automacao.versao_ativa_id).update_all(receita: receita) # rubocop:disable Rails/SkipsModelValidations
    end.reload
  end

  # Uma segunda-feira: a execução da conta, o registro do passo que criou os cards (contrato da G21) e o passo campanha.
  def rodar_segunda(definicao, criados:, ja_existiam: [])
    execucao = definicao.execucoes.create!(account: account, versao: definicao.versao_ativa, alvo: account,
                                           chave_gatilho: 'conta.recorrente', estado: 'andando')
    registrar = lambda do |resultado, motivo, dados|
      Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'cards',
                                             resultado: resultado, motivo: motivo, dados: dados)
    end
    registrar.call('ok', nil, { 'card_ids' => criados.map(&:id) })
    ja_existiam.each { |card| registrar.call('pulado', 'card_ja_existe', { 'card_id' => card.id }) }
    passo = campanha.deep_stringify_keys
    resultado = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: passo, alvo: account).executar
    perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob)
    execucao.update!(estado: 'concluida')
    [execucao, resultado]
  end

  # O receptor guarda tudo (o id da mensagem da Meta de teste sai da contagem): `desde` pula os envios da semana anterior.
  def enviados(desde: 0) = chamadas_para('graph.facebook.com').drop(desde).map(&:corpo).pluck('to')

  it 'sem um passo antes que crie card ou contato, a API recusa ao salvar, com o motivo' do
    post api_automacoes(account), params: { nome: 'Prospecção', receita: { gatilho: segunda_8h, passos: [campanha] } },
                                  headers: andre.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t('autonomia.automacao.receita.campanha_publico_sem_origem', passo: 'apresentar', locale: :pt_BR))
  end

  it 'público desta execução não aceita etiquetas junto (o esquema recusa)' do
    receita = { gatilho: segunda_8h, passos: [campanha.merge(etiquetas: [mes.id])] }

    expect(Autonomia::Automacao::Receita.esquema_valido?(receita)).to be(false)
  end

  # Prova o passo campanha e o envio. Os cards criados entram pelo registro montado aqui (contrato da G21), não pelo
  # passo que cria: esse ponta a ponta é o exemplo 9, ainda no pendentes_spec.
  it 'com o registro da G21 montado, a campanha vai só às empresas criadas nesta vez, não às da semana anterior', :aggregate_failures do
    definicao = automacao_da_prospeccao
    semana1 = [empresa('Padaria Cambuí', '+5519900000001'), empresa('Oficina Barão', '+5519900000002')]

    execucao1, resultado1 = rodar_segunda(definicao, criados: semana1)

    publico1 = CampaignImport.find(resultado1.dados['publico_id'])
    expect(resultado1).to have_attributes(tipo: :ok, motivo: nil)
    expect(resultado1.dados).to include('contatos' => 2, 'fora' => 0)
    hoje = Time.current.in_time_zone(Autonomia::Automacao::Tempo.fuso(account)).to_date
    expect(publico1.name).to eq("Apresentação do escritório · #{hoje.strftime('%d/%m/%Y')}")
    expect(publico1.options).to include('source' => 'automacao', 'automacao_id' => definicao.id, 'execucao_id' => execucao1.id)
    expect(publico1.campaign_import_rows.pluck(:contact_id)).to match_array(semana1.map(&:contact_id))
    expect(CampaignAudienceLink.for_campaign(account.campaigns.find_by!(display_id: resultado1.dados['campanha_id'])).campaign_import_id)
      .to eq(publico1.id)
    expect(enviados).to contain_exactly('+5519900000001', '+5519900000002')
    expect(account.campaigns.find_by!(display_id: resultado1.dados['campanha_id']).sender).to eq(andre)
    ja_enviados = enviados.size

    semana2 = [empresa('Clínica Taquaral', '+5519900000003'), empresa('Pet Shop Guanabara', '+5519900000004')]
    _execucao2, resultado2 = rodar_segunda(definicao, criados: semana2, ja_existiam: semana1)

    expect(resultado2.dados).to include('contatos' => 2, 'fora' => 0)
    expect(CampaignImport.find(resultado2.dados['publico_id']).campaign_import_rows.pluck(:contact_id))
      .to match_array(semana2.map(&:contact_id))
    expect(enviados(desde: ja_enviados)).to contain_exactly('+5519900000003', '+5519900000004')
    expect(Contact.tagged_with('prospeccao_novembro').where(account: account).count).to eq(4)
  end

  it 'quem pediu para não receber depois de criado fica de fora e conta em "fora"' do
    definicao = automacao_da_prospeccao
    cards = [empresa('Padaria Cambuí', '+5519900000001'), empresa('Oficina Barão', '+5519900000002')]
    cards.last.contact.opt_out!(source: 'manual')

    _execucao, resultado = rodar_segunda(definicao, criados: cards)

    expect(resultado.dados).to include('contatos' => 1, 'fora' => 1)
    expect(enviados).to eq(['+5519900000001'])
  end
end
