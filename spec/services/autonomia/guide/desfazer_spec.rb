require 'rails_helper'

# O caderno do Guia e o desfazer (#855), juntos: um só existe para o outro.
#
# O Guia passou a agir sem confirmação. O que protege a conta é voltar atrás,
# e voltar atrás só presta se for exato: mesma linha, mesmo id, mesmos valores
# — e sem apagar o que outra pessoa fez depois.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Caderno e desfazer do Guia' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:execucao) { Autonomia::Guide::Execucao.abrir(account: conta, user: admin) }

  def gravando(passo = 0, &)
    Autonomia::Guide::Diario.gravando(execucao, passo, &)
  end

  def desfazer
    Autonomia::Guide::Desfazer.new(execucao: execucao.reload, user: admin).perform
  end

  describe 'o caderno' do
    it 'anota o que foi criado, alterado e apagado, na ordem', :aggregate_failures do
      etiqueta = conta.labels.create!(title: 'antiga')
      gravando do
        conta.labels.create!(title: 'nova')
        etiqueta.update!(title: 'renomeada')
      end

      expect(execucao.mudancas.map(&:operacao)).to eq(%w[create update])
      expect(execucao.mudancas.last.antes).to include('title' => 'antiga')
      expect(execucao.mudancas.last.depois).to include('title' => 'renomeada')
    end

    # Fora de uma ação do Guia, os callbacks não podem gravar nada: eles rodam
    # em TODA escrita da plataforma.
    it 'não anota nada fora de uma ação do Guia' do
      expect { conta.labels.create!(title: 'solta') }.not_to change(Autonomia::Guide::Mudanca, :count)
    end

    # Transação que voltou atrás dentro do endpoint não aconteceu, e não pode
    # virar mudança a desfazer.
    it 'esquece o que a transação desfez' do
      gravando do
        ActiveRecord::Base.transaction do
          conta.labels.create!(title: 'fantasma')
          raise ActiveRecord::Rollback
        end
      end

      expect(execucao.mudancas).to be_empty
    end

    # Apagar sem callback não deixa "antes" para pôr de volta. A tela tem que
    # avisar, não fingir que tudo volta.
    it 'diz quando algo foi apagado sem passar pelo model' do
      etiqueta = conta.labels.create!(title: 'some')
      gravando { Label.where(id: etiqueta.id).delete_all }

      expect(execucao.reload.pendencias).to eq(['labels'])
    end

    # `dependent: :destroy_async` termina a exclusão num job, depois da
    # requisição e fora do caderno.
    it 'diz quando a exclusão continua em segundo plano' do
      time = conta.teams.create!(name: 'vendas')
      time.team_members.create!(user: admin)
      gravando { time.destroy! }

      expect(execucao.reload.pendencias).to include('ActiveRecord::DestroyAssociationAsyncJob')
    end
  end

  describe 'o desfazer' do
    it 'apaga o que o Guia criou' do
      gravando { conta.labels.create!(title: 'nova') }

      expect { desfazer }.to change(conta.labels, :count).by(-1)
    end

    it 'devolve o valor de antes ao que o Guia alterou' do
      etiqueta = conta.labels.create!(title: 'antiga')
      gravando { etiqueta.update!(title: 'renomeada') }

      desfazer

      expect(etiqueta.reload.title).to eq('antiga')
    end

    # Recriar com outro id quebraria tudo o que apontava para o registro.
    it 'recria o que o Guia apagou, com o mesmo id e os mesmos valores', :aggregate_failures do
      etiqueta = conta.labels.create!(title: 'apagada', description: 'importante', color: '#123456')
      gravando { etiqueta.destroy! }

      desfazer
      volta = Label.find(etiqueta.id)

      expect(volta.title).to eq('apagada')
      expect(volta.description).to eq('importante')
      expect(volta.color).to eq('#123456')
    end

    # O pai apagado leva os filhos (`dependent: :destroy`). Para voltar, o pai
    # precisa existir antes dos filhos — senão a chave estrangeira recusa.
    it 'recria o pai antes dos filhos', :aggregate_failures do
      funil = Crm::Pipeline.create!(account: conta, name: 'Comercial')
      etapa = Crm::PipelineStage.create!(account: conta, pipeline: funil, name: 'Novo')
      gravando { funil.destroy! }

      desfazer

      expect(Crm::Pipeline.exists?(funil.id)).to be(true)
      expect(Crm::PipelineStage.find(etapa.id).pipeline_id).to eq(funil.id)
    end

    # Desfazer não pode apagar trabalho de outra pessoa.
    it 'mantém o que alguém mudou depois e conta no relatório', :aggregate_failures do
      etiqueta = conta.labels.create!(title: 'antiga')
      gravando { etiqueta.update!(title: 'do-guia') }
      etiqueta.update!(title: 'da-pessoa')

      relatorio = desfazer

      expect(etiqueta.reload.title).to eq('da-pessoa')
      expect(relatorio['conflitos'].first).to include('motivo' => 'changed_after', 'campos' => ['title'])
    end

    it 'desfaz o turno inteiro, de trás para frente', :aggregate_failures do
      funil = nil
      gravando(0) { funil = Crm::Pipeline.create!(account: conta, name: 'Vendas') }
      gravando(1) { Crm::PipelineStage.create!(account: conta, pipeline: funil, name: 'Novo') }

      desfazer

      expect(Crm::Pipeline.exists?(funil.id)).to be(false)
      expect(execucao.reload.desfeita_em).to be_present
    end

    it 'não desfaz duas vezes nem depois do prazo', :aggregate_failures do
      gravando { conta.labels.create!(title: 'nova') }
      desfazer

      expect { desfazer }.to raise_error(Autonomia::Guide::Desfazer::Recusado)

      outra = Autonomia::Guide::Execucao.abrir(account: conta, user: admin)
      outra.update!(expira_em: 1.minute.ago)
      expect { Autonomia::Guide::Desfazer.new(execucao: outra, user: admin).perform }
        .to raise_error(Autonomia::Guide::Desfazer::Recusado)
    end
  end

  describe 'a limpeza' do
    it 'apaga o que passou dos 5 dias, com as mudanças junto', :aggregate_failures do
      gravando { conta.labels.create!(title: 'nova') }
      execucao.update!(expira_em: 1.minute.ago)

      Autonomia::Guide::LimparExecucoesJob.perform_now

      expect(Autonomia::Guide::Execucao.exists?(execucao.id)).to be(false)
      expect(Autonomia::Guide::Mudanca.where(execution_id: execucao.id)).to be_empty
    end
  end
end
# rubocop:enable RSpec/DescribeClass
