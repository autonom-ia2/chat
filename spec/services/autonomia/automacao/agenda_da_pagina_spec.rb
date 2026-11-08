require 'rails_helper'

# G44 (#2756, exemplo 20 passos 5 e 8): o link da agenda de uma página escolhida na receita, `agenda.<id da página>`.
# Parecer da Funções: a página é achada pelo escopo da conta (páginas novas usáveis) ao salvar e ao rodar; quem salva, e
# quem ligou ao rodar, precisa de agendamento_view; a página fixa dá o link dela, com o responsável ainda elegível; a
# página por pessoa dá só o link próprio do responsável do alvo, nunca o de outra pessoa.
RSpec.describe Autonomia::Automacao::AgendaDaPagina, :automacao_motor do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:world) { build_booking_world(account: account) }
  let(:card) { world.card }
  let(:treinamento) { create_booking_profile(account: account, host: world.host, title: 'Treinamento') }
  let(:caminho) { "agenda.#{treinamento.id}" }
  let(:url) { Crm::BookingV2::ShortLink.url_for(treinamento) }

  def na_conta(usuario) = account.account_users.find_by(user: usuario)

  def pagina_de_outra_conta
    outra = create(:account)
    create_booking_profile(account: outra, host: create(:user, account: outra, role: :administrator), title: 'De fora')
  end

  def ler(alvo, quem, lido = caminho) = Autonomia::Automacao::Valores.new(alvo: alvo, quem: quem).ler(lido)

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features!('crm_booking_v2')
    world
  end

  describe 'o caminho' do
    it 'só agenda. seguido do id em número', :aggregate_failures do
      expect(described_class.pagina_id('agenda.12')).to eq(12)
      ['agenda.', 'agenda.abc', 'agenda.12x', 'agenda.-3', 'agenda.0', 'agenda. 12', 'card.12'].each do |outro|
        expect(described_class.pagina_id(outro)).to be_nil
      end
    end

    it 'é um valor que a receita sabe ler, em qualquer alvo', :aggregate_failures do
      valores = Autonomia::Automacao::Valores
      expect(valores.caminho_valido?(caminho)).to be(true)
      expect(valores.caminho_valido?('agenda.abc')).to be(false)
      %w[Conversation Crm::Card Contact].each { |alvo| expect(valores.no_alvo?(caminho, alvo)).to be(true) }
    end
  end

  describe 'ao rodar' do
    it 'página fixa: o link da própria página, em card, conversa e contato', :aggregate_failures do
      conversa = create(:conversation, account: account, contact: world.contact)

      expect(ler(card, admin)).to eq(url)
      expect(ler(conversa, admin)).to eq(url)
      expect(ler(world.contact, admin)).to eq(url)
    end

    it 'página fixa com o responsável fora da conta: vazio por sem_pagina' do
      colega = create(:user, account: account, role: :agent)
      treinamento.update!(default_assignee: colega)
      AccountUser.find_by(account: account, user: colega).destroy!

      expect(described_class.resultado(caminho, contexto: Autonomia::Automacao::Contexto.de(card), account_user: na_conta(admin)).to_h)
        .to eq(url: nil, por: 'sem_pagina')
    end

    it 'página por pessoa: o link próprio do dono do card; sem link dele, vazio; nunca o de outra pessoa', :aggregate_failures do
      colega = create(:user, account: account, role: :agent)
      treinamento.update!(assignment_mode: :per_agent)
      account.crm_agent_booking_links.create!(booking_profile: treinamento, agent: colega, slug: SecureRandom.uuid)
      expect(ler(card, admin)).to be_nil

      proprio = account.crm_agent_booking_links.create!(booking_profile: treinamento, agent: card.owner, slug: SecureRandom.uuid)
      expect(ler(card, admin)).to eq(Crm::BookingV2::ShortLink.url_for(treinamento, link: proprio))
    end

    it 'página por pessoa na conversa: o link de quem atende; no contato, sem responsável', :aggregate_failures do
      treinamento.update!(assignment_mode: :per_agent)
      proprio = account.crm_agent_booking_links.create!(booking_profile: treinamento, agent: world.host, slug: SecureRandom.uuid)
      conversa = create(:conversation, account: account, contact: world.contact, assignee: world.host)
      contexto = Autonomia::Automacao::Contexto.de(world.contact)

      expect(ler(conversa, admin)).to eq(Crm::BookingV2::ShortLink.url_for(treinamento, link: proprio))
      expect(described_class.resultado(caminho, contexto: contexto, account_user: na_conta(admin)).to_h)
        .to eq(url: nil, por: 'sem_responsavel')
    end

    it 'página despublicada, apagada, de outra conta ou agendamento desligado: vazio por sem_pagina', :aggregate_failures do
      contexto = Autonomia::Automacao::Contexto.de(card)
      resultado = ->(lido = caminho) { described_class.resultado(lido, contexto: contexto, account_user: na_conta(admin)).to_h }
      de_fora = pagina_de_outra_conta

      expect(resultado.call("agenda.#{de_fora.id}")).to eq(url: nil, por: 'sem_pagina')
      account.disable_features!('crm_booking_v2')
      expect(resultado.call).to eq(url: nil, por: 'sem_pagina')
      account.enable_features!('crm_booking_v2')
      treinamento.update!(enabled: false)
      expect(resultado.call).to eq(url: nil, por: 'sem_pagina')
      treinamento.destroy!
      expect(resultado.call).to eq(url: nil, por: 'sem_pagina')
    end

    it 'quem ligou sem agendamento_view: vazio por sem_acesso_agenda' do
      expect(described_class.resultado(caminho, contexto: Autonomia::Automacao::Contexto.de(card), account_user: na_conta(agente)).to_h)
        .to eq(url: nil, por: 'sem_acesso_agenda')
    end
  end

  describe 'ao salvar' do
    def problema(quem, lido = caminho) = described_class.problema_ao_salvar(lido, conta: account, account_user: quem && na_conta(quem))

    it 'aceita a página usável da conta para quem vê o agendamento' do
      expect(problema(admin)).to be_nil
    end

    it 'recusa sem pessoa, sem agendamento_view, com o agendamento desligado ou página que não marca', :aggregate_failures do
      expect(problema(nil)).to eq(:agenda_so_na_instalacao)
      expect(problema(agente)).to eq(:agenda_sem_permissao)
      account.disable_features!('crm_booking_v2')
      expect(problema(admin)).to eq(:agenda_desligada)
      account.enable_features!('crm_booking_v2')
      treinamento.update!(enabled: false)
      expect(problema(admin)).to eq(:agenda_pagina_inexistente)
      expect(problema(admin, "agenda.#{pagina_de_outra_conta.id}")).to eq(:agenda_pagina_inexistente)
    end
  end

  describe 'no passo de mensagem' do
    # Liga com a página usável (o salvar confere); o bloco muda o mundo antes de o passo rodar.
    def preparar(quem)
      ligar_motor(account)
      ligar_mensagens(account)
      account.enable_features!('automacao_gatilhos')
      conversa = create(:conversation, account: account, contact: world.contact)
      conversa.inbox.add_members([quem.id])
      card.update!(primary_conversation: conversa)
    end

    def executar(quem)
      preparar(quem)
      passo = mensagem_passo('m1', 'Marque o treinamento: ', { '$valor' => caminho })
      definicao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'card.ganho' })
      definicao.update_column(:ligada_por_id, quem.id) # rubocop:disable Rails/SkipsModelValidations
      yield if block_given?
      execucao = Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                                        chave_gatilho: 'card.ganho', evento: 'card.ganho:atividade:1')
      Autonomia::Automacao::PassoDeMensagem.new(execucao: execucao.reload, passo: passo, alvo: card).executar
    end

    it 'quem ligou perdeu agendamento_view: pula com o motivo próprio, sem_acesso_agenda' do
      resultado = executar(agente)

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'sem_acesso_agenda'])
    end

    it 'página sem link para o responsável: faltou_link_da_agenda com o por' do
      resultado = executar(admin) { treinamento.update!(enabled: false) }

      expect([resultado.tipo, resultado.motivo, resultado.dados]).to eq([:pulado, 'faltou_link_da_agenda', { 'por' => 'sem_pagina' }])
    end
  end

  describe 'no ensaio: o mesmo motivo do motor' do
    def ensaiar(quem)
      ligar_motor(account)
      ligar_mensagens(account)
      conversa = create(:conversation, account: account, contact: world.contact, status: :resolved)
      conversa.inbox.add_members([quem.id])
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [mensagem_passo('m1', 'Marque: ', { '$valor' => caminho })] }
      Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: quem, conversa_id: conversa.display_id)
                                  .resultado[:conversas].sole[:passos].sole.slice(:faria, :dados)
    end

    it 'quem pede sem agendamento_view: sem_acesso_agenda; página fora do ar: faltou_link_da_agenda', :aggregate_failures do
      expect(ensaiar(agente)).to eq(faria: 'sem_acesso_agenda', dados: { por: 'sem_acesso_agenda' })
      treinamento.update!(enabled: false)
      expect(ensaiar(admin)).to eq(faria: 'faltou_link_da_agenda', dados: { por: 'sem_pagina' })
    end
  end
end
