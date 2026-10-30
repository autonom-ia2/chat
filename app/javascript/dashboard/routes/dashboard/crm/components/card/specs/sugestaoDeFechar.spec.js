import { textoDoFechamento } from '../sugestaoDeFechar';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

const chave = (catalogo, caminho) =>
  caminho.split('.').reduce((no, parte) => no?.[parte], catalogo);

describe('textoDoFechamento', () => {
  it('sugestão de etapa (sem fechar): null, o cartão segue com "Mover para"', () => {
    expect(textoDoFechamento({ to_stage_name: 'Proposta' })).toBeNull();
    expect(textoDoFechamento(null)).toBeNull();
  });

  it('perdido "adiou": frase com o motivo, botão Encerrar e o aviso do retorno', () => {
    expect(
      textoDoFechamento({ fechar: { resultado: 'perdido', motivo: 'adiou' } })
    ).toEqual({
      frase: 'CRM_CARD.FECHAR_SUGESTAO.FRASE.PERDIDO',
      curta: 'CRM_CARD.FECHAR_SUGESTAO.CURTO.PERDIDO',
      botao: 'CRM_CARD.FECHAR_SUGESTAO.ENCERRAR',
      motivo: 'CRM_CARD.FECHAR_SUGESTAO.MOTIVO.ADIOU',
      retorno: 'CRM_CARD.FECHAR_SUGESTAO.RETORNO',
    });
  });

  it('"era teste": botão Arquivar, sem motivo nem retorno', () => {
    const texto = textoDoFechamento({
      fechar: { resultado: 'arquivado', motivo: 'teste' },
    });
    expect(texto.botao).toBe('CRM_CARD.FECHAR_SUGESTAO.ARQUIVAR');
    expect(texto.motivo).toBe('');
    expect(texto.retorno).toBe('');
  });

  it('resultado desconhecido (ganho): null, nunca vira botão de fechar', () => {
    expect(textoDoFechamento({ fechar: { resultado: 'ganho' } })).toBeNull();
  });

  it('toda chave usada existe em en e pt_BR', () => {
    const casos = [
      { resultado: 'perdido', motivo: 'adiou' },
      { resultado: 'perdido', motivo: 'recusou' },
      { resultado: 'perdido', motivo: 'fechou_com_outra' },
      { resultado: 'resolvido' },
      { resultado: 'arquivado', motivo: 'teste' },
    ];
    casos.forEach(fechar => {
      const texto = textoDoFechamento({ fechar });
      Object.values(texto)
        .filter(Boolean)
        .forEach(caminho => {
          expect(typeof chave(en, caminho)).toBe('string');
          expect(typeof chave(ptBR, caminho)).toBe('string');
        });
    });
  });
});
