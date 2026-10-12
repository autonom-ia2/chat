# atendente.* (#1331): quem atende, pelo nome de exibição (ou o nome do cadastro). Sem pessoa, não oferece nada.
class TemplateFields::AttendantResolver
  include TemplateFields::FieldReader

  READERS = { 'atendente.nome' => :name }.freeze

  def initialize(user)
    @user = user
  end

  def keys
    @user ? super : []
  end

  private

  def name
    @user&.available_name
  end
end
