require 'rails_helper'

# O passo "campanha" (#2414 G14, #2630): disparar pela Campanha da tela, só em gatilho recorrente (no de card ou
# contato, uma campanha por vez: G55), e marcar "não recebe".
RSpec.describe Autonomia::Automacao::PassoDeCampanha, :automacao_motor do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:etiqueta) { create(:label, account: account, title: 'ja_comprou') }
  let(:pre_black) do
    { 'name' => 'pre_black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi! A Black começa {{1}}.' }] }
  end
  let(:disparar) do
    { 'id' => 'c1', 'tipo' => 'campanha', 'faz' => 'disparar', 'titulo' => 'Pré-Black', 'caixa_id' => caixa.id,
      'modelo' => { 'nome' => 'pre_black', 'idioma' => 'pt_BR', 'variaveis' => [['na quinta']] }, 'etiquetas' => [etiqueta.id] }
  end
  let(:nao_receber) { { 'id' => 'n1', 'tipo' => 'campanha', 'faz' => 'nao_receber' } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('whatsapp_campaign')
    canal.update!(message_templates: [pre_black])
  end

  after { Current.reset }

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: 'c1', **valores)

  def problemas(passo, gatilho: 'conversa.resolvida', quem: dona)
    receita = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => [passo] }
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: quem)).problemas
  end

  def execucao_de(passos, gatilho: { 'tipo' => 'conversa.resolvida' }, por: dona)
    definicao = automacao_ligada(account, por, passos, gatilho: gatilho)
    Autonomia::Automacao::Execucao.new(automacao: definicao, account: account)
  end

  describe 'ao salvar' do
    it 'recusa o disparar em gatilho de conversa ou de card: cada execução mandaria a mesma campanha de novo' do
      expect(problemas(disparar)).to eq([frase(:campanha_so_sem_alvo)])
      expect(problemas(disparar, gatilho: 'card.ganho')).to include(frase(:campanha_so_sem_alvo))
    end

    # G55 (exemplo 16): "para cada card perdido" é o card.recorrente; a campanha sai uma vez para a vez inteira.
    it 'aceita o disparar no recorrente de card e de contato' do
      expect(problemas(disparar, gatilho: 'card.recorrente')).not_to include(frase(:campanha_so_sem_alvo))
      expect(problemas(disparar, gatilho: 'contato.recorrente')).not_to include(frase(:campanha_so_sem_alvo))
      expect(problemas(disparar, gatilho: 'card.parado')).to include(frase(:campanha_so_sem_alvo))
    end

    context 'with o gatilho da conta (conta.recorrente, G7)' do
      before { allow(described_class).to receive(:gatilho_da_conta?).and_return(true) }

      it 'aceita a campanha pronta, com modelo de utilidade aprovado' do
        expect(problemas(disparar)).to be_empty
      end

      it 'aceita modelo de propaganda (decisão de 06/11), como o passo mensagem desde o lote 5 (#2681)' do
        propaganda = pre_black.merge('category' => 'MARKETING')
        canal.update!(message_templates: [propaganda])
        mensagem = { 'id' => 'm1', 'tipo' => 'mensagem', 'texto' => ['Oi'],
                     'modelo' => { 'nome' => 'pre_black', 'idioma' => 'pt_BR', 'variaveis' => [['na quinta']] } }

        expect(problemas(disparar)).to be_empty
        expect(problemas(mensagem)).to be_empty
        expect(Autonomia::Automacao::ModeloWhatsapp.serve?(propaganda, 1)).to be(true)
      end

      it 'recusa modelo de autenticação' do
        canal.update!(message_templates: [pre_black.merge('category' => 'AUTHENTICATION')])

        expect(problemas(disparar)).to include(frase(:campanha_modelo, nome: 'pre_black'))
      end

      it 'recusa variável do modelo que lê um valor: a campanha vai para muita gente de uma vez' do
        passo = disparar.deep_merge('modelo' => { 'variaveis' => [[{ '$valor' => 'contato.nome' }]] })

        expect(problemas(passo)).to include(frase(:campanha_variavel_fixa))
      end

      it 'recusa variável só com espaço: o parâmetro iria vazio para todo o público' do
        passo = disparar.deep_merge('modelo' => { 'variaveis' => [['   ']] })

        expect(problemas(passo)).to include(frase(:campanha_variavel_fixa))
      end

      it 'recusa caixa que não é do WhatsApp oficial, etiqueta de outra conta e modelo que a caixa não tem' do
        outra = create(:label)
        passo = disparar.merge('caixa_id' => create(:inbox, account: account).id, 'etiquetas' => [etiqueta.id, outra.id])
        sem_modelo = disparar.deep_merge('modelo' => { 'nome' => 'nao_existe' })

        expect(problemas(passo)).to include(frase(:campanha_sem_caixa), frase(:campanha_etiqueta_de_fora, id: outra.id))
        expect(problemas(disparar.merge('sem_etiquetas' => [outra.id]))).to eq([frase(:campanha_etiqueta_de_fora, id: outra.id)])
        expect(problemas(sem_modelo)).to include(frase(:campanha_modelo, nome: 'nao_existe'))
      end

      it 'recusa com as campanhas de WhatsApp desligadas na conta' do
        account.disable_features!('whatsapp_campaign')

        expect(problemas(disparar)).to include(frase(:campanha_desligada))
      end

      it 'recusa quem salva sem permissão de enviar campanha (no OSS, o agente)' do
        agente = create(:user, account: account, role: :agent)

        expect(problemas(disparar, quem: agente)).to include(frase(:campanha_sem_permissao))
      end
    end

    it 'o não receber vale em qualquer gatilho com contato' do
      expect(problemas(nao_receber)).to be_empty
    end
  end

  describe 'disparar' do
    it 'cria a campanha da tela para a etiqueta, com o modelo, e a põe na fila do disparo' do
      execucao = execucao_de([nao_receber])

      resultado = described_class.new(execucao: execucao, passo: disparar, alvo: account).executar

      campanha = account.campaigns.last
      expect(resultado.tipo).to eq(:ok)
      expect(campanha).to have_attributes(title: 'Pré-Black', inbox: caixa, sender: dona, campaign_type: 'one_off',
                                          message: 'Oi! A Black começa na quinta.',
                                          audience: [{ 'type' => 'Label', 'id' => etiqueta.id }])
      expect(campanha.template_params).to include('name' => 'pre_black', 'language' => 'pt_BR',
                                                  'processed_params' => { 'body' => { '1' => 'na quinta' } })
      expect(resultado.dados).to eq('campanha_id' => campanha.display_id, 'etiquetas' => [etiqueta.id], 'sem_etiquetas' => [])
      expect(Campaigns::TriggerOneoffCampaignJob).to have_been_enqueued.with(campanha)
    end

    # Lote 5 (#2681): o "todos menos quem já comprou" do exemplo 7.
    it 'grava as etiquetas excluídas no público, para o envio deixar essa gente de fora' do
      sem = create(:label, account: account, title: 'comprou_na_black')

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: disparar.merge('sem_etiquetas' => [sem.id]),
                                      alvo: account).executar

      expect(account.campaigns.last.audience).to eq([{ 'type' => 'Label', 'id' => etiqueta.id }, { 'type' => 'ExcludeLabel', 'id' => sem.id }])
      expect(resultado.dados).to include('sem_etiquetas' => [sem.id])
    end

    it 'o gatilho da conta é o de alvo Account (contrato com a G7), não o de conversa ou card' do
      allow(Autonomia::Automacao::Gatilhos).to receive(:alvo).and_call_original
      allow(Autonomia::Automacao::Gatilhos).to receive(:alvo).with('conta.recorrente').and_return('Account')

      expect(described_class.gatilho_da_conta?('conta.recorrente')).to be(true)
      expect(described_class.gatilho_da_conta?('conversa.criada')).to be(false)
      expect(described_class.gatilho_da_conta?('card.ganho')).to be(false)
    end

    it 'receita antiga com alvo pula com o motivo e não cria campanha' do
      conversa = create(:conversation, account: account, inbox: caixa)

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: disparar, alvo: conversa).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'campanha_so_sem_alvo'])
      expect(account.campaigns).to be_empty
    end

    it 'quem ligou sem permissão de enviar campanha: sem acesso, e nada criado' do
      dona.account_users.find_by(account: account).update!(role: :agent)

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: disparar, alvo: account).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_campanha'])
      expect(account.campaigns).to be_empty
    end

    it 'modelo de propaganda sai na campanha (decisão de 06/11)' do
      canal.update!(message_templates: [pre_black.merge('category' => 'MARKETING')])

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: disparar, alvo: account).executar

      expect(resultado.tipo).to eq(:ok)
      expect(account.campaigns.last.template_params['category']).to eq('MARKETING')
    end

    it 'modelo de autenticação pula com o motivo, sem criar campanha' do
      canal.update!(message_templates: [pre_black.merge('category' => 'AUTHENTICATION')])

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: disparar, alvo: account).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'campanha_modelo_de_categoria_fora'])
      expect(account.campaigns).to be_empty
    end

    it 'modelo que deixou de ser aprovado na caixa pula com o motivo da campanha' do
      canal.update!(message_templates: [pre_black.merge('status' => 'PAUSED')])

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: disparar, alvo: account).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'campanha_modelo_nao_aprovado'])
    end

    it 'variável só com espaço que chegar assim mesmo pula, sem criar campanha' do
      passo = disparar.deep_merge('modelo' => { 'variaveis' => [['   ']] })

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: passo, alvo: account).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'campanha_variavel_vazia'])
      expect(account.campaigns).to be_empty
    end
  end

  # G55: no card.recorrente, uma execução por card; a campanha é da vez, criada pela primeira e agendada para JUNTAR
  # depois da última que passar pelo passo.
  describe 'disparar no recorrente de card (G55)' do
    let(:juntar) { Autonomia::Automacao::CampanhaDaOcorrencia::JUNTAR }
    let(:vez) { Time.zone.parse('2026-11-01 12:00:00 UTC') }
    let(:definicao) { automacao_ligada(account, dona, [nao_receber]) }
    let(:cards) do
      funil, etapa = create_crm_pipeline(account: account, user: dona)
      create_list(:contact, 3, account: account).map do |contato|
        account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'C', currency: 'BRL', contact: contato, status: :lost)
      end
    end

    around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

    def execucao_da_vez(card, instante = vez)
      Autonomia::Automacao::Execucao.new(automacao: definicao, account: account, versao: definicao.versao_ativa, alvo: card,
                                         chave_gatilho: 'card.recorrente',
                                         evento: Autonomia::Automacao::Gatilhos.marca_do_recorrente('card.recorrente', card.id, instante))
    end

    def disparar_em(card, momento, instante = vez)
      travel_to(momento) { described_class.new(execucao: execucao_da_vez(card, instante), passo: disparar, alvo: card).executar }
    end

    it 'a vez inteira junta numa campanha só, que sai JUNTAR depois do último card, pelo agendador', :aggregate_failures do
      primeiro = disparar_em(cards[0], vez + 5.minutes)
      segundo = disparar_em(cards[1], vez + 9.minutes)

      expect(account.campaigns.count).to eq(1)
      campanha = account.campaigns.last
      expect([primeiro.tipo, segundo.tipo]).to eq(%i[ok ok])
      expect([primeiro.dados['campanha_id'], segundo.dados['campanha_id']]).to eq([campanha.display_id] * 2)
      expect(campanha).to have_attributes(campaign_status: 'active', audience: [{ 'type' => 'Label', 'id' => etiqueta.id }])
      expect(campanha.scheduled_at).to be_within(1.second).of(vez + 9.minutes + juntar)
      expect(Campaigns::TriggerOneoffCampaignJob).not_to have_been_enqueued
    end

    it 'outra vez (o mês seguinte) ganha a campanha dela' do
      disparar_em(cards[0], vez + 5.minutes)
      account.campaigns.last.update!(campaign_status: :completed)
      seguinte = vez + 30.days

      resultado = disparar_em(cards[0], seguinte + 5.minutes, seguinte)

      expect(resultado.tipo).to eq(:ok)
      expect(account.campaigns.count).to eq(2)
    end

    it 'o card que chega depois de a campanha da vez sair pula com o motivo e não cria outra', :aggregate_failures do
      disparar_em(cards[0], vez + 5.minutes)
      campanha = account.campaigns.last
      campanha.update!(campaign_status: :completed)

      resultado = disparar_em(cards[1], vez + 40.minutes)

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'campanha_da_vez_ja_saiu'])
      expect(resultado.dados['campanha_id']).to eq(campanha.display_id)
      expect(account.campaigns.count).to eq(1)
    end

    it 'sem a marca no Redis, acha a campanha da vez pelo registro do passo' do
      execucao = execucao_da_vez(cards[0]).tap(&:save!)
      primeiro = travel_to(vez + 5.minutes) { described_class.new(execucao: execucao, passo: disparar, alvo: cards[0]).executar }
      Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'c1', resultado: 'ok',
                                             dados: primeiro.dados)
      da_vez = Autonomia::Automacao::Gatilhos.ocorrencia_da_marca(execucao.evento, cards[0].id)
      Redis::Alfred.delete("automacao:campanha_da_vez:#{definicao.id}:c1:#{da_vez}")

      disparar_em(cards[1], vez + 8.minutes)

      expect(account.campaigns.count).to eq(1)
    end

    it 'no gatilho de evento do card (card.ganho), a receita que chegar assim mesmo pula, sem campanha' do
      execucao = Autonomia::Automacao::Execucao.new(automacao: definicao, account: account, alvo: cards[0], chave_gatilho: 'card.ganho',
                                                    evento: "card.ganho:atividade:#{cards[0].id}")

      resultado = described_class.new(execucao: execucao, passo: disparar, alvo: cards[0]).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'campanha_so_sem_alvo'])
      expect(account.campaigns).to be_empty
    end
  end

  describe 'nao receber' do
    let(:contato) { create(:contact, account: account) }
    let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato) }

    it 'marca o contato do alvo como manual, feito por quem ligou' do
      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: nao_receber, alvo: conversa).executar

      expect(resultado).to have_attributes(tipo: :ok, dados: { 'contato_id' => contato.id })
      expect(contato.reload).to have_attributes(opt_out_source: 'manual', opted_out_by_id: dona.id)
      expect(contato.opted_out?).to be(true)
    end

    it 'contato que já não recebia: pula e não troca a origem da recusa' do
      contato.opt_out!(source: 'campaign_reply')

      resultado = described_class.new(execucao: execucao_de([nao_receber]), passo: nao_receber, alvo: conversa).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:pulado, 'contato_ja_nao_recebe'])
      expect(contato.reload.opt_out_source).to eq('campaign_reply')
    end
  end

  describe 'pelo motor' do
    it 'o não receber roda como passo, com o contato no histórico' do
      conversa = create(:conversation, account: account, inbox: caixa, status: :resolved)
      definicao = automacao_ligada(account, dona, [nao_receber])

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

      expect(conversa.contact.reload.opted_out?).to be(true)
      expect(Autonomia::Automacao::Registro.where(automacao: definicao).pluck(:passo, :resultado, :dados))
        .to eq([['n1', 'ok', { 'contato_id' => conversa.contact_id }]])
    end

    it 'o disparar que chegar num gatilho de conversa pula com o motivo e a execução segue' do
      conversa = create(:conversation, account: account, inbox: caixa, status: :resolved)
      # Salva como se fosse o gatilho da conta; ao rodar, a regra de hoje vale.
      allow(described_class).to receive(:gatilho_da_conta?).and_return(true)
      definicao = automacao_ligada(account, dona, [disparar])
      allow(described_class).to receive(:gatilho_da_conta?).and_call_original

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

      expect(Autonomia::Automacao::Registro.where(automacao: definicao).pluck(:passo, :resultado, :motivo))
        .to eq([%w[c1 pulado campanha_so_sem_alvo]])
      expect(account.campaigns).to be_empty
    end
  end
end
