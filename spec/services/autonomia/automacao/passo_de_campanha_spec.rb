require 'rails_helper'

# O passo "campanha" (#2414 G14, #2630): disparar pela Campanha da tela, só em gatilho da conta, e marcar "não recebe".
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

  # O gatilho da conta (G7): o único em que o disparar salva.
  let(:da_conta) { { 'tipo' => 'conta.recorrente', 'frequencia' => 'diaria', 'hora' => 8 } }
  let(:gatilho_padrao) { 'conversa.resolvida' }

  def problemas(passo, gatilho: gatilho_padrao, quem: dona)
    receita = { 'gatilho' => gatilho.is_a?(Hash) ? gatilho : { 'tipo' => gatilho }, 'passos' => [passo] }
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

    context 'with o gatilho da conta (conta.recorrente, G7)' do
      let(:gatilho_padrao) { da_conta }

    before { account.enable_features!('automacao_gatilhos') }

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
      # Uma receita gravada antes da regra: salva no gatilho da conta e, no banco, trocada para o de conversa (o salvar
      # de hoje recusaria). Ao rodar, a regra vale.
      account.enable_features!('automacao_gatilhos')
      definicao = automacao_ligada(account, dona, [disparar], gatilho: da_conta)
      versao = definicao.versao_ativa
      versao.update_column(:receita, versao.receita.merge('gatilho' => { 'tipo' => 'conversa.resolvida' })) # rubocop:disable Rails/SkipsModelValidations

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

      expect(Autonomia::Automacao::Registro.where(automacao: definicao).pluck(:passo, :resultado, :motivo))
        .to eq([%w[c1 pulado campanha_so_sem_alvo]])
      expect(account.campaigns).to be_empty
    end
  end
end
