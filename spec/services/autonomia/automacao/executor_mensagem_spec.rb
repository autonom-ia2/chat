require 'rails_helper'

# Passos "mensagem" e "avisar" de ponta a ponta (#2414 F4): a automação começa, o executor manda como "Automação" e
# a proteção contra laço pega só defeito. Sem teto de uso (regra do Rodrigo, 31/10/2026).
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:contato) { create(:contact, account: account, name: 'Bruno') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def comecar_e_rodar(definicao, alvo = conversa)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, alvo) }
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def dados_do(execucao, passo = 'p1') = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: passo).dados

  def publicas_da_automacao
    conversa.messages.outgoing.where(private: false).select { |mensagem| mensagem.content_attributes['automacao_id'].present? }
  end

  # As públicas de saída, contadas no banco a cada leitura.
  def publicas = conversa.messages.outgoing.where(private: false)

  def recebida(conteudo = 'oi', quando: Time.current)
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: conteudo, created_at: quando)
  end

  def oi = mensagem_passo('p1', 'Oi ', { '$valor' => 'contato.nome' }, ', recebemos.')

  describe 'mensagem' do
    it 'manda ao cliente como "Automação": sem remetente, com a marca, e conta como envio automático', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [oi])
      execucao = comecar_e_rodar(definicao)

      mensagem = conversa.messages.outgoing.last
      expect([mensagem.content, mensagem.private, mensagem.sender]).to eq(['Oi Bruno, recebemos.', false, nil])
      expect(mensagem.content_attributes).to include('automacao_id' => definicao.id, 'execucao_id' => execucao.id, 'passo' => 'p1')
      expect(Messages::EnvioAutomatico.automatico?(mensagem)).to be(true)
      expect([execucao.reload.estado, registros(execucao)]).to eq(['concluida', [['p1', 'ok', nil]]])
    end

    it 'não conta como primeira resposta nem tira a conversa de "esperando" (não é pessoa respondendo)', :aggregate_failures do
      recebida
      conversa.update!(waiting_since: 5.minutes.ago)
      comecar_e_rodar(automacao_ligada(account, admin, [oi]))

      expect(conversa.reload.first_reply_created_at).to be_nil
      expect(conversa.waiting_since).to be_present
    end

    it 'valor vazio pula o passo e nunca manda o texto pela metade', :aggregate_failures do
      contato.update!(name: '')
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [oi]))

      expect(publicas_da_automacao).to be_empty
      expect(registros(execucao)).to eq([%w[p1 pulado faltou_valor]])
    end

    it 'texto que fica só com espaços pula com texto_vazio', :aggregate_failures do
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [mensagem_passo('p1', '   ')]))

      expect(publicas_da_automacao).to be_empty
      expect(registros(execucao)).to eq([%w[p1 pulado texto_vazio]])
    end

    it 'contato que pediu para não receber (o campo das campanhas): pula', :aggregate_failures do
      contato.update!(opted_out_at: Time.current)
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [oi]))

      expect(publicas_da_automacao).to be_empty
      expect(registros(execucao)).to eq([%w[p1 pulado contato_nao_recebe]])
    end

    it 'flag da F4 desligada depois de salvar: fecha como parada e não manda nada (rollback)', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [oi])
      account.disable_features!('automacao_mensagens')
      execucao = comecar_e_rodar(definicao)

      expect(publicas_da_automacao).to be_empty
      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 pulado mensagens_desligadas]]])
    end

    it 'sem a fundação, a F4 não vale, mesmo com a flag dela ligada' do
      account.disable_features!('automacao_fundacao')

      expect(Autonomia::Automacao::Motor.mensagens?(account)).to be(false)
    end

    it 'sem a flag da F4, o salvar recusa o passo' do
      account.disable_features!('automacao_mensagens')

      expect { automacao_ligada(account, admin, [oi]) }.to raise_error(ActiveRecord::RecordInvalid) { |erro|
        expect(erro.message).to include(I18n.t('autonomia.automacao.receita.passo_desligado', passo: 'p1'))
      }
    end

    it 'o menu "responda 1 ou 2" usado 5 vezes em 2 minutos responde as 5 (texto igual não é laço)', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [mensagem_passo('p1', 'Não entendi. Responda 1 ou 2.')])

      5.times do |vez|
        travel_to(((5 - vez) * 20).seconds.ago) do
          recebida("talvez #{vez}")
          comecar_e_rodar(definicao)
        end
      end

      expect(publicas_da_automacao.size).to eq(5)
    end
  end

  describe 'robô do outro lado' do
    let(:definicao) { automacao_ligada(account, admin, [mensagem_passo('p1', 'Recebemos.')]) }

    # Trocas que terminam agora: nosso envio e a resposta do outro lado `resposta_em` depois, com `intervalo` entre elas.
    def trocas(quantas, resposta_em:, intervalo: 1.minute, fim: Time.current)
      Array.new(quantas) { |vez| fim - ((quantas - vez) * (resposta_em + intervalo)) }.each do |envio|
        create(:message, conversation: conversa, account: account, message_type: :outgoing, sender: nil, content: 'nosso',
                         content_attributes: { automacao_id: definicao.id }, created_at: envio)
        create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'deles', created_at: envio + resposta_em)
      end
    end

    it 'robô com latência de 8 a 15 s é pego na 20ª troca: para só nesta conversa, com nota que menciona quem ligou', :aggregate_failures do
      trocas(20, resposta_em: 12.seconds, intervalo: 3.seconds)

      execucao = comecar_e_rodar(definicao)

      expect(publicas.count).to eq(20)
      expect([execucao.reload.estado, registros(execucao)]).to eq(['parada', [%w[p1 falhou laco_suspeito]]])
      expect(definicao.reload.ativa).to be(true)
      nota = conversa.messages.where(private: true).last
      expect(nota.content).to include(definicao.nome, "mention://user/#{admin.id}/")
    end

    it 'com 19 trocas rápidas ainda manda' do
      trocas(19, resposta_em: 8.seconds, intervalo: 3.seconds)

      expect { comecar_e_rodar(definicao) }.to change(publicas, :count).by(1)
    end

    it 'cliente humano com 20 mensagens no próprio ritmo: todas respondidas', :aggregate_failures do
      20.times do |vez|
        travel_to((20 - vez).minutes.ago) do
          recebida("mensagem #{vez}")
          comecar_e_rodar(definicao)
        end
      end

      expect(publicas_da_automacao.size).to eq(20)
      expect(definicao.reload.ativa).to be(true)
    end

    it 'mensagem de IA, de robô ou de outra automação no meio não conta nem zera', :aggregate_failures do
      trocas(10, resposta_em: 2.seconds, intervalo: 3.seconds, fim: 2.minutes.ago)
      create(:message, conversation: conversa, account: account, message_type: :outgoing, sender: create(:agent_bot, account: account),
                       content: 'sou a IA', created_at: 110.seconds.ago)
      create(:message, conversation: conversa, account: account, message_type: :outgoing, sender: nil, content: 'regra antiga',
                       content_attributes: { automation_rule_id: 9 }, created_at: 100.seconds.ago)
      trocas(10, resposta_em: 2.seconds, intervalo: 3.seconds)

      execucao = comecar_e_rodar(definicao)

      expect(registros(execucao)).to eq([%w[p1 falhou laco_suspeito]])
    end

    it 'volta quando uma pessoa da equipe escreve', :aggregate_failures do
      trocas(20, resposta_em: 2.seconds, intervalo: 3.seconds, fim: 1.minute.ago)
      expect(registros(comecar_e_rodar(definicao))).to eq([%w[p1 falhou laco_suspeito]])

      create(:message, conversation: conversa, account: account, message_type: :outgoing, sender: admin, content: 'sou a Ana')

      expect { comecar_e_rodar(definicao) }.to change(publicas_da_automacao_count, :call).by(1)
    end

    it 'volta quando a conversa fica 30 minutos sem mensagem' do
      trocas(20, resposta_em: 2.seconds, intervalo: 3.seconds, fim: 31.minutes.ago)

      expect { comecar_e_rodar(definicao) }.to change(publicas_da_automacao_count, :call).by(1)
    end

    def publicas_da_automacao_count = -> { publicas_da_automacao.size }
  end

  describe 'avisar' do
    let(:inbox) { conversa.inbox }
    let(:responsavel) { create(:user, account: account, role: :agent, name: 'Carla') }
    let(:do_time) { create(:user, account: account, role: :agent, name: 'Davi') }
    let(:fora_da_caixa) { create(:user, account: account, role: :agent, name: 'Eva') }
    let(:time) { create(:team, account: account) }

    before do
      [responsavel, do_time].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
      [do_time, fora_da_caixa].each { |pessoa| create(:team_member, user: pessoa, team: time) }
      conversa.update!(assignee: responsavel)
    end

    it 'nota privada que menciona o responsável e o time, sem quem não enxerga a caixa; a menção vira aviso', :aggregate_failures do
      passo = avisar_passo('p1', { 'responsavel' => true, 'times' => [time.id] }, 'Cliente ', { '$valor' => 'contato.nome' },
                           ' pediu desconto')
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [passo]))

      nota = conversa.messages.where(private: true).last
      expect([nota.sender, nota.content_attributes['automacao_id']]).to eq([nil, execucao.automacao_id])
      expect(nota.content).to start_with('Cliente Bruno pediu desconto')
      expect(nota.content).to include("mention://user/#{responsavel.id}/", "mention://user/#{do_time.id}/")
      expect(nota.content).not_to include("mention://user/#{fora_da_caixa.id}/")
      expect(publicas_da_automacao).to be_empty

      Messages::MentionService.new(message: nota).perform
      avisados = Notification.where(notification_type: 'conversation_mention', primary_actor: conversa).pluck(:user_id)
      expect(avisados).to contain_exactly(responsavel.id, do_time.id)
      expect(registros(execucao)).to eq([['p1', 'ok', nil]])
    end

    it 'na caixa, mas com função que não enxerga esta conversa: fica de fora (Pundit por pessoa)', :aggregate_failures do
      restrita = create(:user, account: account, role: :agent, name: 'Fabi')
      create(:inbox_member, user: restrita, inbox: inbox)
      funcao = create(:custom_role, account: account, permissions: ['conversation_unassigned_manage'])
      restrita.account_users.find_by(account: account).update!(custom_role: funcao)

      passo = avisar_passo('p1', { 'pessoas' => [restrita.id, responsavel.id] }, 'Oi')
      comecar_e_rodar(automacao_ligada(account, admin, [passo]))

      nota = conversa.messages.where(private: true).last
      expect(nota.content).to include("mention://user/#{responsavel.id}/")
      expect(nota.content).not_to include("mention://user/#{restrita.id}/")
    end

    it 'ninguém da lista enxerga a conversa: pula', :aggregate_failures do
      passo = avisar_passo('p1', { 'pessoas' => [fora_da_caixa.id] }, 'Oi')
      execucao = comecar_e_rodar(automacao_ligada(account, admin, [passo]))

      expect(conversa.messages.where(private: true)).to be_empty
      expect(registros(execucao)).to eq([%w[p1 pulado ninguem_para_avisar]])
      expect(dados_do(execucao)['fora']).to eq([{ 'id' => fora_da_caixa.id, 'motivo' => 'nao_ve_a_conversa' }])
    end

    it 'quem sai fica no registro com o motivo: não enxerga a conversa, ou saiu da conta depois do salvar', :aggregate_failures do
      saiu = create(:user, account: account, role: :agent, name: 'Gil')
      definicao = automacao_ligada(account, admin, [avisar_passo('p1', { 'times' => [time.id], 'pessoas' => [saiu.id] }, 'Oi')])
      saiu.account_users.find_by(account: account).destroy!
      execucao = comecar_e_rodar(definicao)

      expect(dados_do(execucao)['pessoas']).to eq([do_time.id])
      expect(dados_do(execucao)['fora']).to contain_exactly({ 'id' => fora_da_caixa.id, 'motivo' => 'nao_ve_a_conversa' },
                                                            { 'id' => saiu.id, 'motivo' => 'fora_da_conta' })
    end

    it 'o salvar recusa time e pessoa de outra conta' do
      de_fora = create(:team)
      outra_pessoa = create(:user)
      passo = avisar_passo('p1', { 'times' => [de_fora.id], 'pessoas' => [outra_pessoa.id] }, 'Oi')

      expect { automacao_ligada(account, admin, [passo]) }.to raise_error(ActiveRecord::RecordInvalid) { |erro|
        expect(erro.message).to include(I18n.t('autonomia.automacao.receita.time_de_fora', passo: 'p1', id: de_fora.id),
                                        I18n.t('autonomia.automacao.receita.pessoa_de_fora', passo: 'p1', id: outra_pessoa.id))
      }
    end
  end

  describe 'alvo card' do
    let(:execucao) { comecar(automacao_ligada(account, admin, [esperar_passo('p0')]), conversa) }
    let(:funil) { create_crm_pipeline(account: account, user: admin) }

    def card(principal)
      Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Pedido', currency: 'BRL',
                        primary_conversation: principal)
    end

    def aviso = avisar_passo('p2', { 'pessoas' => [admin.id] }, 'Cliente ', { '$valor' => 'contato.nome' })

    it 'sem conversa principal: mensagem e aviso pulam com sem_conversa, e nada é mandado', :aggregate_failures do
      sozinho = card(nil)
      mensagem = Autonomia::Automacao::PassoDeMensagem.new(execucao: execucao, passo: oi, alvo: sozinho).executar
      aviso_do_card = Autonomia::Automacao::PassoDeAviso.new(execucao: execucao, passo: aviso, alvo: sozinho).executar

      expect([mensagem.tipo, mensagem.motivo]).to eq([:pulado, 'sem_conversa'])
      expect([aviso_do_card.tipo, aviso_do_card.motivo]).to eq([:pulado, 'sem_conversa'])
      expect(conversa.messages.reload).to be_empty
    end

    it 'com conversa principal: avisa nela, com os valores dela' do
      resultado = Autonomia::Automacao::PassoDeAviso.new(execucao: execucao, passo: aviso, alvo: card(conversa)).executar

      expect([resultado.tipo, conversa.messages.where(private: true).last.content]).to match([:ok, start_with('Cliente Bruno')])
    end
  end

  describe 'a mensagem pelos ouvintes da plataforma' do
    it 'passa por todos os ouvintes do evento e chega ao webhook com remetente vazio', :aggregate_failures do
      create(:webhook, account: account, subscriptions: ['message_created'])
      definicao = automacao_ligada(account, admin, [oi])

      perform_enqueued_jobs(only: [Autonomia::Automacao::AvancarJob, EventDispatcherJob]) { comecar(definicao, conversa) }

      mensagem = publicas_da_automacao.last
      webhook = enqueued_jobs.find { |job| job['job_class'] == 'WebhookJob' && job['arguments'][1]['id'] == mensagem.id }
      expect(webhook).to be_present
      expect(webhook['arguments'][1]['sender']).to be_nil
    end

    it 'regra antiga que responde a toda mensagem de saída responde uma vez e para: a cadeia comum segura o laço', :aggregate_failures do
      create(:automation_rule, account: account, event_name: 'message_created',
                               conditions: [{ 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['outgoing'],
                                              'query_operator' => nil }],
                               actions: [{ 'action_name' => 'send_message', 'action_params' => ['Regra antiga'] }])
      definicao = automacao_ligada(account, admin, [oi])

      perform_enqueued_jobs(only: [Autonomia::Automacao::AvancarJob, EventDispatcherJob]) { comecar(definicao, conversa) }

      expect(publicas_da_automacao.size).to eq(1)
      expect(conversa.messages.where(content: 'Regra antiga').count).to eq(1)
    end
  end
end
