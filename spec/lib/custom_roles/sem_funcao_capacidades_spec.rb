require 'rails_helper'

# O contrato "Sem função" (#2308) sai das policies. Este spec segura o JSON versionado em dia (roda no CI "Testes do
# fork", como o formatos_spec), a flag dos relatórios nos dois estados, o prepend do EE carregado e que as respostas
# mudam com a função: um gerador que respondesse "pode" para todo mundo passaria despercebido sem isso.
RSpec.describe CustomRoles::SemFuncaoCapacidades do
  def capacidade(id)
    gerado = described_class.gerar
    (gerado[:capacidades] + gerado[:extras]).find { |item| item[:id] == id } || raise("sem capacidade #{id}")
  end

  it 'o JSON versionado está em dia com as policies (rode `bundle exec rails autonomia:funcoes:sem_funcao`)' do
    expect(described_class.em_dia?).to be(true), "fora de dia: #{described_class::ARQUIVO.relative_path_from(Rails.root)}"
  end

  it 'traz as 14 capacidades e os 2 extras, com chaves que existem', :aggregate_failures do
    gerado = described_class.gerar

    expect(gerado[:capacidades].size).to eq(14)
    expect(gerado[:extras].pluck(:id)).to eq(%w[responsavel_de_agendamento anuncio_de_origem])
    expect((gerado[:capacidades] + gerado[:extras]).flat_map { |item| item[:chaves] } - CustomRole::PERMISSIONS).to eq([])
    expect(capacidade('anuncio_de_origem')[:chaves]).to eq(%w[meta_ads_view])
  end

  it 'o agente sem função pode o que a tela vai dizer e não pode o que só a função dá', :aggregate_failures do
    pode = %w[conversas_dos_colegas contatos respostas_prontas apagar_mensagens vendas_das_colunas arquivar_vendas
              valores_das_vendas responsavel_de_agendamento anuncio_de_origem]
    nao_pode = %w[procurar_clientes_novos planilha_de_clientes montar_colunas ia_das_vendas cuidar_de_tudo_nas_vendas
                  metas_do_mes]

    pode.each { |id| expect(capacidade(id)).to include(pode: true) }
    nao_pode.each { |id| expect(capacidade(id)).to include(pode: false) }
  end

  describe 'com função' do
    def item_com(id, permissions)
      described_class.gerar(custom_role: CustomRole.new(id: 1, permissions: permissions))[:capacidades]
                     .find { |item| item[:id] == id }
    end

    it 'vê os valores das vendas só com sales_value_view', :aggregate_failures do
      expect(item_com('valores_das_vendas', %w[crm_view crm_admin])).to include(pode: false)
      expect(item_com('valores_das_vendas', %w[sales_value_view])).to include(pode: true)
    end

    it 'crm_admin sozinho liga as chaves crm_* (superchave): mexe nas vendas das colunas' do
      expect(item_com('vendas_das_colunas', %w[crm_admin])).to include(pode: true)
    end
  end

  describe 'relatórios das vendas e a flag crm_numeros_lentes' do
    def ve_relatorios?(flag_ligada)
      account = Account.new
      account.enable_features('crm_numeros_lentes') if flag_ligada
      account_user = AccountUser.new(account: account, user: User.new(id: 1), role: :agent)
      Crm::ReportPolicy.new({ user: account_user.user, account: account, account_user: account_user }, %i[crm report]).view?
    end

    it 'desligada vê, ligada não vê, e o JSON marca depende_da_flag com os dois valores', :aggregate_failures do
      expect(ve_relatorios?(false)).to be(true)
      expect(ve_relatorios?(true)).to be(false)
      expect(capacidade('relatorios_das_vendas'))
        .to include(depende_da_flag: { flag: 'crm_numeros_lentes', desligada: true, ligada: false })
      expect(capacidade('relatorios_das_vendas')).not_to have_key(:pode)
    end
  end

  # Sem o prepend, o Crm::ReportPolicy do OSS dá as mesmas respostas para o sem função e o JSON não mudaria: só o
  # ancestors prova que a regra lida é a do EE.
  it 'lê as policies com o módulo Enterprise do prepend', :aggregate_failures do
    expect(Crm::ReportPolicy.ancestors).to include(Enterprise::Crm::ReportPolicy)
    expect(Crm::CardPolicy.ancestors).to include(Enterprise::Crm::CardPolicy)
    expect(ConversationPolicy.ancestors).to include(Enterprise::ConversationPolicy)
    expect(ContactPolicy.ancestors).to include(Enterprise::ContactPolicy)
  end

  it 'uma função sem chave nenhuma não pode nada: as respostas vêm da função, não de um sim fixo' do
    gerado = described_class.gerar(custom_role: CustomRole.new(id: 1, permissions: []))

    expect((gerado[:capacidades] + gerado[:extras]).map { |item| [item[:id], item[:pode]] })
      .to all(satisfy { |_id, pode| pode == false })
  end

  it 'recusa fonte que não é do dono citado (método herdado ou sobrescrito por outro módulo)' do
    expect { described_class.arquivo_da('Crm::CardPolicy#update?') }
      .to raise_error(ArgumentError, 'Crm::CardPolicy não tem update? próprio (é de Enterprise::Crm::CardPolicy)')
  end
end
