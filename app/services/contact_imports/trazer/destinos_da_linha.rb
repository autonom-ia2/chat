# "Trazer minha lista" (#2896): na hora de gravar uma linha, o que vai para fora das informações da pessoa.
#
# - coluna "cidade": a cidade da pessoa (additional_attributes['city'], a mesma da lista e da ficha);
# - coluna "telefone da empresa": o telefone da empresa DA LINHA (additional_attributes['phone_number'] da empresa). A
#   tela só aceita esse destino com coluna de empresa na planilha e Empresas ligada na conta
#   (Relacionamentos::Trazer::Colunas#tem_empresa?). Só é gravado quando a gravação ligou a pessoa à empresa da linha
#   (o vinculador respondeu `created` ou `reused`). Na linha com a célula da empresa vazia, ou de uma pessoa que já
#   era de outra empresa (`kept_other`), o telefone da empresa dessa linha não é guardado em lugar nenhum: nunca vai
#   para a empresa de outra linha;
# - coluna "cliente" ou a resposta "sim, todas": a pessoa vira cliente com a data de agora (Contact#become_customer!).
#
# Quem já existia é completado, nunca sobrescrito: a cidade e o telefone só entram onde estava vazio, e quem já era
# cliente fica com a data que tinha. O importador chama `aplicar` dentro da gravação de cada linha, logo depois das
# informações da pessoa (CampaignImports::Importer#import_one), tenha a linha ou não alguma coluna além das de contato:
# "sim, todas" vale para todo mundo. Quem grava as informações (ContactImports::CustomAttributes) só pergunta aqui
# quais colunas não viram informação (`chaves`) e que nome a pessoa deu a cada uma (`campos`).
class ContactImports::Trazer::DestinosDaLinha
  CIDADE = 'city'.freeze
  TELEFONE_DA_EMPRESA = 'phone_number'.freeze
  FORA_DAS_INFORMACOES = %w[cidade telefone_da_empresa cliente].freeze
  # O que o vinculador responde quando a empresa da pessoa passou a ser (ou já era) a da linha.
  DA_LINHA = %i[created reused].freeze

  # Os destinos da importação com a marca options['trazer']; nil para todas as outras (e para o passo da automação,
  # que não tem importação).
  def self.da(importacao)
    new(importacao) if importacao && ContactImports::Trazer::Conferencia.marcada?(importacao)
  end

  def initialize(importacao)
    @importacao = importacao
    @colunas = Relacionamentos::Trazer::Colunas.new(importacao)
    @chaves = FORA_DAS_INFORMACOES.index_with { |destino| @colunas.chaves_do_destino(destino) }
    @todas_clientes = ContactImports::Trazer::Conferencia.new(importacao).respostas['clientes'] == 'sim_todas'
  end

  # As colunas (pela chave em extra_values) que não viram informação da pessoa.
  def chaves
    @chaves.values.flatten
  end

  # { chave da coluna => { 'nome' => 'Plano', 'para_que_serve' => '…' } } do que a pessoa escreveu na tela.
  def campos
    @colunas.campos_por_chave
  end

  # empresa: o que o vinculador de empresas respondeu para esta linha (CampaignImports::CompanyLinker::Result) ou nil.
  def aplicar(contato, valores, empresa: nil)
    valores = valores.to_h
    preencher_cidade(contato, primeiro(valores, 'cidade'))
    preencher_telefone_da_empresa(empresa, primeiro(valores, 'telefone_da_empresa'))
    contato.become_customer! if cliente?(valores)
  end

  def cliente?(valores)
    @todas_clientes || @chaves['cliente'].any? { |chave| ContactImports::Trazer::Cliente.marca?(valores[chave]) }
  end

  private

  def primeiro(valores, destino)
    @chaves[destino].filter_map { |chave| valores[chave].to_s.squish.presence }.first
  end

  def preencher_cidade(contato, cidade)
    return if cidade.nil?

    contato.with_lock do
      atuais = contato.additional_attributes.to_h
      contato.update!(additional_attributes: atuais.merge(CIDADE => cidade)) if atuais[CIDADE].blank?
    end
  end

  def preencher_telefone_da_empresa(vinculo, telefone)
    return if telefone.nil? || vinculo.nil? || DA_LINHA.exclude?(vinculo.status) || vinculo.company.nil?

    empresa = vinculo.company
    empresa.with_lock do
      atuais = empresa.additional_attributes.to_h
      empresa.update!(additional_attributes: atuais.merge(TELEFONE_DA_EMPRESA => telefone)) if atuais[TELEFONE_DA_EMPRESA].blank?
    end
  end
end
