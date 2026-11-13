require 'rails_helper'

# Épico #1240, decisão R1: guardar o CPF e o CNPJ, achar o dono pelo número inteiro e ler o de um dono, dentro da conta.
# Os números são inventados (sequências), válidos só na conta do dígito verificador.
RSpec.describe Relacionamentos::Documentos do
  let(:account) { create(:account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo') }
  let(:oficina) { create(:company, account: account, name: 'Oficina Exemplo') }
  let(:documentos) { described_class.new(account) }
  let(:cpf) { '123.456.789-09' }
  let(:outro_cpf) { '987.654.321-00' }
  let(:cnpj) { '11.222.333/0001-81' }

  shared_examples 'guarda e acha por valor exato' do
    it 'guarda o CPF da pessoa e o CNPJ da empresa e acha cada dono pelo número, com ou sem pontuação' do
      documentos.guardar(marina, cpf)
      documentos.guardar(oficina, cnpj)

      expect([documentos.donos('12345678909'), documentos.donos(cpf), documentos.donos('11222333000181')]).to eq([[marina], [marina], [oficina]])
      expect(documentos.ler(marina).attributes.slice('tipo', 'valor')).to eq('tipo' => 'cpf', 'valor' => '12345678909')
      expect([documentos.ler(marina).formatado, documentos.ler(oficina).mascarado]).to eq(['123.456.789-09', '**.***.***/****-81'])
    end

    it 'só acha pelo número inteiro: pedaço do número e outro número não são de ninguém' do
      documentos.guardar(marina, cpf)

      expect([documentos.donos('123456789'), documentos.donos(outro_cpf), documentos.donos('')]).to eq([[], [], []])
    end

    it 'guardar de novo troca o documento do dono, sem criar outro' do
      documentos.guardar(marina, cpf)
      documentos.guardar(marina, outro_cpf)

      expect(Relacionamentos::Documento.where(contact_id: marina.id).count).to eq(1)
      expect([documentos.donos(cpf), documentos.donos(outro_cpf)]).to eq([[], [marina]])
    end

    it 'o mesmo número em dois cadastros da conta devolve os dois, na ordem em que os documentos entraram' do
      repetida = create(:contact, account: account, name: 'Marina E.')
      documentos.guardar(marina, cpf)
      documentos.guardar(repetida, cpf)

      expect(documentos.donos(cpf)).to eq([marina, repetida])
    end

    it 'a pessoa pode ter CPF e CNPJ; sem dizer o tipo, lê o CPF da pessoa e o CNPJ da empresa' do
      documentos.guardar(marina, cpf)
      documentos.guardar(marina, cnpj)
      documentos.guardar(oficina, cnpj)

      expect([documentos.ler(marina).tipo, documentos.ler(marina, tipo: 'cnpj').tipo, documentos.ler(oficina).tipo]).to eq(%w[cpf cnpj cnpj])
      expect([documentos.ler(oficina, tipo: 'cpf'), documentos.donos(cnpj)]).to eq([nil, [marina, oficina]])
    end
  end

  context 'when a cifra está ligada (as três variáveis ACTIVE_RECORD_ENCRYPTION_* presentes)' do
    include_context 'with o model do documento recarregado'

    before { carregar_o_documento(com_cifra: true) }

    it_behaves_like 'guarda e acha por valor exato'

    it 'grava o número cifrado, e o mesmo número vira sempre o mesmo texto cifrado' do
      repetida = create(:contact, account: account, name: 'Marina E.')
      gravados = [documentos.guardar(marina, cpf), documentos.guardar(repetida, cpf)].map { |documento| valor_no_banco(documento) }

      expect(Relacionamentos::Documento.encrypted_attributes.to_a).to eq([:valor])
      expect(gravados.first).not_to include('12345678909')
      expect(gravados.uniq.size).to eq(1)
    end

    # A instalação que guardou documento sem as chaves e passou a tê-las depois: a linha antiga segue em texto puro. O
    # `extend_queries` do Rails, ligado junto com as chaves em config/application.rb, faz a busca procurar as duas formas.
    it 'lê e acha pelo número também o documento gravado em texto puro antes de as chaves existirem' do
      antiga = create(:contact, account: account, name: 'Marina E.')
      documentos.guardar(marina, cpf)
      gravar_em_texto_puro(documentos.guardar(antiga, cpf), '12345678909')

      expect(Relacionamentos::Documento.order(:id).map { |documento| valor_no_banco(documento) == '12345678909' }).to eq([false, true])
      expect(documentos.donos(cpf)).to eq([marina, antiga])
      expect(documentos.ler(antiga).valor).to eq('12345678909')
    end

    # Guardar e ler nunca levam o número em claro para a consulta. A busca (`donos`) fica de fora: com o `extend_queries`
    # ela procura também a forma em texto puro, que vai na consulta, e escondê-la no log de consultas depende do filtro
    # do ActiveRecord::Base, que este PR não mexe (o `filter_attributes` do model só cobre o `inspect`).
    it 'guardar e ler não põem o número nem no log de consultas, o nível mais falador' do
      marina
      escrito = log_de(:debug) do
        documentos.guardar(marina, cpf)
        documentos.ler(marina)
      end

      expect(escrito).to include('relacionamentos_documentos')
      expect(escrito).not_to include('12345678909', '123.456.789-09')
    end
  end

  context 'when a cifra está desligada (sem as variáveis)' do
    include_context 'with o model do documento recarregado'

    before { carregar_o_documento(com_cifra: false) }

    it_behaves_like 'guarda e acha por valor exato'

    it 'grava a forma de comparação em texto puro' do
      expect(valor_no_banco(documentos.guardar(marina, cpf))).to eq('12345678909')
      expect(Relacionamentos::Documento.encrypted_attributes.to_a).to eq([])
    end

    # O log de consultas (debug) fica de fora aqui: sem cifra, o valor vai na consulta como o de qualquer outra coluna,
    # e escondê-lo ali depende do filtro do ActiveRecord::Base, que este PR não mexe (o `filter_attributes` do model só
    # cobre o `inspect`). A produção registra a partir de info.
    it 'no nível de log da produção, nada do que o serviço faz traz o número' do
      marina
      escrito = log_de(:info) do
        documentos.guardar(marina, cpf)
        documentos.donos(cpf)
        documentos.ler(marina)
      end

      expect(escrito).not_to include('12345678909', '123.456.789-09')
    end
  end

  describe 'isolamento entre contas' do
    let(:outra) { create(:account) }
    let(:de_fora) { create(:contact, account: outra, name: 'Caio Exemplo') }
    let(:documentos_da_outra) { described_class.new(outra) }

    it 'o mesmo número em outra conta não aparece na busca desta, nem o desta na de lá' do
      documentos.guardar(marina, cpf)
      documentos_da_outra.guardar(de_fora, cpf)

      expect([documentos.donos(cpf), documentos_da_outra.donos(cpf)]).to eq([[marina], [de_fora]])
    end

    it 'não lê nem guarda documento de pessoa ou de empresa de outra conta' do
      documentos_da_outra.guardar(de_fora, cpf)
      empresa_de_fora = create(:company, account: outra, name: 'Empresa de Fora')

      expect(documentos.ler(de_fora)).to be_nil
      expect { documentos.guardar(de_fora, outro_cpf) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { documentos.guardar(empresa_de_fora, cnpj) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Relacionamentos::Documento.where(account_id: account.id)).to be_empty
      expect(documentos_da_outra.ler(de_fora).valor).to eq('12345678909')
    end
  end

  describe 'número que não confere' do
    let(:frase) { 'Este CPF ou CNPJ não confere. Confira os números e digite de novo: o CPF tem 11 dígitos e o CNPJ tem 14 caracteres.' }

    it 'é recusado com uma frase que diz o que fazer e não repete o que foi digitado' do
      conferir = lambda do |recusa|
        expect([recusa.codigo, recusa.message, recusa.http_status]).to eq(['invalido', frase, 422])
        expect(recusa.to_hash).to eq(error: 'invalido', message: frase)
        expect(recusa.message + recusa.inspect).not_to include('123', '456', '789', '08')
      end

      I18n.with_locale(:pt_BR) do
        expect { documentos.guardar(marina, '123.456.789-08') }.to raise_error(CustomExceptions::DocumentoRecusa, &conferir)
      end
      expect(Relacionamentos::Documento.count).to eq(0)
    end

    it 'vale para todo texto que não é CPF nem CNPJ, e a busca por ele não acha ninguém' do
      errados = ['', nil, '1234567890', '111.111.111-11', '11.222.333/0001-80', 'não sei o CPF', 'CLI 123.456.789-09', 'CLI123.456.789-09',
                 'CLI12345678909']

      errados.each { |texto| expect { documentos.guardar(marina, texto) }.to raise_error(CustomExceptions::DocumentoRecusa) }
      expect(errados.map { |texto| documentos.donos(texto) }).to all(eq([]))
      expect(Relacionamentos::Documento.count).to eq(0)
    end
  end

  describe 'texto com letra' do
    let(:frase) do
      'Este número tem letras. Se é um CNPJ com letras, escreva com os pontos, a barra e o traço, assim: 12.ABC.345/01DE-35. ' \
        'Se não é, digite só os números.'
    end

    # O rótulo colado no CPF e o CNPJ com letra sem pontuação têm os mesmos 14 caracteres: sem a pontuação não dá para
    # saber qual dos dois é, e o CPF de uma pessoa era guardado como CNPJ.
    it 'fora da forma completa do CNPJ é recusado com código próprio e uma frase que diz o que fazer' do
      conferir = lambda do |recusa|
        expect([recusa.codigo, recusa.message, recusa.http_status]).to eq(['letra_fora_da_forma_do_cnpj', frase, 422])
        expect(recusa.to_hash).to eq(error: 'letra_fora_da_forma_do_cnpj', message: frase)
        expect(recusa.message + recusa.inspect).not_to include('123456789', '123.456.789', 'CLI')
      end

      I18n.with_locale(:pt_BR) do
        ['CLI123.456.789-09', 'CLI12345678909', 'cli12345678909', '12ABC34501DE35', '12abc34501de35'].each do |texto|
          expect { documentos.guardar(marina, texto) }.to raise_error(CustomExceptions::DocumentoRecusa, &conferir)
        end
      end
      expect(Relacionamentos::Documento.count).to eq(0)
    end

    it 'na forma completa do CNPJ, em qualquer caixa, é guardado como CNPJ e achado; sem a pontuação a busca não acha' do
      documentos.guardar(oficina, '12.abc.345/01de-35')

      expect(documentos.ler(oficina).attributes.slice('tipo', 'valor')).to eq('tipo' => 'cnpj', 'valor' => '12ABC34501DE35')
      expect([documentos.ler(oficina).formatado, documentos.ler(oficina).mascarado]).to eq(['12.ABC.345/01DE-35', '**.***.***/****-35'])
      expect([documentos.donos('12.ABC.345/01DE-35'), documentos.donos('12.abc.345/01de-35')]).to eq([[oficina], [oficina]])
      expect([documentos.donos('12ABC34501DE35'), documentos.donos('12.ABC.345/01DE-36')]).to eq([[], []])
    end
  end

  describe 'CPF em empresa' do
    let(:frase) { 'Empresa tem CNPJ, não CPF. Digite aqui o CNPJ da empresa e guarde o CPF na pessoa que é dona dele.' }

    it 'é recusado com uma frase que diz o que fazer; a pessoa pode ter CNPJ' do
      conferir = lambda do |recusa|
        expect([recusa.codigo, recusa.message, recusa.http_status]).to eq(['cpf_em_empresa', frase, 422])
        expect(recusa.message + recusa.inspect).not_to include('123', '456', '789')
      end

      I18n.with_locale(:pt_BR) do
        expect { documentos.guardar(oficina, cpf) }.to raise_error(CustomExceptions::DocumentoRecusa, &conferir)
      end
      expect(documentos.guardar(marina, cnpj).tipo).to eq('cnpj')
      expect(Relacionamentos::Documento.where(company_id: oficina.id)).to be_empty
    end
  end

  describe 'dois pedidos ao mesmo tempo para o mesmo dono' do
    # O segundo pedido procurou o documento antes de o primeiro gravar: não achou, e vai criar um que o índice único
    # recusa. Aqui o primeiro já gravou, e a primeira procura do segundo devolve o que ele viu naquela hora: nada.
    it 'o que chega depois tenta de novo e troca o documento, sem erro e sem derrubar a transação de quem chamou' do
      documentos.guardar(marina, cpf)
      visto_antes = Relacionamentos::Documento.new(account_id: account.id, contact_id: marina.id, tipo: 'cpf')
      procuras = 0
      allow(documentos).to receive(:do_tipo).and_wrap_original do |procurar, *argumentos|
        procuras += 1
        procuras == 1 ? visto_antes : procurar.call(*argumentos)
      end

      guardado = documentos.guardar(marina, outro_cpf)

      expect(procuras).to eq(2)
      expect([guardado.valor, Relacionamentos::Documento.where(contact_id: marina.id).count]).to eq(['98765432100', 1])
      expect(documentos.donos(outro_cpf)).to eq([marina])
    end

    # A segunda tentativa também não acha o documento (toda procura devolve um novo, às cegas) e o banco recusa de novo.
    it 'tenta de novo uma vez só: se o banco recusa outra vez, o erro sobe e o documento fica como estava' do
      documentos.guardar(marina, cpf)
      procuras = 0
      allow(documentos).to receive(:do_tipo) do
        procuras += 1
        Relacionamentos::Documento.new(account_id: account.id, contact_id: marina.id, tipo: 'cpf')
      end

      expect { documentos.guardar(marina, outro_cpf) }.to raise_error(ActiveRecord::RecordNotUnique)

      expect(procuras).to eq(2)
      expect([documentos.ler(marina).valor, Relacionamentos::Documento.where(contact_id: marina.id).count]).to eq(['12345678909', 1])
      expect([documentos.donos(cpf), documentos.donos(outro_cpf)]).to eq([[marina], []])
    end
  end

  describe 'o número fora do erro e do inspect' do
    it 'o inspect do documento e o erro de validação não trazem o número' do
      documento = documentos.guardar(marina, cpf)
      de_fora = create(:contact, account: create(:account), name: 'Caio Exemplo')
      sem_o_numero = ->(erro) { expect(erro.message + erro.record.inspect).not_to include('12345678909', '98765432100') }

      expect(documento.inspect + documento.to_json).not_to include('12345678909')
      expect("#{documento.numero} #{documento.numero.inspect}").not_to include('12345678909', '123.456.789')
      expect { documentos.guardar(de_fora, outro_cpf) }.to raise_error(ActiveRecord::RecordInvalid, &sem_o_numero)
    end

    it 'recusa dono que não é pessoa nem empresa' do
      expect { documentos.guardar(account, cpf) }.to raise_error(ArgumentError)
      expect { documentos.ler(account) }.to raise_error(ArgumentError)
    end
  end
end
