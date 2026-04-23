"""
domain/parser.py — Logica pura di parsing del JSON Revit.

Questo modulo NON dipende da nessuna libreria cloud. Riceve un dict Python
(il JSON parsato) e restituisce oggetti domain (BimModel, BimElement, BimQuantity).

Regole di filtro per il Ponte sul Po di Levante (83 elementi target):
  - Structural Foundations: tutte le 48 fondazioni (plinti, platee)
  - Structural Columns: tutte le 2 colonne (Torri)
  - Structural Connections: solo famiglia IDG_CN_SU_STL_SlidingBearing (8 appoggi)
  - Structural Framing: solo famiglie IDG impalcato e stralli (25 elementi)
  - ESCLUSE sempre: Model Groups, Specialty Equipment

Struttura JSON di input (plugin Orienta Trium):
  {
    "FileName": "0549-IDG-PPDL-L00-A-INF-3D-A",
    "ExportGuid": "...",
    "DateTime": "...",
    "Elements": {
      "Structural Foundations": [ {elem1}, {elem2}, ... ],
      "Structural Framing": [ ... ],
      ...
    }
  }

Struttura di un singolo elemento:
  {
    "IfcGuid": "2L$Pj4Y6P8Q9H...",
    "FamilyName": "IDG_SF_STL_Segment1",     ← campo radice, NON parametro
    "SymbolName": "Segment1_HEA300",
    "Category": "Structural Framing",
    "Level": "-1",
    "InstanceParameters": [{"Name": "Length", "Value": 12.5, "UM": "m"}, ...],
    "SymbolParameters": [{"Name": "Volume", "Value": 0.45, "UM": "m³"}, ...]
  }
"""

import hashlib
import logging
from typing import Optional

from domain.models import BimModel, BimElement, BimQuantity

logger = logging.getLogger(__name__)


# =============================================================================
# Regole di filtro per il Ponte sul Po di Levante
# =============================================================================

# Categorie incluse nel filtro.
# None = tutte le famiglie di quella categoria sono accettate.
# set = solo le famiglie in questo set vengono accettate.
FILTER_RULES: dict[str, Optional[set[str]]] = {
    "Structural Foundations": None,  # Tutti i 48 plinti/fondazioni
    "Structural Columns":     None,  # Tutte le 2 Torri
    "Structural Connections": {      # Solo gli 8 appoggi scorrevoli
        "IDG_CN_SU_STL_SlidingBearing"
    },
    "Structural Framing": {          # Solo impalcati e stralli (25 totale)
        "IDG_SF_STL_Segment1",
        "IDG_SF_STL_Segment2",
        "IDG_SF_STL_Segment3",
        "IDG_SF_STL_Segment4",
        "IDG_SF_STL_Segment5",
        "IDG_SF_STL_Segment6",
        "IDG_SF_STL_Segment7",
        "IDG_SF_STL_Segment8",
        "IDG_SF_STL_Segment9",
        "IDG_CN_CB_0.11m_STL",       # Strallo diametro 0.11m
        "IDG_CN_CB_0.20m_STL",       # Strallo diametro 0.20m
    },
}

# Categorie completamente escluse (anche se in FILTER_RULES per errore)
EXCLUDED_CATEGORIES: set[str] = {"Model Groups", "Specialty Equipment"}

# Quantità da estrarre, in ordine di priorità per tipo.
# Se un elemento ha "CutLength", viene preferita a "Length" (lunghezza reale vs profilo grezzo).
QUANTITY_PRIORITY: list[str] = ["CutLength", "Length"]

# Tutte le quantità geometriche da estrarre (oltre alla priorità lunghezza)
QUANTITY_NAMES: set[str] = {
    "Volume", "Area", "CutLength", "Length", "Weight",
    "Cut Length", "Cut Area",  # varianti con spazio (alcune versioni plugin)
}


# =============================================================================
# Funzione principale di parsing
# =============================================================================

def parse_bim_json(
    json_data: dict,
    tenant_id: str,
    gcs_path: str,
) -> tuple[BimModel, list[BimElement], list[BimQuantity]]:
    """
    Punto di ingresso del parser. Riceve il JSON grezzo di Orienta Trium
    e restituisce gli oggetti domain pronti per il salvataggio nel DB.

    Args:
        json_data:  dict Python con il contenuto del file JSON Revit
        tenant_id:  UUID della company a cui appartiene questo modello
        gcs_path:   percorso GCS del file (es. "gs://bucket/uploads/file.json")

    Returns:
        (bim_model, elementi_filtrati, quantità_degli_elementi)
    """
    file_name = json_data.get("FileName", "unknown")
    project_code = _extract_project_code(json_data)

    logger.info("Inizio parsing: file=%s project=%s tenant=%s", file_name, project_code, tenant_id)

    # ─── Costruisci BimModel ─────────────────────────────────────────────────
    bim_model = BimModel(
        tenant_id=tenant_id,
        project_code=project_code,
        file_name=file_name,
        source_gcs_path=gcs_path,
        export_guid=json_data.get("ExportGuid"),
        json_version=json_data.get("VersionJsonFile"),
        exported_at=json_data.get("DateTime"),
    )

    # ─── Filtra elementi ─────────────────────────────────────────────────────
    elements_raw = json_data.get("Elements", {})
    bim_model.total_elements_raw = _count_raw_elements(elements_raw)

    elements: list[BimElement] = []
    quantities: list[BimQuantity] = []

    for category, element_list in elements_raw.items():
        # Salta le categorie escluse sempre
        if category in EXCLUDED_CATEGORIES:
            logger.debug("Categoria esclusa: %s (%d elementi)", category, len(element_list))
            continue

        # Salta le categorie non nel filtro
        if category not in FILTER_RULES:
            logger.debug("Categoria non nel filtro: %s (%d elementi)", category, len(element_list))
            continue

        # Regola famiglia per questa categoria (None = tutte, set = whitelist)
        family_whitelist = FILTER_RULES[category]

        for elem_raw in element_list:
            family = elem_raw.get("FamilyName", "")

            # Se c'è una whitelist famiglie, controlla
            if family_whitelist is not None and family not in family_whitelist:
                continue

            bim_element, bim_quantities = _parse_element(elem_raw, category, family, tenant_id)
            elements.append(bim_element)
            quantities.extend(bim_quantities)

    bim_model.total_elements_imported = len(elements)
    bim_model.import_status = "completed"

    logger.info(
        "Parsing completato: %d/%d elementi importati, %d quantità",
        bim_model.total_elements_imported,
        bim_model.total_elements_raw,
        len(quantities),
    )

    return bim_model, elements, quantities


