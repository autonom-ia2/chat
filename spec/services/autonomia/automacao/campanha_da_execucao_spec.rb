require 'rails_helper'

# G58 (#2779): o passo campanha com `publico: desta_execucao`. Os contatos que os passos anteriores da execução criaram
# (ContatosDaExecucao) viram um Público, e a Campanha sai ligada a ele (CampanhaDaExecucao).
RSpec.describe Autonomia::Automacao::CampanhaDaExecucao, :automacao_motor do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:funil) { create_crm_pipeline(account: account, user: dona) }
  let(:modelo) do
    { 'name' => 'apresentacao', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá! Somos o escritório {{1}}.' }] }
  end
  let(:card_antes) { { 'id' => 'cards', 'tipo' => 'prospeccao' } }
  let(:campanha) do
    { 'id' => 'apresentar', 'tipo' => 'campanha', 'faz' => 'disparar', 'publico' => 'desta_execucao', 'titulo' => 'Apresentação',
      'caixa_id' => caixa.id, 'modelo' => { 'nome' => 'apresentacao', 'idioma' => 'pt_BR', 'variaveis' => [['Conta Certa']] } }
  end
  let(:gatilho) { { 'tipo' => 'conta.recorrente', 'frequencia' => 'semanal', 'dia_da_semana' => 1, 'hora' => 8 } }
  # Até a G21 (#2706), nenhum passo que cria card ou contato salva num gatilho da conta (o "card" pede alvo; o
  # "prospeccao" não está no esquema). A versão ganha a receita direto no banco, como ela fica com o passo da G21, que
  # grava `card_ids` no registro.
  let(:definicao) do
    automacao_ligada(account, dona, [esperar_passo('antes')], gatilho: gatilho).tap do |automacao|
      Autonomia::Automacao::Versao.where(id: automacao.versao_ativa_id)
                                  .update_all(receita: { 'gatilho' => gatilho, 'passos' => [card_antes, campanha] }) # rubocop:disable Rails/SkipsModelValidations
    end.reload
  end
  let(:execucao) do
    definicao.execucoes.create!(account: account, versao: definicao.versao_ativa, alvo: account, chave_gatilho: 'conta.recorrente',
                                estado: 'andando')
  end

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('whatsapp_campaign', 'automacao_gatilhos')
    canal.update!(message_templates: [modelo])
  end

  after { Current.reset }

  def contato(nome, telefone) = create(:contact, account: account, name: nome, phone_number: telefone)

  def card_de(pessoa)
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, contact: pessoa, owner: dona, title: pessoa.name, currency: 'BRL')
  end

  def registro(passo, resultado, dados, motivo: nil)
    Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: passo,
                                           resultado: resultado, motivo: motivo, dados: dados)
  end

  def disparar = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: campanha, alvo: account).executar

  describe Autonomia::Automacao::ContatosDaExecucao do
    subject(:contatos) { described_class.new(execucao: execucao) }

    it 'lê card_id/card_ids e contato_id/contato_ids dos passos que criam, só dos registros ok', :aggregate_failures do
      ana = contato('Ana', '+5519900000001')
      bia = contato('Bia', '+5519900000002')
      caio = contato('Caio', '+5519900000003')
      duda = contato('Duda', '+5519900000004')
      registro('cards', 'ok', { 'card_ids' => [card_de(ana).id], 'contato_ids' => [bia.id] })
      registro('cards', 'ok', { 'card_id' => card_de(caio).id })
      registro('cards', 'pulado', { 'card_id' => card_de(duda).id }, motivo: 'card_ja_existe')
      registro('apresentar', 'ok', { 'contato_id' => duda.id })

      expect(contatos.dentro).to eq([ana, bia, caio])
      expect(contatos.fora).to eq(0)
    end

    it 'deixa de fora quem não recebe no WhatsApp: pediu para não receber, só tem e-mail ou não tem canal', :aggregate_failures do
      ana = contato('Ana', '+5519900000001')
      recusou = contato('Recusou', '+5519900000002').tap { |pessoa| pessoa.opt_out!(source: 'manual') }
      so_email = create(:contact, account: account, name: 'Só e-mail', phone_number: nil, email: 'so@email.com')
      sem_canal = create(:contact, account: account, name: 'Sem canal', phone_number: nil, email: nil)
      registro('cards', 'ok', { 'contato_ids' => [ana.id, recusou.id, so_email.id, sem_canal.id] })

      expect(contatos.dentro).to eq([ana])
      expect(contatos.fora).to eq(3)
      expect(contatos.sem_alcance).to be_empty
    end

    it 'ignora card e contato de outra conta' do
      de_fora = create(:contact, phone_number: '+5519900000009')
      outra_conta = de_fora.account
      outro_funil = create_crm_pipeline(account: outra_conta, user: create(:user, account: outra_conta, role: :administrator))
      card_de_fora = outra_conta.crm_cards.create!(pipeline: outro_funil.first, stage: outro_funil.last, contact: de_fora,
                                                   owner: outra_conta.users.first, title: 'De fora', currency: 'BRL')
      registro('cards', 'ok', { 'contato_ids' => [de_fora.id], 'card_ids' => [card_de_fora.id] })

      expect(contatos.dentro).to be_empty
    end
  end

  # A regra real, sem dublê: o contato vale pela função de quem ligou (ContactPolicy#update?; no EE, contact_manage).
  describe 'quem ligou perde contact_manage' do
    let(:agente) { create(:user, account: account, role: :agent) }

    before do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage campaign_manage])
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      definicao.update!(ligada_por: agente)
    end

    it 'não alcança nenhum contato e a automação pausa com sem_acesso, sem criar Público nem Campanha', :aggregate_failures do
      ana = contato('Ana', '+5519900000001')
      registro('cards', 'ok', { 'card_ids' => [card_de(ana).id] })
      template_params = Autonomia::Automacao::PassoDeCampanha.modelo_pronto(caixa, campanha['modelo'])

      expect(Autonomia::Automacao::ContatosDaExecucao.new(execucao: execucao).sem_alcance).to eq([ana])
      resultado = described_class.new(execucao: execucao.reload, passo: campanha, caixa: caixa, template_params: template_params).disparar

      expect(resultado).to have_attributes(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso')
      expect(CampaignImport.count).to eq(0)
      expect(account.campaigns.count).to eq(0)
    end
  end

  describe 'disparar' do
    it 'grava o Público da execução, cria a Campanha ligada a ele e a põe na fila', :aggregate_failures do
      ana = contato('Ana', '+5519900000001')
      registro('cards', 'ok', { 'card_ids' => [card_de(ana).id] })

      resultado = disparar

      publico = CampaignImport.find(resultado.dados['publico_id'])
      campanha_criada = account.campaigns.find_by!(display_id: resultado.dados['campanha_id'])
      expect(resultado).to have_attributes(tipo: :ok, motivo: nil)
      expect(resultado.dados.keys).to match_array(%w[campanha_id publico_id contatos fora])
      expect(publico).to have_attributes(status: 'completed', name: start_with('Apresentação · '))
      expect(publico.options).to include('source' => 'automacao', 'automacao_id' => definicao.id, 'execucao_id' => execucao.id)
      expect(publico.campaign_import_rows.pluck(:contact_id)).to eq([ana.id])
      # Quem ligou é o remetente (F3.9): cada mensagem enviada leva o nome dele (SentMessageRecorder usa campaign.sender).
      expect(campanha_criada).to have_attributes(title: 'Apresentação', inbox: caixa, message: 'Olá! Somos o escritório Conta Certa.',
                                                 sender: dona)
      expect(publico.user_id).to eq(dona.id)
      expect(CampaignAudienceLink.for_campaign(campanha_criada).variable_bindings)
        .to eq({ '1' => { 'source' => 'fixed', 'value' => 'Conta Certa' } })
      expect(enqueued_jobs.pluck('job_class')).to include('Campaigns::TriggerOneoffCampaignJob')
    end

    it 'sem ninguém criado nesta vez, pula sem criar Público nem Campanha', :aggregate_failures do
      resultado = disparar

      expect(resultado).to have_attributes(tipo: :pulado, motivo: 'campanha_execucao_sem_contatos')
      expect(CampaignImport.count).to eq(0)
      expect(account.campaigns.count).to eq(0)
    end

    it 'a recusa do creator desfaz o Público e vira campanha_recusada', :aggregate_failures do
      registro('cards', 'ok', { 'contato_ids' => [contato('Ana', '+5519900000001').id] })
      template_params = Autonomia::Automacao::PassoDeCampanha.modelo_pronto(caixa, campanha['modelo'])
      # A flag cai entre a guarda do passo e o creator: o creator recusa (feature_disabled) depois do Público gravado.
      account.disable_features!('whatsapp_campaign')

      resultado = described_class.new(execucao: execucao.reload, passo: campanha, caixa: caixa, template_params: template_params).disparar

      expect(resultado).to have_attributes(tipo: :pulado, motivo: 'campanha_recusada')
      expect(CampaignImport.count).to eq(0)
    end
  end

  describe 'ao salvar' do
    def problemas(passos)
      receita = { 'gatilho' => gatilho, 'passos' => passos }
      Autonomia::Automacao::PassoDeCampanha.problemas_do_publico(passos.last, receita)
    end

    let(:sem_origem) { I18n.t('autonomia.automacao.receita.campanha_publico_sem_origem', passo: 'apresentar') }

    it 'pede um passo antes que crie card ou contato', :aggregate_failures do
      expect(problemas([campanha])).to eq([sem_origem])
      expect(problemas([card_antes, campanha])).to be_empty
    end

    it 'o passo que cria depois, ou noutro galho, não conta' do
      se = { 'id' => 'se1', 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => 'conta.id' }, 'op' => 'existe' },
             'entao' => [card_antes], 'senao' => [campanha] }

      expect(Autonomia::Automacao::PassoDeCampanha.problemas_do_publico(campanha, { 'gatilho' => gatilho, 'passos' => [se] }))
        .to eq([sem_origem])
    end

    it 'a receita só com etiquetas não muda' do
      etiquetas = campanha.except('publico').merge('etiquetas' => [create(:label, account: account).id])

      expect(problemas([etiquetas])).to be_empty
      expect(Autonomia::Automacao::Receita.esquema_valido?({ 'gatilho' => gatilho, 'passos' => [etiquetas] })).to be(true)
    end
  end
end
