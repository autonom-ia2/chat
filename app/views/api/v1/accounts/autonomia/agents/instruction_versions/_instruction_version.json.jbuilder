json.id instruction_version.id
json.created_at instruction_version.created_at
json.reason instruction_version.reason
# Autoria: nome do usuário que editou, ou fallback de sistema quando foi um refresh automático.
json.created_by_name(instruction_version.created_by&.name || 'Autonom.ia')
json.instruction_hash instruction_version.instruction_hash
# IP OCULTO: o TEXTO da instrução só sai de versão gravada em modo MANUAL (texto do próprio usuário).
# Versão guiada tem instrução gerada pelo Construtor (IP nosso) → nunca expomos o conteúdo, qualquer que
# seja o modo atual do agente (#1484); só metadados que ainda permitem a volta. O retrato não sai.
json.instruction instruction_version.instruction if instruction_version.instrucao_visivel?
