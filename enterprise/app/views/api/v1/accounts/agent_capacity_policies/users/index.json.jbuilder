# O formato da lista de agentes, sem token nem dado de sessão: a rota chega a quem tem assignment_manage (#1797).
json.array! @users do |user|
  json.partial! 'api/v1/models/agent', resource: user
end
