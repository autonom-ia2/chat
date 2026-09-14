require 'rails_helper'

# UM EXEMPLO POR PADRÃO. Cada exemplo de categoria casa só o seu padrão; cada exemplo de termo casa só o seu termo, e
# colado a um texto que sairia `veiculo` o leva ao genérico.
module PadroesDoMotivo
  POR_CATEGORIA = {
    'idade do veículo' => ['Idade do veículo acima do limite.', 'Veículo acima da idade permitida.'],
    'ano modelo' => ['Ano modelo fora da política de aceitação.', 'Ano de fabricação fora da política.'],
    'modelo' => ['Cobertura não permitida para este modelo.', 'Modelo restrito para aceitação.', 'Modelo do veículo sem aceitação.'],
    'tipo de veículo' => ['Tipo de veículo não aceito.'],
    'categoria tarifária' => ['Categoria tarifária sem aceitação.', 'Categoria do veículo sem aceitação.'],
    'CEP' => ['CEP sem aceitação.'], 'localidade' => ['Localidade sem aceitação.'], 'região' => ['Região sem aceitação.'],
    'circulação' => ['Área de circulação sem aceitação.'], 'pernoite' => ['Local de pernoite sem aceitação.']
  }.freeze

  POR_TERMO = {
    'login' => ['faça login novamente', 'sistema deslogado', 'faça o log in'], 'senha' => ['senha vencida', 'password errado'],
    'sessão' => ['sessão encerrada'], 'token' => ['token inválido'], 'usuário' => ['usuário inativo', 'user inativo'],
    'acesso' => ['acesso negado', 'access denied'], 'permissão' => ['sem permissão'], 'corretor' => ['corretor inativo', 'corretagem alta'],
    'credencial' => ['descredenciado', 'invalid credentials'], 'autenticação' => ['falha de autenticação'],
    'autorização' => ['desautorizado a calcular', 'not authorized'], 'habilitação' => %w[desabilitado inabilitado],
    'produtor' => ['produtor inativo'], 'SUSEP' => ['código SUSEP inválido'], 'cadastro' => ['recadastramento pendente'],
    'comissão' => ['comissão acima do permitido'], 'certificado' => ['certificado digital vencido'], 'bloqueio' => ['emissão bloqueada'],
    'conta' => ['conta inativa', 'account inativa'], 'suspensão' => ['operação suspensa'], 'agenciamento' => ['código do agenciador inválido'],
    'inadimplência' => ['inadimplência com a seguradora'], 'chave' => ['chave inválida'], 'integração' => ['falha na integração'],
    'expiração' => ['prazo expirado'], 'portal' => ['entre novamente no portal'], 'licença' => ['licença vencida'],
    'multicálculo' => ['uso indevido do multicálculo'], 'operador' => ['operador joao.silva'], 'sucursal' => ['sucursal inexistente'],
    'filial' => ['filial inativa'], 'convênio' => ['convênio inativo'], 'pró-labore' => ['pró-labore acima do permitido'],
    'vínculo' => ['vínculo inexistente'], 'perfil' => ['perfil não configurado'], 'verificação' => ['código de verificação inválido'],
    'parceiro' => ['parceiro inativo', 'parceria encerrada'], 'comercial' => ['desconto comercial'], 'contrato' => ['contrato encerrado'],
    'e-mail' => ['contato@exemplo.test', 'e mail não confirmado'], 'link' => ['veja www.exemplo.test'],
    'redigido' => ['contato do suporte <REDACTED>']
  }.freeze

  POR_TERMO_DA_PESSOA = {
    'segurado' => ['segurado com restrição'], 'condutor' => ['condutor principal com restrição'], 'motorista' => ['motorista com restrição'],
    'proprietário' => ['proprietário com restrição'], 'cliente' => ['cliente com restrição'], 'pessoa' => ['pessoa física com restrição'],
    'documento' => ['CPF divergente', 'CNH vencida'], 'crédito' => ['restrição de crédito'], 'financeiro' => ['restrição financeira'],
    'sinistro' => ['histórico de sinistros'], 'bônus' => ['classe de bônus'], 'profissão' => ['profissão sem aceitação']
  }.freeze

  POR_TERMO_DE_DUVIDA = {
    'interno' => ['política interna'], 'critério' => ['critério da seguradora'], 'análise' => ['após análise']
  }.freeze
end

