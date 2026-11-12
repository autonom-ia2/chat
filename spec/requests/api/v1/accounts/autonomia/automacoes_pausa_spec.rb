require 'rails_helper'

# #2572 (F3.7): a automação que o motor pausou porque quem ligou perdeu o acesso aparece pausada, com o motivo, no
# editor e na lista. A desligada à mão, a que voltou a ser ligada e a pausa de antes do último ligar não aparecem.
RSpec.describe 'Api::V1::Accounts::Autonomia::Automacoes pausada', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:quem_ligou) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:passos) { [{ 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }] }
  let(:definicao) { automacao_ligada(account, quem_ligou, passos) }
  let(:frase) { I18n.t('autonomia.automacao.motivos.quem_ligou_saiu_da_conta') }

  before do
    account.enable_features!('automacao_editor')
    ligar_motor(account)
  end

  def pausar_pelo_motor
    definicao
    AccountUser.find_by(account: account, user: quem_ligou).destroy!
    comecar(definicao.reload, conversa)
    definicao.reload
  end

  def da_lista = response.parsed_body['automacoes'].find { |item| item['id'] == definicao.id }

  it 'mostra a pausa e o motivo no editor e na lista', :aggregate_failures do
    pausar_pelo_motor
    expect(definicao.ativa).to be(false)

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['pausa']).to eq('motivo' => 'quem_ligou_saiu_da_conta', 'frase' => frase)

    get base, headers: admin.create_new_auth_token, as: :json
    expect(da_lista['pausa']).to eq('motivo' => 'quem_ligou_saiu_da_conta', 'frase' => frase)
  end

  # Revisão do #2572: a pausa do Executor no meio da rodada (a ação negada depois que a Partida deixou começar) aparece
  # como a da Partida, sem depender de o motivo estar numa lista.
  it 'mostra a pausa do Executor no meio da rodada', :aggregate_failures do
    funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage])
    agente = create(:user, account: account, role: :agent)
    account.account_users.find_by(user: agente).update!(custom_role: funcao)
    create(:inbox_member, user: agente, inbox: conversa.inbox)
    criar = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST labels', 'descricao' => 'Criar a etiqueta',
              'corpo' => { 'title' => 'renovacao', 'description' => 'Cliente em renovação' } }
    pela_acao = automacao_ligada(account, agente, [criar])

    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(pela_acao, conversa) }
    expect(pela_acao.reload.ativa).to be(false)

    get "#{base}/#{pela_acao.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['pausa']).to eq('motivo' => 'quem_ligou_sem_acesso',
                                                'frase' => I18n.t('autonomia.automacao.motivos.quem_ligou_sem_acesso'))
  end

  it 'mostra a pausa do passo de Prospecção, com a frase dela' do
    definicao.update!(ativa: false)
    execucao = Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa,
                                                      alvo: conversa, chave_gatilho: 'conversa.resolvida', estado: 'parada')
    Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'p1', resultado: 'falhou',
                                           motivo: 'quem_ligou_sem_permissao_prospeccao',
                                           dados: { Autonomia::Automacao::Registro::PAUSOU => true })

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['pausa']).to eq('motivo' => 'quem_ligou_sem_permissao_prospeccao',
                                                'frase' => I18n.t('autonomia.automacao.motivos.quem_ligou_sem_permissao_prospeccao'))
  end

  it 'não mostra pausa na desligada à mão' do
    definicao.desligar!

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['pausa']).to be_nil
  end

  it 'esquece a pausa de antes do último ligar', :aggregate_failures do
    pausar_pelo_motor
    travel 1.minute do
      post "#{base}/#{definicao.id}/ligar", params: { versao_id: definicao.versao_ativa_id }, headers: admin.create_new_auth_token,
                                            as: :json
      expect(response.parsed_body['ativa']).to be(true)
      expect(response.parsed_body['pausa']).to be_nil

      definicao.reload.desligar!
      get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['pausa']).to be_nil
    end
  end
end
