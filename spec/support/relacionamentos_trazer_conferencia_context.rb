# #2896: o que os specs da conferência de "Trazer minha lista" têm em comum: a conta, a planilha, as linhas com
# problema e os pedidos da tela (ler, responder, trocar coluna, consertar, deixar de fora, voltar atrás, trazer).
RSpec.shared_context 'with trazer conferencia' do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos/trazer" }
  let(:ligadas) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }
  let(:variaveis) { ligadas }
  # Colunas: 0 Nome, 1 Celular, 2 E-mail, 3 Empresa, 4 Cidade, 5 Cliente?, 6 Fone 2.
  let(:planilha) do
    <<~CSV
      Nome;Celular;E-mail;Empresa;Cidade;Cliente?;Fone 2
      Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br;Padaria Bom Dia;Campinas;Sim;1133330001
      Bruno Brandolim;11987650002;bruno.brandolim@exemplo.com.br;;Santos;não;
      Carla Carvalhedo;11987650003;;;;X;
    CSV
  end
  let(:valores_da_planilha) { %w[11987650001 11987650002 11987650003 ana.albuquerino bruno.brandolim 1133330001] }

  around { |example| with_modified_env(variaveis) { example.run } }

  before { account.enable_features!('relacionamentos_novo', 'companies') }

  def cabecalhos(quem)
    quem.create_new_auth_token
  end

  def arquivo(texto, nome: 'Clientes 2025.csv')
    temporario = Tempfile.new(['lista', File.extname(nome)])
    temporario.write(texto)
    temporario.rewind
    Rack::Test::UploadedFile.new(temporario.path, 'text/csv', original_filename: nome)
  end

  # Envia e deixa a leitura terminar, como o job faz em segundo plano.
  def ler_planilha(texto = planilha, conta: account, quem: admin)
    perform_enqueued_jobs(only: CampaignImports::ValidateJob) do
      post "/api/v1/accounts/#{conta.id}/relacionamentos/trazer/leituras", params: { arquivo: arquivo(texto) }, headers: cabecalhos(quem)
    end
    conta.campaign_imports.order(:id).last
  end

  def ler(importacao, quem: admin)
    get "#{base}/leituras/#{importacao.id}", headers: cabecalhos(quem)
    response.parsed_body
  end

  def responder(importacao, quem: admin, **respostas)
    patch "#{base}/leituras/#{importacao.id}/respostas", params: respostas, headers: cabecalhos(quem), as: :json
  end

  def trocar(importacao, indice, quem: admin, **pedido)
    patch "#{base}/leituras/#{importacao.id}/colunas/#{indice}", params: pedido, headers: cabecalhos(quem), as: :json
  end

  def ler_de_novo
    perform_enqueued_jobs(only: CampaignImports::ValidateJob)
  end

  def agente(permissoes: nil)
    pessoa = create(:user, account: account, role: :agent)
    pessoa.account_users.first.update!(custom_role: create(:custom_role, account: account, permissions: permissoes)) if permissoes
    pessoa
  end

  # Colunas: 0 Nome, 1 Celular, 2 E-mail. Linhas com problema: 4 telefone, 5 e-mail, 6 sem nome, 7 sem contato, 8 repetida.
  let(:com_problemas) do
    <<~CSV
      Nome;Celular;E-mail;Plano
      Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br;Ouro
      Bruno Brandolim;11987650002;;Prata
      Carla Carvalhedo;(11) 2345-678;;Bronze
      Davi Dornelino;;davi.dornelino.exemplo.com.br;
      ;11987650005;;
      Elisa Esteveira;;;
      Ana Outra;11987650001;;
    CSV
  end

  def consertar(importacao, linha, quem: admin, **pedido)
    patch "#{base}/leituras/#{importacao.id}/linhas/#{linha}", params: pedido, headers: cabecalhos(quem), as: :json
  end

  def deixar_de_fora(importacao, linha, quem: admin)
    post "#{base}/leituras/#{importacao.id}/linhas/#{linha}/deixar_de_fora", headers: cabecalhos(quem)
  end

  def reabrir(importacao, linha, quem: admin)
    post "#{base}/leituras/#{importacao.id}/linhas/#{linha}/reabrir", headers: cabecalhos(quem)
  end

  def trazer(importacao, quem: admin)
    post "#{base}/leituras/#{importacao.id}/trazer", headers: cabecalhos(quem)
  end

  def estados(importacao)
    ler(importacao)['problemas'].to_h { |problema| [problema['linha'], problema['estado']] }
  end

  def conferido(importacao)
    CampaignImports::NormalizedRows.new(importacao.reload).perform.map { |linha| linha.slice(:row_number, :name, :phone_number, :email) }
  end

  # { linha => [o que foi consertado, o que a pessoa digitou, a linha como vai entrar] } do arquivo dos consertos.
  def consertos(importacao)
    ContactImports::Trazer::Consertos.new(importacao.reload).ler.transform_values do |feito|
      [feito['campo'], feito['valores'], feito['conferida']&.slice('name', 'phone_number', 'email')]
    end
  end

  # O que os dois jobs do "Trazer" fazem em segundo plano: fechar a conferência e gravar a lista.
  def gravar_a_lista
    perform_enqueued_jobs(only: ContactImports::Trazer::FecharConferenciaJob)
    perform_enqueued_jobs(only: CampaignImports::ImportJob)
  end
end
