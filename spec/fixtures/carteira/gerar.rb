# Gera os PDFs fictícios do leitor de apólice (E6, #2899). Tudo aqui é inventado: seguradora, corretora, pessoas,
# documentos (com dígito verificador inválido de propósito), telefones, e-mails (.invalid), placas e endereços.
# Nunca ponha dado real neste arquivo: o repositório é público.
#
#   bundle exec ruby spec/fixtures/carteira/gerar.rb
#
# O PDF escaneado precisa do `pdftoppm` (poppler) para virar imagem. O gabarito de cada arquivo está em gabarito.json.
require 'prawn'
require 'open3'
require 'tmpdir'

PASTA = __dir__
TOTAL_DA_LONGA = 160

def pdf(nome, paginas, **opcoes)
  Prawn::Document.generate(File.join(PASTA, nome), page_size: 'A4', margin: 48, compress: true, **opcoes) do |documento|
    documento.font_size 10
    paginas.each_with_index do |linhas, indice|
      documento.start_new_page unless indice.zero?
      linhas.each { |linha| linha.empty? ? documento.move_down(8) : documento.text(linha) }
    end
  end
end

AUTO = [
  ['SEGURADORA EXEMPLO S.A.', 'APÓLICE DE SEGURO DE AUTOMÓVEL', '',
   'Apólice nº: EX-2026.001234        Proposta nº: 998877', 'Ramo: 0531 - Automóvel - Casco',
   'Data de emissão: 10/11/2026', 'Vigência: das 24h de 12/11/2026 às 24h de 12/11/2027', '',
   'DADOS DO SEGURADO', 'Nome: Marina Exemplo de Souza        CPF: 123.456.789-00',
   'Endereço: Rua das Amostras, 100 - Centro - Cidade Exemplo/EX',
   'Telefone: (11) 99999-0001        E-mail: marina.exemplo@exemplo.invalid', '',
   'VEÍCULO SEGURADO', 'Marca/Modelo: Veículo Modelo Exemplo 1.0        Ano: 2024        Placa: EXM0A00', '',
   'PRÊMIO', 'Prêmio líquido: R$ 2.100,00        IOF: R$ 154,98        Prêmio total: R$ 2.254,98',
   'Forma de pagamento: 6 parcelas de R$ 375,83', '',
   'CORRETOR', 'Corretora Amostra de Seguros Ltda.',
   'Telefone: (11) 3000-0002        E-mail: contato@corretora-amostra.invalid', '',
   'Central de atendimento da seguradora: 0800 000 0003'],
  ['SEGURADORA EXEMPLO S.A.        Apólice nº: EX-2026.001234', '',
   'COBERTURAS', 'Colisão, incêndio e roubo: 100% da tabela de referência', 'Danos materiais a terceiros: R$ 100.000,00',
   'Danos corporais a terceiros: R$ 100.000,00', 'Franquia: R$ 3.500,00', '',
   'ASSISTÊNCIA 24 HORAS', 'Guincho e socorro mecânico: 0800 000 0004']
].freeze

EMPRESARIAL = [
  ['SEGURADORA EXEMPLO S.A.', 'APÓLICE DE SEGURO EMPRESARIAL', '',
   'Número da apólice: 77.0118.0005678', 'Ramo: 0118 - Compreensivo Empresarial',
   'Emitida em 20/12/2026', 'Vigência: 01/01/2027 a 01/01/2028', '',
   'SEGURADO', 'Razão social: Padaria Amostra Ltda.        CNPJ: 12.345.678/0001-00', '',
   'LOCAL DO RISCO', 'Avenida do Exemplo, 250 - Bairro Modelo - Cidade Exemplo/EX', '',
   'PRÊMIO TOTAL: R$ 5.000,00 em 10 parcelas de R$ 500,00', '',
   'CORRETOR: Corretora Amostra de Seguros Ltda. - (11) 3000-0002'],
  ['VISTORIA E INSPEÇÃO DE RISCO', '',
   'Contato para agendar a vistoria: Sr. Carlos Modelo, (11) 98888-0005, vistoria@exemplo.invalid', '',
   'COBERTURAS', 'Incêndio, raio e explosão: R$ 800.000,00', 'Danos elétricos: R$ 50.000,00']
].freeze

