require 'rails_helper'
require 'pdf-reader'

# E6 (#2899): o leitor de apólice em PDF, do arquivo ao resultado. Os PDFs são fictícios (spec/fixtures/carteira,
# gerados por gerar.rb; o de 160 páginas é montado na hora) e o modelo é um dublê que responde no esquema fechado:
# nenhuma chamada paga sai daqui.
RSpec.describe Carteira::Leitor do
  let(:account) { create(:account) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:perguntas) { [] }
  # Todos os campos do esquema em "não achei".
  let(:sem_resposta) { Carteira::Leitor::Campos.schema[:schema][:required].index_with { nil }.merge('e_apolice' => true) }
  let(:do_auto) do
    { 'tipo' => 'auto', 'ramo' => '0531 - Automóvel - Casco', 'seguradora' => 'SEGURADORA EXEMPLO S.A.', 'numero' => 'EX-2026.001234',
      'inicio_vigencia' => '2026-11-12', 'fim_vigencia' => '2027-11-12', 'valor_centavos' => 225_498,
      'bem' => 'Veículo Modelo Exemplo 1.0 Ano: 2024 Placa: EXM0A00', 'corretora' => 'Corretora Amostra de Seguros Ltda.',
      'segurado_nome' => 'Marina Exemplo de Souza', 'segurado_documento' => '123.456.789-00',
      'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
      'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1 }
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    Carteira::Leitor::Liberado.ligar!(account)
  end

  def pdf(nome)
    Rails.root.join('spec/fixtures/carteira', nome).to_s
  end

  def modelo_responde(campos)
    allow(cliente).to receive(:create) do |**opcoes|
      perguntas << opcoes
      { text: sem_resposta.merge(campos).to_json, usage: {} }
    end
  end

  def ler(arquivo, ocr: false, **quem)
    described_class.new(account: account, ocr: ocr).ler(pdf(arquivo), **quem)
  end

  # A apólice de 160 páginas é montada na hora (spec/support/carteira_pdf_longo.rb).
  def ler_a_longa(**quem)
    described_class.new(account: account).ler(CarteiraPdfLongo.caminho, **quem)
  end

  # Os números das páginas que foram na última pergunta ao modelo.
  def paginas_perguntadas
    JSON.parse(perguntas.last[:input])['paginas'].pluck('numero')
  end

  describe 'a chave da conta' do
    it 'desligada: devolve leitura_desligada sem abrir o arquivo e sem chamar o modelo' do
      Carteira::Leitor::Liberado.desligar!(account)
      modelo_responde(do_auto)

      resultado = described_class.new(account: account).ler('/caminho/que/nao/existe.pdf')

      expect(resultado).to have_attributes(recusa: 'leitura_desligada', lido?: false, campos: {}, duvidas: [], paginas_enviadas: [])
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(perguntas).to be_empty
    end

    # Achado H da revisão: quem pergunta ao modelo confere a chave de novo; se ela caiu no meio, nada é pago.
    it 'desligada entre abrir o arquivo e perguntar: devolve leitura_desligada sem chamar o modelo' do
      allow(Carteira::Leitor::Liberado).to receive(:para?).and_return(true, false)
      modelo_responde(do_auto)

      expect(ler('apolice_auto.pdf')).to have_attributes(recusa: 'leitura_desligada', campos: {}, paginas_enviadas: [])
      expect(perguntas).to be_empty
    end

    it 'ligada: lê, pela credencial da conta, com o uso registrado na feature do leitor' do
      modelo_responde(do_auto)

      resultado = ler('apolice_auto.pdf')

      expect(resultado).to be_lido
      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(credential: hash_including(api_key: 'chave-da-conta'), feature: 'carteira_leitor', account: account, max_retries: 1)
      expect(perguntas.last).to include(model: Carteira::Leitor::Campos::MODEL, schema: Carteira::Leitor::Campos.schema,
                                        max_output_tokens: Carteira::Leitor::Campos::MAX_OUTPUT_TOKENS)
    end
  end

  it 'devolve cada campo na forma do banco, sem dúvida nenhuma, quando o modelo copia o que está escrito' do
    modelo_responde(do_auto)

    resultado = ler('apolice_auto.pdf')

    expect(resultado.campos).to eq(
      'tipo' => 'auto', 'ramo_original' => '0531 - Automóvel - Casco', 'seguradora' => 'SEGURADORA EXEMPLO S.A.',
      'numero' => 'EX-2026.001234', 'inicio_vigencia' => '2026-11-12', 'fim_vigencia' => '2027-11-12', 'valor_centavos' => 225_498,
      'bem' => 'Veículo Modelo Exemplo 1.0 Ano: 2024 Placa: EXM0A00', 'corretora' => 'Corretora Amostra de Seguros Ltda.',
      'segurado_nome' => 'Marina Exemplo de Souza', 'segurado_documento' => '12345678900'
    )
    expect(resultado).to have_attributes(recusa: nil, duvidas: [], a_confirmar: %w[segurado_telefone segurado_email], paginas_total: 2,
                                         paginas_enviadas: [1, 2])
    expect(resultado.dados_da_apolice).to include(seguradora_chave: 'seguradoraexemplosa', numero_chave: 'EX2026001234', tipo: 'auto',
                                                  valor_centavos: 225_498)
  end

  # Segunda revisão, alto 3: telefone e e-mail só valem depois de uma pessoa confirmar, então não podem estar onde quem
  # grava iterando os campos os alcança.
  it 'o telefone e o e-mail saem só em valores_a_confirmar: nem em campos, nem nos dados da apólice' do
    modelo_responde(do_auto)

    resultado = ler('apolice_auto.pdf')

    contato = { 'segurado_telefone' => '11999990001', 'segurado_email' => 'marina.exemplo@exemplo.invalid' }
    expect(resultado.valores_a_confirmar).to eq(contato)
    expect(resultado.campos.keys & contato.keys).to eq([])
    expect(resultado.campos.values + resultado.dados_da_apolice.values).not_to include(*contato.values)
  end

  describe 'nenhum campo errado calado' do
    it 'o que o modelo diz que não achou fica em "não achei" e entra nas dúvidas' do
      modelo_responde(do_auto.merge('bem' => nil, 'valor_centavos' => nil, 'corretora' => nil))

      resultado = ler('apolice_auto.pdf')

      expect(resultado.campos.values_at('bem', 'valor_centavos', 'corretora')).to eq([nil, nil, nil])
      expect(resultado.duvidas).to eq(%w[valor_centavos bem corretora])
      expect(resultado.campos).to include('numero' => 'EX-2026.001234')
      expect(resultado.valores_a_confirmar).to include('segurado_telefone' => '11999990001')
    end

    it 'o valor que o modelo devolve e não está escrito nas páginas vira "não achei", nunca é aceito' do
      inventados = { 'tipo' => 'moto', 'seguradora' => 'Seguradora Inventada', 'numero' => 'EX-2026.009999', 'inicio_vigencia' => '12/11/2026',
                     'fim_vigencia' => '2027-12-31', 'valor_centavos' => 999_999, 'bem' => 'Caminhão Fantasma',
                     'corretora' => 'Corretora Que Não Existe', 'segurado_nome' => 'Fulano Trocado', 'segurado_documento' => '999.888.777-66' }
      modelo_responde(do_auto.merge(inventados))

      resultado = ler('apolice_auto.pdf')

      nomes = %w[tipo seguradora numero inicio_vigencia fim_vigencia valor_centavos bem corretora segurado_nome segurado_documento]
      expect(resultado.campos.slice(*nomes).values).to all(be_nil)
      expect(resultado.duvidas).to include(*nomes)
      expect(resultado.campos['ramo_original']).to eq('0531 - Automóvel - Casco')
      expect(resultado).to be_lido
    end

    # Achados A, B e C da revisão: um pedaço do que está escrito não é o valor escrito.
    it 'um pedaço do número, do prêmio ou de uma palavra, e a frase montada com pedaços de lugares diferentes, viram "não achei"' do
      pedacos = { 'numero' => '001234', 'valor_centavos' => 2254, 'segurado_nome' => 'Marina Exemplo Souza', 'corretora' => 'Amostra de Seguro',
                  'bem' => 'Veículo Modelo Exemplo Placa EXM0A00' }
      modelo_responde(do_auto.merge(pedacos))

      resultado = ler('apolice_auto.pdf')

      expect(resultado.campos.slice(*pedacos.keys).values).to all(be_nil)
      expect(resultado.duvidas).to eq(%w[numero valor_centavos bem corretora segurado_nome])
    end

    it 'valor que não é número inteiro de centavos não passa' do
      [2254.98, '225498', 0, -225_498].each do |valor|
        modelo_responde(do_auto.merge('valor_centavos' => valor))

        expect(ler('apolice_auto.pdf').campos['valor_centavos']).to be_nil
      end
    end
  end

  describe 'telefone e e-mail só da página do CPF/CNPJ do segurado' do
    let(:da_empresa) do
      { 'tipo' => 'empresarial', 'numero' => '77.0118.0005678', 'segurado_nome' => 'Padaria Amostra Ltda.',
        'segurado_documento' => '12.345.678/0001-00' }
    end

    it 'aceita o contato que está escrito na página em que o documento do segurado aparece' do
      modelo_responde(do_auto)

      expect(ler('apolice_auto.pdf').valores_a_confirmar)
        .to eq('segurado_telefone' => '11999990001', 'segurado_email' => 'marina.exemplo@exemplo.invalid')
    end

    it 'recusa o contato de uma página em que o documento do segurado não aparece' do
      modelo_responde(da_empresa.merge('segurado_telefone' => '(11) 98888-0005', 'segurado_telefone_pagina' => 2,
                                       'segurado_email' => 'vistoria@exemplo.invalid', 'segurado_email_pagina' => 2))

      resultado = ler('apolice_empresarial.pdf')

      expect(resultado.campos).to include('segurado_documento' => '12345678000100')
      expect(resultado.valores_a_confirmar).to eq({})
      expect(resultado.duvidas).to include('segurado_telefone', 'segurado_email')
    end

    it 'recusa o contato que o modelo põe na página do documento, mas que não está escrito nela' do
      modelo_responde(da_empresa.merge('segurado_telefone' => '(11) 98888-0005', 'segurado_telefone_pagina' => 1,
                                       'segurado_email' => 'vistoria@exemplo.invalid', 'segurado_email_pagina' => 1))

      expect(ler('apolice_empresarial.pdf').valores_a_confirmar).to eq({})
    end

    it 'sem o documento do segurado conferido não há contato, mesmo que o telefone esteja escrito' do
      [nil, '999.888.777-66'].each do |documento|
        modelo_responde(do_auto.merge('segurado_documento' => documento))

        expect(ler('apolice_auto.pdf')).to have_attributes(valores_a_confirmar: {}, campos: hash_including('segurado_documento' => nil))
      end
    end

    # Achados D e E da revisão.
    it 'recusa o 0800, o CPF devolvido como telefone, o DDD trocado e o pedaço de um e-mail, mesmo na página do CPF' do
      tentativas = [{ 'segurado_telefone' => '0800 000 0003' }, { 'segurado_telefone' => '123.456.789-00' },
                    { 'segurado_telefone' => '(21) 99999-0001' }, { 'segurado_telefone' => '99999-0001' },
                    { 'segurado_email' => 'exemplo@exemplo.invalid' }, { 'segurado_email' => 'marina.exemplo@exemplo.inv' }]

      tentativas.each do |campos|
        modelo_responde(do_auto.merge(campos))

        expect(ler('apolice_auto.pdf').valores_a_confirmar[campos.keys.first]).to be_nil
      end
    end

    # A decisão de produto dos achados D e E: o contato do corretor está escrito por inteiro na página do CPF, e nenhuma
    # conferência de valor o separa do contato do segurado. Por isso o que passa nunca é dado por certo.
    it 'o contato que passa sai como "a confirmar", nunca como dúvida, e o que não passa sai só como dúvida' do
      modelo_responde(do_auto.merge('segurado_telefone' => '(11) 3000-0002', 'segurado_email' => nil))

      resultado = ler('apolice_auto.pdf')

      expect(resultado.valores_a_confirmar).to eq('segurado_telefone' => '1130000002')
      expect(resultado).to have_attributes(a_confirmar: ['segurado_telefone'], duvidas: ['segurado_email'])
    end

    it 'recusa telefone inventado, com dígitos de menos e página que não foi enviada' do
      tentativas = [{ 'segurado_telefone' => '(11) 91234-5678' }, { 'segurado_telefone' => '9999-0001' }, { 'segurado_telefone_pagina' => 7 },
                    { 'segurado_telefone_pagina' => nil }, { 'segurado_telefone_pagina' => '1' }]

      tentativas.each do |campos|
        modelo_responde(do_auto.merge(campos))

        expect(ler('apolice_auto.pdf').valores_a_confirmar['segurado_telefone']).to be_nil
      end
    end
  end

  describe 'só as páginas escolhidas vão ao modelo' do
    it 'PDF de 160 páginas não manda 160 páginas: sem saber quem é o segurado, vão as primeiras' do
      modelo_responde('tipo' => 'residencial')

      resultado = ler_a_longa

      expect(perguntas.size).to eq(1)
      expect(paginas_perguntadas).to eq([1, 2, 3, 4])
      expect(resultado).to have_attributes(paginas_total: 160, paginas_enviadas: [1, 2, 3, 4])
    end

    # Achado I da revisão.
    it 'sabendo o CPF, vão só as páginas em que ele aparece, mesmo a última, e as vizinhas de cada uma' do
      modelo_responde('tipo' => 'residencial')

      resultado = ler_a_longa(documento: '987.654.321-99')

      expect(paginas_perguntadas).to eq([1, 2, 3, 159, 160])
      expect(resultado.paginas_enviadas).to eq([1, 2, 3, 159, 160])
    end

    it 'lê a apólice longa pelas primeiras páginas, com o contato da página 2, onde o CPF também está' do
      modelo_responde('tipo' => 'residencial', 'seguradora' => 'SEGURADORA EXEMPLO S.A.', 'numero' => 'RS-0114.000777',
                      'inicio_vigencia' => '2027-02-01', 'fim_vigencia' => '2028-02-01', 'valor_centavos' => 89_040,
                      'bem' => 'Rua do Modelo, 45, apto 12 - Bairro Exemplo', 'segurado_nome' => 'Renata Amostra Lima',
                      'segurado_documento' => '987.654.321-99', 'segurado_telefone' => '(31) 96666-0008', 'segurado_telefone_pagina' => 2,
                      'segurado_email' => 'renata.amostra@exemplo.invalid', 'segurado_email_pagina' => 2)

      resultado = ler_a_longa

      expect(resultado.campos).to include('numero' => 'RS-0114.000777', 'inicio_vigencia' => '2027-02-01', 'fim_vigencia' => '2028-02-01',
                                          'valor_centavos' => 89_040, 'bem' => 'Rua do Modelo, 45, apto 12 - Bairro Exemplo',
                                          'segurado_documento' => '98765432199')
      expect(resultado.valores_a_confirmar).to eq('segurado_telefone' => '31966660008', 'segurado_email' => 'renata.amostra@exemplo.invalid')
      expect(resultado.duvidas).to eq(%w[ramo_original corretora])
    end

    it 'sem o CPF, mas com o nome, vão as páginas em que o nome aparece' do
      modelo_responde('tipo' => 'residencial')

      ler_a_longa(nome: 'RENATA amostra Lima')

      expect(paginas_perguntadas).to eq([1, 2, 160])
    end
  end

  it 'PDF que não é apólice é recusado com nao_e_apolice, sem campo nenhum' do
    modelo_responde('e_apolice' => false, 'seguradora' => 'CONDOMÍNIO EDIFÍCIO EXEMPLO')

    resultado = ler('nao_e_apolice.pdf')

    expect(resultado).to have_attributes(recusa: 'nao_e_apolice', lido?: false, campos: {}, duvidas: [], paginas_total: 1,
                                         paginas_enviadas: [1])
  end

  describe 'falha do modelo' do
    let(:respostas_ruins) do
      [{ text: 'isto não é JSON', usage: {} }, { text: '["lista"]', usage: {} }, { text: { 'e_apolice' => 'sim' }.to_json, usage: {} },
       { text: do_auto.merge('e_apolice' => true).to_json, usage: {}, incomplete_reason: 'max_output_tokens' }]
    end
    let(:quebras) do
      [Crm::Ai::ResponsesClient::Error.new('network_timeout: read_timeout', rede: true, tempo_esgotado: true),
       Crm::Ai::ResponsesClient::Error.new('empty_response'), OpenSSL::SSL::SSLError.new('conexão caiu')]
    end

    it 'vira nao_deu_para_ler e não levanta: erro de rede, resposta vazia, cortada ou fora do esquema' do
      falhas = respostas_ruins.map { |resposta| -> { allow(cliente).to receive(:create).and_return(resposta) } } +
               quebras.map { |erro| -> { allow(cliente).to receive(:create).and_raise(erro) } }

      falhas.each do |preparar|
        preparar.call

        expect(ler('apolice_auto.pdf')).to have_attributes(recusa: 'nao_deu_para_ler', motivo: :modelo_falhou, campos: {},
                                                           paginas_total: 2, paginas_enviadas: [1, 2])
      end
    end

    # Segunda revisão, alto 4: defeito nosso não vira "o modelo falhou"; sobe.
    it 'erro de programação dentro da pergunta ao modelo sobe, não vira nao_deu_para_ler' do
      allow(cliente).to receive(:create).and_raise(NoMethodError)

      expect { ler('apolice_auto.pdf') }.to raise_error(NoMethodError)
    end

    it 'o log leva só a conta, o motivo e a contagem de páginas: nada do PDF nem da mensagem do erro' do
      allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('Marina Exemplo de Souza 123.456.789-00'))
      allow(Rails.logger).to receive(:warn)

      ler('apolice_auto.pdf')

      expect(Rails.logger).to have_received(:warn).once
      expect(Rails.logger).to have_received(:warn).with("[carteira][leitor] account_id=#{account.id} nao_deu_para_ler motivo=modelo_falhou paginas=2")
    end
  end

  describe 'o que não chega ao modelo' do
    it 'conta sem a IA configurada: nao_deu_para_ler, sem cliente' do
      Integrations::Hook.where(account_id: account.id).destroy_all

      expect(ler('apolice_auto.pdf')).to have_attributes(recusa: 'nao_deu_para_ler', motivo: :sem_ia, paginas_total: 2, paginas_enviadas: [])
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'arquivo que não é PDF, ou PDF quebrado: nao_deu_para_ler' do
      modelo_responde(do_auto)

      ['só texto, sem cabeçalho de PDF', '%PDF-1.4 e depois lixo'].each do |conteudo|
        Tempfile.create(['arquivo', '.pdf']) do |arquivo|
          arquivo.write(conteudo)
          arquivo.flush

          expect(described_class.new(account: account).ler(arquivo.path)).to have_attributes(recusa: 'nao_deu_para_ler', motivo: :pdf_ilegivel)
        end
      end
      expect(perguntas).to be_empty
    end

    # Achado F da revisão: nenhum arquivo ruim faz o leitor levantar.
    it 'caminho que não existe e PDF com senha: nao_deu_para_ler, sem levantar' do
      modelo_responde(do_auto)
      ilegivel = { recusa: 'nao_deu_para_ler', motivo: :pdf_ilegivel, paginas_total: nil, paginas_enviadas: [] }

      Tempfile.create(['com_senha', '.pdf']) do |com_senha|
        Prawn::Document.generate(com_senha.path) do |documento|
          documento.encrypt_document(user_password: 'senha-de-exemplo', owner_password: 'outra-senha-de-exemplo')
          documento.text 'Apólice com senha de abertura'
        end

        expect(described_class.new(account: account).ler(com_senha.path)).to have_attributes(ilegivel)
      end
      expect(described_class.new(account: account).ler('/caminho/que/nao/existe.pdf')).to have_attributes(ilegivel)
      expect(perguntas).to be_empty
    end

    it 'erro que o leitor de PDF não previu: nao_deu_para_ler, sem levantar, com a classe do erro no registro' do
      modelo_responde(do_auto)
      allow(PDF::Reader).to receive(:new).and_raise(NoMethodError, 'Marina Exemplo de Souza')
      allow(Rails.logger).to receive(:warn)

      expect(ler('apolice_auto.pdf')).to have_attributes(recusa: 'nao_deu_para_ler', motivo: :pdf_ilegivel)
      expect(Rails.logger).to have_received(:warn).with('[carteira][leitor] pdf_nao_abriu NoMethodError')
      expect(Rails.logger).to have_received(:warn).twice
      expect(perguntas).to be_empty
    end

    # Achado G da revisão.
    it 'arquivo maior que o teto: nao_deu_para_ler, sem abrir o PDF' do
      stub_const('Carteira::Leitor::Paginas::MAXIMO_DE_BYTES', 1_000)
      modelo_responde(do_auto)

      expect(ler('apolice_auto.pdf')).to have_attributes(recusa: 'nao_deu_para_ler', motivo: :pdf_ilegivel, paginas_total: nil)
      expect(perguntas).to be_empty
    end
  end

  describe 'página-chave sem texto (PDF escaneado)' do
    let(:processadores) { Autonomia::Agents::Knowledge::Processors }
    let(:texto_do_ocr) do
      "SEGURADORA EXEMPLO S.A.\nAPOLICE DE SEGURO DE VIDA INDIVIDUAL\nApolice n: VD-0093.004321\nVigencia: 15/03/2026 a 15/03/2027\n" \
        "Nome: Paulo Modelo Ferreira CPF: 111.222.333-00\nTelefone: (21) 97777-0007 E-mail: paulo.modelo@exemplo.invalid\n" \
        'Premio total anual: R$ 1.380,00'
    end
    let(:da_vida) do
      { 'tipo' => 'vida', 'numero' => 'VD-0093.004321', 'inicio_vigencia' => '2026-03-15', 'fim_vigencia' => '2027-03-15',
        'valor_centavos' => 138_000, 'segurado_nome' => 'Paulo Modelo Ferreira', 'segurado_documento' => '111.222.333-00',
        'segurado_telefone' => '(21) 97777-0007', 'segurado_telefone_pagina' => 1 }
    end

    before do
      allow(processadores::Rasterizacao).to receive(:pagina) { |_pdf, _indice, **_opcoes, &bloco| bloco.call('pagina.png') }
      allow(processadores::Ocr).to receive(:ler).and_return(texto_do_ocr)
      modelo_responde(da_vida)
    end

    it 'sem OCR (dentro de uma requisição): não lê, não rasteriza e não chama o modelo' do
      expect(ler('apolice_escaneada.pdf')).to have_attributes(recusa: 'nao_deu_para_ler', motivo: :sem_texto, paginas_total: 1)
      expect(processadores::Rasterizacao).not_to have_received(:pagina)
      expect(perguntas).to be_empty
    end

    it 'com OCR (em job): lê só a página escolhida sem texto e confere os campos contra o que o OCR leu' do
      resultado = ler('apolice_escaneada.pdf', ocr: true)

      expect(processadores::Rasterizacao).to have_received(:pagina).once.with(pdf('apolice_escaneada.pdf'), 0)
      expect(resultado.campos).to include('tipo' => 'vida', 'numero' => 'VD-0093.004321', 'fim_vigencia' => '2027-03-15',
                                          'valor_centavos' => 138_000, 'segurado_documento' => '11122233300', 'bem' => nil)
      expect(resultado).to have_attributes(paginas_enviadas: [1], valores_a_confirmar: { 'segurado_telefone' => '21977770007' })
    end
  end
end
