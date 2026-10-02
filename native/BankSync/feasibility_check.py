#!/usr/bin/env python3
"""Interaktiver, nicht persistierender FinTS-Machbarkeitstest.

Das Skript speichert weder Zugangsdaten noch Bankantworten. Es zeigt nur
maskierte Konten, TAN-Anforderungen und die Anzahl abgerufener Umsätze an.
"""

from __future__ import annotations

import argparse
import getpass
import importlib.metadata
import sys
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any, Callable
from urllib.parse import urlparse


@dataclass
class ProbeResult:
    label: str
    account_visible: bool = False
    supported: bool = False
    tan_required: bool = False
    transaction_count: int | None = None
    error: str | None = None


def required_input(prompt: str) -> str:
    while True:
        value = input(prompt).strip()
        if value:
            return value
        print("Die Eingabe darf nicht leer sein.")


def yes_no(prompt: str, default: bool = False) -> bool:
    suffix = " [J/n]: " if default else " [j/N]: "
    value = input(prompt + suffix).strip().lower()
    if not value:
        return default
    return value in {"j", "ja", "y", "yes"}


def mask_iban(iban: str | None) -> str:
    compact = "".join((iban or "").split())
    if len(compact) < 8:
        return "nicht angegeben"
    return f"{compact[:4]} … {compact[-4:]}"


def parse_index(prompt: str, account_count: int, optional: bool = True) -> int | None:
    while True:
        value = input(prompt).strip()
        if optional and not value:
            return None
        try:
            index = int(value) - 1
        except ValueError:
            print("Bitte eine Kontonummer aus der Liste eingeben.")
            continue
        if 0 <= index < account_count:
            return index
        print("Diese Kontonummer existiert nicht.")


def transaction_count(value: Any) -> int:
    try:
        return len(value)
    except TypeError:
        return sum(1 for _ in value)


def resolve_tan(
    client: Any,
    response: Any,
    operation: str,
    need_tan_type: type,
    tan_events: list[str],
) -> Any:
    attempts = 0
    while isinstance(response, need_tan_type):
        attempts += 1
        if attempts > 3:
            raise RuntimeError("Die Bank hat wiederholt eine TAN angefordert.")
        tan_events.append(operation)
        print(f"\nTAN-Anforderung bei: {operation}")
        challenge = getattr(response, "challenge", None)
        if challenge:
            print(f"Hinweis der Bank: {challenge}")
        if getattr(response, "decoupled", False):
            input("Freigabe in der Banking-App bestätigen, danach Enter drücken: ")
            tan = ""
        else:
            tan = getpass.getpass("TAN (Eingabe bleibt unsichtbar): ")
        response = client.send_tan(response, tan)
        tan = ""
    return response


def probe_standard_account(
    client: Any,
    account: Any,
    label: str,
    start_date: date,
    end_date: date,
    need_tan_type: type,
    unsupported_type: type,
    fints_error_type: type,
    tan_events: list[str],
) -> ProbeResult:
    result = ProbeResult(label=label, account_visible=True)
    before = len(tan_events)
    try:
        transactions = client.get_transactions(
            account,
            start_date=start_date,
            end_date=end_date,
            include_pending=True,
        )
        transactions = resolve_tan(
            client,
            transactions,
            f"Umsatzabruf {label}",
            need_tan_type,
            tan_events,
        )
        result.transaction_count = transaction_count(transactions)
        result.supported = True
    except unsupported_type:
        result.error = "Kontoumsatz-Abruf wird für dieses Konto nicht angeboten."
    except fints_error_type:
        raise
    except Exception as error:
        result.error = f"Abruf fehlgeschlagen ({type(error).__name__})."
    result.tan_required = len(tan_events) > before
    return result


def probe_credit_card(
    client: Any,
    account: Any,
    card_number: str,
    start_date: date,
    end_date: date,
    need_tan_type: type,
    unsupported_type: type,
    fints_error_type: type,
    tan_events: list[str],
) -> ProbeResult:
    result = ProbeResult(label="Mastercard")
    before = len(tan_events)
    try:
        transactions = client.get_credit_card_transactions(
            account,
            card_number,
            start_date=start_date,
            end_date=end_date,
        )
        transactions = resolve_tan(
            client,
            transactions,
            "Kreditkarten-Umsatzabruf",
            need_tan_type,
            tan_events,
        )
        result.transaction_count = transaction_count(transactions)
        result.supported = True
    except unsupported_type:
        result.error = "Die Bank bietet DKKKU für diese Verbindung nicht an."
    except fints_error_type:
        raise
    except Exception as error:
        result.error = f"Abruf fehlgeschlagen ({type(error).__name__})."
    result.tan_required = len(tan_events) > before
    card_number = ""
    return result


