require 'rails_helper'

# #2931, #2935 e #2936: o salvar (esquema + Receita) e o ensaio da aprovação, da reunião e da pesquisa. O ensaio diz o
# que fariam pelas mesmas perguntas do motor e não faz nada: nenhuma mensagem, nenhum pedido, nenhum aviso.
RSpec.describe Autonomia::Automacao::PassosQueEsperam, :automacao_motor do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:gerente) { create(:user, account: account, role: :administrator, name: 'Gerente Ana') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }

  before do
    # A conversa que o ensaio lê (a última da conta).
    create(:conversation, account: account, inbox: inbox, contact: contato, status: :resolved)
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia', 'automacao_passos_novos')
  end

  def aprovacao(extra = {})
    { 'id' => 'aprova', 'tipo' => 'pedir_aprovacao', 'quem' => { 'de' => 'pessoa', 'id' => gerente.id }, 'pergunta' => ['Pode seguir?'],
      'prazo' => { 'valor' => 1, 'unidade' => 'dias' }, 'aprovado' => [esperar_passo('depois')] }.merge(extra)
  end

  def pesquisa(extra = {})
    { 'id' => 'nota', 'tipo' => 'pesquisa_nota', 'pergunta' => 'De 0 a 10?', 'baixa_ate' => 6, 'alta_desde' => 9,
      'intervalo_dias' => 30, 'espera' => { 'valor' => 2, 'unidade' => 'dias' } }.merge(extra)
  end

  def receita(*passos, gatilho: { 'tipo' => 'conversa.resolvida' }) = { 'gatilho' => gatilho, 'passos' => passos }

  def problemas(receita)
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account.account_users.find_by(user: admin)).problemas
  end

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  describe 'o esquema' do
    it 'aceita os três como a tela monta e recusa o que a tela não deixa', :aggregate_failures do
      reuniao = { 'id' => 'r', 'tipo' => 'marcar_reuniao', 'com' => { 'de' => 'responsavel' }, 'duracao' => 30, 'convite' => 'Oi!',
                  'espera' => { 'valor' => 1, 'unidade' => 'dias' } }
      valido = ->(passo) { Autonomia::Automacao::Receita.esquema_valido?(receita(passo)) }

      expect([aprovacao, pesquisa, reuniao].map(&valido)).to all(be(true))
      expect(valido.call(reuniao.merge('com' => { 'de' => 'time', 'id' => 3 }))).to be(false)
      expect(valido.call(reuniao.merge('duracao' => 20))).to be(false)
      expect(valido.call(aprovacao('quem' => { 'de' => 'pessoa' }))).to be(false)
      expect(valido.call(pesquisa('intervalo_dias' => 10))).to be(false)
    end
  end

  describe 'ao salvar' do
    it 'sem a flag dos passos novos, recusa com o porquê' do
      account.disable_features!('automacao_passos_novos')

      expect(problemas(receita(aprovacao))).to include(frase(:passos_novos_desligados, passo: 'aprova'))
    end

    it 'a pesquisa com a nota média vazia é recusada' do
      expect(problemas(receita(pesquisa('baixa_ate' => 8, 'alta_desde' => 9)))).to include(frase(:pesquisa_faixa_media_vazia, passo: 'nota'))
    end

    it 'a pessoa de outra conta não aprova' do
      de_fora = create(:user)

      expect(problemas(receita(aprovacao('quem' => { 'de' => 'pessoa', 'id' => de_fora.id }))))
        .to include(frase(:pessoa_de_fora, passo: 'aprova', id: de_fora.id))
    end

    it 'a pesquisa precisa de conversa: no gatilho de contato, recusa' do
      gatilho = { 'tipo' => 'contato.data', 'campo' => 'aniversario', 'quando' => 'antes', 'dias' => 0, 'hora' => 9 }
      account.enable_features!('automacao_gatilhos')

      expect(problemas(receita(pesquisa, gatilho: gatilho))).to include(frase(:espera_resposta_sem_conversa, passo: 'nota'))
    end

    it 'o texto do pedido passa pela régua dos valores' do
      lido = problemas(receita(aprovacao('pergunta' => ['Valor: ', { '$valor' => 'conversa.inexistente' }])))

      expect(lido).to include(frase(:valor_desconhecido, passo: 'aprova', caminho: 'conversa.inexistente'))
    end

    it 'os três prontos passam' do
      expect(problemas(receita(aprovacao, pesquisa))).to be_empty
    end
  end

  describe 'no ensaio' do
    def passos_do_ensaio(receita)
      Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos]
    end

    it 'a aprovação diz a quem o pedido iria e abre os três galhos, sem pedido nem aviso', :aggregate_failures do
      no = nil
      expect { no = passos_do_ensaio(receita(aprovacao)).first }.not_to change(Notification, :count)

      expect(no).to include(faria: 'pedir_aprovacao', dados: { para: ['Gerente Ana'] })
      expect(no[:ramos].pluck(:chave)).to eq(%w[aprovado recusado ninguem_respondeu])
      expect(no[:ramos].first[:passos].first).to include(id: 'depois')
      expect(Autonomia::Automacao::Registro.count).to eq(0)
    end

    it 'a pesquisa mostra a pergunta e o prazo, sem mandar nada', :aggregate_failures do
      no = nil
      expect { no = passos_do_ensaio(receita(pesquisa)).first }.not_to change(Message, :count)

      expect(no).to include(faria: 'pesquisa_nota')
      expect(no[:dados]).to include(pergunta: 'De 0 a 10?', espera: { 'valor' => 2, 'unidade' => 'dias' })
    end

    it 'a pesquisa recente pula e segue para o passo seguinte' do
      contato.update!(additional_attributes: { 'pesquisa_perguntada_em' => 1.day.ago.iso8601 })

      lido = passos_do_ensaio(receita(pesquisa, esperar_passo('seguinte')))
      expect(lido.pluck(:id, :faria)).to eq([%w[nota pesquisa_recente], %w[seguinte esperar]])
    end

    # Como o motor (decisão do Rodrigo, 12/11): sem com quem marcar, ou sem a página dela, seguiria sem reunião pelo
    # caminho "Se o cliente não responder", com o mesmo motivo do histórico.
    describe 'a reunião sem com quem marcar' do
      around do |example|
        with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { example.run }
      end

      before { account.enable_features!('crm_booking_v2') }

      def reuniao(com)
        { 'id' => 'reuniao', 'tipo' => 'marcar_reuniao', 'com' => com, 'duracao' => 30, 'convite' => 'Posso te ligar?',
          'espera' => { 'valor' => 1, 'unidade' => 'dias' }, 'outro_horario' => [esperar_passo('outro')],
          'nao_respondeu' => [esperar_passo('calado')] }
      end

      it 'sem responsável na conversa: seguiria por "Se o cliente não responder", sem mandar nada', :aggregate_failures do
        no = nil
        expect { no = passos_do_ensaio(receita(reuniao({ 'de' => 'responsavel' }))).first }.not_to change(Message, :count)

        expect(no).to include(id: 'reuniao', faria: 'reuniao_sem_responsavel', dados: {})
        expect(no[:ramos].pluck(:chave)).to eq(%w[nao_respondeu])
        expect(no[:ramos].first[:passos].first).to include(id: 'calado')
      end

      it 'a pessoa sem página de agendamento: seguiria por "Se o cliente não responder", sem mandar nada', :aggregate_failures do
        no = nil
        expect { no = passos_do_ensaio(receita(reuniao({ 'de' => 'pessoa', 'id' => gerente.id }))).first }.not_to change(Message, :count)

        expect(no).to include(id: 'reuniao', faria: 'reuniao_sem_pagina', dados: { por: 'sem_pagina' })
        expect(no[:ramos].pluck(:chave)).to eq(%w[nao_respondeu])
        expect(no[:ramos].first[:passos].first).to include(id: 'calado')
      end
    end

    # O ensaio responde o mesmo que o motor: o que o motor confere antes de mandar (a pesquisa recente; a pessoa, a página
    # e os horários da reunião), o ensaio confere antes do canal. A janela fechada: a caixa API com o limite de 24 h do
    # dono vencido, sem modelo.
    context 'with a janela da conversa fechada' do
      let(:fechada) do
        canal = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '24' })
        create(:conversation, account: account, inbox: canal.inbox, contact: contato, status: :resolved).tap do |conversa|
          create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'oi',
                           created_at: 30.hours.ago)
        end
      end

      def reuniao
        { 'id' => 'reuniao', 'tipo' => 'marcar_reuniao', 'com' => { 'de' => 'pessoa', 'id' => gerente.id }, 'duracao' => 30,
          'convite' => 'Posso te ligar?', 'espera' => { 'valor' => 1, 'unidade' => 'dias' }, 'outro_horario' => [esperar_passo('outro')] }
      end

      def ensaio_na_fechada(receita)
        Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin, conversa_id: fechada.display_id)
                                    .resultado[:conversas].first[:passos]
      end

      it 'sem pesquisa recente, para pela janela, como a mensagem' do
        expect(ensaio_na_fechada(receita(pesquisa)).first).to include(id: 'nota', faria: 'pararia')
      end

      # Como o motor (espera_de_resposta_spec): com o modelo no lugar, o passo pergunta e espera; não segue em frente.
      it 'com o modelo no lugar, a pesquisa pergunta e abre os caminhos, com o modelo', :aggregate_failures do
        envio = instance_double(Autonomia::Automacao::EnvioNoEnsaio, pausaria_ao_agir: nil,
                                                                     do_canal: [Autonomia::Automacao::EnvioNoEnsaio::MODELO])
        allow(Autonomia::Automacao::EnvioNoEnsaio).to receive(:new).and_return(envio)

        no = ensaio_na_fechada(receita(pesquisa('modelo' => { 'nome' => 'retomar' }), esperar_passo('seguinte'))).first
        expect(no).to include(id: 'nota', faria: 'pesquisa_nota')
        expect(no[:dados]).to include(pergunta: 'De 0 a 10?', modelo: 'retomar')
        expect(no[:ramos]).to be_present
      end

      it 'a pesquisa recente pula e segue antes de olhar a janela, como no motor' do
        contato.update!(additional_attributes: { 'pesquisa_perguntada_em' => 1.day.ago.iso8601 })

        lido = ensaio_na_fechada(receita(pesquisa, esperar_passo('seguinte')))
        expect(lido.pluck(:id, :faria)).to eq([%w[nota pesquisa_recente], %w[seguinte esperar]])
      end

      it 'a reunião sem horário livre segue por "Se pedir outro horário" antes de olhar a janela, como no motor', :aggregate_failures do
        agenda = instance_double(Autonomia::Automacao::AgendaDaReuniao, pagina: true, horarios: [])
        allow(Autonomia::Automacao::AgendaDaReuniao).to receive(:new).and_return(agenda)

        no = ensaio_na_fechada(receita(reuniao)).first
        expect(no).to include(id: 'reuniao', faria: 'sem_horario')
        expect(no[:ramos].pluck(:chave)).to eq(%w[outro_horario])
        expect(no[:ramos].first[:passos].first).to include(id: 'outro')
      end
    end
  end
end
