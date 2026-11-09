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

  it 'grava a rodada como importação de contatos da automação (Contatos > Importações), uma linha por item', :aggregate_failures do
    joao = create(:contact, account: account, name: 'João', phone_number: '+5511988880001', email: nil)
    openai_devolve([item('João Lima', '11 98888-0001'), item('Maria Souza', '(11) 98888-0002'), item('Zé', '123')])

    execucao = rodar

    importacao = account.campaign_imports.contact_imports.sole
    expect(importacao).to be_from_automation
    expect(importacao).to have_attributes(
      user_id: admin.id, name: execucao.automacao.nome, status: 'completed_with_failures', total_rows: 3, valid_rows: 2,
      invalid_rows: 1, imported_contacts_count: 2, existing_contacts_count: 1, failed_contacts_count: 0,
      companies_reused_count: 1, company_contacts_linked_count: 2, source_filename: nil
    )
    expect(importacao.options).to include('automacao_id' => execucao.automacao_id, 'execucao_id' => execucao.id)
    linhas = importacao.campaign_import_rows.order(:row_number)
    maria = account.contacts.find_by!(phone_number: '+5511988880002')
    expect(linhas.map { |linha| [linha.row_number, linha.status, linha.contact_id, linha.was_existing_contact] })
      .to eq([[1, 'imported', joao.id, true], [2, 'imported', maria.id, false], [3, 'invalid', nil, false]])
    expect(linhas.map(&:raw_phone_masked)).to all(include('•'))
    expect(linhas.map(&:raw_phone_masked).join).not_to include('98888')
    expect(linhas.last.error_messages).to eq(['invalid_brazilian_mobile_number'])
    expect(dados_do(execucao)['importacao_id']).to eq(importacao.id)
    expect(account.campaign_imports.campaign_flows).to be_empty
  end

  it 'a nova tentativa da rodada usa a mesma importação, sem duplicar linhas', :aggregate_failures do
    openai_devolve([item('Outro Nome')])
    execucao = comecar(automacao_ligada(account, admin, [para_cada]), conversa)
    execucao.guardar_texto!('lista.itens', [item('João Lima', '11 98888-0001')])
    anterior = Autonomia::Automacao::ImportacaoDoParaCada.abrir(execucao: execucao, passo_id: 'lista',
                                                                account_user: admin.account_users.first, total: 1)

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)

    expect(account.campaign_imports.contact_imports.sole).to eq(anterior.campaign_import)
    expect(anterior.campaign_import.reload).to have_attributes(status: 'completed', imported_contacts_count: 1)
    expect(anterior.campaign_import.campaign_import_rows.count).to eq(1)
  end

  # O passo direto, numa execução aberta: a mesma execução roda de novo, como na nova tentativa do executor.
  def rodar_o_passo(execucao)
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao.reload)
    described_class.new(execucao: execucao, passo: para_cada, alvo: conversa, acesso: acesso).executar
  end

  # Quem ligou perde a permissão de importar no meio: o 2º contato da rodada é negado.
  def negar_o_segundo_contato
    escritos = 0
    allow(CampaignImports::ContactRow).to receive(:new).and_wrap_original do |novo, *args, **opcoes|
      novo.call(*args, **opcoes).tap do |linha|
        allow(linha).to receive(:write).and_wrap_original do |escrever, row|
          escritos += 1
          raise CampaignImports::ContactRow::NotAllowed if escritos == 2

          escrever.call(row)
        end
      end
    end
  end

  it 'a rodada que pausa no 2º item deixa a importação em andamento, e a nova tentativa fecha sem duplicar linhas',
     :aggregate_failures do
    execucao = comecar(automacao_ligada(account, admin, [para_cada]), conversa)
    execucao.guardar_texto!('lista.itens', [item('João Lima', '11 98888-0001'), item('Maria Souza', '11 98888-0002'),
                                            item('Pedro Alves', '11 98888-0003')])
    negar_o_segundo_contato

    pausada = rodar_o_passo(execucao)

    importacao = account.campaign_imports.contact_imports.sole
    expect([pausada.tipo, pausada.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_importar'])
    expect(importacao).to have_attributes(status: 'importing', import_finished_at: nil, total_rows: 3,
                                          imported_contacts_count: 1, invalid_rows: 0, failed_contacts_count: 0)
    expect(importacao.campaign_import_rows.pluck(:row_number)).to eq([1])

    allow(CampaignImports::ContactRow).to receive(:new).and_call_original
    retomada = rodar_o_passo(execucao)

    expect(retomada.tipo).to eq(:ok)
    expect(account.campaign_imports.contact_imports.sole).to eq(importacao)
    expect(importacao.reload).to have_attributes(status: 'completed', imported_contacts_count: 3, failed_contacts_count: 0)
    expect(importacao.import_finished_at).to be_present
    expect(importacao.campaign_import_rows.order(:row_number).pluck(:row_number)).to eq([1, 2, 3])
    expect(funil.cards.count).to eq(3)
  end

  it 'execução já encerrada não deixa importação órfã e o passo não grava nada', :aggregate_failures do
    execucao = comecar(automacao_ligada(account, admin, [para_cada]), conversa)
    execucao.guardar_texto!('lista.itens', [item('João Lima', '11 98888-0001')])
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao.reload)
    passo = described_class.new(execucao: execucao, passo: para_cada, alvo: conversa, acesso: acesso)
    Autonomia::Automacao::Execucao.where(id: execucao.id).update_all(estado: 'interrompida', finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations

    resultado = passo.executar

    expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'execucao_encerrada'])
    expect(CampaignImport.count).to eq(0)
    expect(account.contacts.where(name: 'João Lima')).to be_empty
    expect(funil.cards).to be_empty
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
