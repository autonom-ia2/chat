# Modelos do WhatsApp oficial (#1330): ver com `whatsapp_templates_view`; criar, editar, apagar, duplicar e subir o
# arquivo de exemplo com `whatsapp_templates_manage` (que implica ver). Administrador sempre pode (OSS: `administrator?`).
class WhatsappTemplatePolicy < ApplicationPolicy
  def index?
    view?
  end

  def usage?
    view?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  def media?
    manage?
  end

  # A conversão do vídeo que a mesma pessoa subiu (#2370).
  def media_status?
    manage?
  end

  private

  def view?
    @account_user&.permission_granted?('whatsapp_templates_view') || false
  end

  def manage?
    @account_user&.permission_granted?('whatsapp_templates_manage') || false
  end
end
