"""
Unit tests for proposta calculation (escalonado model).
"""
import pytest
from motor.models.proposta import (
    calcular_complemento,
    calcular_proposta,
    TETO_RPV_SP_2026,
)


class TestCalcularComplemento:
    """Tests for complement percentage calculation."""

    def test_prazo_ate_60_dias(self):
        """0-60 days: 40% complement."""
        assert calcular_complemento(0) == 0.40
        assert calcular_complemento(30) == 0.40
        assert calcular_complemento(60) == 0.40

    def test_prazo_61_a_90_dias(self):
        """61-90 days: 30% complement."""
        assert calcular_complemento(61) == 0.30
        assert calcular_complemento(75) == 0.30
        assert calcular_complemento(90) == 0.30

    def test_prazo_91_a_120_dias(self):
        """91-120 days: 20% complement."""
        assert calcular_complemento(91) == 0.20
        assert calcular_complemento(105) == 0.20
        assert calcular_complemento(120) == 0.20

    def test_prazo_121_a_180_dias(self):
        """121-180 days: 10% complement."""
        assert calcular_complemento(121) == 0.10
        assert calcular_complemento(150) == 0.10
        assert calcular_complemento(180) == 0.10

    def test_prazo_acima_180_dias(self):
        """180+ days: 0% complement."""
        assert calcular_complemento(181) == 0.00
        assert calcular_complemento(365) == 0.00
        assert calcular_complemento(1000) == 0.00


class TestCalcularProposta:
    """Tests for full proposta calculation."""

    def test_proposta_basica(self):
        """Basic proposta calculation."""
        resultado = calcular_proposta(valor_rpv=20000.00, dias_desde_expedicao=90)

        assert resultado["valor_adiantamento"] == 10000.00  # 50%
        assert resultado["valor_rpv"] == 20000.00
        assert "prazo_estimado" in resultado
        assert "complemento_provavel" in resultado
        assert "total_provavel_credor" in resultado

    def test_adiantamento_sempre_50_porcento(self):
        """Adiantamento should always be 50%."""
        for valor in [10000, 20000, 30000]:
            resultado = calcular_proposta(valor_rpv=valor, dias_desde_expedicao=60)
            assert resultado["valor_adiantamento"] == valor * 0.50

    def test_total_credor_maximo_90_porcento(self):
        """Maximum total for creditor is 90% (fast payment)."""
        resultado = calcular_proposta(valor_rpv=20000.00, dias_desde_expedicao=30)
        # With 30 days elapsed, expecting quick payment
        assert resultado["total_provavel_credor"] <= 20000.00 * 0.90

    def test_total_credor_minimo_50_porcento(self):
        """Minimum total for creditor is 50% (slow payment)."""
        resultado = calcular_proposta(valor_rpv=20000.00, dias_desde_expedicao=300)
        assert resultado["total_provavel_credor"] >= 20000.00 * 0.50

    def test_tabela_complemento_presente(self):
        """Proposta should include complement table."""
        resultado = calcular_proposta(valor_rpv=20000.00, dias_desde_expedicao=60)

        assert "tabela_complemento" in resultado
        assert len(resultado["tabela_complemento"]) == 5  # 5 faixas

    def test_rejeita_valor_acima_teto(self):
        """Should reject values above RPV ceiling."""
        with pytest.raises(ValueError, match="teto"):
            calcular_proposta(valor_rpv=40000.00, dias_desde_expedicao=60)

    def test_aceita_valor_no_teto(self):
        """Should accept values exactly at the ceiling."""
        resultado = calcular_proposta(
            valor_rpv=TETO_RPV_SP_2026,
            dias_desde_expedicao=60
        )
        assert resultado["valor_rpv"] == TETO_RPV_SP_2026


class TestTetoRpv:
    """Tests for RPV ceiling constant."""

    def test_teto_sp_2026(self):
        """SP ceiling for 2026 should be R$ 31,667.41."""
        assert TETO_RPV_SP_2026 == 31667.41
