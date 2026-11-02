require 'rails_helper'

# O motor de ponta a ponta (#2414 F3, #2459): a automação começa, espera no banco, a varredura acorda e a ação roda pela
# porta da frente, como quem ligou. Os aceites F3.1 a F3.9 estão no nome de cada exemplo.
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before { ligar_motor(account) }

  after { Current.reset }

  def comecar_e_rodar(definicao, alvo = conversa)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, alvo) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  describe 'esperar e agir (F3.1, F3.3)' do
    let(:definicao) { automacao_ligada(account, admin, [esperar_passo('p1'), prioridade_passo('p2')]) }

    it 'espera no banco, sem job agendado, e age depois que a varredura acorda', :aggregate_failures do
      execucao = comecar_e_rodar(definicao).reload

      expect(execucao.estado).to eq('esperando')
      expect(execucao.cursor).to eq('p1')
      expect(execucao.due_at).to be_within(1.minute).of(1.day.from_now)
      expect(enqueued_jobs.count { |job| job['job_class'] == Autonomia::Automacao::AvancarJob.name }).to eq(0)

      travel(23.hours) { varrer }
      expect(execucao.reload.estado).to eq('esperando')

      travel(1.day + 1.minute) { varrer }
      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('urgent')
      expect(registros(execucao)).to eq([%w[p1 ok] + [nil], %w[p2 ok] + [nil]])
    end

    it 'cada rodada depois da espera tem raiz nova, com as mesmas origens e a mesma profundidade', :aggregate_failures do
      raizes = []
      allow(Autonomia::Automacao::Cadeia).to receive(:retomar).and_wrap_original do |original, lista, conta, raiz, &bloco|
        raizes << [lista, raiz]
        original.call(lista, conta, raiz, &bloco)
      end

      execucao = comecar_e_rodar(definicao)
      travel(1.day + 1.minute) { varrer }

      origem = "automacao:#{definicao.id}"
      expect(raizes.map(&:first)).to eq([[origem], [origem]])
      expect(raizes.map(&:last).uniq.size).to eq(2)
      expect(execucao.reload.profundidade).to eq(1)
    end

    # Sidekiq devolve o job em voo quando o processo é derrubado, e o Dead set reenvia com os mesmos argumentos.
    it 'o mesmo job entregue duas vezes anda uma vez só', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      travel(1.day + 1.minute) do
        Autonomia::Automacao::VarreduraJob.perform_now
        argumentos = enqueued_jobs.find { |job| job['job_class'] == Autonomia::Automacao::AvancarJob.name }['arguments']
        2.times { Autonomia::Automacao::AvancarJob.perform_now(*argumentos) }
      end

      expect(execucao.reload.estado).to eq('concluida')
      expect(Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'p2').count).to eq(1)
      expect(Audited.audit_class.where(action: 'automacao_action').count).to eq(1)
    end

    it 'a rodada que começou e quebrou no meio fica para a varredura fechar, sem repetir', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      allow(Autonomia::Automacao::PassoDeAcao).to receive(:new).and_raise(Redis::CannotConnectError)

      travel(1.day + 1.minute) { varrer }
      expect([execucao.reload.estado, execucao.due_at]).to eq(['andando', nil])
      quebra = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).last
      expect(quebra).to have_attributes(passo: 'p2', resultado: 'falhou', motivo: 'erro_inesperado',
                                        dados: { 'erro' => 'Redis::CannotConnectError' })

      travel(1.day + 17.minutes) { varrer }
      expect([execucao.reload.estado, registros(execucao).last]).to eq(['interrompida', %w[p1 falhou travada]])
    end
  end

  it 'o alvo apagado entre a reserva e a rodada fecha a execução como interrompida' do
    execucao = comecar_e_rodar(automacao_ligada(account, admin, [esperar_passo('p1'), prioridade_passo('p2')]))

    travel(1.day + 1.minute) do
      Autonomia::Automacao::VarreduraJob.perform_now
      conversa.delete
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)
    end

    expect([execucao.reload.estado, registros(execucao).last]).to eq(['interrompida', %w[p1 pulado alvo_sumiu]])
  end

  describe 'ramos e fim' do
    it 'segue pelo ramo da condição, e "parar" conclui sem rodar o resto', :aggregate_failures do
      passos = [{ 'id' => 's1', 'tipo' => 'se',
                  'condicao' => { 'campo' => { '$valor' => 'conversa.status' }, 'op' => 'igual', 'valor' => 'open' },
                  'entao' => [prioridade_passo('a1', 'high')],
                  'senao' => [prioridade_passo('a2', 'low')] },
                { 'id' => 'fim', 'tipo' => 'parar' },
                prioridade_passo('a3', 'urgent')]
      execucao = comecar_e_rodar(automacao_ligada(account, admin, passos)).reload

      expect(execucao.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('high')
      expect(registros(execucao).map(&:first)).to eq(%w[s1 a1 fim])
    end

    it '"esperar até" com o prazo vencido segue pelo caminho "se vencer"', :aggregate_failures do
      passos = [{ 'id' => 'e1', 'tipo' => 'esperar_ate',
                  'condicao' => { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' },
                  'prazo' => { 'valor' => 2, 'unidade' => 'horas' },
                  'se_vencer' => [prioridade_passo('v1', 'low')] }]
      execucao = comecar_e_rodar(automacao_ligada(account, admin, passos))
      expect(execucao.reload.estado).to eq('esperando')

      travel(2.hours + 1.minute) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
      expect(registros(execucao)).to eq([%w[e1 ok] + [nil], %w[e1 pulado prazo_vencido], %w[v1 ok] + [nil]])
    end

    it 'o passo depois de uma ação lê o alvo já mudado por ela', :aggregate_failures do
      prioridade = ->(valor) { { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => valor } }
      passos = [prioridade_passo('a1', 'urgent'),
                { 'id' => 's1', 'tipo' => 'se', 'condicao' => prioridade.call('urgent'), 'entao' => [prioridade_passo('a2', 'high')] },
                { 'id' => 'e1', 'tipo' => 'esperar_ate', 'condicao' => prioridade.call('high'), 'prazo' => { 'valor' => 2, 'unidade' => 'dias' } }]
      execucao = comecar_e_rodar(automacao_ligada(account, admin, passos)).reload

      expect(execucao.estado).to eq('concluida')
      expect(registros(execucao)).to eq([%w[a1 ok] + [nil], %w[s1 ok] + [nil], %w[a2 ok] + [nil], %w[e1 ok] + [nil]])
    end

    it '"esperar até" com a condição já cumprida segue sem esperar' do
      conversa.update!(priority: :urgent)
      passos = [{ 'id' => 'e1', 'tipo' => 'esperar_ate',
                  'condicao' => { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' },
                  'prazo' => { 'valor' => 2, 'unidade' => 'horas' } }, prioridade_passo('p2', 'low')]

      expect(comecar_e_rodar(automacao_ligada(account, admin, passos)).reload.estado).to eq('concluida')
    end

    it 'valor vazio do alvo pula a ação e segue' do
      passos = [prioridade_passo('p1', conversa_id: { '$valor' => 'conversa.time_id' }), prioridade_passo('p2', 'low')]
      execucao = comecar_e_rodar(automacao_ligada(account, admin, passos))

      expect(registros(execucao)).to eq([%w[p1 pulado faltou_valor], %w[p2 ok] + [nil]])
    end
  end

  describe 'desligar no meio (F3.4)' do
    let(:definicao) { automacao_ligada(account, admin, [esperar_passo('p1'), prioridade_passo('p2')]) }

    it 'desligada entre duas ações da mesma rodada, a segunda não roda', :aggregate_failures do
      duas = automacao_ligada(account, admin, [prioridade_passo('a1', 'high'), prioridade_passo('a2', 'urgent')])
      allow(Autonomia::Automacao::PassoDeAcao).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap do |passo|
          allow(passo).to(receive(:executar).and_wrap_original { |executar| executar.call.tap { duas.desligar! } })
        end
      end

      execucao = comecar_e_rodar(duas)

      expect(conversa.reload.priority).to eq('high')
      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[a1 ok] + [nil]]])
    end

    it 'fechada pela varredura no meio da rodada, a próxima ação não roda e nada é gravado por cima', :aggregate_failures do
      duas = automacao_ligada(account, admin, [prioridade_passo('a1', 'high'), prioridade_passo('a2', 'urgent')])
      allow(Autonomia::Automacao::PassoDeAcao).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap do |passo|
          allow(passo).to(receive(:executar).and_wrap_original do |executar|
            executar.call.tap do
              Autonomia::Automacao::Execucao.where(automacao: duas).update_all(estado: 'interrompida', finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
            end
          end)
        end
      end

      execucao = comecar_e_rodar(duas)

      expect(conversa.reload.priority).to eq('high')
      expect([execucao.reload.estado, registros(execucao)]).to eq(['interrompida', [%w[a1 ok] + [nil]]])
    end

    it 'desligar fecha a execução cujo alvo já foi apagado' do
      execucao = comecar_e_rodar(definicao)
      conversa.delete

      definicao.desligar!

      expect([definicao.reload.ativa, execucao.reload.estado]).to eq([false, 'parada'])
    end

    it 'outra pessoa salvar uma versão nova pausa a automação; quem ligou salvar, não (parecer do Funções)', :aggregate_failures do
      outro_admin = create(:user, account: account, role: :administrator)
      receita = definicao.versao_ativa.receita

      definicao.salvar_versao!(receita: receita, autor: admin)
      expect(definicao.reload.ativa).to be(true)

      definicao.salvar_versao!(receita: receita, autor: outro_admin)
      expect([definicao.reload.ativa, definicao.ligada_por]).to eq([false, admin])
    end

    it 'quem espera para, e a varredura não acorda', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)

      definicao.desligar!
      travel(1.day + 1.minute) { varrer }

      expect(execucao.reload.estado).to eq('parada')
      expect(conversa.reload.priority).to be_nil
    end

    it 'a rodada já na fila confere a automação e para' do
      execucao = comecar_e_rodar(definicao)
      definicao.update!(ativa: false)

      travel(1.day + 1.minute) { varrer }

      expect([execucao.reload.estado, registros(execucao).last]).to eq(['parada', %w[p1 pulado desligada]])
    end

    it 'sem o motor na conta, a rodada fecha a execução como parada (rollback da flag)' do
      execucao = comecar_e_rodar(definicao)
      account.disable_features!('automacao_motor')

      travel(1.day + 1.minute) { varrer }

      expect([execucao.reload.estado, registros(execucao).last]).to eq(['parada', %w[p1 pulado motor_desligado]])
    end
  end

  describe 'Spam (F3.5)' do
    let(:caixa) { create(:inbox, account: account, channel: create(:channel_email, account: account)) }
    let(:conversa) { create(:conversation, account: account, inbox: caixa, status: :open) }

    before { account.enable_features!('conversa_email_nova') }

    it 'não começa no Spam, e a que esperava para quando a conversa vai para o Spam', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [esperar_passo('p1'), prioridade_passo('p2')])
      execucao = comecar_e_rodar(definicao)

      ConversaCanal::PastaDoEmail.create!(account: account, conversation: conversa, pasta: 'spam')
      travel(1.day + 1.minute) { varrer }

      expect([execucao.reload.estado, registros(execucao).last]).to eq(['parada', %w[p1 pulado spam]])
      expect(comecar(automacao_ligada(account, admin, [prioridade_passo('p1')]), conversa)).to be_nil
    end
  end

  describe 'erros da ação (F3.6)' do
    def responder(codigo, &antes)
      chamada = instance_double(Autonomia::Guide::ChamadaInterna)
      allow(chamada).to receive(:chamar) do
        antes&.call
        Autonomia::Guide::ChamadaInterna::Resposta.new(codigo: codigo, corpo: '{}')
      end
      allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_return(chamada)
    end

    it 'limite de pedidos (429) é passageiro: tenta de novo' do
      responder('429')

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [prioridade_passo('p1')])).reload

      expect([execucao.estado, execucao.tentativas, registros(execucao)]).to eq(['esperando', 1, [%w[p1 falhou erro_passageiro]]])
    end

    it 'erro depois de gravar parte da ação não repete, para não fazer duas vezes', :aggregate_failures do
      responder('500') { account.labels.create!(title: 'criada-antes-do-erro') }

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [prioridade_passo('p1')])).reload

      expect([execucao.estado, registros(execucao)]).to eq(['falhou', [%w[p1 falhou erro_depois_de_gravar]]])
      expect(account.labels.where(title: 'criada-antes-do-erro').count).to eq(1)
    end

    it 'erro permanente (404) fecha a execução como falhou, sem tentar de novo', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [prioridade_passo('p1', conversa_id: 999_999)])
      execucao = comecar_e_rodar(definicao).reload

      expect(execucao.estado).to eq('falhou')
      expect(registros(execucao)).to eq([%w[p1 falhou erro_permanente]])
      expect(Autonomia::Automacao::Registro.find_by(execucao: execucao).dados).to include('codigo' => 404)
    end

    it 'erro passageiro tenta 3 vezes, com 1 e 5 minutos entre elas, e então falha', :aggregate_failures do
      fora_do_ar = instance_double(Autonomia::Guide::ChamadaInterna)
      allow(fora_do_ar).to receive(:chamar).and_return(Autonomia::Guide::ChamadaInterna::Resposta.new(codigo: '503', corpo: '{}'))
      allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_return(fora_do_ar)

      execucao = comecar_e_rodar(automacao_ligada(account, admin, [prioridade_passo('p1')])).reload
      expect([execucao.estado, execucao.tentativas]).to eq(['esperando', 1])
      expect(execucao.due_at).to be_within(5.seconds).of(1.minute.from_now)

      travel(1.minute + 1.second) { varrer }
      expect([execucao.reload.estado, execucao.tentativas]).to eq(['esperando', 2])

      travel(7.minutes) { varrer }
      expect(execucao.reload.estado).to eq('falhou')
      expect(registros(execucao)).to eq([%w[p1 falhou erro_passageiro]] * 3)
      expect(fora_do_ar).to have_received(:chamar).exactly(3).times
    end
  end

  describe 'quem ligou (D1, F3.7, F3.9)' do
    let(:funcao) { create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage]) }
    let(:agente) { create(:user, account: account, role: :agent) }
    let(:definicao) { automacao_ligada(account, agente, [esperar_passo('p1'), prioridade_passo('p2')]) }

    before do
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      create(:inbox_member, user: agente, inbox: conversa.inbox)
    end

    it 'agente com a chave e a caixa age como ele mesmo' do
      comecar_e_rodar(definicao)
      travel(1.day + 1.minute) { varrer }

      expect(conversa.reload.priority).to eq('urgent')
    end

    it 'tirado da caixa durante a espera, pausa a automação; assumir e religar devolve a vez', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      InboxMember.find_by(user: agente, inbox: conversa.inbox).destroy!

      travel(1.day + 1.minute) { varrer }

      expect([execucao.reload.estado, registros(execucao).last]).to eq(['parada', %w[p1 pulado quem_ligou_sem_acesso]])
      expect(definicao.reload.ativa).to be(false)
      expect(conversa.reload.priority).to be_nil

      expect(definicao.assumir_e_religar!(admin, versao_id: definicao.versao_ativa_id)).to be_nil
      expect([definicao.reload.ativa, definicao.ligada_por]).to eq([true, admin])
    end

    # Q1 da qualidade: a chave de automações não dá o que o endpoint nega (criar etiqueta pede label_manage).
    it 'o endpoint nega a ação (401): pausa a automação e não cria nada', :aggregate_failures do
      criar = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST labels', 'descricao' => 'Criar a etiqueta',
                'corpo' => { 'title' => 'renovacao', 'description' => 'Cliente em renovação' } }
      execucao = comecar_e_rodar(automacao_ligada(account, agente, [criar]))

      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 falhou quem_ligou_sem_acesso]]])
      expect(Autonomia::Automacao::Definicao.where(ligada_por: agente).pluck(:ativa)).to eq([false])
      expect(account.labels.count).to eq(0)
    end

    it 'perdeu a chave entre a reconferência e a chamada: pausa', :aggregate_failures do
      definicao = automacao_ligada(account, agente, [prioridade_passo('p1')])
      funcao.update!(permissions: %w[conversation_manage])
      allow(Autonomia::Automacao::Acesso).to receive(:new).and_wrap_original do |original, *argumentos|
        original.call(*argumentos).tap { |acesso| allow(acesso).to receive(:motivo).and_return(nil) }
      end

      execucao = comecar_e_rodar(definicao)

      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 falhou quem_ligou_sem_permissao]]])
      expect([definicao.reload.ativa, conversa.reload.priority]).to eq([false, nil])
    end

    it 'assumir e religar recusa quem não tem a chave, sem mudar nada', :aggregate_failures do
      sem_chave = create(:user, account: account, role: :agent)
      definicao.update!(ativa: false)

      expect(definicao.assumir_e_religar!(sem_chave, versao_id: definicao.versao_ativa_id).motivo).to eq('quem_ligou_sem_permissao')
      expect([definicao.reload.ativa, definicao.ligada_por]).to eq([false, agente])
    end

    it 'perdeu a chave durante a espera: pausa' do
      execucao = comecar_e_rodar(definicao)
      funcao.update!(permissions: %w[conversation_manage])

      travel(1.day + 1.minute) { varrer }

      expect([execucao.reload.estado, registros(execucao).last]).to eq(['parada', %w[p1 pulado quem_ligou_sem_permissao]])
    end

    it 'saiu da conta durante a espera: pausa, e nunca roda em nome de outro (F3.9)', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      account.account_users.find_by(user: agente).destroy!

      travel(1.day + 1.minute) { varrer }

      expect([execucao.reload.estado, registros(execucao).last]).to eq(['parada', %w[p1 pulado quem_ligou_saiu_da_conta]])
      expect(definicao.reload.ativa).to be(false)
      expect(conversa.reload.priority).to be_nil
    end
  end

  describe 'histórico e desfazer (F3.8, F3.9)' do
    let(:definicao) { automacao_ligada(account, admin, [prioridade_passo('p1')]) }

    it 'a auditoria diz que foi a automação, com o id dela e o da execução' do
      execucao = comecar_e_rodar(definicao)

      auditoria = Audited.audit_class.find_by(action: 'automacao_action')
      expect(auditoria.user).to eq(admin)
      expect(auditoria.audited_changes).to include('acao' => 'POST conversations/:id/toggle_priority', 'frase' => 'Marcar a prioridade',
                                                   'automacao_id' => definicao.id, 'execucao_id' => execucao.id)
    end

    it 'a mudança fica no caderno de quem ligou e se desfaz como no Guia', :aggregate_failures do
      execucao = comecar_e_rodar(definicao)
      caderno = Autonomia::Guide::Execucao.find(Autonomia::Automacao::Registro.find_by(execucao: execucao).dados['caderno_id'])
      expect(caderno.user).to eq(admin)
      expect(conversa.reload.priority).to eq('urgent')

      Autonomia::Guide::Desfazer.new(execucao: caderno, user: admin).perform

      expect(conversa.reload.priority).to be_nil
    end
  end
end
