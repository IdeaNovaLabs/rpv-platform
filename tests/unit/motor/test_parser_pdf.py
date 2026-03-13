"""
Unit tests for PDF parser.
"""
import pytest
from motor.crawler.parser_pdf import (
    normalizar_processo,
    extrair_numero_rpv,
    parse_decimal,
    parse_date,
)


class TestNormalizarProcesso:
    """Tests for processo number normalization."""

    def test_normaliza_19_digitos_para_cnj(self):
        """19 digits should be padded to 20 and formatted as CNJ."""
        raw = "0019063752025826005"
        expected = "0019063-75.2025.8.26.0053"
        assert normalizar_processo(raw) == expected

    def test_normaliza_20_digitos_para_cnj(self):
        """20 digits should be formatted as CNJ without padding."""
        raw = "00190637520258260053"
        expected = "0019063-75.2025.8.26.0053"
        assert normalizar_processo(raw) == expected

    def test_ja_formatado_retorna_igual(self):
        """Already formatted CNJ should return unchanged."""
        formatted = "0019063-75.2025.8.26.0053"
        assert normalizar_processo(formatted) == formatted

    def test_remove_espacos_e_caracteres(self):
        """Should remove spaces and special characters."""
        raw = "0019063 75.2025.8.26.005"
        result = normalizar_processo(raw)
        assert "-" in result
        assert " " not in result


class TestExtrairNumeroRpv:
    """Tests for RPV number extraction."""

    def test_extrai_formato_padrao(self):
        """Should extract RPV number in standard format."""
        texto = "RPV 12345/2025 referente ao processo"
        assert extrair_numero_rpv(texto) == "12345/2025"

    def test_extrai_com_espacos(self):
        """Should extract RPV number with spaces."""
        texto = "RPV  12345 / 2025 referente"
        result = extrair_numero_rpv(texto)
        assert "12345" in result
        assert "2025" in result

    def test_retorna_none_sem_rpv(self):
        """Should return None when no RPV found."""
        texto = "Texto sem número de RPV"
        assert extrair_numero_rpv(texto) is None


class TestParseDecimal:
    """Tests for decimal parsing."""

    def test_parse_formato_brasileiro(self):
        """Should parse Brazilian format (dot for thousands, comma for decimal)."""
        assert parse_decimal("25.000,50") == 25000.50
        assert parse_decimal("1.234.567,89") == 1234567.89

    def test_parse_formato_simples(self):
        """Should parse simple numbers."""
        assert parse_decimal("25000") == 25000.00
        assert parse_decimal("25000,50") == 25000.50

    def test_parse_com_rs(self):
        """Should parse with R$ prefix."""
        assert parse_decimal("R$ 25.000,00") == 25000.00
        assert parse_decimal("R$25.000,00") == 25000.00


class TestParseDate:
    """Tests for date parsing."""

    def test_parse_formato_brasileiro(self):
        """Should parse dd/mm/yyyy format."""
        from datetime import date
        assert parse_date("15/10/2024") == date(2024, 10, 15)
        assert parse_date("01/01/2025") == date(2025, 1, 1)

    def test_parse_formato_iso(self):
        """Should parse ISO format yyyy-mm-dd."""
        from datetime import date
        assert parse_date("2024-10-15") == date(2024, 10, 15)

    def test_retorna_none_invalido(self):
        """Should return None for invalid dates."""
        assert parse_date("invalid") is None
        assert parse_date("") is None
