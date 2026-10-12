// #1149 — CRM → Caixas no CRM. Enquanto o endpoint não existe, os dados vêm do
// adaptador em memória; trocar pela API real é esta linha.
import adaptador from './crmCaixasFalso';

export default adaptador;