def print_summary(
    init_tan_required: bool,
    account_list_tan_required: bool,
    probes: list[ProbeResult],
    credit_card_operation_advertised: bool,
) -> None:
    print("\n" + "=" * 64)
    print("Ergebnis der FinTS-Machbarkeitsprüfung")
    print("=" * 64)
    print(f"TAN bei Dialogstart: {'ja' if init_tan_required else 'nein'}")
    print(f"TAN beim Kontenabruf: {'ja' if account_list_tan_required else 'nein'}")
    for result in probes:
        visible = "ja" if result.account_visible else "nein"
        supported = "ja" if result.supported else "nein"
        tan = "ja" if result.tan_required else "nein"
        count = "nicht ermittelt" if result.transaction_count is None else str(result.transaction_count)
        print(f"\n{result.label}:")
        print(f"  als SEPA-Konto sichtbar: {visible}")
        print(f"  Umsatzabruf unterstützt: {supported}")
        print(f"  TAN für Umsatzabruf: {tan}")
        print(f"  Umsätze im Testzeitraum: {count}")
        if result.error:
            print(f"  Hinweis: {result.error}")
    print(
        "\nKreditkarten-Segment DKKKU von der Bank gemeldet: "
        + ("ja" if credit_card_operation_advertised else "nein")
    )
    silent_sync_possible = not init_tan_required and not account_list_tan_required and all(
        not item.tan_required and item.error is None
        for item in probes
        if item.label in {"Girokonto", "Tagesgeldkonto"}
    )
    print(
        "Ein-Klick-Abruf ohne TAN im geprüften Ablauf: "
        + ("ja" if silent_sync_possible else "nein")
    )
    print("Es wurden keine Zugangsdaten oder Bankumsätze gespeichert.")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prüft FinTS-Konten, TAN-Anforderungen und Mastercard-Unterstützung, ohne Daten zu speichern."
    )
    parser.add_argument("--days", type=int, default=30, help="Testzeitraum in Tagen (Standard: 30)")
    args = parser.parse_args()
    if not 1 <= args.days <= 365:
        parser.error("--days muss zwischen 1 und 365 liegen")

    try:
        from fints.client import FinTS3PinTanClient, FinTSOperations, NeedTANResponse
        from fints.exceptions import (
            FinTSClientPINError,
            FinTSConnectionError,
            FinTSError,
            FinTSUnsupportedOperation,
        )
        from fints.utils import minimal_interactive_cli_bootstrap
    except ImportError:
        print(
            "python-fints fehlt. Bitte zuerst die Schritte in native/BankSync/README.md ausführen.",
            file=sys.stderr,
        )
        return 2

    try:
        version = importlib.metadata.version("fints")
    except importlib.metadata.PackageNotFoundError:
        version = "unbekannt"
    print(f"python-fints: {version}")
    print("Alle Zugangsdaten bleiben ausschließlich im Arbeitsspeicher dieses Prozesses.")

    blz = required_input("BLZ: ")
    login = required_input("FinTS-Login/Kennung: ")
    endpoint = required_input("FinTS-/HBCI-Endpunkt (https://…): ")
    product_id = required_input("Registrierte FinTS-Produkt-ID: ")
    parsed_endpoint = urlparse(endpoint)
    if parsed_endpoint.scheme != "https" or not parsed_endpoint.netloc:
        print("Der FinTS-Endpunkt muss eine vollständige HTTPS-Adresse sein.", file=sys.stderr)
        return 2
    pin = getpass.getpass("FinTS-PIN (Eingabe bleibt unsichtbar): ")
    if not pin:
        print("Die PIN darf nicht leer sein.", file=sys.stderr)
        return 2

    tan_events: list[str] = []
    probes: list[ProbeResult] = []
    init_tan_required = False
    account_list_tan_required = False
    credit_card_operation_advertised = False
    client = FinTS3PinTanClient(
        blz,
        login,
        pin,
        endpoint,
        product_id=product_id,
        product_version="0.15",
    )

    start_date = date.today() - timedelta(days=args.days)
    end_date = date.today()
    try:
        minimal_interactive_cli_bootstrap(client)
        with client:
            init_response = client.init_tan_response
            init_tan_required = isinstance(init_response, NeedTANResponse)
            if init_response is not None:
                client.init_tan_response = resolve_tan(
                    client,
                    init_response,
                    "Dialogstart",
                    NeedTANResponse,
                    tan_events,
                )

            before_accounts = len(tan_events)
            accounts = client.get_sepa_accounts()
            accounts = resolve_tan(
                client,
                accounts,
                "Kontenabruf",
                NeedTANResponse,
                tan_events,
            )
            account_list_tan_required = len(tan_events) > before_accounts
            accounts = list(accounts)

            information = client.get_information()
            bank_operations = information.get("bank", {}).get("supported_operations", {})
            credit_card_operation_advertised = bool(
                bank_operations.get(FinTSOperations.GET_CREDIT_CARD_TRANSACTIONS, False)
            )

            print("\nÜber diese FinTS-Verbindung sichtbare SEPA-Konten:")
            if not accounts:
                print("  keine")
            for index, account in enumerate(accounts, start=1):
                print(f"  {index}. {mask_iban(getattr(account, 'iban', None))}")

            if accounts:
                giro_index = parse_index("Nummer des Girokontos (leer = nicht sichtbar): ", len(accounts))
                savings_index = parse_index("Nummer des Tagesgeldkontos (leer = nicht sichtbar): ", len(accounts))
                card_index = parse_index(
                    "Nummer der Mastercard, falls sie als SEPA-Konto erscheint (leer = nein): ",
                    len(accounts),
                )

                selections: list[tuple[str, int | None]] = [
                    ("Girokonto", giro_index),
                    ("Tagesgeldkonto", savings_index),
                ]
                for label, selected_index in selections:
                    if selected_index is None:
                        probes.append(ProbeResult(label=label, error="Nicht in der SEPA-Kontenliste zugeordnet."))
                    else:
                        probes.append(
                            probe_standard_account(
                                client,
                                accounts[selected_index],
                                label,
                                start_date,
                                end_date,
                                NeedTANResponse,
                                FinTSUnsupportedOperation,
                                FinTSError,
                                tan_events,
                            )
                        )

                if card_index is not None:
                    probes.append(
                        probe_standard_account(
                            client,
                            accounts[card_index],
                            "Mastercard",
                            start_date,
                            end_date,
                            NeedTANResponse,
                            FinTSUnsupportedOperation,
                            FinTSError,
                            tan_events,
                        )
                    )
                elif credit_card_operation_advertised and yes_no(
                    "Die Bank meldet DKKKU. Separaten Kreditkartenabruf jetzt verdeckt testen?"
                ):
                    reference_index = parse_index(
                        "Nummer des zugehörigen Referenz-/Abrechnungskontos: ",
                        len(accounts),
                        optional=False,
                    )
                    card_number = getpass.getpass("Kreditkartennummer (Eingabe bleibt unsichtbar): ").replace(" ", "")
                    if reference_index is not None and card_number:
                        probes.append(
                            probe_credit_card(
                                client,
                                accounts[reference_index],
                                card_number,
                                start_date,
                                end_date,
                                NeedTANResponse,
                                FinTSUnsupportedOperation,
                                FinTSError,
                                tan_events,
                            )
                        )
                    else:
                        probes.append(
                            ProbeResult(label="Mastercard", error="Separater Kreditkartenabruf wurde nicht ausgeführt.")
                        )
                    card_number = ""
                else:
                    reason = (
                        "DKKKU wird gemeldet, der optionale Live-Test wurde aber nicht ausgeführt."
                        if credit_card_operation_advertised
                        else "Weder als SEPA-Konto sichtbar noch DKKKU von der Bank gemeldet."
                    )
                    probes.append(ProbeResult(label="Mastercard", error=reason))
            else:
                probes.extend(
                    ProbeResult(label=label, error="Keine SEPA-Konten sichtbar.")
                    for label in ("Girokonto", "Tagesgeldkonto", "Mastercard")
                )
    except FinTSClientPINError:
        print("Anmeldung abgelehnt. Bitte PIN und FinTS-Kennung prüfen.", file=sys.stderr)
        return 3
    except FinTSConnectionError:
        print("Verbindung zur Bank fehlgeschlagen. Bitte Endpunkt und Netzwerk prüfen.", file=sys.stderr)
        return 4
    except FinTSError as error:
        print(f"FinTS-Vorgang fehlgeschlagen ({type(error).__name__}).", file=sys.stderr)
        return 5
    except (EOFError, KeyboardInterrupt):
        print("\nTest abgebrochen. Es wurde nichts gespeichert.", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"Test fehlgeschlagen ({type(error).__name__}). Es wurden keine Bankdaten ausgegeben.",
            file=sys.stderr,
        )
        return 6
    finally:
        pin = ""
        login = ""

    print_summary(
        init_tan_required,
        account_list_tan_required,
        probes,
        credit_card_operation_advertised,
    )
    return 0


def safe_main() -> int:
    try:
        return main()
    except (EOFError, KeyboardInterrupt):
        print("\nTest abgebrochen. Es wurde nichts gespeichert.", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"Test fehlgeschlagen ({type(error).__name__}). Es wurden keine Bankdaten ausgegeben.",
            file=sys.stderr,
        )
        return 6


if __name__ == "__main__":
    raise SystemExit(safe_main())
