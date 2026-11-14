# "Trazer minha lista" (#2896): na hora de gravar uma linha, o que vai para fora das informações da pessoa.
#
# - coluna "cidade": a cidade da pessoa (additional_attributes['city'], a mesma da lista e da ficha);
# - coluna "telefone da empresa": o telefone da empresa DA LINHA (additional_attributes['phone_number'] da empresa). A
#   tela só aceita esse destino com coluna de empresa na planilha e Empresas ligada na conta
#   (Relacionamentos::Trazer::Colunas#tem_empresa?). Só é gravado quando a gravação ligou a pessoa à empresa da linha
#   (o vinculador respondeu `created` ou `reused`). Na linha com a célula da empresa vazia, ou de uma pessoa que já
#   era de outra empresa (`kept_other`), o telefone da empresa dessa linha não é guardado em lugar nenhum: nunca vai
#   para a empresa de outra linha;
# - a resposta "sim, todas", ou a coluna "cliente" com um dos valores que a pessoa disse que querem dizer cliente
#   (ContactImports::Trazer::Cliente): a pessoa vira cliente com a data de agora (Contact#become_customer!). O código
#   não interpreta a célula: sem a escolha da pessoa, a coluna "cliente" não marca ninguém.
#
# Quem já existia é completado, nunca sobrescrito: a cidade e o telefone só entram onde estava vazio, e quem já era
# cliente fica com a data que tinha. O importador chama `aplicar` dentro da gravação de cada linha, logo depois das
# informações da pessoa (CampaignImports::Importer#import_one), tenha a linha ou não alguma coluna além das de contato:
# "sim, todas" vale para todo mundo. Quem grava as informações (ContactImports::CustomAttributes) só pergunta aqui
# quais colunas não viram informação (`chaves`) e que nome a pessoa deu a cada uma (`campos`).
#
# O importador chama `gravar`, que aplica os destinos e manda anotar o que a linha preencheu
# (Relacionamentos::Trazer::CamposPreenchidos), para o "Desfazer" devolver só isso. `aplicar` responde o que pôs
# (`Postos`): a cidade e o telefone da empresa como ficaram gravados, ou nil quando já havia valor, e a promoção de quem
# virou cliente agora (`Promocao`: o tipo que a pessoa tinha, lido sob a trava, e a data como ficou no banco). Quem já
# era cliente não tem promoção.
class ContactImports::Trazer::DestinosDaLinha
  Postos = Struct.new(:cidade, :telefone_da_empresa, :cliente, keyword_init: true)
  Promocao = Struct.new(:tipo_anterior, :desde, keyword_init: true)
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
    @cliente = ContactImports::Trazer::Cliente.new(importacao)
    @preenchidos = Relacionamentos::Trazer::CamposPreenchidos.new(importacao)
  end

  # As colunas (pela chave em extra_values) que não viram informação da pessoa.
  def chaves
    @chaves.values.flatten
  end

  # { chave da coluna => { 'nome' => 'Plano', 'para_que_serve' => '…' } } do que a pessoa escreveu na tela.
  def campos
    @colunas.campos_por_chave
  end

  # A gravação de uma linha, dentro da transação dela. linha: a linha da importação. gravada: o que o importador
  # escreveu (CampaignImports::ContactRow::Result). informacoes: o que ContactImports::CustomAttributes#merge! acrescentou.
  def gravar(linha, gravada, informacoes)
    postos = aplicar(gravada.contact, linha.extra_values, empresa: gravada.company)
    @preenchidos.registrar(linha, gravada, informacoes, postos)
  end

  # empresa: o que o vinculador de empresas respondeu para esta linha (CampaignImports::CompanyLinker::Result) ou nil.
  def aplicar(contato, valores, empresa: nil)
    valores = valores.to_h
    Postos.new(
      cidade: preencher_cidade(contato, primeiro(valores, 'cidade')),
      telefone_da_empresa: preencher_telefone_da_empresa(empresa, primeiro(valores, 'telefone_da_empresa')),
      cliente: (virar_cliente(contato) if cliente?(valores))
    )
  end

  def cliente?(valores)
    @cliente.marca?(valores)
  end

  private

  def primeiro(valores, destino)
    @chaves[destino].filter_map { |chave| valores[chave].to_s.squish.presence }.first
  end

  def preencher_cidade(contato, cidade)
    return if cidade.nil?

    contato.with_lock do
      atuais = contato.additional_attributes.to_h
      next if atuais[CIDADE].present?

      contato.update!(additional_attributes: atuais.merge(CIDADE => cidade))
      cidade
    end
  end

  def preencher_telefone_da_empresa(vinculo, telefone)
    return if telefone.nil? || vinculo.nil? || DA_LINHA.exclude?(vinculo.status) || vinculo.company.nil?

    empresa = vinculo.company
    empresa.with_lock do
      atuais = empresa.additional_attributes.to_h
      next if atuais[TELEFONE_DA_EMPRESA].present?

      empresa.update!(additional_attributes: atuais.merge(TELEFONE_DA_EMPRESA => telefone))
      telefone
    end
  end

  def virar_cliente(contato)
    contato.with_lock do
      antes = contato.contact_type
      next unless contato.become_customer!

      Promocao.new(tipo_anterior: Contact.contact_types[antes], desde: contato.reload.customer_since)
    end
  end
end