# =============================================================================
# Funzioni di supporto (private)
# =============================================================================

def _extract_project_code(json_data: dict) -> str:
    """
    Estrae il codice progetto da ProjectInformation.
    Il campo "Project_Number_" contiene il codice (es. "0549-IDG").
    Fallback: usa i primi 50 caratteri di FileName.
    """
    project_info = json_data.get("ProjectInformation", [])
    for item in project_info:
        if item.get("Name") in ("Project_Number_", "ProjectNumber", "Project Number"):
            val = item.get("Value", "").strip()
            if val:
                return val[:50]
    # Fallback
    file_name = json_data.get("FileName", "unknown")
    return file_name[:50]


def _count_raw_elements(elements_raw: dict) -> int:
    """Conta il totale elementi nel JSON prima del filtro."""
    return sum(len(v) for v in elements_raw.values() if isinstance(v, list))


def _parse_element(
    elem_raw: dict,
    category: str,
    family: str,
    tenant_id: str,
) -> tuple[BimElement, list[BimQuantity]]:
    """
    Trasforma un elemento grezzo del JSON in BimElement + lista di BimQuantity.

    Logica quantità:
      1. Raccoglie tutti i parametri da InstanceParameters e SymbolParameters
      2. Per la lunghezza: usa CutLength se presente, altrimenti Length
      3. Estrae Volume, Area, Weight se presenti
    """
    ifc_guid = elem_raw.get("IfcGuid", "")

    # Unisce i parametri di istanza e di simbolo in un unico dict
    # {NomeParametro: {"Value": valore, "UM": unità}}
    params: dict = {}
    for param in elem_raw.get("InstanceParameters", []):
        name = param.get("Name", "")
        if name:
            params[name] = {"Value": param.get("Value"), "UM": param.get("UM", "")}
    for param in elem_raw.get("SymbolParameters", []):
        name = param.get("Name", "")
        if name and name not in params:  # InstanceParameters ha priorità
            params[name] = {"Value": param.get("Value"), "UM": param.get("UM", "")}

    bim_element = BimElement(
        tenant_id=tenant_id,
        ifc_guid=ifc_guid,
        category=category,
        family=family,
        type_name=elem_raw.get("SymbolName"),
        level=elem_raw.get("Level"),
        parameters=params,
    )

    quantities = _extract_quantities(params, ifc_guid, tenant_id)

    return bim_element, quantities


def _extract_quantities(
    params: dict,
    ifc_guid: str,
    tenant_id: str,
) -> list[BimQuantity]:
    """
    Estrae le quantità geometriche dai parametri dell'elemento.

    Logica CutLength vs Length:
      Molti elementi (travi, stralli) hanno sia "Length" (profilo grezzo)
      che "CutLength" (lunghezza reale dopo taglio a misura).
      Usiamo CutLength perché è la quantità fisica reale.
      Se CutLength non c'è, usiamo Length come fallback.
    """
    quantities: list[BimQuantity] = []

    # ─── Gestione lunghezza (CutLength > Length) ─────────────────────────────
    length_added = False
    for qty_name in QUANTITY_PRIORITY:
        if qty_name in params:
            raw = params[qty_name]
            val = _to_float(raw.get("Value"))
            if val is not None and val > 0:
                quantities.append(BimQuantity(
                    tenant_id=tenant_id,
                    quantity_type=qty_name,
                    value=val,
                    unit_of_measure=raw.get("UM", "m"),
                    _ifc_guid=ifc_guid,
                ))
                length_added = True
                break  # Trovata la migliore, non aggiungere l'altra

    # ─── Altre quantità geometriche ──────────────────────────────────────────
    for qty_name in ("Volume", "Area", "Weight"):
        if qty_name in params:
            raw = params[qty_name]
            val = _to_float(raw.get("Value"))
            if val is not None and val > 0:
                quantities.append(BimQuantity(
                    tenant_id=tenant_id,
                    quantity_type=qty_name,
                    value=val,
                    unit_of_measure=raw.get("UM", ""),
                    _ifc_guid=ifc_guid,
                ))

    if not quantities:
        logger.warning("Nessuna quantità trovata per elemento %s", ifc_guid)

    return quantities


def _to_float(value) -> Optional[float]:
    """Converte un valore (stringa, int, float) in float. Restituisce None se non convertibile."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def compute_file_hash(file_bytes: bytes) -> str:
    """Calcola SHA-256 di un file (usato per deduplicazione e integrità)."""
    return hashlib.sha256(file_bytes).hexdigest()
