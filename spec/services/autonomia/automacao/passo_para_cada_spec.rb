require 'rails_helper'

# O passo "para cada item" de ponta a ponta (#2414 G24, #2771): o RH manda a lista na conversa, a IA (simulada no HTTP)
# devolve os itens, e cada item vira um card na etapa, com o contato achado pelo telefone ou criado pela linha do
# Importar contatos, como quem ligou.
RSpec.describe Autonomia::Automacao::PassoParaCada, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Inclusões') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:empresa) { account.companies.create!(name: 'Alfa Metalúrgica') }
  let(:rh) { create(:contact, account: account, name: 'Rita do RH', phone_number: '+5511900000001', company: empresa) }
  let(:conversa) { create(:conversation, account: account, contact: rh, status: :open) }
  let(:corpos) { [] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos', 'companies')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming,
                     content: 'Inclusões: João Lima 11 98888-0001, Maria Souza 11 98888-0002, Pedro Alves')
  end

  after { Current.reset }

  def openai_devolve(itens)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: { 'itens' => itens }.to_json, usage: { input_tokens: 900, output_tokens: 150 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def item(nome, telefone = nil) = { 'nome' => nome, 'telefone' => telefone }

  def para_cada(maximo: 20)
    { 'id' => 'lista', 'tipo' => 'para_cada', 'le' => %w[mensagens_recentes], 'descricao' => 'Cada funcionário novo da lista',
      'campos' => [{ 'chave' => 'nome', 'descricao' => 'Nome completo' }, { 'chave' => 'telefone', 'descricao' => 'WhatsApp' }],
      'etapa_id' => etapa.id, 'maximo' => maximo }
  end

  def rodar(passos = [para_cada], por: admin)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, por, passos), conversa) }
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def dados_do(execucao) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'lista').dados

  it 'abre um card por item: acha o contato pelo telefone, cria os novos e liga à empresa do RH', :aggregate_failures do
    joao = create(:contact, account: account, name: 'João', phone_number: '+551188880001', email: nil)
    openai_devolve([item('João Lima', '11 98888-0001'), item('Maria Souza', '(11) 98888-0002'), item('Pedro Alves')])

    execucao = rodar

    expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['lista', 'ok', nil]]])
    expect(joao.reload).to have_attributes(name: 'João', phone_number: '+551188880001', company_id: empresa.id)
    maria = account.contacts.find_by!(phone_number: '+5511988880002')
    pedro = account.contacts.find_by!(name: 'Pedro Alves')
    expect(maria).to have_attributes(name: 'Maria Souza', company_id: empresa.id)
    expect(pedro).to have_attributes(phone_number: nil, company_id: empresa.id)
    cards = funil.cards.order(:id)
    expect(cards.map(&:contact_id)).to eq([joao.id, maria.id, pedro.id])
    expect(cards.map(&:conversation_id)).to all(be_nil)
    expect(dados_do(execucao)).to include('quantos' => 3, 'passou_do_limite' => 0, 'cards_criados' => 3, 'contatos_novos' => 2,
                                          'empresas_ligadas' => 3, 'pulados' => {}, 'card_ids' => cards.map(&:id))
    expect(execucao.textos).to eq({})
  end

  it 'o registro e o pedido à IA não levam nome nem telefone de ninguém da lista', :aggregate_failures do
    openai_devolve([item('Maria Souza', '11 98888-0002')])

    execucao = rodar

    expect(dados_do(execucao).to_json).not_to include('Maria', '98888')
    expect(corpos.sole.dig('text', 'format', 'name')).to eq('automacao_para_cada')
    expect(corpos.sole['instructions']).to include('No máximo 20 itens', 'Cada funcionário novo da lista', '- nome: Nome completo')
  end

  it 'contato de outra empresa fica nela, e o nome e o telefone de quem já existe não mudam', :aggregate_failures do
    outra = account.companies.create!(name: 'Outra')
    maria = create(:contact, account: account, name: 'Maria S.', phone_number: '+5511988880002', email: nil, company: outra)
    openai_devolve([item('Maria Souza', '11 98888-0002')])

    execucao = rodar

    expect(maria.reload).to have_attributes(name: 'Maria S.', company_id: outra.id)
    expect(dados_do(execucao)).to include('contatos_novos' => 0, 'empresas_ligadas' => 0, 'cards_criados' => 1)
  end

  it 'os outros campos vão para o contato como as colunas extras do Importar contatos, só o que ele não tem', :aggregate_failures do
    nascimento = { 'chave' => 'data_nascimento', 'descricao' => 'Data de nascimento' }
    passo = para_cada.merge('campos' => para_cada['campos'] + [nascimento])
    joao = create(:contact, account: account, name: 'João', phone_number: '+5511988880001', email: nil,
                            custom_attributes: { 'data_nascimento' => '01/01/1980' })
    openai_devolve([item('João Lima', '11 98888-0001').merge('data_nascimento' => '12/03/1990'),
                    item('Maria Souza', '11 98888-0002').merge('data_nascimento' => '05/07/1985'),
                    item('Pedro Alves').merge('data_nascimento' => nil)])

    rodar([passo])

    expect(joao.reload.custom_attributes).to eq('data_nascimento' => '01/01/1980')
    expect(account.contacts.find_by!(phone_number: '+5511988880002').custom_attributes).to eq('data_nascimento' => '05/07/1985')
    expect(account.contacts.find_by!(name: 'Pedro Alves').custom_attributes).to eq({})
    definicao = account.custom_attribute_definitions.contact_attribute.sole
    expect(definicao).to have_attributes(attribute_key: 'data_nascimento', attribute_display_type: 'text')
  end

  it 'o campo extra com atributo de data já na conta é convertido como no import, e o que não serve fica de fora' do
    account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'data_nascimento',
                                                 attribute_display_name: 'Data de nascimento', attribute_display_type: :date)
    passo = para_cada.merge('campos' => para_cada['campos'] + [{ 'chave' => 'data_nascimento', 'descricao' => 'Data de nascimento' }])
    openai_devolve([item('Maria Souza', '11 98888-0002').merge('data_nascimento' => 'quando der'),
                    item('Pedro Alves').merge('data_nascimento' => '12/03/1990')])

    rodar([passo])

    expect([account.contacts.find_by!(name: 'Maria Souza'), account.contacts.find_by!(name: 'Pedro Alves')].map(&:custom_attributes))
      .to eq([{}, { 'data_nascimento' => ContactImports::AttributeValue.new(account.custom_attribute_definitions.sole).cast('12/03/1990') }])
  end

  it 'duas execuções no mesmo contato somam os campos: a segunda não apaga o que a primeira gravou', :aggregate_failures do
    nascimento = { 'chave' => 'data_nascimento', 'descricao' => 'Data de nascimento' }
    cargo = { 'chave' => 'cargo', 'descricao' => 'Cargo' }
    openai_devolve([item('Bruno Dias', '11 98888-0003').merge('data_nascimento' => '01/02/1990')])
    rodar([para_cada.merge('campos' => para_cada['campos'] + [nascimento])])
    openai_devolve([item('Bruno Dias', '11 98888-0003').merge('cargo' => 'Soldador')])
    rodar([para_cada.merge('campos' => para_cada['campos'] + [cargo])])

    bruno = account.contacts.find_by!(phone_number: '+5511988880003')
    expect(bruno.custom_attributes).to eq('data_nascimento' => '01/02/1990', 'cargo' => 'Soldador')
  end

  it 'o campo que a conta recusa criar como atributo falha o passo com motivo próprio, sem marcar o contato como recusado',
     :aggregate_failures do
    em_branco = { 'chave' => ' ', 'descricao' => 'Data de nascimento' }
    # Uma receita salva antes da conferência da chave em branco: ao salvar de novo, ela não passaria.
    sem_problemas = instance_double(Autonomia::Automacao::ProblemasDoParaCada, problemas: [])
    allow(Autonomia::Automacao::ProblemasDoParaCada).to receive(:new).and_return(sem_problemas)
    openai_devolve([item('Bruno Dias', '11 98888-0003').merge(' ' => '01/02/1990')])

    execucao = rodar([para_cada.merge('campos' => para_cada['campos'] + [em_branco])])

    expect([execucao.reload.estado, registros(execucao)]).to eq(['falhou', [%w[lista falhou atributo_recusado]]])
    expect(dados_do(execucao)['pulados']).to eq({})
    expect(account.contacts.where(name: 'Bruno Dias')).to be_empty
    expect(funil.cards).to be_empty
  end

  it 'os passos seguintes leem quantos e os nomes da lista', :aggregate_failures do
    ligar_mensagens(account)
    openai_devolve([item('João Lima'), item('Maria Souza')])
    nota = { 'id' => 'aviso', 'tipo' => 'avisar', 'para' => { 'responsavel' => true },
             'texto' => ['Recebi ', { '$valor' => 'ia.lista.quantos' }, ': ', { '$valor' => 'ia.lista.nomes' }] }
    conversa.update!(assignee: admin)

    execucao = rodar([para_cada, nota])

    expect(registros(execucao)).to eq([['lista', 'ok', nil], ['aviso', 'ok', nil]])
    expect(conversa.messages.where(private: true).last.content).to include('Recebi 2: João Lima, Maria Souza')
  end

  it 'fica com os primeiros até o máximo e conta o resto em passou_do_limite', :aggregate_failures do
    openai_devolve([item('A Um'), item('B Dois'), item('C Três')])

    execucao = rodar([para_cada(maximo: 2)])

    expect(funil.cards.count).to eq(2)
    expect(dados_do(execucao)).to include('quantos' => 2, 'passou_do_limite' => 1)
  end

  it 'o contato com card aberto no funil não ganha outro, e o telefone que não é celular pula o item', :aggregate_failures do
    joao = create(:contact, account: account, name: 'João', phone_number: '+5511988880001', email: nil)
    aberto = account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'João', contact: joao)
    openai_devolve([item('João Lima', '11988880001'), item('Zé', '123')])

    execucao = rodar

    expect(funil.cards.pluck(:id)).to eq([aberto.id])
    expect(dados_do(execucao)).to include('cards_criados' => 0, 'pulados' => { 'card_ja_existe' => 1, 'telefone_invalido' => 1 })
    expect(account.contacts.where(name: 'Zé')).to be_empty
  end

  it 'a lista já guardada na execução (nova tentativa) não vai à IA de novo', :aggregate_failures do
    openai_devolve([item('Outro Nome')])
    execucao = comecar(automacao_ligada(account, admin, [para_cada]), conversa)
    execucao.guardar_texto!('lista.itens', [item('João Lima')])

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)

    expect(corpos).to be_empty
    expect(funil.cards.sole.contact.name).to eq('João Lima')
  end

  it 'sem lista na conversa, pula com lista_vazia e não cria nada', :aggregate_failures do
    openai_devolve([])

    execucao = rodar

    expect(registros(execucao)).to eq([%w[lista pulado lista_vazia]])
    expect(funil.cards).to be_empty
  end

  it 'quem ligou sem permissão de importar contatos pausa a automação, sem pagar a IA', :aggregate_failures do
    definicao = automacao_ligada(account, admin, [para_cada])
    allow(CampaignImports::ContactRow).to receive(:allowed?).and_return(false)
    openai_devolve([item('João Lima')])

    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

    expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[lista falhou quem_ligou_sem_permissao_importar]]])
    expect(execucao.automacao.reload.ativa).to be(false)
    expect(corpos).to be_empty
  end
end
