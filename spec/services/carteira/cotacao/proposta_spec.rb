require 'rails_helper'

# E8 (#2901): o envio da proposta de renovação. O passo do envio entra sob a trava ANTES de a mensagem sair, e a
# mensagem sai fora da trava: dois cliques ao mesmo tempo mandam uma vez só, e a mensagem que falha deixa a história
# com o envio que não saiu e a proposta pronta para tentar de novo. Tudo fictício; a Meta é dublê.
RSpec.describe Carteira::Cotacao::Proposta do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) do
    criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', valor_centavos: 200_000,
                          fim_vigencia: 30.days.from_now.to_date)
  end
  let(:pdf) do
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('%PDF-1.4 exemplo'), filename: 'Proposta de renovação.pdf',
                                           content_type: 'application/pdf')
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    allow(Whatsapp::Templates::HeaderMedia).to receive(:dispatch_file)
      .and_return('media_url' => 'https://exemplo.test/proposta.pdf', 'media_name' => 'Proposta de renovação.pdf')
    aprovar_modelos(caixa, 'renovacao_algo_mudou', 'renovacao_proposta')
    por_em_renovacao(seguro, cotacao_ligada(account, user: admin, caixa: caixa, quem_envia: 'pessoa'))
    proposta_pronta!
  end

  def config
    Carteira::RenovacaoConfig.find_by(account_id: account.id)
  end

  # A proposta pronta como a Carteira::Cotacao::Pronta guarda: a nota privada com o PDF e o passo da história.
  def proposta_pronta!
    conversa = Carteira::Cotacao::Envio.new(seguro.reload, config).conversa
    nota = conversa.messages.new(account_id: account.id, inbox_id: caixa.id, message_type: :outgoing, private: true, content: 'Proposta')
    nota.attachments.new(account_id: account.id, file_type: :file, file: pdf.signed_id)
    nota.save!
    Carteira::Cotacao.registrar(seguro, 'proposta_pronta', premio_centavos: 210_000, seguradora: 'Seguradora B', nota: nota.id)
  end

  def clicar
    described_class.new(seguro.reload, config, user: admin).enviar
  end

  def propostas
    Message.where(account_id: account.id).to_a.select { |mensagem| Carteira::Cotacao.marca_de(mensagem)['etapa'] == 'proposta' }
  end

  def pode_enviar?
    Carteira::Cotacao::Situacao.new([seguro.reload]).call[seguro.id][:podeEnviar]
  end

  it 'dois cliques ao mesmo tempo: o segundo encontra o envio já gravado e a proposta sai uma vez só' do
    segundo = nil
    allow_any_instance_of(Carteira::Cotacao::Envio).to receive(:modelo).and_wrap_original do |original, *args, **opcoes| # rubocop:disable RSpec/AnyInstance
      if segundo.nil?
        segundo = :sem_recusa
        begin
          clicar
        rescue CustomExceptions::CarteiraRecusa => e
          segundo = e.message
        end
      end
      original.call(*args, **opcoes)
    end

    clicar

    expect(segundo).to eq('proposta_ja_enviada')
    expect(propostas.size).to eq(1)
    expect(seguro.eventos.where(tipo: 'proposta_enviada').count).to eq(1)
    expect(seguro.eventos.find_by(tipo: 'proposta_enviada')).to have_attributes(user_id: admin.id)
  end

  describe 'a mensagem falha depois do passo do envio' do
    before do
      tentativas = 0
      allow_any_instance_of(Carteira::Cotacao::Envio).to receive(:modelo).and_wrap_original do |original, *args, **opcoes| # rubocop:disable RSpec/AnyInstance
        tentativas += 1
        raise StandardError, 'Meta fora do ar' if tentativas == 1

        original.call(*args, **opcoes)
      end
    end

    it 'o envio que não saiu fica na história, depois do passo do envio, e a equipe é avisada' do
      expect { clicar }.to raise_error(CustomExceptions::CarteiraRecusa)

      expect(tipos_da_historia(seguro).last(2)).to eq(%w[proposta_enviada proposta_nao_saiu])
      expect(seguro.eventos.where(tipo: 'proposta_nao_saiu').last.valores).to include('motivo' => 'envio', 'detalhe' => 'erro')
      expect(Crm::FollowUp.where(account_id: account.id).map { |tarefa| tarefa.metadata['motivo'] }).to include('proposta_nao_saiu')
      expect(propostas).to be_empty
    end

    it 'a proposta volta a poder ser enviada, e o novo clique manda' do
      expect { clicar }.to raise_error(CustomExceptions::CarteiraRecusa)
      expect([described_class.enviada?(seguro.reload), pode_enviar?]).to eq([false, true])

      clicar

      expect(propostas.size).to eq(1)
      expect([described_class.enviada?(seguro.reload), pode_enviar?]).to eq([true, false])
    end
  end
end
