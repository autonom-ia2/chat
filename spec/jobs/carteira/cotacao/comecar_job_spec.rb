require 'rails_helper'

# E8 (#2901): o começo da cotação da renovação. Uma vez só por vigência, e o "Algo mudou?" sai pela caixa escolhida, na
# conversa do contato, sem responsável, com a marca da cotação. O que impede não manda nada, fica na história e avisa a
# equipe. Tudo fictício; a Meta é falsa (o envio só cria a mensagem, o job de envio não roda).
RSpec.describe Carteira::Cotacao::ComecarJob do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
    por_em_renovacao(seguro, ajustes)
  end

  def rodar
    described_class.perform_now(seguro.id, seguro.fim_vigencia.iso8601)
  end

  def tarefas
    Crm::FollowUp.where(account_id: account.id, card_id: seguro.reload.crm_card_id)
  end

  it 'manda o "Algo mudou?" pela caixa escolhida, com os botões e a marca, sem responsável, e agenda o sem resposta' do
    expect { rodar }.to have_enqueued_job(Carteira::Cotacao::SemRespostaJob).with(seguro.id, seguro.fim_vigencia.iso8601)

    mensagem = algo_mudou_de(seguro)
    expect(mensagem).to have_attributes(inbox_id: caixa.id, message_type: 'outgoing', private: false, sender_id: nil)
    expect(mensagem.content).to start_with('Olá, Marina! O seu seguro termina em')
    expect(mensagem.conversation).to have_attributes(contact_id: marina.id, assignee_id: nil)
    expect(tipos_da_historia(seguro)).to eq(%w[renovacao_card_nasceu cotacao_pedida])
  end

  # A trava por seguro e vigência: o job repetido (ou o card recriado) não pede nem manda de novo.
  it 'rodando duas vezes, pede e manda uma vez só' do
    rodar
    rodar

    expect(seguro.eventos.where(tipo: 'cotacao_pedida').count).to eq(1)
    expect(Message.where(account_id: account.id).to_a.count { |m| Carteira::Cotacao.marca_de(m)['etapa'] == 'algo_mudou' }).to eq(1)
  end

  it 'a vigência que mudou desde o pedido não pede nada' do
    described_class.perform_now(seguro.id, (seguro.fim_vigencia + 1.year).iso8601)

    expect(tipos_da_historia(seguro)).to eq(['renovacao_card_nasceu'])
  end

  describe 'o que impede o "Algo mudou?"' do
    it 'sem caixa escolhida: não manda, guarda o motivo e avisa quem cuida do card' do
      ajustes.update!(inbox: nil)

      rodar

      expect(algo_mudou_de(seguro)).to be_nil
      expect(seguro.eventos.find_by(tipo: 'algo_mudou_nao_saiu').valores).to include('motivo' => 'sem_caixa')
      expect(tarefas.sole.metadata).to include('source' => 'carteira_cotacao', 'motivo' => 'algo_mudou_nao_saiu', 'detalhe' => 'sem_caixa')
    end

    it 'sem o modelo aprovado na caixa: não manda e avisa' do
      caixa.channel.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations

      rodar

      expect(algo_mudou_de(seguro)).to be_nil
      expect(seguro.eventos.find_by(tipo: 'algo_mudou_nao_saiu').valores).to include('motivo' => 'sem_modelo')
      expect(tarefas.count).to eq(1)
    end

    it 'o contato que recusou mensagens (relido do banco agora): não manda e avisa' do
      Contact.where(id: marina.id).update_all(opted_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      rodar

      expect(algo_mudou_de(seguro)).to be_nil
      expect(seguro.eventos.find_by(tipo: 'algo_mudou_nao_saiu').valores).to include('motivo' => 'contato_recusou')
    end

    it 'o contato bloqueado: não manda' do
      Contact.where(id: marina.id).update_all(blocked: true) # rubocop:disable Rails/SkipsModelValidations

      rodar

      expect(seguro.eventos.find_by(tipo: 'algo_mudou_nao_saiu').valores).to include('motivo' => 'contato_recusou')
    end
  end
end
