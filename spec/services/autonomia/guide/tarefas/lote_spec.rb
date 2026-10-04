require 'rails_helper'

# O lote de uma tarefa longa (#936): 25 itens por vez, com o diário, a pausa de segurança depois do
# primeiro, as pausas automáticas, a retomada sem repetir e o "Desfazer tudo".
RSpec.describe Autonomia::Guide::Tarefas::Lote do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let!(:contatos) { contatos_em_maiusculas!(conta, 60) }
  let(:tarefa) { comecar!(planejar!(conta, admin, receita_de_nomes)) }

  before do
    simular_ia_do_cliente!
    limpar_semaforo!
  end

  def classificar
    { 'pergunta' => 'Está em maiúsculas?', 'agir_quando' => ['sim'],
      'opcoes' => [{ 'chave' => 'sim', 'descricao' => 'sim' }, { 'chave' => 'nao', 'descricao' => 'não' }] }
  end

  def nomes
    Contact.where(id: contatos.map(&:id)).order(:id).pluck(:name)
  end

  # AC-TL5 — depois do 1º lote de 25, para e mostra o que mudou por tabela e os jobs na fila.
  describe 'a pausa de segurança' do
    it 'para depois do primeiro lote, com as contagens', :aggregate_failures do
      expect(rodar_lote!(tarefa)).to eq(described_class::PARAR)

      tarefa.reload
      expect(tarefa.status).to eq('aguardando_ok_canario')
      expect(tarefa.feitos).to eq(25)
      expect(tarefa.canario['tabelas']).to eq('contacts' => 25)
      expect(tarefa.canario['jobs']).to be_a(Hash)
      expect(tarefa.canario['jobs'].values.sum).to be_positive
      expect(nomes.first(25)).to all(start_with('Cliente Numero'))
      expect(nomes.last(35)).to all(start_with('CLIENTE NUMERO'))
    end

    it 'sem Seguir, nada mais roda' do
      rodar_lote!(tarefa)
      Autonomia::Guide::TarefaJob.perform_now(tarefa.id)

      expect(nomes.last(35)).to all(start_with('CLIENTE NUMERO'))
    end

    it 'com Seguir, anda até o fim, cada lote uma execução com task_id', :aggregate_failures do
      rodar_lote!(tarefa)
      tarefa.reload.mudar!('seguir')
      2.times { rodar_lote!(tarefa) }
      expect(rodar_lote!(tarefa)).to eq(described_class::PARAR)

      expect(tarefa.reload.status).to eq('concluida')
      expect(nomes).to all(start_with('Cliente Numero'))
      expect(Autonomia::Guide::Execucao.where(task_id: tarefa.id).count).to eq(3)
      expect(Autonomia::Guide::Mudanca.joins(:execucao).where(autonomia_guide_executions: { task_id: tarefa.id }).count).to eq(60)
    end
  end

  # AC-TL3 — a receita mudou depois do OK: o próximo lote não roda.
  it 'falha com o motivo quando a receita muda depois do OK', :aggregate_failures do
    tarefa.update!(receita: tarefa.receita.merge('corpo' => { 'name' => 'TROCADO' }))

    expect(rodar_lote!(tarefa)).to eq(described_class::PARAR)
    expect(tarefa.reload.status).to eq('falhou')
    expect(tarefa.para_tela['motivo']).to eq(I18n.t('autonomia.guide.tarefa.motivo.receita_mudou'))
    expect(nomes).to all(start_with('CLIENTE NUMERO'))
  end

  # AC-TL6 — o processo morre no meio do lote 3; a vigia retoma e ninguém é feito duas vezes.
  it 'retoma o lote que morreu no meio sem repetir item nem mudança', :aggregate_failures do
    rodar_lote!(tarefa)
    tarefa.reload.mudar!('seguir')
    rodar_lote!(tarefa)

    vez = 0
    acoes = Autonomia::Guide::Acoes
    allow_any_instance_of(acoes).to receive(:executar).and_wrap_original do |original, *argumentos| # rubocop:disable RSpec/AnyInstance
      vez += 1
      raise Sidekiq::Shutdown if vez == 4

      original.call(*argumentos)
    end
    expect { rodar_lote!(tarefa) }.to raise_error(Sidekiq::Shutdown)
    expect(tarefa.reload.status).to eq('rodando')

    travel 4.minutes do
      expect { Autonomia::Guide::TarefasVigiaJob.perform_now }.to have_enqueued_job(Autonomia::Guide::TarefaJob).with(tarefa.id)
      Autonomia::Guide::TarefaJob.perform_now(tarefa.id)
    end

    expect(tarefa.reload.status).to eq('concluida')
    expect(tarefa.itens.group(:status).count).to eq('feito' => 60)
    mudancas = Autonomia::Guide::Mudanca.joins(:execucao).where(autonomia_guide_executions: { task_id: tarefa.id })
    expect(mudancas.group(:record_id).count.values).to all(eq(1))
    expect(mudancas.count).to eq(60)
  end

  # AC-TL7 — cada gatilho de pausa leva a `pausada` com o motivo legível.
  describe 'as pausas automáticas' do
    def expect_pausou_por(motivo)
      tarefa.reload
      expect(tarefa.status).to eq('pausada')
      expect(tarefa.motivo_pausa).to eq(motivo)
      expect(tarefa.para_tela['motivo']).to eq(I18n.t("autonomia.guide.tarefa.motivo.#{motivo}"))
    end

    it 'pausa quando mais de 20% do lote falha' do
      contatos.first(6).each { |contato| contato.update_columns(name: '') } # rubocop:disable Rails/SkipsModelValidations
      allow_any_instance_of(Autonomia::Guide::Acoes).to receive(:executar).and_wrap_original do |original, acao, dados| # rubocop:disable RSpec/AnyInstance
        next Autonomia::Guide::Acoes::Resultado.new(ok: false, mensagem: 'recusado') if dados[:corpo][:name].blank?

        original.call(acao, dados)
      end

      rodar_lote!(tarefa)
      expect_pausou_por('falhas')
    end

    it 'pausa quando sai mensagem da conta durante o lote' do
      conversa = create(:conversation, account: conta)
      allow_any_instance_of(Autonomia::Guide::Acoes).to receive(:executar).and_wrap_original do |original, *argumentos| # rubocop:disable RSpec/AnyInstance
        create(:message, :bot_message, conversation: conversa, account: conta) unless Message.outgoing.exists?
        original.call(*argumentos)
      end

      rodar_lote!(tarefa)
      expect_pausou_por('mensagens')
    end

    it 'não pausa por mensagem de atividade nem de pessoa da equipe', :aggregate_failures do
      conversa = create(:conversation, account: conta)
      create(:message, conversation: conversa, account: conta, message_type: :activity, content: 'etiqueta posta')
      create(:message, conversation: conversa, account: conta, message_type: :outgoing, sender: admin)

      rodar_lote!(tarefa)
      expect(tarefa.reload.status).to eq('aguardando_ok_canario')
    end

    it 'pausa quando o custo passa do teto' do
      tarefa.update!(teto_custo: 0.0000001)

      rodar_lote!(tarefa)
      expect_pausou_por('custo')
    end

    it 'pausa quando a cota do Jev acaba' do
      tarefa.update!(receita: tarefa.receita.merge('classificar' => classificar))
      comecar!(tarefa.reload.tap { |t| t.update_columns(status: 'amostra_pronta') }) # rubocop:disable Rails/SkipsModelValidations
      allow(Autonomia::Guide::Tarefas::Jev).to receive(:restante).and_return(0)

      rodar_lote!(tarefa)
      expect_pausou_por('cota_jev')
    end

    it 'pausa quando o dono deixa de administrar' do
      tarefa
      conta.account_users.find_by(user: admin).update!(role: :agent)

      rodar_lote!(tarefa)
      expect_pausou_por('admin')
    end

    it 'pausa quando fica parte sem desfazer' do
      allow_any_instance_of(Autonomia::Guide::Diario::Sessao).to receive(:pendencias).and_return(['labels']) # rubocop:disable RSpec/AnyInstance

      rodar_lote!(tarefa)
      expect_pausou_por('pendencia')
    end
  end

  # AC-TL10 — desfazer tudo: do último lote ao primeiro, e a edição de uma pessoa fica.
  describe 'desfazer tudo' do
    it 'volta 59 ao original e preserva o que a pessoa editou, como conflito', :aggregate_failures do
      rodar_lote!(tarefa)
      tarefa.reload.mudar!('seguir')
      3.times { rodar_lote!(tarefa) }
      editado = contatos[30]
      editado.reload.update!(name: 'Nome Que A Pessoa Escolheu')

      tarefa.reload.mudar!('desfazer')
      Autonomia::Guide::DesfazerTarefaJob.perform_now(tarefa.id)

      tarefa.reload
      expect(tarefa.status).to eq('desfeita')
      expect(editado.reload.name).to eq('Nome Que A Pessoa Escolheu')
      expect(nomes.count { |nome| nome.start_with?('CLIENTE NUMERO') }).to eq(59)
      expect(tarefa.relatorio['desfazer']).to include('lotes' => 3, 'lotes_desfeitos' => 3, 'desfeitas' => 59, 'conflitos_total' => 1)
      expect(tarefa.relatorio['desfazer']['conflitos'].first).to include('id' => editado.id, 'motivo' => 'changed_after')
    end
  end

  # AC-TL12 — o Jev recebe o registro sem e-mail nem telefone.
  it 'manda ao Jev o registro sem e-mail e sem telefone', :aggregate_failures do
    contatos.first.update!(phone_number: '+5511999990000')
    estados = []
    allow_any_instance_of(TypesafeAi::Decisor).to receive(:decidir) do |_jev, decisor:, estado:| # rubocop:disable RSpec/AnyInstance
      estados << estado.para_o_jev(decisor).to_json
      TypesafeAi::Decisor::Resultado.new(resposta: 'sim', certeza: 0.9, modelo: 'jev')
    end
    planejar!(conta, admin, receita_de_nomes('classificar' => classificar))

    expect(estados.join).to include('CLIENTE NUMERO 1')
    expect(estados.join).not_to include('cliente1@exemplo.com', '99999', 'exemplo.com')
  end
end
