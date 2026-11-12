require 'rails_helper'

# G71 (#2883, decisão 20 do Rodrigo, 10/11): o "extrair" que grava no card da conversa espera a IA de assunto decidir,
# com teto, antes de marcar os campos como ausentes. Sem a IA de assunto ligada na caixa, nada muda.
RSpec.describe Autonomia::Automacao::EsperaDoAssunto, :automacao_motor do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  # O que a IA devolve (o dublê) só existe aqui: o que chega ao card só pode ter vindo da resposta dela, pelo passo.
  let(:peca_da_ia) { 'blusa listrada 4417' }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Vanessa') }
  let(:contato) { create(:contact, account: account, name: 'Ana', phone_number: '+5511999990071') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let!(:mensagem) { create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Quero a blusa no P') }
  let(:extrair) do
    { 'id' => 'p1', 'tipo' => 'extrair', 'le' => %w[mensagens_recentes],
      'campos' => [{ 'chave' => 'peca', 'descricao' => 'a peça', 'destino' => 'card.atributos.peca' }] }
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:custom_attribute_definition, account: account, attribute_key: 'peca', attribute_model: 'card_attribute', attribute_display_type: 'text')
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'r1', output_text: { 'peca' => peca_da_ia }.to_json, usage: { input_tokens: 10, output_tokens: 5 } }.to_json
    )
    Redis::Alfred.delete(Crm::Subjects::Marco.chave(conversa.id))
  end

  after { Current.reset }

  def ligar_a_ia_de_assunto(modo = :auto)
    account.crm_inbox_settings.create!(inbox: conversa.inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: modo)
  end

  def rodar(definicao, alvo = conversa, chave_gatilho = 'mensagem.criada')
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: chave_gatilho).call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last
  end

  # A IA de assunto abre o card do pedido na conversa (o card que ela cria é o assunto atual).
  def ia_de_assunto_abre_o_card
    Crm::Cards::Creator.new(account: account, user: admin, params: { pipeline_id: funil.first.id, stage_id: funil.last.id,
                                                                     contact_id: contato.id, conversation_id: conversa.id,
                                                                     title: 'Pedido da Ana' }).perform
  end

  # O fim do IdentifyJob: o marco e o aviso da decisão, que o assinante do config/initializers leva ao EsperaDoAssunto.
  def ia_de_assunto_decide
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Crm::Subjects::Marco.gravar(conversa.id, mensagem.id)
      ActiveSupport::Notifications.instrument(Crm::Subjects::IdentifyJob::EVENTO, conversation_id: conversa.id, message_id: mensagem.id,
                                                                                  estado: 'applied')
    end
  end

  def registro(execucao) = Autonomia::Automacao::Registro.find_by(execucao: execucao, passo: 'p1')

  it 'com a IA de assunto ligada, o extrair espera a decisão e grava no card que ela abriu', :aggregate_failures do
    ligar_a_ia_de_assunto
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = rodar(definicao)

    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'p1')
    expect(execucao.due_at).to be_within(1.second).of(mensagem.created_at + described_class::TETO)
    expect(registro(execucao)).to be_nil
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made

    card = ia_de_assunto_abre_o_card
    ia_de_assunto_decide

    expect(card.reload.custom_attributes).to include('peca' => peca_da_ia)
    expect(registro(execucao)).to have_attributes(resultado: 'ok')
    expect(registro(execucao).dados['campos']).to include('gravados' => %w[peca], 'ausentes' => [])
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'passado o teto sem decisão, segue como hoje: sem card, o campo fica ausente', :aggregate_failures do
    ligar_a_ia_de_assunto
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'mensagem.criada' })
    execucao = rodar(definicao)

    travel_to(mensagem.created_at + described_class::TETO + 1.second) { varrer }

    expect(registro(execucao)).to have_attributes(resultado: 'pulado', motivo: 'dado_ausente')
    expect(registro(execucao).dados['campos']).to include('ausentes' => %w[peca])
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
  end

  it 'com a IA de assunto desligada na caixa, não espera: sem card, o campo fica ausente na hora', :aggregate_failures do
    ligar_a_ia_de_assunto(:off)
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = rodar(definicao)

    expect(execucao.estado).to eq('concluida')
    expect(registro(execucao)).to have_attributes(resultado: 'pulado', motivo: 'dado_ausente')
  end

  it 'com o assunto já decidido para a última mensagem, não espera', :aggregate_failures do
    ligar_a_ia_de_assunto
    card = ia_de_assunto_abre_o_card
    Crm::Subjects::Marco.gravar(conversa.id, mensagem.id)
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = rodar(definicao)

    expect(execucao.estado).to eq('concluida')
    expect(card.reload.custom_attributes).to include('peca' => peca_da_ia)
  end

  it 'no gatilho de card, o card é o alvo: não espera a IA de assunto', :aggregate_failures do
    ligar_a_ia_de_assunto
    card = ia_de_assunto_abre_o_card
    definicao = automacao_ligada(account, admin, [extrair], gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil.first.id })

    execucao = rodar(definicao, card, 'card.ganho')

    expect(execucao.estado).to eq('concluida')
    expect(card.reload.custom_attributes).to include('peca' => peca_da_ia)
  end

  it 'o aviso da decisão só acorda a execução que espera no extrair', :aggregate_failures do
    ligar_a_ia_de_assunto
    definicao = automacao_ligada(account, admin, [esperar_passo('e1')], gatilho: { 'tipo' => 'mensagem.criada' })
    execucao = rodar(definicao)
    expect(execucao).to have_attributes(estado: 'esperando', cursor: 'e1')

    expect { described_class.decidido(conversa.id) }.not_to have_enqueued_job(Autonomia::Automacao::AvancarJob)
    expect(execucao.reload).to have_attributes(estado: 'esperando', travada_em: nil)
  end
end
