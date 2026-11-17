require 'rails_helper'

# E8 (#2901): a resposta do segurado ao "Algo mudou?" é casada pelo payload do botão e pela mensagem citada com a marca
# da cotação, nunca pelo texto. "Nada mudou" cota; "Mudou algo" não cota, avisa a equipe e pergunta o que mudou (quando
# quem responde é a equipe). A mensagem seguinte vai à história só com o id. Tudo fictício.
RSpec.describe Carteira::Cotacao::Resposta do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa) }
  let(:modelo) { algo_mudou_de(seguro) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
    por_em_renovacao(seguro, ajustes)
    Carteira::Cotacao::ComecarJob.perform_now(seguro.id, seguro.fim_vigencia.iso8601)
  end

  def responder(mensagem)
    described_class.new(mensagem).call
  end

  def recebida(texto, **atributos)
    modelo.conversation.messages.create!(account_id: account.id, inbox_id: caixa.id, message_type: :incoming, sender: marina,
                                         content: texto, content_attributes: atributos)
  end

  it '"Nada mudou" no botão do nosso modelo: guarda a resposta e pede a cotação' do
    toque = tocar(modelo, 'renovacao_nada_mudou')

    expect { responder(toque) }.to have_enqueued_job(Carteira::Cotacao::CotarJob).with(seguro.id, seguro.fim_vigencia.iso8601)
    expect(seguro.eventos.find_by(tipo: 'respondeu_algo_mudou').valores)
      .to include('resposta' => 'nada_mudou', 'conversa_id' => toque.conversation_id, 'mensagem' => toque.id)
  end

  it 'o segundo toque não muda a resposta nem pede de novo' do
    responder(tocar(modelo, 'renovacao_nada_mudou'))

    expect { responder(tocar(modelo, 'renovacao_mudou', titulo: 'Mudou algo')) }.not_to have_enqueued_job(Carteira::Cotacao::CotarJob)
    expect(seguro.eventos.where(tipo: 'respondeu_algo_mudou').pluck(:valores).map { |v| v['resposta'] }).to eq(['nada_mudou'])
  end

  describe '"Mudou algo"' do
    it 'não cota, avisa quem cuida do card e pergunta o que mudou na sessão (quem responde é a equipe)' do
      expect { responder(tocar(modelo, 'renovacao_mudou', titulo: 'Mudou algo')) }.not_to have_enqueued_job(Carteira::Cotacao::CotarJob)

      pergunta = modelo.conversation.messages.order(:id).last
      expect(Carteira::Cotacao.marca_de(pergunta)).to eq('apolice_id' => seguro.id, 'etapa' => 'o_que_mudou')
      expect(pergunta).to have_attributes(content: I18n.t('carteira.cotacao.o_que_mudou', locale: 'pt_BR'), sender_id: nil, private: false)
      expect(Crm::FollowUp.where(account_id: account.id).pluck(:metadata).map { |m| m['motivo'] }).to include('mudou')
    end

    it 'com "Lia responde", não manda a pergunta: quem pergunta é a Lia' do
      ajustes.update!(quem_responde: 'lia')

      responder(tocar(modelo, 'renovacao_mudou', titulo: 'Mudou algo'))

      expect(modelo.conversation.messages.order(:id).last.message_type).to eq('incoming')
    end

    it 'a mensagem seguinte do segurado vai à história só com o id, avisa a equipe, uma vez só' do
      responder(tocar(modelo, 'renovacao_mudou', titulo: 'Mudou algo'))
      resposta = recebida('Troquei de carro')

      responder(resposta)
      responder(recebida('E de endereço também'))

      expect(seguro.eventos.where(tipo: 'cliente_respondeu').pluck(:valores))
        .to eq([{ 'vigencia' => seguro.fim_vigencia.iso8601, 'mensagem' => resposta.id }])
      expect(Crm::FollowUp.where(account_id: account.id).pluck(:metadata).map { |m| m['motivo'] }).to include('cliente_respondeu')
    end

    it 'a cotação pedida depois (sem resposta em 3 dias) não cota quem disse que mudou' do
      responder(tocar(modelo, 'renovacao_mudou', titulo: 'Mudou algo'))

      Carteira::Cotacao::SemRespostaJob.perform_now(seguro.id, seguro.fim_vigencia.iso8601)
      Carteira::Cotacao::CotarJob.perform_now(seguro.id, seguro.fim_vigencia.iso8601)

      expect(tipos_da_historia(seguro)).not_to include('proposta_pedida', 'proposta_nao_saiu')
    end
  end

  describe 'o que não é resposta ao nosso modelo' do
    it 'o mesmo texto do botão, digitado, sem payload nem mensagem citada: nada' do
      expect { responder(recebida('Nada mudou')) }.not_to have_enqueued_job(Carteira::Cotacao::CotarJob)
      expect(tipos_da_historia(seguro)).not_to include('respondeu_algo_mudou')
    end

    it 'o payload certo citando uma mensagem sem a nossa marca: nada' do
      outra = modelo.conversation.messages.create!(account_id: account.id, inbox_id: caixa.id, message_type: :outgoing, content: 'Oi')

      responder(tocar(outra, 'renovacao_nada_mudou'))

      expect(tipos_da_historia(seguro)).not_to include('respondeu_algo_mudou')
    end

    it 'o payload certo citando o nosso modelo de outra conversa: nada' do
      outra_conversa = create(:conversation, account: account, inbox: caixa, contact: marina)
      toque = outra_conversa.messages.create!(account_id: account.id, inbox_id: caixa.id, message_type: :incoming, sender: marina,
                                              content: 'Nada mudou',
                                              content_attributes: { 'selected_option' => { 'id' => 'renovacao_nada_mudou' },
                                                                    'in_reply_to' => modelo.id })
      responder(toque)

      expect(tipos_da_historia(seguro)).not_to include('respondeu_algo_mudou')
    end

    it 'sem a chave da cotação: nada' do
      Carteira::Cotacao::Liberada.desligar!(account)

      responder(tocar(modelo, 'renovacao_nada_mudou'))

      expect(tipos_da_historia(seguro)).not_to include('respondeu_algo_mudou')
    end
  end

  it 'o ouvinte de mensagens passa a mensagem recebida adiante, e um erro não sobe' do
    toque = tocar(modelo, 'renovacao_nada_mudou')
    evento = Events::Base.new('message.created', Time.zone.now, message: toque)

    expect { Carteira::CotacaoRespostaListener.instance.message_created(evento) }.to have_enqueued_job(Carteira::Cotacao::CotarJob)

    allow(described_class).to receive(:new).and_raise(StandardError, 'falhou')
    expect { Carteira::CotacaoRespostaListener.instance.message_created(evento) }.not_to raise_error
  end
end