# A REGRA DO MOTIVO (fatia 2 do #420; decisão do CEO de 13/09/2026): o código classifica o motivo em `veiculo` ou `regiao`,
# e só isso vai ao modelo. `kind` fora de `risco`, termo de conta, termo da pessoa, termo de dúvida, letra ilegível, duas
# categorias ou nenhuma: nil, o genérico.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  def categoria(texto, kind: 'risco')
    described_class.categoria('kind' => kind, 'text' => texto)
  end

  def alvo(texto)
    ActiveSupport::Inflector.transliterate(texto).downcase
  end

  describe 'o corpus do conector' do
    TextosDoMotivo::CORPUS.each do |texto, kind, _status, esperada|
      it "«#{texto}» (#{kind}) sai #{esperada.inspect}" do
        expect(categoria(texto, kind: kind)).to eq(esperada)
      end
    end
  end

  describe 'o que cai no genérico, mesmo classificado como risco pelo conector' do
    { 'conta da corretora' => TextosDoMotivo::CONTA, 'dado da pessoa' => TextosDoMotivo::PESSOA,
      'textos das revisões' => TextosDoMotivo::REVISOES }.each do |grupo, textos|
      textos.each do |texto|
        it "#{grupo}: «#{texto}»" do
          expect(categoria(texto)).to be_nil
        end
      end
    end
  end

  describe 'o kind decide antes do texto' do
    %w[passageiro credencial outro].each do |kind|
      it "o kind #{kind} com um texto que o risco classificaria sai genérico" do
        expect(categoria('Tipo de veículo não aceito.', kind: kind)).to be_nil
      end
    end

    it 'motivo sem kind, sem texto, com texto que não é String ou que não é Hash sai genérico' do
      expect(described_class.categoria('text' => 'Tipo de veículo não aceito.')).to be_nil
      expect(described_class.categoria('kind' => 'risco', 'text' => nil)).to be_nil
      expect(described_class.categoria('kind' => 'risco', 'text' => { 'a' => 1 })).to be_nil
      expect(described_class.categoria('Tipo de veículo não aceito.')).to be_nil
      expect(described_class.categoria(nil)).to be_nil
    end
  end

  describe 'cada categoria' do
    PadroesDoMotivo::POR_CATEGORIA.each do |padrao, textos|
      textos.each do |texto|
        it "#{padrao}: «#{texto}»" do
          esperada = described_class::CATEGORIAS.find { |_nome, padroes| padroes.key?(padrao) }.first

          expect(categoria(texto)).to eq(esperada)
        end
      end
    end

    it 'texto com as duas categorias sai genérico' do
      expect(categoria('Modelo do veículo sem aceitação neste CEP.')).to be_nil
    end

    it 'texto de risco que não nomeia o atributo sai genérico' do
      expect(categoria('Veículo sem aceitação.')).to be_nil
      expect(categoria('Risco sem aceitação para este cenário.')).to be_nil
    end

    it 'texto com letra que a transliteração não escreve sai genérico, com o atributo nomeado' do
      expect(categoria('Tipo de veículo não aceito: ꜱᴇɴʜᴀ ᴇˣᴘɪʀᴏᴜ.')).to be_nil
    end

    it 'todo padrão de categoria tem exemplo, e um que só ele casa' do
      padroes = described_class::CATEGORIAS.values.reduce(:merge)
      sem_exemplo_proprio = padroes.keys.reject do |nome|
        PadroesDoMotivo::POR_CATEGORIA.fetch(nome, []).any? { |texto| padroes.select { |_, padrao| alvo(texto).match?(padrao) }.keys == [nome] }
      end

      expect(PadroesDoMotivo::POR_CATEGORIA.keys).to match_array(padroes.keys)
      expect(sem_exemplo_proprio).to be_empty
    end
  end

  # UM TERMO TIRA A CATEGORIA: colado a "Tipo de veículo não aceito", que sozinho sai `veiculo`.
  describe 'cada termo que leva ao genérico' do
    let(:base) { 'Tipo de veículo não aceito' }

    it 'o controle: o texto sem termo sai veiculo' do
      expect(categoria("#{base}.")).to eq(described_class::VEICULO)
    end

    { TERMOS_DE_CONTA: PadroesDoMotivo::POR_TERMO, TERMOS_DA_PESSOA: PadroesDoMotivo::POR_TERMO_DA_PESSOA,
      TERMOS_DE_DUVIDA: PadroesDoMotivo::POR_TERMO_DE_DUVIDA }.each do |lista, exemplos|
      exemplos.each do |termo, textos|
        textos.each do |texto|
          it "#{lista} #{termo}: «#{texto}»" do
            expect(categoria("#{base}, #{texto}.")).to be_nil
          end
        end
      end

      it "todo padrão de #{lista} tem exemplo, e um que só ele casa entre todos os termos" do
        todos = described_class::TERMOS_DE_CONTA.merge(described_class::TERMOS_DA_PESSOA).merge(described_class::TERMOS_DE_DUVIDA)
        padroes = described_class.const_get(lista)
        sem_exemplo_proprio = padroes.keys.reject do |nome|
          exemplos.fetch(nome, []).any? { |texto| todos.select { |_, padrao| alvo(texto).match?(padrao) }.keys == [nome] }
        end

        expect(exemplos.keys).to match_array(padroes.keys)
        expect(sem_exemplo_proprio).to be_empty
      end
    end
  end
end
