require 'rails_helper'

# O job das tarefas longas (#936): fila por conta e na instalação, erro que pausa sem descartar, e a
# limpeza dos 5 dias.
RSpec.describe Autonomia::Guide::TarefaJob do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  before do
    simular_ia_do_cliente!
    limpar_semaforo!
  end

  def tarefa_na_fila!(account, user)
    comecar!(planejar!(account, user, receita_de_nomes))
  end

  # AC-TL8 — 1 por conta: a segunda espera a primeira terminar; 3 na instalação: a quarta espera.
  describe 'a fila' do
    before { contatos_em_maiusculas!(conta, 30) }

    it 'segura a segunda tarefa da conta até a primeira parar', :aggregate_failures do
      primeira = tarefa_na_fila!(conta, admin)
      segunda = tarefa_na_fila!(conta, admin)
      allow(Autonomia::Guide::Tarefas::Lote).to receive(:new).and_wrap_original do |original, tarefa|
        lote = original.call(tarefa)
        allow(lote).to receive(:rodar).and_return(Autonomia::Guide::Tarefas::Lote::CONTINUAR) if tarefa.id == primeira.id
        lote
      end

      described_class.perform_now(primeira.id)
      expect { described_class.perform_now(segunda.id) }
        .to have_enqueued_job(described_class).with(segunda.id).at(a_value_within(2.seconds).of(described_class::NA_FILA.from_now))
      expect(segunda.reload.status).to eq('na_fila')

      Autonomia::Guide::Tarefas::Semaforo.sair(primeira)
      described_class.perform_now(segunda.id)
      expect(segunda.reload.status).to eq('aguardando_ok_canario')
    end

    it 'deixa no máximo 3 rodando na instalação', :aggregate_failures do
      outras = Array.new(3) do
        conta_de_fora, dono = create_account_and_user
        contatos_em_maiusculas!(conta_de_fora, 1)
        tarefa_na_fila!(conta_de_fora, dono)
      end
      outras.each { |tarefa| expect(Autonomia::Guide::Tarefas::Semaforo.entrar(tarefa)).to be(true) }
      quarta = tarefa_na_fila!(conta, admin)

      expect { described_class.perform_now(quarta.id) }.to have_enqueued_job(described_class).with(quarta.id)
      expect(quarta.reload.status).to eq('na_fila')

      Autonomia::Guide::Tarefas::Semaforo.sair(outras.first)
      described_class.perform_now(quarta.id)
      expect(quarta.reload.status).to eq('aguardando_ok_canario')
    end
  end

  it 'pausa com o motivo quando o lote quebra, sem descartar a tarefa', :aggregate_failures do
    contatos_em_maiusculas!(conta, 3)
    tarefa = tarefa_na_fila!(conta, admin)
    allow(Autonomia::Guide::Tarefas::Lote).to receive(:new).and_raise(ArgumentError, 'quebrou')

    described_class.perform_now(tarefa.id)

    expect(tarefa.reload.status).to eq('pausada')
    expect(tarefa.motivo_pausa).to eq('erro')
    expect(tarefa.itens.count).to eq(3)
  end

  # AC-TL12 — a amostra e as mudanças vencem em 5 dias.
  it 'apaga a tarefa vencida, com a amostra e os itens', :aggregate_failures do
    contatos_em_maiusculas!(conta, 3)
    tarefa = planejar!(conta, admin, receita_de_nomes)

    travel(Autonomia::Guide::Tarefa::PRAZO + 1.minute) { Autonomia::Guide::LimparExecucoesJob.perform_now }

    expect(Autonomia::Guide::Tarefa.exists?(tarefa.id)).to be(false)
    expect(Autonomia::Guide::TarefaItem.where(task_id: tarefa.id)).to be_empty
  end

  it 'a vigia não mexe na tarefa que está batendo' do
    contatos_em_maiusculas!(conta, 3)
    tarefa_na_fila!(conta, admin).update!(status: 'rodando', batimento_em: Time.current)

    expect { Autonomia::Guide::TarefasVigiaJob.perform_now }.not_to have_enqueued_job(described_class)
  end
end
