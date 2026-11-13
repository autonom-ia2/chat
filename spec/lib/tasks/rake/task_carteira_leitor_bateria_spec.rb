require 'rake'
require 'rails_helper'

# E6 (#2899): a bateria paga do leitor de apólice fica desligada por padrão. Aqui o modelo é sempre um dublê: nenhuma
# chamada paga sai deste arquivo. Os PDFs e o gabarito são os fictícios de spec/fixtures/carteira.
RSpec.describe Rake::Task do
  subject(:task) { described_class['carteira:leitor:bateria'] }

  let(:processadores) { Autonomia::Agents::Knowledge::Processors }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:sem_resposta) { Carteira::Leitor::Campos.schema[:schema][:required].index_with { nil } }
  let(:da_seguradora) { { 'e_apolice' => true, 'seguradora' => 'SEGURADORA EXEMPLO S.A.' } }
  # O que um modelo que acerta responderia para cada PDF, achado por um trecho que só aquele PDF tem.
  let(:respostas) do
    {
      'EX-2026.001234' => da_seguradora.merge(
        'tipo' => 'auto', 'ramo' => '0531 - Automóvel - Casco', 'numero' => 'EX-2026.001234', 'inicio_vigencia' => '2026-11-12',
        'fim_vigencia' => '2027-11-12', 'valor_centavos' => 225_498, 'bem' => 'Veículo Modelo Exemplo 1.0 Ano: 2024 Placa: EXM0A00',
        'corretora' => 'Corretora Amostra de Seguros Ltda.', 'segurado_nome' => 'Marina Exemplo de Souza',
        'segurado_documento' => '123.456.789-00', 'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
        'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1
      ),
      # O contato da vistoria está numa página sem o CNPJ: um modelo que o desse como do segurado é barrado pelo leitor.
      '77.0118.0005678' => da_seguradora.merge(
        'tipo' => 'empresarial', 'ramo' => '0118 - Compreensivo Empresarial', 'numero' => '77.0118.0005678',
        'inicio_vigencia' => '2027-01-01', 'fim_vigencia' => '2028-01-01', 'valor_centavos' => 500_000,
        'bem' => 'Avenida do Exemplo, 250 - Bairro Modelo', 'corretora' => 'Corretora Amostra de Seguros Ltda.',
        'segurado_nome' => 'Padaria Amostra Ltda.', 'segurado_documento' => '12.345.678/0001-00',
        'segurado_telefone' => '(11) 98888-0005', 'segurado_telefone_pagina' => 2,
        'segurado_email' => 'vistoria@exemplo.invalid', 'segurado_email_pagina' => 2
      ),
      # Na página do CPF só há o contato do corretor e o 0800: o modelo que acerta não devolve contato do segurado.
      'EX-2026.004455' => da_seguradora.merge(
        'tipo' => 'auto', 'numero' => 'EX-2026.004455', 'inicio_vigencia' => '2027-01-05', 'fim_vigencia' => '2028-01-05',
        'valor_centavos' => 312_050, 'bem' => 'Veículo Exemplo Sedan 2.0 2025 Placa EXM1B11',
        'corretora' => 'Corretora Amostra de Seguros Ltda.', 'segurado_nome' => 'Bruno Amostra Pereira',
        'segurado_documento' => '222.333.444-00'
      ),
      'COMUNICADO DE ASSEMBLEIA' => { 'e_apolice' => false },
      'VD-0093.004321' => da_seguradora.merge(
        'tipo' => 'vida', 'numero' => 'VD-0093.004321', 'inicio_vigencia' => '2026-03-15', 'fim_vigencia' => '2027-03-15',
        'valor_centavos' => 138_000, 'segurado_nome' => 'Paulo Modelo Ferreira', 'segurado_documento' => '111.222.333-00',
        'segurado_telefone' => '(21) 97777-0007', 'segurado_telefone_pagina' => 1,
        'segurado_email' => 'paulo.modelo@exemplo.invalid', 'segurado_email_pagina' => 1
      )
    }
  end
  let(:texto_do_ocr) do
    "SEGURADORA EXEMPLO S.A.\nAPOLICE DE SEGURO DE VIDA INDIVIDUAL\nApolice n: VD-0093.004321\nVigencia: 15/03/2026 a 15/03/2027\n" \
      "Nome: Paulo Modelo Ferreira CPF: 111.222.333-00\nTelefone: (21) 97777-0007 E-mail: paulo.modelo@exemplo.invalid\n" \
      'Premio total anual: R$ 1.380,00'
  end

  before do
    Rails.application.load_tasks unless described_class.task_defined?('carteira:leitor:bateria')
    task.reenable
    allow(Crm::Ai::ResponsesClient).to receive(:new)
    allow(processadores::Rasterizacao).to receive(:pagina) { |_pdf, _indice, **_opcoes, &bloco| bloco.call('pagina.png') }
    allow(processadores::Ocr).to receive(:ler).and_return(texto_do_ocr)
  end

  def modelo_acerta(usage: {})
    allow(cliente).to receive(:create) do |**opcoes|
      _trecho, resposta = respostas.find { |trecho, _resposta| opcoes[:input].include?(trecho) }
      { text: sem_resposta.merge(resposta).to_json, usage: usage }
    end
  end

  # O contato vai como o leitor o entrega: a confirmar, fora dos campos.
  def resultado(campos)
    Carteira::Leitor::Resultado.lido(campos: campos, a_confirmar: campos.slice(*Carteira::Leitor::Resultado::CONTATO), paginas_total: 2,
                                     paginas_enviadas: [1, 2])
  end

  describe 'desligada por padrão' do
    let(:inteira) { { AUTONOMIA_EVAL_PAGO: '1', CARTEIRA_LEITOR_BATERIA: '1', OPENAI_API_KEY: 'chave-de-desenvolvimento', CI: nil } }

    it 'sem as variáveis, a tarefa para antes de criar o cliente e diz como ligar' do
      with_modified_env(AUTONOMIA_EVAL_PAGO: nil, CARTEIRA_LEITOR_BATERIA: nil, OPENAI_API_KEY: nil, CI: nil) do
        expect { expect { task.invoke }.to raise_error(SystemExit) }.to output(a_string_including('Bateria desligada')).to_stderr
      end
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'só liga com as duas variáveis em 1 e a chave: faltando qualquer uma, segue desligada' do
      ligar = inteira.except(:CI)
      tentativas = ligar.keys.map { |falta| inteira.merge(falta => nil) } + [inteira.merge(CARTEIRA_LEITOR_BATERIA: 'true'), inteira]

      ligadas = tentativas.map { |ambiente| with_modified_env(ambiente) { CarteiraLeitorBateria.ligada? } }

      expect(ligadas).to eq([false, false, false, false, true])
    end

    it 'fora da tarefa, quem não passa um cliente também não chega ao modelo com a bateria desligada' do
      with_modified_env(AUTONOMIA_EVAL_PAGO: nil, CARTEIRA_LEITOR_BATERIA: nil, OPENAI_API_KEY: nil, CI: nil) do
        expect { CarteiraLeitorBateria.new }.to raise_error(ArgumentError)
      end
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    # Segunda revisão: sem nova tentativa, o teto de gasto conta uma chamada por caso.
    it 'ligada, o cliente de verdade nasce com a chave do ambiente e sem nova tentativa' do
      with_modified_env(inteira) { CarteiraLeitorBateria.new }

      credencial = hash_including(api_key: 'chave-de-desenvolvimento', source: :bateria)
      expect(Crm::Ai::ResponsesClient).to have_received(:new).once.with(credential: credencial, max_retries: 0)
    end

    # Achado J da revisão: em produção a chave seria a de produção, e na CI ninguém aprovou o gasto.
    it 'na CI, a tarefa para mesmo com tudo ligado, e quem não passa um cliente não chega ao modelo' do
      with_modified_env(inteira.merge(CI: 'true')) do
        expect(CarteiraLeitorBateria.ligada?).to be(false)
        expect { expect { task.invoke }.to raise_error(SystemExit) }.to output(a_string_including('não roda em produção nem na CI')).to_stderr
        expect { CarteiraLeitorBateria.new }.to raise_error(ArgumentError, CarteiraLeitorBateria::PROIBIDA)
      end
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'em produção, a tarefa para mesmo com tudo ligado, e quem não passa um cliente não chega ao modelo' do
      allow(Rails.env).to receive(:production?).and_return(true)

      with_modified_env(inteira) do
        expect(CarteiraLeitorBateria.ligada?).to be(false)
        expect { expect { task.invoke }.to raise_error(SystemExit) }.to output(a_string_including('não roda em produção nem na CI')).to_stderr
        expect { CarteiraLeitorBateria.new }.to raise_error(ArgumentError, CarteiraLeitorBateria::PROIBIDA)
      end
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end
  end

  it 'com o modelo acertando, o leitor passa no gabarito inteiro, sem gravar conta nem uso de IA' do
    modelo_acerta
    saida = StringIO.new
    bateria = CarteiraLeitorBateria.new(cliente: cliente)

    expect { expect(bateria.rodar(saida: saida)).to be(true) }.to not_change(Account, :count).and not_change(Crm::AiUsageEvent, :count)

    expect(saida.string).to include('5 casos.', 'Campos errados: 0 (o aceite é 0).', 'Campos em "não achei" que o gabarito tinha: 0.')
    expect(saida.string).not_to include('ERRADO')
    expect(cliente).to have_received(:create).exactly(5).times
  end

  # O que a conferência de valor não separa (o contato do corretor está escrito por inteiro na página do CPF), o
  # gabarito pega: o modelo que der o contato do corretor como do segurado reprova a bateria.
  it 'reprova a bateria quando o modelo dá o contato do corretor, que está na página do CPF, como do segurado' do
    respostas['EX-2026.004455'].merge!('segurado_telefone' => '(11) 3000-0002', 'segurado_telefone_pagina' => 1,
                                       'segurado_email' => 'contato@corretora-amostra.invalid', 'segurado_email_pagina' => 1)
    modelo_acerta
    saida = StringIO.new

    expect(CarteiraLeitorBateria.new(cliente: cliente).rodar(saida: saida)).to be(false)
    expect(saida.string).to include('errados: segurado_telefone, segurado_email', 'Campos errados: 2 (o aceite é 0).')
  end

  it 'a saída traz só nomes de campo e contagens, nada do que foi lido' do
    modelo_acerta
    saida = StringIO.new

    CarteiraLeitorBateria.new(cliente: cliente).rodar(saida: saida)

    lidos = ['Marina', '123.456.789-00', '12345678900', '99999-0001', '11999990001', 'exemplo.invalid', 'EX-2026.001234']
    expect(lidos.none? { |valor| saida.string.include?(valor) }).to be(true)
  end

  describe 'a régua' do
    let(:caso) do
      { 'recusa' => nil, 'paginas_enviadas' => [1, 2],
        'campos' => { 'numero' => 'EX-2026.001234', 'valor_centavos' => 225_498, 'segurado_telefone' => nil, 'bem' => { 'contem' => ['EXM0A00'] },
                      'seguradora' => 'Seguradora Exemplo S.A.' } }
    end

    it 'certo: igual ao gabarito na forma de comparação, e o trecho pedido dentro do valor' do
      lido = resultado('numero' => 'ex 2026 001234', 'valor_centavos' => 225_498, 'bem' => 'Veículo placa EXM0A00',
                       'seguradora' => 'SEGURADORA EXEMPLO SA')

      expect(CarteiraLeitorBateria.conferir(caso, lido)).to eq(errados: [], nao_achou: [])
    end

    it 'errado: valor diferente do gabarito, e valor onde o gabarito diz que não pode haver' do
      lido = resultado('numero' => 'EX-2026.001235', 'valor_centavos' => 37_583, 'segurado_telefone' => '1130000002', 'bem' => 'Veículo',
                       'seguradora' => 'Seguradora Exemplo S.A.')

      expect(CarteiraLeitorBateria.conferir(caso, lido)).to eq(errados: %w[numero valor_centavos segurado_telefone bem], nao_achou: [])
    end

    it '"não achei" onde o gabarito tinha valor não é erro: é contado à parte' do
      expect(CarteiraLeitorBateria.conferir(caso, resultado('numero' => 'EX-2026.001234')))
        .to eq(errados: [], nao_achou: %w[valor_centavos bem seguradora])
    end

    it 'o valor que o leitor entrega a confirmar também é medido: certo quando bate, errado quando não' do
      a_confirmar = lambda do |valor|
        Carteira::Leitor::Resultado.lido(campos: { 'numero' => 'EX-2026.001234' }, a_confirmar: { 'valor_centavos' => valor }, paginas_total: 2,
                                         paginas_enviadas: [1, 2])
      end

      expect(CarteiraLeitorBateria.conferir(caso, a_confirmar.call(225_498))).to eq(errados: [], nao_achou: %w[bem seguradora])
      expect(CarteiraLeitorBateria.conferir(caso, a_confirmar.call(125_050))).to eq(errados: ['valor_centavos'], nao_achou: %w[bem seguradora])
    end

    it 'recusa diferente da esperada e páginas diferentes das esperadas são erro' do
      recusado = Carteira::Leitor::Resultado.recusado('nao_e_apolice', paginas_total: 2, paginas_enviadas: [1, 2])
      outras = Carteira::Leitor::Resultado.lido(campos: {}, paginas_total: 9, paginas_enviadas: [1, 2, 3])

      expect(CarteiraLeitorBateria.conferir(caso, recusado)).to eq(errados: ['recusa'], nao_achou: [])
      expect(CarteiraLeitorBateria.conferir(caso, outras)[:errados]).to eq(['paginas_enviadas'])
      expect(CarteiraLeitorBateria.conferir({ 'recusa' => 'nao_e_apolice' }, recusado)).to eq(errados: [], nao_achou: [])
    end

    it 'reprova a bateria quando o leitor devolve um campo errado' do
      respostas['EX-2026.001234']['valor_centavos'] = 37_583
      modelo_acerta
      saida = StringIO.new

      expect(CarteiraLeitorBateria.new(cliente: cliente).rodar(saida: saida)).to be(false)
      expect(saida.string).to include('ERRADO', 'errados: valor_centavos', 'Campos errados: 1 (o aceite é 0).')
    end
  end

  describe 'o teto de custo' do
    it 'o pior caso estimado da bateria inteira fica muito abaixo do teto' do
      expect(CarteiraLeitorBateria.teto_por_caso * 5).to be_between(0.0001, CarteiraLeitorBateria::TETO_USD / 10)
    end

    it 'para no caso seguinte quando o custo real passa do teto' do
      modelo_acerta(usage: { 'input_tokens' => 50_000_000_000 })

      expect { CarteiraLeitorBateria.new(cliente: cliente).rodar(saida: StringIO.new) }.to raise_error(CarteiraLeitorBateria::EstourouOTeto)
      expect(cliente).to have_received(:create).once
    end
  end
end
