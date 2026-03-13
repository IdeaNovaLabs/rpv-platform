# RPV Capital — Base de Conhecimento

Insights, descobertas técnicas e aprendizados acumulados durante o desenvolvimento.

---

## Descobertas Técnicas

### Truncamento de Número de Processo (CNJ)

**Problema**: Os PDFs da Prefeitura de SP têm números de processo com **19 dígitos**, mas o formato CNJ padrão tem **20 dígitos**.

**Solução**: Adicionar "3" ao final do número.

```
PDF:  0019063752025826005  (19 dígitos)
CNJ:  00190637520258260053 (20 dígitos)
      ↓
Formatado: 0019063-75.2025.8.26.0053
```

**Por quê funciona**: O último dígito "3" completa o código do foro (0053 = Vara da Fazenda Pública de SP). A Prefeitura trunca esse dígito nos PDFs.

**Código**:
```python
def normalizar_processo(raw: str) -> str:
    if len(raw) == 19:
        raw = raw + "3"
    return f"{raw[:7]}-{raw[7:9]}.{raw[9:13]}.{raw[13]}.{raw[14:16]}.{raw[16:20]}"
```

---

### Rate Limiting ESAJ

**Descoberta**: O ESAJ TJSP tolera até 1 requisição a cada 4 segundos sem bloqueio.

**Taxa de sucesso validada**: 98.4% com intervalo de 4s.

**Limites**:
- Máximo recomendado: 200 consultas/dia
- Intervalo mínimo: 4 segundos entre requests
- Melhor horário: 6h-8h (menos tráfego)

**Código**:
```python
async def consultar_batch(rpvs: list):
    for rpv in rpvs:
        await consultar_tjsp(rpv["numero_processo"])
        await asyncio.sleep(4)  # CRÍTICO: respeitar rate limit
```

---

### Teto RPV São Paulo 2026

**Valor**: R$ 31.667,41

**Base legal**: 60 salários mínimos (SM 2026 = R$ 527,79 estimado)

**Validação**:
```python
TETO_RPV_SP_2026 = 31667.41

def validar_rpv(valor: float) -> bool:
    if valor > TETO_RPV_SP_2026:
        return False  # É precatório, não RPV
    return True
```

---

## Padrões de PDF da Prefeitura

### Estrutura do PDF de Lotes

Os PDFs seguem padrão tabular com colunas:
1. Data de Vencimento
2. Credor
3. Valor da OE
4. Complemento (contém RPV nº e processo)
5. Status (aceito/rejeitado)

### Regex de Extração

```python
PATTERN_RPV = r"""
    (\d{2}/\d{2}/\d{4})           # Data vencimento
    \s+
    ([A-ZÁÉÍÓÚÂÊÎÔÛÃÕÇ\s]+)        # Nome credor
    \s+
    ([\d.,]+)                      # Valor
    \s+
    (RPV\s*\d+/\d+.*?\d{19,20})   # Complemento com RPV e processo
    \s+
    (ACEITO|REJEITADO)             # Status
"""
```

---

## Modelo Escalonado

### Tabela Completa de Precificação

| Prazo | Adiantamento | Complemento | Total Credor | Margem |
|-------|--------------|-------------|--------------|--------|
| 0-60 dias | 50% | 40% | 90% | 10% |
| 61-90 dias | 50% | 30% | 80% | 20% |
| 91-120 dias | 50% | 20% | 70% | 30% |
| 121-180 dias | 50% | 10% | 60% | 40% |
| 180+ dias | 50% | 0% | 50% | 50% |

### Lógica de Cálculo

```python
def calcular_complemento(dias_ate_pagamento: int) -> float:
    if dias_ate_pagamento <= 60:
        return 0.40
    elif dias_ate_pagamento <= 90:
        return 0.30
    elif dias_ate_pagamento <= 120:
        return 0.20
    elif dias_ate_pagamento <= 180:
        return 0.10
    else:
        return 0.00

def calcular_proposta(valor_rpv: float, dias_desde_expedicao: int) -> dict:
    adiantamento = valor_rpv * 0.50
    prazo_estimado = estimar_prazo(dias_desde_expedicao)
    complemento_pct = calcular_complemento(prazo_estimado)

    return {
        "valor_adiantamento": adiantamento,
        "prazo_estimado": prazo_estimado,
        "complemento_provavel": valor_rpv * complemento_pct,
        "total_provavel_credor": valor_rpv * (0.50 + complemento_pct)
    }
```

