require 'rails_helper'

# E8 (#2901): o envio da proposta de renovação, no máximo uma vez e com o estado honesto. O passo do envio entra sob a
# trava ANTES de a mensagem sair, e a mensagem sai fora da trava: dois cliques ao mesmo tempo mandam uma vez só. A falha
# clara deixa enviar de novo; a falha depois da chamada, ou o passo que ficou sem o id da mensagem, é incerta: nada sai
# sozinho, a equipe confere e a tela oferece "Enviar de novo". Tudo fictício; a Meta é dublê.
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
    expect(seguro.eventos.find_by(tipo: 'proposta_enviada').valores).to include('mensagem_id' => propostas.sole.id)
  end

  # A primeira tentativa falha com `erro`; as seguintes mandam de verdade.
  def falhar_a_primeira(erro)
    tentativas = 0
    allow_any_instance_of(Carteira::Cotacao::Envio).to receive(:modelo).and_wrap_original do |original, *args, **opcoes| # rubocop:disable RSpec/AnyInstance
      tentativas += 1
      raise erro if tentativas == 1

      original.call(*args, **opcoes)
    end
  end

  def avisos
    Crm::FollowUp.where(account_id: account.id).map { |tarefa| tarefa.metadata['motivo'] }
  end

  describe 'falha clara do envio, sem mensagem' do
    before { falhar_a_primeira(Carteira::Cotacao::Envio::NaoSaiu.new('sem_modelo')) }

    it 'o envio que não saiu fica na história, depois do passo do envio, e a equipe é avisada' do
      expect { clicar }.to raise_error(CustomExceptions::CarteiraRecusa, 'sem_modelo')

      expect(tipos_da_historia(seguro).last(2)).to eq(%w[proposta_enviada proposta_nao_saiu])
      expect(seguro.eventos.where(tipo: 'proposta_nao_saiu').last.valores).to include('motivo' => 'envio', 'detalhe' => 'sem_modelo')
      expect(avisos).to include('proposta_nao_saiu')
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

  describe 'falha depois da chamada (a mensagem pode ter saído)' do
    before { falhar_a_primeira(StandardError.new('resposta perdida')) }

    it 'não grava "não saiu", não manda de novo sozinho, avisa a equipe e a cotação fica incerta' do
      expect { clicar }.to raise_error(CustomExceptions::CarteiraRecusa, 'proposta_incerta')

      expect(tipos_da_historia(seguro)).not_to include('proposta_nao_saiu')
      expect(seguro.eventos.where(tipo: 'proposta_enviada').sole.valores).to include('incerta' => true)
      expect(avisos).to include('proposta_incerta')
      expect(Carteira::Cotacao::Situacao.new([seguro.reload]).call[seguro.id]).to include(incerta: true, podeEnviar: true)
    end

    it '"Enviar de novo" grava um passo novo e manda' do
      expect { clicar }.to raise_error(CustomExceptions::CarteiraRecusa)

      clicar

      expect(propostas.size).to eq(1)
      expect(seguro.eventos.where(tipo: 'proposta_enviada').count).to eq(2)
      expect([described_class.enviada?(seguro.reload), pode_enviar?]).to eq([true, false])
    end
  end

  describe 'o passo do envio ficou sem o id da mensagem (o processo caiu entre a reserva e o envio)' do
    before { Carteira::Cotacao.registrar(seguro, 'proposta_enviada', user: admin) }

    it 'antes de MINUTOS_PARA_INCERTA, ainda conta como enviada e o segundo clique para' do
      travel(described_class::MINUTOS_PARA_INCERTA.minutes - 1.minute)

      expect(pode_enviar?).to be(false)
      expect { clicar }.to raise_error(CustomExceptions::CarteiraRecusa, 'proposta_ja_enviada')
    end

    it 'depois de MINUTOS_PARA_INCERTA, fica incerta e oferece "Enviar de novo", que manda' do
      travel(described_class::MINUTOS_PARA_INCERTA.minutes + 1.minute)

      expect(Carteira::Cotacao::Situacao.new([seguro.reload]).call[seguro.id]).to include(incerta: true, podeEnviar: true)

      clicar

      expect(propostas.size).to eq(1)
    end
  end
end
