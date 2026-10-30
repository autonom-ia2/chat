# Este contato é (#2084/#2085): ler e gravar a relação do contato (interessado, parceiro do mercado, não é negócio).
# Só com a flag `contato_relacao` da conta; desligada, a rota responde 404 e a tela nem aparece.
#
# Ler segue a regra de ver a origem do contato (ContactPolicy#origins?): a escolha aparece no painel da conversa, para
# quem vê a conversa, e na ficha do contato. Gravar é editar o contato (ContactPolicy#update?, contact_manage no EE).
#
#   GET /api/v1/accounts/:account_id/crm/contacts/:contact_id/relacao
#     -> { relacao, cardsAbertos, podeEditar }  (cardsAbertos: os abertos que a pessoa pode arquivar, para perguntar "Arquivar?")
#   PUT /api/v1/accounts/:account_id/crm/contacts/:contact_id/relacao  { relacao, arquivar_cards }
#     -> { relacao, cardsArquivados, cardsNaoArquivados }
class Api::V1::Accounts::Crm::Contacts::RelacoesController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_feature!
  before_action :fetch_contact

  def show
    authorize @contact, :origins?
    render json: { relacao: @contact.relacao, cardsAbertos: cards_abertos.size, podeEditar: policy(@contact).update? }
  end

  def update
    authorize @contact, :update?
    return render_unprocessable('crm.relacao.invalid') unless Contact.defined_enums.fetch('relacao').key?(params[:relacao].to_s)

    resultado = ::Crm::Relacao::Marcar.new(contact: @contact, user: Current.user, account_user: Current.account_user,
                                           relacao: params[:relacao], arquivar_cards: arquivar_cards?).perform
    render json: { relacao: resultado[:relacao], cardsArquivados: resultado[:cards_arquivados],
                   cardsNaoArquivados: resultado[:cards_nao_arquivados] }
  end

  private

  def ensure_feature!
    head :not_found unless ::Crm::Relacao.ligada?(Current.account)
  end

  def fetch_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def arquivar_cards?
    ActiveModel::Type::Boolean.new.cast(params[:arquivar_cards]) == true
  end

  # Os mesmos cards que o "Arquivar" alcança (Crm::Relacao::Marcar.arquivaveis): a pergunta não promete mais do que faz.
  def cards_abertos
    ::Crm::Relacao::Marcar.arquivaveis(contact: @contact, user: Current.user, account_user: Current.account_user)
  end
end
