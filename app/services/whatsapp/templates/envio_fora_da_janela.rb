# PONTO ÚNICO de toda mensagem automática fora da janela de 24 h no WhatsApp oficial (#1587, C+D do épico #1585):
# cobrança, follow-up agendado, cadência, retorno e avisos. Quem chama é o Followup IA (pré-voo 10 min antes e envio no
# horário) e, depois, o Agendamento. Contrato combinado no #1587 (comentário de 15/10/2026):
#
#   plano = Whatsapp::Templates::EnvioForaDaJanela.planejar(inbox:, tipo: 'andamento', contato:, ja_recusado: false)
#   # => { 'versao' => 1, 'tipo' => 'andamento', 'caminho' => 'modelo' | 'criando' | 'equipe', 'motivo' => (só equipe),
#   #      'escolha' => 'do_tipo' | 'compativel', 'nome' =>, 'idioma' =>, 'categoria' => 'UTILITY' | 'MARKETING',
#   #      'origem' => 'sistema' | 'conta', 'texto' => 'Olá, {{1}}! ...', 'campos' => { '1' => 'cliente.primeiro_nome' },
#   #      'opcoes' => { 'com_valor' => true } (cobrança), 'ja_recusado' => false }
#   envio = Whatsapp::Templates::EnvioForaDaJanela.enviar(inbox:, plano:, valores: { '1' => 'Ana', ... }, contato:)
#   # => Envio(status: :enviar, metadata: { 'template_name', 'template_language', 'template_category',
#   #          'template_params_category', 'template_processed_params', 'message_body', 'envio_fora_da_janela' })
#   #  | Envio(status: :equipe, motivo: 'campo_sem_valor', metadata: {})
#   Whatsapp::Templates::EnvioForaDaJanela.encaixar_tipo(account:, texto:)  # follow-up livre -> 'andamento' | nil
#   Whatsapp::Templates::EnvioForaDaJanela.previa(plano:, valores:)         # o texto como vai sair
#
# - JSON simples (vai no metadata do follow-up), idempotente e barato: o pré-voo e o envio chamam o mesmo plano; nome
#   estável por (caixa, tipo); o Jev do "compatível" fica no cache. Só o caminho "criar" paga a IA e fala com a Meta.
# - Ordem (janela aberta e Híbrido são do Followup, pelo `MessagingWindow`): o modelo do tipo aprovado; um aprovado da
#   caixa que o Jev julga compatível (pulado com `ja_recusado: true`, quando o composer do Followup já recusou com
#   `no_fitting_template`); o modelo do tipo em análise (`criando`); criar o do tipo (`criando`); avisar a equipe.
# - `campos`: posição -> chave do catálogo (`TemplateFields`); quem preenche é o Followup (`TemplateFields::Resolver`).
# - `enviar` NÃO envia: relê o modelo na Meta (`DispatchCheck`) e devolve o metadata que o `MessageSender` manda, com o
#   registro do envio (`envio_fora_da_janela`: tipo, caminho, modelo, categoria, origem e a autorização vigente).
# - Todo motivo de `equipe` tem texto em `crm.service_reminders.aviso.<motivo>` (en e pt_BR): `MOTIVOS`.
# Fala com a Meta e com a IA: chamar de job, nunca da requisição do painel (exceto `previa` e `encaixar_tipo`).
class Whatsapp::Templates::EnvioForaDaJanela
  Envio = Data.define(:status, :metadata, :motivo) do
    def enviar?
      status == :enviar
    end
  end

  MODELO = 'modelo'.freeze
  CRIANDO = 'criando'.freeze
  EQUIPE = 'equipe'.freeze
  # Os motivos de `equipe` que este ponto devolve (os do `Garantir` e os códigos do `DispatchCheck` inclusive).
  MOTIVOS = %w[
    sem_whatsapp_oficial sem_consentimento sem_consentimento_propaganda sem_contato contato_recusou numero_eua no_template
    em_analise conferencia_sem_meta
    recusado pausado desativado situacao_desconhecida formato texto_diferente botoes_diferentes sem_base_url perfil_invalido
    meta_fora sem_permissao meta_recusou sem_campos ia_indisponivel ia_sem_opcao limite_de_modelos limite_por_hora
    campo_sem_valor template_missing template_not_approved template_category_changed template_structure_changed
    template_format_unsupported template_offer_expired templates_not_synced template_unverifiable
  ].freeze

  # rubocop:disable Metrics/ParameterLists
  def self.planejar(inbox:, tipo:, com_valor: false, ja_recusado: false, contato: nil, criar: true)
    Planejador.new(inbox: inbox, tipo: tipo, com_valor: com_valor, ja_recusado: ja_recusado, contato: contato, criar: criar).call
  end
  # rubocop:enable Metrics/ParameterLists

  def self.enviar(inbox:, plano:, valores:, contato: nil)
    Despacho.new(inbox: inbox, plano: plano, valores: valores, contato: contato).call
  end

  def self.encaixar_tipo(account:, texto:)
    Encaixe.call(account: account, texto: texto)
  end

  def self.previa(plano:, valores:)
    preencher(plano.to_h.stringify_keys['texto'], valores)
  end

  # "Olá, {{1}}!" + { '1' => 'Ana' } -> "Olá, Ana!". Uma passada só: o valor escrito nunca é relido.
  def self.preencher(texto, valores)
    valores = valores.to_h.stringify_keys
    Ai::Redacao::Chaves.preencher(texto.to_s) { |posicao| valores[posicao] }
  end
end
