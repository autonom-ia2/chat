require 'rails_helper'

# #3055: quem enfileira o pedido dos 2 modelos da cotação da renovação (Carteira::Cotacao::ModelosJob), fora o
# assinante do Aviso de serviço (spec/initializers/whatsapp_templates_consentimento_ligado_spec.rb): salvar os ajustes
# da renovação e a autocura do envio, com a trava de tempo por caixa. Tudo fictício; a Meta é dublê e não é chamada.
RSpec.describe Carteira::Cotacao::Modelos do
  include ActiveJob::TestHelper

  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:job) { Carteira::Cotacao::ModelosJob }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { allow(Whatsapp::Templates::MetaClient).to receive(:new) }

  def autorizar(acao = WhatsappTemplateConsent::LIGOU)
    WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: acao, versao_aviso: 'v1', texto_aviso: 'Aviso.')
  end

  # Ajustar renovações: o que a tela manda (as escolhas da cotação pedem a chave da cotação na conta).
  describe 'salvar os ajustes da renovação' do
    before do
      Carteira::Cotacao::Liberada.ligar!(account)
      agente_de_cotacao(account)
      caixa.update!(enable_auto_assignment: false)
    end

    def salvar(**dados)
      Carteira::Renovacao::SalvarAjustes.new(account, dados.stringify_keys, user: admin, funis: Crm::Pipeline.none).call
    end

    # Motivo: escolher a caixa com a cotação aberta é o momento de pedir os modelos nela.
    it 'caixa escolhida com a cotação aberta: enfileira' do
      autorizar

      expect { salvar(quemCota: 'robo', caixaId: caixa.id) }.to have_enqueued_job(job).with(account.id).exactly(:once)
    end

    # Motivo: trocar a caixa leva os modelos para a nova; salvar sem mexer na caixa nem em quem cota não pede de novo.
    it 'caixa trocada enfileira; outro ajuste sem trocar a caixa não' do
      autorizar
      salvar(quemCota: 'robo', caixaId: caixa.id)
      outra = caixa_oficial(account, nome: 'Outra caixa')
      outra.update!(enable_auto_assignment: false)

      expect { salvar(caixaId: outra.id) }.to have_enqueued_job(job).with(account.id).exactly(:once)
      expect { salvar(quemEnvia: 'sozinho', caixaId: outra.id) }.not_to have_enqueued_job(job)
    end

    # Motivo: a caixa já estava escolhida com "ninguém cota"; passar a cotar abre a cotação, e é aí que se pede.
    it 'quem cota sai de ninguém com a caixa já escolhida: enfileira' do
      autorizar
      salvar(quemCota: 'ninguem', caixaId: caixa.id)

      expect { salvar(quemCota: 'robo') }.to have_enqueued_job(job).with(account.id).exactly(:once)
    end

    # Motivo: sem a cotação aberta, ou sem o Aviso de serviço, o job não faria nada: nem vai para a fila.
    it 'ninguém cota, ou sem o Aviso de serviço: não enfileira' do
      autorizar
      expect { salvar(quemCota: 'ninguem', caixaId: caixa.id) }.not_to have_enqueued_job(job)

      autorizar(WhatsappTemplateConsent::DESLIGOU)
      expect { salvar(quemCota: 'robo') }.not_to have_enqueued_job(job)
    end

    # Motivo: a fila fora do ar não pode desfazer o ajuste gravado; o erro vai ao tracker.
    it 'erro ao enfileirar: o ajuste fica gravado e o erro vai ao tracker' do
      autorizar
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      allow(job).to receive(:perform_later).and_raise(StandardError)

      config = salvar(quemCota: 'robo', caixaId: caixa.id)

      expect(config.reload.inbox_id).to eq(caixa.id)
      expect(tracker).to have_received(:capture_exception).once
    end
  end

  # Autocura: o envio que encontra o modelo fora da lista da caixa (`sem_modelo`) pede os 2 à Meta. Cobre a chave da
  # cotação ligada direto no banco, que não passa por nenhum outro gatilho.
  describe 'autocura do envio' do
    let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
    let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
    let(:ajustes) { cotacao_ligada(account, user: admin, caixa: caixa) }
    let(:trava) { format(described_class::CURA_TRAVA, inbox_id: caixa.id) }

    # A trava mora no Redis, que não volta com a transação do exemplo.
    before do
      Redis::Alfred.delete(trava)
      por_em_renovacao(seguro, ajustes)
    end

    after { Redis::Alfred.delete(trava) }

    def conferir(finalidade = 'renovacao_algo_mudou')
      Carteira::Cotacao::Envio.new(seguro.reload, ajustes.reload).conferir!(finalidade)
    rescue Carteira::Cotacao::Envio::NaoSaiu => e
      e.message
    end

    def trava?
      Redis::Alfred.exists?(trava)
    end

    # Motivo: o caminho da correção. Enfileira UMA vez; o envio seguinte, de outro seguro ou do outro modelo, não
    # enfileira de novo enquanto a trava vale (sem ela, cada envio enfileiraria um job). O envio de agora não espera.
    it 'sem_modelo com tudo liberado: enfileira uma vez, e o envio seguinte não enfileira de novo' do
      autorizar

      expect { expect(conferir).to eq('sem_modelo') }.to have_enqueued_job(job).with(account.id).exactly(:once)
      expect { conferir('renovacao_proposta') }.not_to have_enqueued_job(job)
      expect(trava?).to be(true)
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
    end

    # Motivo: passada a validade da trava, o envio seguinte que ainda encontra o modelo fora da lista pede de novo.
    it 'trava vencida: enfileira de novo' do
      autorizar
      conferir
      Redis::Alfred.delete(trava)

      expect { conferir }.to have_enqueued_job(job).with(account.id).exactly(:once)
    end

    # Motivo: sem o Aviso de serviço o sistema não pode criar modelo na Meta (#1586): nem enfileira, nem gasta a trava.
    it 'sem o Aviso de serviço: não enfileira nem grava a trava' do
      expect { expect(conferir).to eq('sem_modelo') }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: com a cotação fechada o job não faria nada; a trava não pode ser gasta à toa.
    it 'cotação fechada: não enfileira nem grava a trava' do
      autorizar
      Carteira::Cotacao::Liberada.desligar!(account)

      expect { conferir }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: em análise (ou recusado) o modelo já está na Meta; enfileirar seria trabalho à toa.
    it 'modelo em análise: não enfileira' do
      autorizar
      pronto = Whatsapp::Templates::Finalidades.pronto('renovacao_algo_mudou')
      em_analise = pronto.corpo.deep_stringify_keys.merge('status' => 'PENDING')
      caixa.channel.update_columns(message_templates: [em_analise]) # rubocop:disable Rails/SkipsModelValidations

      expect { expect(conferir).to eq('sem_modelo') }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: a fila fora do ar tira a trava (o próximo envio tenta de novo) e vai ao tracker; o envio segue `sem_modelo`.
    it 'erro ao enfileirar: tira a trava e vai ao tracker' do
      autorizar
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      allow(job).to receive(:perform_later).and_raise(StandardError)

      expect(conferir).to eq('sem_modelo')
      expect(tracker).to have_received(:capture_exception).once
      expect(trava?).to be(false)
    end
  end
end