NAO_E_APOLICE = [
  ['CONDOMÍNIO EDIFÍCIO EXEMPLO', 'COMUNICADO DE ASSEMBLEIA', '',
   'Prezados moradores,', 'A assembleia geral ordinária será no dia 05/12/2026, às 19h30, no salão de festas.',
   'Pauta: prestação de contas, previsão orçamentária de 2027 e eleição do conselho.', '',
   'Dúvidas: administração, (11) 3000-0006, sindico@condominio-exemplo.invalid', '', 'Cidade Exemplo, 13/11/2026']
].freeze

ESCANEADA = [
  ['SEGURADORA EXEMPLO S.A.', 'APÓLICE DE SEGURO DE VIDA INDIVIDUAL', '',
   'Apólice nº: VD-0093.004321', 'Ramo: 0993 - Vida Individual', 'Vigência: 15/03/2026 a 15/03/2027', '',
   'SEGURADO', 'Nome: Paulo Modelo Ferreira        CPF: 111.222.333-00',
   'Telefone: (21) 97777-0007        E-mail: paulo.modelo@exemplo.invalid', '',
   'Prêmio total anual: R$ 1.380,00']
].freeze

LONGA = [
  ['SEGURADORA EXEMPLO S.A.', 'APÓLICE DE SEGURO RESIDENCIAL', '',
   'Apólice nº: RS-0114.000777', 'Ramo: 0114 - Compreensivo Residencial', 'Vigência: 01/02/2027 a 01/02/2028', '',
   'SEGURADO', 'Nome: Renata Amostra Lima        CPF: 987.654.321-99', '',
   'IMÓVEL SEGURADO', 'Rua do Modelo, 45, apto 12 - Bairro Exemplo - Cidade Exemplo/EX', '',
   'Prêmio total: R$ 890,40'],
  ['DADOS PARA CONTATO DO SEGURADO', 'Renata Amostra Lima        CPF: 987.654.321-99',
   'Telefone: (31) 96666-0008        E-mail: renata.amostra@exemplo.invalid', '',
   'CORRETOR', 'Corretora Amostra de Seguros Ltda. - (11) 3000-0002'],
  *(3..(TOTAL_DA_LONGA - 1)).map do |numero|
    ['CONDIÇÕES GERAIS DO SEGURO RESIDENCIAL', "Página #{numero} de #{TOTAL_DA_LONGA}", '',
     "Cláusula #{numero}: texto de exemplo das condições gerais, sem dado de nenhum seguro em particular."]
  end,
  ['ANEXO - DADOS DE COBRANÇA', 'Titular: Renata Amostra Lima        CPF: 987.654.321-99', 'Débito em conta, todo dia 10.']
].freeze

# A página vira imagem e a imagem vira o PDF: o arquivo final não tem texto, como um papel escaneado.
def escaneada(nome, paginas)
  Dir.mktmpdir do |pasta|
    Dir.chdir(pasta) do
      Prawn::Document.generate('texto.pdf', page_size: 'A4', margin: 48) do |documento|
        documento.font_size 12
        paginas.first.each { |linha| linha.empty? ? documento.move_down(10) : documento.text(linha) }
      end
      _saida, status = Open3.capture2e('pdftoppm', '-r', '110', '-gray', '-png', '-singlefile', 'texto.pdf', 'pagina')
      raise 'pdftoppm falhou' unless status.success?
    end
    Prawn::Document.generate(File.join(PASTA, nome), page_size: 'A4', margin: 0, compress: true) do |documento|
      documento.image File.join(pasta, 'pagina.png'), fit: [documento.bounds.width, documento.bounds.height]
    end
  end
end

pdf('apolice_auto.pdf', AUTO)
pdf('apolice_empresarial.pdf', EMPRESARIAL)
pdf('nao_e_apolice.pdf', NAO_E_APOLICE)
pdf('apolice_longa.pdf', LONGA)
escaneada('apolice_escaneada.pdf', ESCANEADA)
