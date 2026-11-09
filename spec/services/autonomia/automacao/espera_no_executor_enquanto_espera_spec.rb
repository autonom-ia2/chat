require 'rails_helper'

# O que o "esperar até" faz enquanto espera (G63 #2830, G64 #2839; exemplo 17, passos 4 e 5): o galho "a cada mensagem
# do cliente", que roda e volta à mesma espera, e a conferência numa hora marcada da manhã, no fuso da conta.
RSpec.describe Autonomia::Automacao::EsperaNoExecutor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:account) { create(:account, reporting_timezone: fuso.name) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:fernanda) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, status: :open, assignee: fernanda) }
  let(:urgente) { { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' } }
  let(:galho) { [etiqueta_passo('galho', 'atendido')] }
  let(:espera) do
    { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => 'sem_prazo', 'conferir_as' => 8,
      'a_cada_mensagem' => galho }
  end
  let(:definicao) { automacao_ligada(account, admin, [espera, prioridade_passo('depois', 'low')]) }

  before do
    ligar_motor(account)
    conversa.inbox.add_members([fernanda.id])
    create(:label, account: account, title: 'atendido')
  end

  after { Current.reset }

  def etiqueta_passo(id, etiqueta)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'PATCH conversations/:conversation_id/labels/alterar', 'descricao' => 'Etiquetar',
      'caminho' => { 'conversation_id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'por' => [etiqueta] } }
  end

  def comecar_e_rodar = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
  def execucao = Autonomia::Automacao::Execucao.find_by!(automacao: definicao)
  def registros = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id)
  def linhas = registros.pluck(:passo, :resultado, :motivo)
  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  # A mensagem chega pelo caminho de verdade: o listener, a Escuta e o AvancarJob.
  def escreve(tipo = :incoming, **atributos)
    remetente = tipo == :incoming ? conversa.contact : fernanda
    mensagem = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: tipo,
                                sender: remetente, content: 'Oi', **atributos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
  end

  def voltas = registros.where(passo: 'espera', motivo: 'mensagem_do_cliente').count

  # A versão salva não muda (readonly); o spec troca a receita por baixo para ler o passo de outro jeito.
  def trocar_receita(versao, receita)
    Autonomia::Automacao::Versao.where(id: versao.id).update_all(receita: receita) # rubocop:disable Rails/SkipsModelValidations
  end

  describe 'a conferência marcada (G64)' do
    it 'entra esperando até as próximas 8h no fuso da conta, com a hora no registro', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 15)) { comecar_e_rodar }

      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera', due_at: fuso.local(2026, 11, 10, 8))
      expect(registros.sole.dados).to include('sem_prazo' => true, 'conferir_as' => 8)
      expect(registros.sole.dados['marco']).to include('lido_ate')
    end

    it 'antes das 8h, a próxima é a de hoje' do
      travel_to(fuso.local(2026, 11, 9, 6, 30)) { comecar_e_rodar }

      expect(execucao.due_at).to eq(fuso.local(2026, 11, 9, 8))
    end

    it 'a condição cumprida antes da hora não segue: a mudança e a mensagem da equipe não conferem; às 8h confere', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 15)) { comecar_e_rodar }
      travel_to(fuso.local(2026, 11, 9, 16)) do
        conversa.update!(priority: :urgent)
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::Despertador.acordar(execucao) }
        escreve(:outgoing)
      end
      expect(execucao).to have_attributes(estado: 'esperando', due_at: fuso.local(2026, 11, 10, 8))
      expect(linhas).to eq([['espera', 'ok', nil]])

      travel_to(fuso.local(2026, 11, 10, 7, 59)) { varrer }
      expect(execucao.estado).to eq('esperando')

      travel_to(fuso.local(2026, 11, 10, 8, 1)) { varrer }
      expect(execucao.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'na conferência sem a condição, volta a esperar o dia seguinte, sem registro novo', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 15)) { comecar_e_rodar }

      travel_to(fuso.local(2026, 11, 10, 8, 1)) { varrer }

      expect(execucao).to have_attributes(estado: 'esperando', due_at: fuso.local(2026, 11, 11, 8))
      expect(linhas).to eq([['espera', 'ok', nil]])
    end

    it 'o card que muda não acorda a espera com hora marcada (EsperaDoCard)' do
      le_o_card = espera.merge('condicao' => { 'campo' => { '$valor' => 'card.atributos.x' }, 'op' => 'preenchido' })
      versao = definicao.versao_ativa
      base = versao.receita
      gravar = ->(passo) { trocar_receita(versao, base.merge('passos' => [passo])) }
      esperando = create(:autonomia_automacao_execucao, versao: versao, alvo: conversa, estado: 'esperando', cursor: 'espera',
                                                        due_at: 1.hour.from_now)

      gravar.call(le_o_card)
      expect(Autonomia::Automacao::EsperaDoCard.le_o_card?(esperando.reload)).to be(false)
      gravar.call(le_o_card.except('conferir_as'))
      expect(Autonomia::Automacao::EsperaDoCard.le_o_card?(esperando.reload)).to be(true)
    end

    context 'with horário de verão' do
      let(:fuso) { ActiveSupport::TimeZone['America/New_York'] }

      it 'a conferência cai às 8h locais na entrada e na saída do horário de verão', :aggregate_failures do
        travel_to(fuso.local(2026, 3, 7, 15)) { comecar_e_rodar }
        expect(execucao.due_at).to eq(fuso.local(2026, 3, 8, 8))
        expect(execucao.due_at.utc.hour).to eq(12)

        travel_to(fuso.local(2026, 10, 31, 15)) { varrer }
        expect(execucao.due_at).to eq(fuso.local(2026, 11, 1, 8))
        expect(execucao.due_at.utc.hour).to eq(13)
      end

      # A hora que não existe (2h na entrada do horário de verão) avança 1 h: a decisão é aceitar, e a conferência do
      # dia não some (Tempo.na_hora).
      it 'conferir_as 2 em 08/03/2026 cai às 3h locais', :aggregate_failures do
        conferencia = Autonomia::Automacao::Tempo.proxima_hora(account, 2, fuso.local(2026, 3, 8, 0, 30))

        expect(conferencia.in_time_zone(fuso).strftime('%Y-%m-%d %H:%M')).to eq('2026-03-08 03:00')
        expect(conferencia.utc.hour).to eq(7)
      end
    end
  end

  describe 'a cada mensagem do cliente (G63)' do
    before { travel_to(fuso.local(2026, 11, 9, 10)) { comecar_e_rodar } }

    it 'a mensagem do cliente roda o galho e volta a esperar, com a mesma conferência marcada', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 11)) { escreve }

      expect(conversa.reload.label_list).to include('atendido')
      expect(linhas).to eq([['espera', 'ok', nil], %w[espera ok mensagem_do_cliente], ['galho', 'ok', nil], %w[espera ok voltou_a_esperar]])
      expect(registros.find_by(motivo: 'mensagem_do_cliente').dados['vez']).to eq(1)
      expect(registros.find_by(motivo: 'voltou_a_esperar').dados).to include('volta' => 1, 'sem_prazo' => true, 'conferir_as' => 8)
      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera', due_at: fuso.local(2026, 11, 10, 8))
    end

    it 'a mensagem da equipe e a nota não rodam o galho' do
      travel_to(fuso.local(2026, 11, 9, 11)) do
        escreve(:outgoing)
        escreve(:outgoing, private: true)
      end

      expect(voltas).to eq(0)
    end

    it 'uma rajada de mensagens antes de a rodada andar vira uma volta só', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 11)) do
        3.times do
          create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, sender: conversa.contact)
        end
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::Despertador.acordar(execucao) }
      end

      expect(voltas).to eq(1)
      expect(execucao.estado).to eq('esperando')
    end

    it 'cada mensagem depois da volta roda o galho de novo, contando a vez' do
      [11, 12, 13].each { |hora| travel_to(fuso.local(2026, 11, 9, hora)) { escreve } }

      expect(registros.where(motivo: 'mensagem_do_cliente').map { |registro| registro.dados['vez'] }).to eq([1, 2, 3])
    end

    it 'na volta do galho, confere a condição fora da hora marcada: o cliente que escreve não atrasa a saída', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 11)) do
        conversa.update!(priority: :urgent)
        escreve
      end

      expect(execucao.estado).to eq('concluida')
      expect(linhas.last(2)).to eq([['espera', 'ok', nil], ['depois', 'ok', nil]])
    end

    # A mensagem que chega entre o fim do último passo do galho e a espera gravada: o marco da volta é lido antes de
    # conferir a condição, então ela fica depois dele, a reconferência a vê e ela abre a próxima volta.
    it 'a mensagem que chega depois do fim do galho, antes de a espera ser gravada, abre a próxima volta', :aggregate_failures do
      chegou = false
      allow(Autonomia::Automacao::Condicao).to receive(:new).and_wrap_original do |original, *argumentos|
        if !chegou && voltas == 1
          chegou = true
          create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming,
                           sender: conversa.contact, content: 'Mais uma coisa')
        end
        original.call(*argumentos)
      end

      travel_to(fuso.local(2026, 11, 9, 11)) { escreve }

      expect(chegou).to be(true)
      expect(voltas).to eq(2)
      expect(registros.where(motivo: 'mensagem_do_cliente').map { |registro| registro.dados['vez'] }).to eq([1, 2])
      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera', due_at: fuso.local(2026, 11, 10, 8))
    end

    it 'passado o teto, registra uma vez e segue esperando só pela condição', :aggregate_failures do
      stub_const('Autonomia::Automacao::EnquantoEspera::A_CADA_TETO', 2)

      [11, 12, 13, 14].each { |hora| travel_to(fuso.local(2026, 11, 9, hora)) { escreve } }

      expect(voltas).to eq(2)
      expect(linhas.count { |linha| linha == %w[espera pulado teto_a_cada] }).to eq(1)
      expect(execucao).to have_attributes(estado: 'esperando', due_at: fuso.local(2026, 11, 10, 8))

      conversa.update!(priority: :urgent)
      travel_to(fuso.local(2026, 11, 10, 8, 1)) { varrer }
      expect(execucao.estado).to eq('concluida')
    end
  end

  # Decisão 11 do Rodrigo (09/11): uma espera só. A mensagem que chega enquanto o galho espera a equipe entra no
  # atendimento em curso: não abre outra rodada nem recomeça o prazo de 2 h.
  describe 'o galho que espera a equipe' do
    let(:respondeu) { { 'campo' => { '$valor' => 'conversa.responsavel_respondeu' }, 'op' => 'igual', 'valor' => true } }
    let(:galho) do
      [{ 'id' => 'espera_a_fernanda', 'tipo' => 'esperar_ate', 'condicao' => respondeu, 'prazo' => { 'valor' => 2, 'unidade' => 'horas' },
         'se_vencer' => [etiqueta_passo('sem_resposta', 'atendido')] }]
    end

    before { travel_to(fuso.local(2026, 11, 9, 10)) { comecar_e_rodar } }

    it 'a Fernanda responde em 1 h: o galho acaba sem o "se vencer" e volta a esperar', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 11)) { escreve }
      expect(execucao.cursor).to eq('espera_a_fernanda')

      travel_to(fuso.local(2026, 11, 9, 12)) { escreve(:outgoing) }

      expect(conversa.reload.label_list).not_to include('atendido')
      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera', due_at: fuso.local(2026, 11, 10, 8))
    end

    it 'o cliente escreve de novo durante as 2 h: uma volta só, e o prazo não recomeça', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 11)) { escreve }
      travel_to(fuso.local(2026, 11, 9, 12)) { escreve }
      expect(execucao.due_at).to eq(fuso.local(2026, 11, 9, 13))

      travel_to(fuso.local(2026, 11, 9, 13, 1)) { varrer }

      expect(conversa.reload.label_list).to include('atendido')
      expect(voltas).to eq(1)
      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera')

      travel_to(fuso.local(2026, 11, 9, 14)) { escreve }
      expect(voltas).to eq(2)
    end
  end

  describe 'com prazo de duração' do
    let(:espera) do
      { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => { 'valor' => 3, 'unidade' => 'dias' },
        'a_cada_mensagem' => galho, 'se_vencer' => [prioridade_passo('venceu', 'high')] }
    end

    it 'o galho não recomeça o prazo; vencido, segue pelo "se vencer"', :aggregate_failures do
      travel_to(fuso.local(2026, 11, 9, 10)) { comecar_e_rodar }
      prazo = execucao.due_at

      travel_to(fuso.local(2026, 11, 11, 10)) { escreve }
      expect(execucao).to have_attributes(estado: 'esperando', due_at: prazo)

      travel_to(prazo + 1.minute) { varrer }
      expect(linhas).to include(%w[espera pulado prazo_vencido], ['venceu', 'ok', nil])
      expect(execucao.estado).to eq('concluida')
    end
  end

  describe 'sem hora marcada' do
    let(:espera) { { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => 'sem_prazo', 'a_cada_mensagem' => galho } }

    it 'a espera sem prazo segue conferindo a cada mudança, como antes, e o galho roda', :aggregate_failures do
      comecar_e_rodar
      expect(execucao.due_at).to be_within(1.minute).of(1.day.from_now)

      escreve
      expect(voltas).to eq(1)

      conversa.update!(priority: :urgent)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::Despertador.acordar(execucao) }
      expect(execucao.estado).to eq('concluida')
    end
  end

  describe 'Tempo.proxima_hora' do
    it 'é a hora cheia que vem, no fuso da conta', :aggregate_failures do
      expect(Autonomia::Automacao::Tempo.proxima_hora(account, 8, fuso.local(2026, 11, 9, 7, 59))).to eq(fuso.local(2026, 11, 9, 8))
      expect(Autonomia::Automacao::Tempo.proxima_hora(account, 8, fuso.local(2026, 11, 9, 8))).to eq(fuso.local(2026, 11, 10, 8))
      expect(Autonomia::Automacao::Tempo.proxima_hora(account, 0, fuso.local(2026, 11, 9, 23, 30))).to eq(fuso.local(2026, 11, 10, 0))
    end
  end
end
