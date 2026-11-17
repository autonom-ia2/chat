# Gera os PDFs fictícios do leitor de apólice (E6, #2899). Tudo aqui é inventado: seguradora, corretora, pessoas,
# documentos (com dígito verificador inválido de propósito), telefones, e-mails (.invalid), placas e endereços.
# Nunca ponha dado real neste arquivo: o repositório é público.
#
#   bundle exec ruby spec/fixtures/carteira/gerar.rb                      # todos
#   bundle exec ruby spec/fixtures/carteira/gerar.rb apolice_auto.pdf     # só os arquivos pedidos
#
# O PDF escaneado precisa do `pdftoppm` (poppler) para virar imagem: sem ele, gere só os outros pelo nome.
#
# E8.1 (#3043): as armadilhas dos dados do segurado da cotação. No auto, o nascimento do segurado com o ano em dois
# dígitos e o do condutor ao lado (outro nascimento, outro sexo), o CEP do segurado e o da corretora, e a classe de bônus
# com um percentual de bônus ao lado. No empresarial, a empresa segurada (sem nascimento nem sexo), o CEP do risco e o da
# corretora. A vida escaneada não tem placa nem bônus. O gabarito de cada arquivo está em gabarito.json.
# A apólice de 160 páginas não é arquivo: os specs a montam na hora (spec/support/carteira_pdf_longo.rb).
require 'prawn'
require 'open3'
require 'tmpdir'

PASTA = __dir__

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
   'Data de nascimento: 15/03/85        Sexo: Feminino',
   'Endereço: Rua das Amostras, 100 - Centro - Cidade Exemplo/EX - CEP 12345-678',
   'Telefone: (11) 99999-0001        E-mail: marina.exemplo@exemplo.invalid', '',
   'CONDUTOR PRINCIPAL', 'Nome: Carlos Exemplo de Souza        Nascimento: 02/07/1990        Sexo: Masculino', '',
   'VEÍCULO SEGURADO', 'Marca/Modelo: Veículo Modelo Exemplo 1.0        Ano: 2024        Placa: EXM0A00', '',
   'BÔNUS', 'Classe de bônus: 5        Bônus: 10% de desconto', '',
   'PRÊMIO', 'Prêmio líquido: R$ 2.100,00        IOF: R$ 154,98        Prêmio total: R$ 2.254,98',
   'Forma de pagamento: 6 parcelas de R$ 375,83', '',
   'CORRETOR', 'Corretora Amostra de Seguros Ltda. - Rua da Corretora, 50 - CEP 98765-432',
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
   'LOCAL DO RISCO', 'Avenida do Exemplo, 250 - Bairro Modelo - Cidade Exemplo/EX - CEP 54321-000', '',
   'Classe de bônus: 3', '',
   'PRÊMIO TOTAL: R$ 5.000,00 em 10 parcelas de R$ 500,00', '',
   'CORRETOR: Corretora Amostra de Seguros Ltda. - (11) 3000-0002 - CEP 98765-432'],
  ['VISTORIA E INSPEÇÃO DE RISCO', '',
   'Contato para agendar a vistoria: Sr. Carlos Modelo, (11) 98888-0005, vistoria@exemplo.invalid', '',
   'COBERTURAS', 'Incêndio, raio e explosão: R$ 800.000,00', 'Danos elétricos: R$ 50.000,00']
].freeze

# A armadilha do contato: na página do CPF do segurado só há o telefone e o e-mail do corretor e o 0800 da seguradora.
# O leitor não pode devolver nenhum deles como contato do segurado.
SO_CONTATO_DO_CORRETOR = [
  ['SEGURADORA EXEMPLO S.A.', 'APÓLICE DE SEGURO DE AUTOMÓVEL', '',
   'Apólice nº: EX-2026.004455', 'Ramo: 0531 - Automóvel - Casco', 'Vigência: 05/01/2027 a 05/01/2028', '',
   'SEGURADO', 'Nome: Bruno Amostra Pereira        CPF: 222.333.444-00', '',
   'VEÍCULO SEGURADO', 'Veículo Exemplo Sedan 2.0 2025 Placa EXM1B11', '',
   'Prêmio total: R$ 3.120,50 em 4 parcelas de R$ 780,13', '',
   'CORRETOR', 'Corretora Amostra de Seguros Ltda.',
   'Telefone: (11) 3000-0002        E-mail: contato@corretora-amostra.invalid', '',
   'Central de atendimento da seguradora: 0800 000 0003']
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

# A página vira imagem e a imagem vira o PDF: o arquivo final não tem texto, como um papel escaneado. Imagem em
# preto e branco (1 bit), para o arquivo ficar com poucos KB.
def escaneada(nome, paginas)
  Dir.mktmpdir do |pasta|
    Dir.chdir(pasta) do
      Prawn::Document.generate('texto.pdf', page_size: 'A4', margin: 48) do |documento|
        documento.font_size 16
        paginas.first.each { |linha| linha.empty? ? documento.move_down(10) : documento.text(linha) }
      end
      _saida, status = Open3.capture2e('pdftoppm', '-r', '100', '-mono', '-png', '-singlefile', 'texto.pdf', 'pagina')
      raise 'pdftoppm falhou' unless status.success?
    end
    Prawn::Document.generate(File.join(PASTA, nome), page_size: 'A4', margin: 0, compress: true) do |documento|
      documento.image File.join(pasta, 'pagina.png'), fit: [documento.bounds.width, documento.bounds.height]
    end
  end
end

PEDIDOS = ARGV

def gerar?(nome)
  PEDIDOS.empty? || PEDIDOS.include?(nome)
end

pdf('apolice_auto.pdf', AUTO) if gerar?('apolice_auto.pdf')
pdf('apolice_empresarial.pdf', EMPRESARIAL) if gerar?('apolice_empresarial.pdf')
pdf('apolice_contato_so_do_corretor.pdf', SO_CONTATO_DO_CORRETOR) if gerar?('apolice_contato_so_do_corretor.pdf')
pdf('nao_e_apolice.pdf', NAO_E_APOLICE) if gerar?('nao_e_apolice.pdf')
escaneada('apolice_escaneada.pdf', ESCANEADA) if gerar?('apolice_escaneada.pdf')
