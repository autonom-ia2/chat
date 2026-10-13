import { usePodeCriarModelo } from './usePodeCriarModelo';

// "Criar com IA" e "Melhorar com IA" (#1333) são escrever modelo: quem pode
// criar e alterar (administrador ou whatsapp_templates_manage). Sem IA
// configurada na conta, o botão aparece e responde com a frase simples; o
// texto continua editável à mão.
export function useCanUseIA() {
  return usePodeCriarModelo();
}
