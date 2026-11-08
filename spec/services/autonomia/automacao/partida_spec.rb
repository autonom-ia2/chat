require 'rails_helper'

# A automação começando para um alvo (#2414 F3): o que barra, o que pula e o que pausa.
RSpec.describe Autonomia::Automacao::Partida, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:definicao) { automacao_ligada(account, admin, [esperar_passo('p1')]) }

  before { ligar_motor(account) }

  it 'abre a execução reservada, na cadeia da automação, e enfileira a primeira rodada', :aggregate_failures do
    execucao = comecar(definicao, conversa)

    expect(execucao).to have_attributes(estado: 'andando', cadeia: ["automacao:#{definicao.id}"], profundidade: 1,
                                        versao: definicao.versao_ativa, chave_gatilho: 'conversa.resolvida')
    expect(execucao.travada_em).to be_present
    expect(Autonomia::Automacao::AvancarJob).to have_been_enqueued.with(execucao.id, execucao.travada_em.iso8601(6), kind_of(String))
  end

  it 'não abre outra enquanto houver uma aberta para a mesma automação, alvo e gatilho (F2.5)' do
    comecar(definicao, conversa)

    expect { expect(comecar(definicao, conversa)).to be_nil }.not_to change(Autonomia::Automacao::Execucao, :count)
  end

  # O revisor do #2554: o gatilho que acontece de novo com a execução aberta aparece no histórico dela, uma vez só.
  it 'o gatilho de novo com a execução aberta fica no histórico dela, uma linha só', :aggregate_failures do
    execucao = comecar(definicao, conversa)
    2.times { comecar(definicao, conversa) }

    pulos = Autonomia::Automacao::Registro.where(execucao: execucao, resultado: 'pulado', motivo: 'ja_aberta')
    expect(pulos.count).to eq(1)
    expect(I18n.t("autonomia.automacao.motivos.#{pulos.sole.motivo}", locale: :pt_BR)).to include('já estava rodando')
  end

  it 'não começa sem o motor, com a automação desligada ou para alvo de outra conta', :aggregate_failures do
    outra = create(:conversation)
    expect(comecar(definicao, outra)).to be_nil

    definicao.update!(ativa: false)
    expect(comecar(definicao, conversa)).to be_nil

    definicao.update!(ativa: true)
    account.disable_features!('automacao_motor')
    expect(comecar(definicao.reload, conversa)).to be_nil
    expect(Autonomia::Automacao::Execucao.count).to eq(0)
  end

  it 'pula o alvo fora do filtro do gatilho' do
    filtro = { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' }
    filtrada = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'conversa.resolvida', 'filtros' => [filtro] })

    expect(comecar(filtrada, conversa)).to be_nil
    conversa.update!(priority: :urgent)
    expect(comecar(filtrada, conversa)).to be_present
  end

  it 'respeita a cadeia comum: a automação não dispara a si mesma (D6)' do
    resultado = Autonomia::Automacao::Cadeia.com("automacao:#{definicao.id}", account.id) { comecar(definicao, conversa) }

    expect([resultado, Autonomia::Automacao::Execucao.count]).to eq([nil, 0])
  end

  describe 'quem ligou' do
    let(:agente) { create(:user, account: account, role: :agent) }
    let(:funcao) { create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage]) }
    let(:do_agente) { automacao_ligada(account, admin, [esperar_passo('p1')]).tap { |definicao| definicao.update!(ligada_por: agente) } }

    it 'agente sem a chave de automações: pausa, e o porquê fica numa execução parada', :aggregate_failures do
      expect(comecar(do_agente, conversa)).to be_nil

      expect(do_agente.reload.ativa).to be(false)
      execucao = Autonomia::Automacao::Execucao.find_by!(automacao: do_agente)
      expect(execucao.estado).to eq('parada')
      expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao)).to have_attributes(passo: 'inicio', motivo: 'quem_ligou_sem_permissao')
    end

    it 'agente com a chave, fora da caixa: pula a conversa sem pausar (D5)', :aggregate_failures do
      account.account_users.find_by(user: agente).update!(custom_role: funcao)

      expect(comecar(do_agente, conversa)).to be_nil
      expect(do_agente.reload.ativa).to be(true)

      create(:inbox_member, user: agente, inbox: conversa.inbox)
      expect(comecar(do_agente, conversa)).to be_present
    end

    it 'sem quem ligou (usuário apagado): pausa, sem trocar de pessoa' do
      definicao.update!(ligada_por: nil)

      expect(comecar(definicao, conversa)).to be_nil
      expect([definicao.reload.ativa, definicao.ligada_por]).to eq([false, nil])
    end
  end
end
