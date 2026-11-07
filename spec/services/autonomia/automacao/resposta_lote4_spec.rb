require 'rails_helper'

# Lote 4 da Automação livre (#2682), o "esperar até" que espera:
# - a pessoa responsável responder (ex. 10, passo 6: a Fernanda; ex. 15, passo 7: o Carlos), não qualquer pessoa da equipe;
# - o gatilho acontecer de novo (ex. 4, passos 1 e 10: a 2ª falta dentro dos 30 dias);
# - o card mudar (ex. 12, passo 3: o corretor preenche o campo, e a espera vê na hora, não no fim das 24 h).
RSpec.describe Autonomia::Automacao::Resposta, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:fernanda) { create(:user, account: account, role: :agent) }
  let(:rafael) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, status: :open, assignee: fernanda) }

  before do
    ligar_motor(account)
    conversa.inbox.add_members([fernanda.id, rafael.id])
  end

  after { Current.reset }

  def condicao(caminho, operador: 'igual', valor: true) = { 'campo' => { '$valor' => caminho }, 'op' => operador, 'valor' => valor }

  def esperar_ate(condicao, prazo = 30, unidade = 'minutos')
    { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => condicao, 'prazo' => { 'valor' => prazo, 'unidade' => unidade },
      'se_vencer' => [prioridade_passo('venceu', 'high'), { 'id' => 'fim', 'tipo' => 'parar' }] }
  end

  def rodar(definicao, alvo = conversa)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, alvo) }
  end

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  def escreve(**atributos)
    mensagem = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, **atributos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
  end

  def execucao_de(definicao) = Autonomia::Automacao::Execucao.find_by!(automacao: definicao)

  describe 'até a pessoa responsável responder' do
    let(:definicao) do
      automacao_ligada(account, admin, [esperar_ate(condicao('conversa.responsavel_respondeu')), prioridade_passo('respondeu', 'low')])
    end

    it 'outra pessoa da equipe responde: continua esperando a responsável', :aggregate_failures do
      rodar(definicao)

      travel(5.minutes) { escreve(message_type: :outgoing, sender: rafael) }

      expect(execucao_de(definicao).estado).to eq('esperando')
      expect(conversa.reload.priority).to be_nil
    end

    it 'a responsável responde: segue na hora', :aggregate_failures do
      rodar(definicao)

      travel(5.minutes) { escreve(message_type: :outgoing, sender: fernanda) }

      expect(execucao_de(definicao).estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'não contam a nota da responsável, o eco do celular e a mensagem que falhou', :aggregate_failures do
      rodar(definicao)

      travel(5.minutes) do
        escreve(message_type: :outgoing, sender: fernanda, private: true)
        escreve(message_type: :outgoing, sender: fernanda, status: :failed)
        escreve(message_type: :outgoing, sender: nil, content_attributes: { 'external_echo' => true }, source_id: 'wamid.celular')
      end

      expect(execucao_de(definicao).estado).to eq('esperando')
    end

    it 'a conversa passa para outra pessoa: vale a resposta de quem está com ela agora', :aggregate_failures do
      rodar(definicao)
      conversa.update!(assignee: rafael)

      travel(5.minutes) { escreve(message_type: :outgoing, sender: rafael) }

      expect(execucao_de(definicao).estado).to eq('concluida')
    end

    it 'sem ninguém atribuído, ninguém é a responsável: segue pelo "se vencer"', :aggregate_failures do
      conversa.update!(assignee: nil)
      rodar(definicao)

      travel(5.minutes) { escreve(message_type: :outgoing, sender: rafael) }
      travel(31.minutes) { varrer }

      expect(conversa.reload.priority).to eq('high')
    end
  end

  describe 'até o gatilho acontecer de novo' do
    let(:definicao) do
      automacao_ligada(account, admin, [esperar_ate(condicao('gatilho.repetiu'), 30, 'dias'), prioridade_passo('repetiu', 'low')])
    end

    it 'o gatilho acontece de novo durante a espera: segue na hora, e o histórico fica com uma linha', :aggregate_failures do
      rodar(definicao)
      execucao = execucao_de(definicao)

      travel(3.days) { rodar(definicao) }
      travel(4.days) { rodar(definicao) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
      expect(Autonomia::Automacao::Registro.where(execucao: execucao, motivo: 'ja_aberta').count).to eq(1)
    end

    it 'sem repetição no prazo: segue pelo "se vencer"' do
      rodar(definicao)

      travel(30.days + 1.minute) { varrer }

      expect(conversa.reload.priority).to eq('high')
    end

    it 'a repetição de antes da espera não conta', :aggregate_failures do
      passos = [esperar_passo('antes', 1, 'horas'), esperar_ate(condicao('gatilho.repetiu'), 30, 'dias'), prioridade_passo('repetiu', 'low')]
      antes = automacao_ligada(account, admin, passos)
      rodar(antes)

      travel(10.minutes) { rodar(antes) }
      travel(61.minutes) { varrer }

      expect(execucao_de(antes).reload.estado).to eq('esperando')
      expect(conversa.reload.priority).to be_nil
    end

    it 'no ensaio, sem execução, o gatilho nunca repetiu' do
      valores = Autonomia::Automacao::Valores.new(alvo: conversa, quem: nil, espera: (1.hour.ago..))

      expect(valores.ler('gatilho.repetiu')).to be(false)
    end
  end

  describe 'o card mudou' do
    around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

    let(:funil) { create_crm_pipeline(account: account, user: admin) }
    let(:card) do
      Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Apartamento Jardim', currency: 'BRL',
                        primary_conversation: conversa, contact: conversa.contact)
    end
    let(:definicao) do
      passos = [esperar_ate(condicao('card.atributos.impressao', valor: 'gostou'), 24, 'horas'), prioridade_passo('preenchido', 'low')]
      automacao_ligada(account, admin, passos, gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => funil.last.id })
    end

    def rodar_no_card
      partida = Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.entrou_na_etapa')
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { partida.call }
    end

    before do
      account.enable_features!('automacao_gatilhos')
      create(:custom_attribute_definition, account: account, attribute_model: 'card_attribute', attribute_key: 'impressao',
                                           attribute_display_type: 'text')
    end

    it 'o corretor preenche o campo: a espera vê na hora, sem esperar as 24 h', :aggregate_failures do
      rodar_no_card
      expect(execucao_de(definicao).estado).to eq('esperando')

      travel(2.hours) do
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { card.update!(custom_attributes: { 'impressao' => 'gostou' }) }
      end

      expect(execucao_de(definicao).estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'mudança que a receita não lê (a nota de qualificação) não acorda a espera' do
      rodar_no_card

      expect { card.update!(score: 40) }.not_to have_enqueued_job(Autonomia::Automacao::AvancarJob)
    end

    it 'sem execução esperando no card, a mudança só faz a consulta pelo alvo: nem lê a flag' do
      allow(Autonomia::Automacao::Motor).to receive(:ligado?).and_call_original

      card.update!(custom_attributes: { 'impressao' => 'gostou' })

      expect(Autonomia::Automacao::Motor).not_to have_received(:ligado?)
    end

    it 'a mudança no card não acorda quem espera em outro card' do
      rodar_no_card
      outro = Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Outro', currency: 'BRL')

      expect { outro.update!(custom_attributes: { 'impressao' => 'x' }) }.not_to have_enqueued_job(Autonomia::Automacao::AvancarJob)
    end
  end
end
