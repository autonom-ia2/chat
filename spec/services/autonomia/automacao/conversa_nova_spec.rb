require 'rails_helper'

# #2680 (lote 3 da auditoria do #2414): quem não tem conversa. O card do lead do formulário nasce sem conversa, e o
# contato do gatilho de data não tem conversa. A receita escolhe a caixa; o passo "mensagem" abre a conversa como o
# "Nova conversa" do painel, e os passos seguintes usam essa conversa.
RSpec.describe Autonomia::Automacao::ConversaNova, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:atendente) { create(:user, account: account, role: :agent, name: 'Rafa') }
  let(:caixa) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
  let(:contato) { account.contacts.create!(name: 'Mariana', phone_number: '+5511987654321') }
  let(:card) do
    funil, etapa = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: funil, stage: etapa, contact: contato, title: 'Lead do formulário')
  end

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_gatilhos')
  end

  after { Current.reset }

  def gatilho(tipo = 'card.criado', caixa_id: caixa.id)
    { 'tipo' => tipo, 'conversa_nova' => ({ 'caixa_id' => caixa_id } if caixa_id) }.compact
  end

  def rodar(passos, alvo, por: admin, gatilho: self.gatilho)
    definicao = automacao_ligada(account, por, passos, gatilho: gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: gatilho['tipo']).call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def dados_do(execucao, passo) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: passo).dados

  def oi = mensagem_passo('oi', 'Oi ', { '$valor' => 'contato.nome' }, ', vimos seu cadastro.')

  describe 'no card sem conversa' do
    it 'a mensagem abre a conversa na caixa da receita, manda, e ela vira a principal do card (no registro)', :aggregate_failures do
      execucao = rodar([oi], card)
      conversa = Conversation.find_by!(inbox: caixa, contact: contato)

      expect(registros(execucao)).to eq([['oi', 'ok', nil]])
      expect(conversa.messages.outgoing.last.content).to eq('Oi Mariana, vimos seu cadastro.')
      expect(card.reload.conversation_id).to eq(conversa.id)
      expect(dados_do(execucao, 'oi')).to include('conversa_aberta' => conversa.display_id, 'conversa_principal_do_card' => card.id)
    end

    it 'a IA, o aviso e a espera usam a conversa aberta, e a resposta do cliente acorda a espera', :aggregate_failures do
      espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => 2, 'unidade' => 'horas' },
                 'condicao' => { 'campo' => { '$valor' => 'conversa.cliente_respondeu' }, 'op' => 'igual', 'valor' => true } }
      execucao = rodar([oi, espera, avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Respondeu')], card)
      expect(execucao.reload.estado).to eq('esperando')

      conversa = card.reload.primary_conversation
      travel(10.minutes) do
        mensagem = create(:message, account: account, conversation: conversa, inbox: caixa, message_type: :incoming)
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
          Autonomia::AutomacaoListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: mensagem))
        end
      end

      expect(execucao.reload.estado).to eq('concluida')
      expect(registros(execucao).last).to eq(['aviso', 'ok', nil])
      expect(conversa.messages.where(private: true).last.content).to include('Respondeu')
    end

    it 'o card que já tem conversa principal manda nela, sem abrir outra', :aggregate_failures do
      conversa = create_crm_conversation(account: account, inbox: caixa, contact: contato)
      card.update!(primary_conversation: conversa)

      execucao = rodar([oi], card)

      expect(Conversation.where(contact: contato).count).to eq(1)
      expect(dados_do(execucao, 'oi').keys).not_to include('conversa_aberta')
    end

    it 'a mensagem que não sai desfaz a conversa: nada fica vazio na caixa', :aggregate_failures do
      execucao = rodar([mensagem_passo('oi', { '$valor' => 'contato.email' })], card)

      expect(registros(execucao)).to eq([%w[oi pulado faltou_valor]])
      expect(Conversation.where(contact: contato)).to be_empty
      expect(card.reload.conversation_id).to be_nil
    end

    it 'sem a caixa na receita, pula com sem_conversa, como antes' do
      execucao = rodar([oi], card, gatilho: gatilho(caixa_id: nil))

      expect(registros(execucao)).to eq([%w[oi pulado sem_conversa]])
    end

    it 'contato sem telefone: pula sem abrir conversa', :aggregate_failures do
      contato.update!(phone_number: nil)
      caixa_sms = create(:channel_sms, account: account).inbox
      caixa_sms.add_members([admin.id])

      execucao = rodar([oi], card, gatilho: gatilho(caixa_id: caixa_sms.id))

      expect(registros(execucao)).to eq([%w[oi pulado contato_sem_telefone]])
      expect(Conversation.where(contact: contato)).to be_empty
    end

    it 'contato que pediu para não receber: pula sem abrir conversa', :aggregate_failures do
      contato.update!(opted_out_at: Time.current)

      execucao = rodar([oi], card)

      expect(registros(execucao)).to eq([%w[oi pulado contato_nao_recebe]])
      expect(Conversation.where(contact: contato)).to be_empty
    end

    it 'quem ligou não pode começar conversa na caixa: pausa a automação, sem abrir conversa', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [oi], gatilho: gatilho)
      allow(Autonomia::Automacao::Acesso).to receive(:comeca_conversa?).and_return(false)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.criado').call
      end
      execucao = Autonomia::Automacao::Execucao.find_by!(automacao: definicao)

      expect(registros(execucao)).to eq([%w[oi falhou quem_ligou_sem_acesso]])
      expect(Conversation.where(contact: contato)).to be_empty
    end
  end

  describe 'no contato' do
    it 'abre a conversa, e o registro não fala em card', :aggregate_failures do
      create(:custom_attribute_definition, account: account, attribute_key: 'aniversario', attribute_display_name: 'Aniversário',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'date')
      de_data = gatilho('contato.data').merge('dias' => 0, 'campo' => 'aniversario', 'quando' => 'antes', 'hora' => 8)
      execucao = rodar([oi], contato, gatilho: de_data)
      conversa = Conversation.find_by!(inbox: caixa, contact: contato)

      expect(registros(execucao)).to eq([['oi', 'ok', nil]])
      expect(dados_do(execucao, 'oi')).to include('conversa_aberta' => conversa.display_id)
      expect(dados_do(execucao, 'oi').keys).not_to include('conversa_principal_do_card')
    end
  end

  describe 'ao salvar' do
    let(:account_user) { account.account_users.find_by(user: admin) }

    def problemas(gatilho, quem = account_user) = described_class.problemas_ao_salvar(account, gatilho, quem)

    it 'aceita a caixa da conta em gatilho de card ou de contato' do
      expect(problemas(gatilho)).to eq([])
    end

    it 'recusa no gatilho de conversa, que já tem conversa' do
      expect(problemas(gatilho('conversa.criada'))).to eq([I18n.t('autonomia.automacao.receita.conversa_nova_sem_alvo')])
    end

    it 'recusa caixa de outra conta ou de canal que não começa conversa', :aggregate_failures do
      de_fora = create_crm_whatsapp_api_inbox(account: create(:account))
      email = create(:channel_email, account: account).inbox

      invalida = ->(id) { [I18n.t('autonomia.automacao.receita.conversa_nova_caixa_invalida', id: id)] }
      expect(problemas(gatilho(caixa_id: de_fora.id))).to eq(invalida.call(de_fora.id))
      expect(problemas(gatilho(caixa_id: email.id))).to eq(invalida.call(email.id))
    end

    it 'recusa quem não está na caixa e não é administrador' do
      quem = account.account_users.find_by(user: atendente)

      expect(problemas(gatilho, quem)).to eq([I18n.t('autonomia.automacao.receita.conversa_nova_sem_acesso', id: caixa.id)])
    end
  end
end