---

## Meta Cloud API

### Custos por Tipo de Mensagem (Brasil)

| Tipo | Custo | Uso |
|------|-------|-----|
| Marketing | ~R$ 0,50 | Outbound proativo (templates de prospecção) |
| Utility | ~R$ 0,12 | Notificações (alerta de pagamento) |
| Service | Gratuito | Respostas dentro da janela de 24h |

### Janela de 24 Horas

- Credor manda mensagem → abre janela de 24h
- Dentro da janela: podemos enviar qualquer mensagem (gratuito)
- Fora da janela: apenas templates aprovados (pago)

### Validação de Webhook

```python
import hmac
import hashlib

def validar_assinatura_meta(payload: bytes, signature: str, secret: str) -> bool:
    expected = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)
```

---

## OpenRouter

### Modelos por Tarefa

| Tarefa | Modelo | Justificativa |
|--------|--------|---------------|
| Acolhimento/FAQ | mistral/mistral-small | Simples, barato |
| Qualificação | anthropic/claude-sonnet-4 | Tool calling confiável |
| Proposta | anthropic/claude-sonnet-4 | Precisão crítica |
| Objeções | mistral/mistral-small | Respostas padronizadas |
| Advogado | anthropic/claude-sonnet-4 | Tom profissional |
| OCR (foto) | anthropic/claude-sonnet-4 | Melhor vision |
| Transcrição | openai/whisper | Especializado |

### Fallback Automático

```python
response = client.chat.completions.create(
    model="anthropic/claude-sonnet-4-20250514",
    messages=[...],
    extra_body={
        "provider": {
            "order": ["Anthropic", "OpenAI"],
            "allow_fallbacks": True,
        }
    }
)
```

---

## ESAJ TJSP

### URL de Consulta

```
https://esaj.tjsp.jus.br/cpopg/open.do
```

### Campos do Formulário

```python
partes = {
    "numero_ano": "0019063-75.2025",  # Até o ano
    "foro": "0053"                     # Código do foro
}
```

### Movimentação de Expedição

Buscar no HTML:
```
"Ofício Requisitório-Pequeno Valor Expedido"
```

A data dessa movimentação é a **data de expedição** da RPV.

---

## Erros Comuns e Soluções

### "RPV não encontrada no banco"

**Causas possíveis**:
1. Processo ainda não foi parseado do PDF
2. Número digitado incorretamente
3. É precatório (não RPV)

**Ação**: Registrar lead como "pendente_verificacao", operador consulta ESAJ manualmente.

### "ESAJ timeout"

**Causas possíveis**:
1. ESAJ fora do ar
2. Rate limit excedido

**Ação**: Aumentar intervalo para 6s, retry no próximo batch.

### "Template rejeitado pela Meta"

**Causas possíveis**:
1. Linguagem promocional excessiva
2. Falta de opção de opt-out
3. Variáveis mal formatadas

**Ação**: Revisar guidelines da Meta, resubmeter com ajustes.

---

## Glossário

| Termo | Definição |
|-------|-----------|
| **RPV** | Requisição de Pequeno Valor — crédito judicial até 60 SM |
| **Precatório** | Crédito judicial acima de 60 SM (prazo maior) |
| **Cessão** | Transferência do direito de crédito do credor para a empresa |
| **ESAJ** | Sistema eletrônico do TJSP para consulta de processos |
| **WABA** | WhatsApp Business Account |
| **CNJ** | Conselho Nacional de Justiça (formato padrão de numeração) |
| **Expedição** | Data em que o ofício requisitório foi emitido pelo juiz |
| **Lote** | Agrupamento de pagamentos processados pela Prefeitura |
| **Complemento** | Valor adicional pago ao credor quando Prefeitura paga |

---

## Referências Externas

- [Portal RPVs Prefeitura SP](https://prefeitura.sp.gov.br/web/procuradoria_geral/w/lista-dos-processamentos-de-pagamentos-rpv)
- [ESAJ TJSP](https://esaj.tjsp.jus.br/cpopg/open.do)
- [Meta Cloud API Docs](https://developers.facebook.com/docs/whatsapp/cloud-api)
- [OpenRouter Docs](https://openrouter.ai/docs)
- [Resolução 303 CNJ (numeração única)](https://atos.cnj.jus.br/atos/detalhar/119)
