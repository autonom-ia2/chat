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
#   não interpreta a célula: sem a escolha da pessoa, a coluna "cliente" não marca ninguém;
# - na planilha que traz seguros (E4, #2897), as colunas do seguro: a apólice da linha vai para a carteira, ligada à
#   pessoa (Carteira::Trazer::SeguroDaLinha), e a pessoa vira cliente desde o começo da vigência (a data mais antiga
#   vence; sem começo, a de agora). Sem seguros na planilha, `@seguro` é nil e nada disso roda.
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
# era cliente não tem promoção; se o seguro da linha levou a data de cliente dela para mais cedo, `adiantou` traz a data
# como ficou, para a anotação que esta lista fez numa linha de cima não ficar velha.
class ContactImports::Trazer::DestinosDaLinha
  Postos = Struct.new(:cidade, :telefone_da_empresa, :cliente, :adiantou, keyword_init: true)
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
    @seguro = Carteira::Trazer::SeguroDaLinha.da(importacao)
  end

  # As colunas (pela chave em extra_values) que não viram informação da pessoa.
  def chaves
    @chaves.values.flatten + @seguro&.chaves.to_a
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
    cidade = preencher_cidade(contato, primeiro(valores, 'cidade'))
    telefone = preencher_telefone_da_empresa(empresa, primeiro(valores, 'telefone_da_empresa'))
    apolice = @seguro&.gravar(contato, valores, empresa: empresa)
    cliente = virar_cliente(contato, desde: apolice&.inicio_vigencia) if apolice || cliente?(valores)
    Postos.new(cidade: cidade, telefone_da_empresa: telefone, cliente: (cliente if cliente.is_a?(Promocao)),
               adiantou: (cliente unless cliente.is_a?(Promocao)))
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

  # desde: o começo da vigência do seguro da linha, quando há seguro (a data mais antiga vence). Devolve a promoção de
  # quem virou cliente agora; de quem já era cliente e só teve a data levada para mais cedo, o instante novo; senão nil.
  def virar_cliente(contato, desde: nil)
    contato.with_lock do
      antes = contato.contact_type
      desde_antes = contato.customer_since
      promovida = contato.become_customer!(since: desde)
      agora = contato.reload.customer_since
      next Promocao.new(tipo_anterior: Contact.contact_types[antes], desde: agora) if promovida

      agora unless agora == desde_antes
    end
  end
end
