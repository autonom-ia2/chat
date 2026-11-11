require 'rails_helper'

# #2889 parte 2: com a porta da Automação (automacao_porta + automacao_editor), o Guia monta automação no motor novo
# (autonomia/automacoes). Cria e ajusta desligada, com a origem 'guia'; não liga (só a pessoa, na tela); vê o formato
# da receita; e quem tem a chave de automações faz isso sem ser administrador, como em automation_rules.
RSpec.describe Autonomia::Guide::Acoes do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:receita) do
    { 'gatilho' => { 'tipo' => 'conversa.resolvida' },
      'passos' => [{ 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }] }
  end
  let(:outra_receita) do
    receita.merge('passos' => [{ 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 2, 'unidade' => 'dias' } }])
  end

  before { account.enable_features!('automacao_editor', 'automacao_porta', 'automacao_fundacao') }

  def com_funcao(permissions)
    user, account_user = create_crm_agent(account: account, name: 'Pessoa de Teste')
    account_user.update!(custom_role: CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}",
                                                         permissions: permissions))
    user
  end

  def para(user) = described_class.new(account: account, user: user)

  def criar(user = admin)
    para(user).executar('POST autonomia/automacoes', { corpo: { 'nome' => 'Lembrete', 'receita' => receita } })
  end

  describe 'criar e ajustar' do
    it 'cria desligada, com origem guia, e a criação pela tela continua manual', :aggregate_failures do
      resultado = criar

      expect(resultado.ok).to be(true)
      automacao = Autonomia::Automacao::Definicao.find(resultado.registro)
      expect(automacao.ativa).to be(false)
      expect(automacao.origem).to eq('guia')
      expect(Autonomia::Guide::PeloGuia.agora?).to be(false)
    end

    it 'ajusta com a versão vista e recusa a versão velha', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      vista = automacao.versao_ativa_id
      patch = lambda do |base|
        para(admin).executar('PATCH autonomia/automacoes/:id',
                             { caminho: { id: automacao.id }, corpo: { 'receita' => outra_receita, 'base_versao_id' => base } })
      end

      expect(patch.call(vista).ok).to be(true)
      expect(automacao.reload.versao_ativa.receita.dig('passos', 0, 'duracao', 'valor')).to eq(2)
      velha = patch.call(vista)
      expect(velha.ok).to be(false)
      expect(velha.mensagem).to eq(I18n.t('autonomia.automacao.editor.versao_mudou'))
    end

    it 'sem a porta (só com o editor), o Guia não mexe no motor novo' do
      account.disable_features!('automacao_porta')

      expect { criar }.to raise_error(described_class::Recusada, I18n.t('autonomia.guide.automacao_sem_porta'))
    end

    # Ajustar a ligada vale na hora: passa pela confirmação da pessoa, com o aviso. A desligada segue direto.
    it 'ajustar uma automação ligada pede confirmação; a desligada não', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      dados = { caminho: { id: automacao.id }, corpo: { 'receita' => outra_receita, 'base_versao_id' => automacao.versao_ativa_id },
                descricao: 'Esperar dois dias' }

      expect(para(admin).desfazivel?('PATCH autonomia/automacoes/:id', dados)).to be(true)

      automacao.assumir_e_religar!(admin, versao_id: automacao.versao_ativa_id)
      expect(para(admin).desfazivel?('PATCH autonomia/automacoes/:id', dados)).to be(false)
      expect { para(admin).conferir!('PATCH autonomia/automacoes/:id', dados) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.needs_confirmation'))
      expect(para(admin).descrever('PATCH autonomia/automacoes/:id', dados)[:aviso])
        .to eq(I18n.t('autonomia.guide.automacao_ligada_vale_na_hora'))
    end

    it 'o sinal do Guia volta a desligado mesmo quando o pedido levanta', :aggregate_failures do
      expect { Autonomia::Guide::PeloGuia.durante { raise ArgumentError, 'falhou' } }.to raise_error(ArgumentError)
      expect(Autonomia::Guide::PeloGuia.agora?).to be(false)
    end

    it 'com automation_manage, cria sem ser administrador' do
      expect(criar(com_funcao(%w[automation_view automation_manage])).ok).to be(true)
    end

    it 'sem automation_manage, ouve que não tem acesso' do
      expect { criar(com_funcao(%w[automation_view])) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.automation_manage_only'))
    end

    it 'o ensaio passa só com automation_view' do
      so_ve = com_funcao(%w[automation_view])

      expect(Autonomia::Guide::PorteiroDaAutomacao.recusa('POST autonomia/automacoes/ensaio', so_ve.account_users.first, {})).to be_nil
      expect(Autonomia::Guide::PorteiroDaAutomacao.recusa('POST autonomia/automacoes/:id/ensaio', so_ve.account_users.first, {})).to be_nil
    end
  end

  # O desfazer do Guia (#855) vale também aqui: criar some com as versões; ajustar volta a versão anterior.
  describe 'desfazer' do
    let(:execucao) { Autonomia::Guide::Execucao.abrir(account: account, user: admin) }

    def gravando(passo, &) = Autonomia::Guide::Diario.gravando(execucao, passo, &)
    def desfazer = Autonomia::Guide::Desfazer.new(execucao: execucao.reload, user: admin).perform

    it 'desfazer a criação apaga a automação e as versões dela', :aggregate_failures do
      id = gravando(0) { criar }.registro

      relatorio = desfazer

      expect(relatorio['conflitos']).to eq([])
      expect(Autonomia::Automacao::Definicao.exists?(id)).to be(false)
      expect(Autonomia::Automacao::Versao.where(automacao_id: id)).to be_empty
    end

    it 'desfazer o ajuste volta a versão anterior', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      anterior = automacao.versao_ativa_id
      gravando(0) do
        para(admin).executar('PATCH autonomia/automacoes/:id',
                             { caminho: { id: automacao.id }, corpo: { 'receita' => outra_receita, 'base_versao_id' => anterior } })
      end

      relatorio = desfazer

      expect(relatorio['conflitos']).to eq([])
      expect(automacao.reload.versao_ativa_id).to eq(anterior)
      expect(automacao.versoes.count).to eq(1)
    end

    it 'alguém salvou depois do ajuste: o desfazer avisa e não tira a versão de ninguém', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      gravando(0) do
        para(admin).executar('PATCH autonomia/automacoes/:id',
                             { caminho: { id: automacao.id }, corpo: { 'receita' => outra_receita, 'base_versao_id' => automacao.versao_ativa_id } })
      end
      depois = automacao.reload.salvar_versao!(receita: receita, autor: admin, base: automacao.versao_ativa_id)

      relatorio = desfazer

      expect(relatorio['conflitos'].pluck('motivo')).to include('changed_after', 'versao_mais_nova')
      expect(relatorio['conflitos'].pluck('texto')).to include(I18n.t('autonomia.guide.undo.conflitos.versao_mais_nova'))
      expect(automacao.reload.versao_ativa_id).to eq(depois.id)
      expect(automacao.versoes.count).to eq(3)
    end

    it 'a automação que a pessoa já ligou não some com o desfazer da criação', :aggregate_failures do
      id = gravando(0) { criar }.registro
      automacao = Autonomia::Automacao::Definicao.find(id)
      automacao.assumir_e_religar!(admin, versao_id: automacao.versao_ativa_id)

      relatorio = desfazer

      expect(relatorio['conflitos'].pluck('motivo')).to include('automacao_ja_ligada')
      expect(automacao.reload.versao_ativa).to be_present
      expect(automacao.ativa).to be(true)
    end

    # Defesa em profundidade: mesmo que um desligar entre no caderno, o desfazer não religa.
    it 'o desfazer nunca religa: a automação desligada continua desligada', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      automacao.assumir_e_religar!(admin, versao_id: automacao.versao_ativa_id)
      gravando(0) { automacao.desligar! }

      relatorio = desfazer

      expect(relatorio['conflitos'].pluck('motivo')).to eq(['ligar_na_tela'])
      expect(relatorio['conflitos'].first['texto']).to eq(I18n.t('autonomia.guide.undo.conflitos.ligar_na_tela'))
      expect(automacao.reload.ativa).to be(false)
    end
  end

  describe 'ligar' do
    it 'o Guia não liga, nem para o administrador: a resposta diz onde ligar na tela', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      ligar = -> { para(admin).executar('POST autonomia/automacoes/:id/ligar', { caminho: { id: automacao.id }, corpo: {} }) }

      expect { ligar.call }.to raise_error(described_class::Recusada, I18n.t('autonomia.guide.only_on_screen.automacao_ligar'))
      expect(para(admin).catalogo).not_to include('POST autonomia/automacoes/:id/ligar')
      expect(automacao.reload.ativa).to be(false)
    end

    # Desligar não tem desfazer (desfazer religaria sem "assumir"): vai pela confirmação, com o aviso de onde religar.
    it 'desligar o Guia pode, com a confirmação da pessoa e sem desfazer', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)
      automacao.assumir_e_religar!(admin, versao_id: automacao.versao_ativa_id)
      desligar = 'POST autonomia/automacoes/:id/desligar'
      dados = { caminho: { id: automacao.id }, corpo: {}, descricao: 'Desligar o lembrete' }

      expect { para(admin).conferir!(desligar, dados) }
        .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.needs_confirmation'))
      expect(para(admin).descrever(desligar, dados)[:aviso]).to eq(I18n.t('autonomia.guide.automacao_desligar_sem_desfazer'))
      expect(para(admin).executar(desligar, dados).ok).to be(true)
      expect(automacao.reload.ativa).to be(false)
    end
  end

  describe 'cabeçalho' do
    def cabecalho(rota, parametros = {})
      Autonomia::Guide::Cabecalho.call(account: account.reload, role: 'administrator', route_context: rota, route_params: parametros)
    end

    it 'com as flags, diz o motor e, na tela da automação, a versão atual', :aggregate_failures do
      automacao = Autonomia::Automacao::Definicao.find(criar.registro)

      expect(cabecalho('automacoes_nova')).to include('Motor das automações desta conta: novo')
      expect(cabecalho('automacoes_guia_editar', { 'id' => automacao.id }))
        .to include("Registro aberto na tela: automação id=#{automacao.id}, versão atual id=#{automacao.versao_ativa_id}.")
    end

    it 'sem a porta, o cabeçalho é o de antes' do
      account.disable_features!('automacao_porta')

      texto = cabecalho('automacoes_editar', { 'id' => 7 })

      expect(texto).not_to include('Motor das automações')
      expect(texto).to include('Tela atual: automacoes_editar. Registro aberto na tela: id=7. ')
    end

    it 'automação de outra conta não entra no cabeçalho; a da conta entra', :aggregate_failures do
      outra = create(:account)
      alheia = Autonomia::Automacao::Definicao.create!(account: outra, nome: 'x', origem: 'manual')
      propria = Autonomia::Automacao::Definicao.find(criar.registro)

      expect(cabecalho('automacoes_guia_editar', { 'id' => propria.id })).to include("automação id=#{propria.id}, versão atual")
      expect(cabecalho('automacoes_guia_editar', { 'id' => alheia.id })).not_to include('versão atual')
    end
  end

  describe 'formato' do
    it 'a receita leva o esquema, e o ajuste leva base_versao_id', :aggregate_failures do
      criacao = Autonomia::Guide::Formatos.para('POST autonomia/automacoes')
      ajuste = Autonomia::Guide::Formatos.para('PATCH autonomia/automacoes/:id')

      expect(criacao.dig('campos', 'receita', 'esquema')).to eq(Autonomia::Automacao::Receita::ESQUEMA)
      expect(ajuste.dig('campos', 'receita', 'esquema_de')).to eq('Autonomia::Automacao::Versao#receita')
      expect(ajuste['campos']).to include('base_versao_id')
    end

    it 'o resumo da receita ensina a descer, e cada pedaço sai pelo caminho', :aggregate_failures do
      resumo = ->(campo) { Autonomia::Guide::Formatos.resumo_para_o_modelo('POST autonomia/automacoes', campo: campo) }

      expect(resumo.call('receita')).to include('"receita.gatilho"', '"receita.passos"')
      expect(resumo.call('receita.passos')).to include('tipo = mensagem', 'tipo = esperar')
      expect(resumo.call('receita.passos.mensagem')).to include('texto', 'Partes citadas')
      expect(resumo.call('receita.gatilho.tipo')).to include('conversa.criada', 'mensagem.criada')
      expect(resumo.call('receita.condicao')).to include('igual')
    end

    it 'o corpo fora do esquema da receita é recusado antes de chamar a plataforma' do
      errada = { 'nome' => 'x', 'receita' => { 'gatilho' => { 'tipo' => 'nao_existe' }, 'passos' => [] } }

      expect { para(admin).executar('POST autonomia/automacoes', { corpo: errada }) }
        .to raise_error(described_class::CorpoForaDoFormato)
    end
  end
end
