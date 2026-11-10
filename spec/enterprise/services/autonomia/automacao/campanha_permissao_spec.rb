require 'rails_helper'

# #2630 (G14, funções personalizadas #1784): o passo "campanha" age como quem ligou, com a pergunta da tela de cada coisa,
# relida a cada execução. Disparar pede a da API de campanhas (CampaignPolicy#send_campaign?: campaign_manage e
# campaign_send); não receber pede a do botão do contato (ContactPolicy#update?: contact_manage numa função). Fica em
# spec/enterprise: a metade de função personalizada é EE.
RSpec.describe 'Automação livre: passo campanha com função personalizada (#2630)', :aggregate_failures, :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa) { canal.inbox }
  let(:etiqueta) { create(:label, account: account, title: 'ja_comprou') }
  let(:modelo_aprovado) do
    { 'name' => 'pre_black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi! A Black começa {{1}}.' }] }
  end
  let(:disparar) do
    { 'id' => 'c1', 'tipo' => 'campanha', 'faz' => 'disparar', 'titulo' => 'Pré-Black', 'caixa_id' => caixa.id,
      'modelo' => { 'nome' => 'pre_black', 'idioma' => 'pt_BR', 'variaveis' => [['na quinta']] }, 'etiquetas' => [etiqueta.id] }
  end
  let(:nao_receber) { { 'id' => 'n1', 'tipo' => 'campanha', 'faz' => 'nao_receber' } }
  let(:base) { %w[automation_manage conversation_manage] }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('whatsapp_campaign')
    canal.update!(message_templates: [modelo_aprovado])
  end

  after { Current.reset }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: caixa)
    user
  end

  def problemas(quem)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [disparar] }
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: quem)).problemas
  end

  def disparar_como(quem)
    definicao = create(:autonomia_automacao, account: account, ligada_por: quem)
    execucao = Autonomia::Automacao::Execucao.new(automacao: definicao, account: account)
    Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: disparar, alvo: account).executar
  end

  describe 'disparar' do
    before { allow(Autonomia::Automacao::PassoDeCampanha).to receive(:alvo_da_conta?).and_return(true) }

    it 'quem só monta campanha (sem campaign_send) não salva nem dispara' do
      so_monta = pessoa_com(base + %w[campaign_manage])
      frase = I18n.t('autonomia.automacao.receita.campanha_sem_permissao', passo: 'c1')

      expect(problemas(so_monta)).to include(frase)
      resultado = disparar_como(so_monta)
      expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_campanha'])
      expect(account.campaigns).to be_empty
    end

    it 'quem monta e envia campanha salva e dispara' do
      envia = pessoa_com(base + %w[campaign_manage campaign_send])

      expect(problemas(envia)).to be_empty
      expect(disparar_como(envia).tipo).to eq(:ok)
      expect(account.campaigns.count).to eq(1)
    end

    it 'perder campaign_send depois de ligar é visto na execução seguinte' do
      envia = pessoa_com(base + %w[campaign_manage campaign_send])
      AccountUser.find_by(account: account, user: envia).custom_role.update!(permissions: base + %w[campaign_manage])

      expect(disparar_como(envia).tipo).to eq(:sem_acesso)
    end
  end

  describe 'nao receber' do
    let(:conversa) { create(:conversation, account: account, inbox: caixa, status: :resolved) }

    it 'quem ligou sem contact_manage não marca o contato, e a automação pausa' do
      sem_contato = pessoa_com(base)
      definicao = automacao_ligada(account, sem_contato, [nao_receber])

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

      expect(conversa.contact.reload.opted_out?).to be(false)
      expect(definicao.reload.ativa).to be(false)
      expect(Autonomia::Automacao::Registro.where(automacao: definicao).pluck(:passo, :resultado, :motivo))
        .to eq([%w[n1 falhou quem_ligou_sem_acesso]])
    end

    it 'quem ligou com contact_manage marca o contato' do
      com_contato = pessoa_com(base + %w[contact_manage])
      definicao = automacao_ligada(account, com_contato, [nao_receber])

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

      expect(conversa.contact.reload).to have_attributes(opt_out_source: 'manual', opted_out_by_id: com_contato.id)
    end
  end
end
