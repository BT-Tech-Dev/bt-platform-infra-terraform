"""
domain/models.py — Modelli dati puri del dominio BIM.

Queste dataclass rappresentano le entità del dominio senza dipendere da
nessuna libreria cloud (GCS, PostgreSQL, FastAPI). Sono "oggetti di valore"
che il parser produce e che gli adapter trasformano in operazioni DB/GCS.

Architettura Esagonale (Ports & Adapters):
  ┌─────────────────────────────────────────────┐
  │  Domain (questo file + parser.py)            │
  │  - Conosce solo Python puro e le regole      │
  │    di business (filtri BIM, estrazione qty)  │
  │  - NON dipende da GCS, PostgreSQL, FastAPI   │
  └─────────────────────────────────────────────┘
"""

from dataclasses import dataclass, field
from typing import Optional


# =============================================================================
# Tabelle schema bim: dati geometrici dal plugin Revit
# =============================================================================

@dataclass
class BimModel:
    """
    Rappresenta un export JSON dal plugin Revit (Orienta Trium).
    Un BimModel = una campagna di export = un file JSON caricato su GCS.
    """
    tenant_id: str                          # UUID della company (tenant)
    project_code: str                       # Es: "0549-IDG"
    file_name: str                          # Nome file senza estensione
    source_gcs_path: str                    # Path completo GCS (per tracciabilità)
    export_guid: Optional[str] = None       # GUID univoco dell'export (da plugin)
    authoring_tool: str = "Revit"
    ifc_version: Optional[str] = None      # Es: "IFC2x3"
    json_version: Optional[str] = None     # Versione del formato JSON
    exported_at: Optional[str] = None      # Datetime dell'export (stringa ISO)
    source_file_hash: Optional[str] = None # SHA-256 del file JSON
    total_elements_raw: int = 0            # Elementi nel JSON prima del filtro
    total_elements_imported: int = 0       # Elementi dopo il filtro (es. 83)
    import_status: str = "processing"      # Sarà aggiornato a "completed" o "failed"
    id: Optional[str] = None              # UUID assegnato dal DB dopo l'insert


@dataclass
class BimElement:
    """
    Un singolo elemento strutturale filtrato dal modello BIM.
    Corrisponde a una riga in bim.bim_element.

    Nota sul campo "family":
        Nel JSON di Orienta Trium, FamilyName è un campo radice dell'elemento,
        NON un parametro (cioè NON è in InstanceParameters o SymbolParameters).
        Questo è importante: il filtro avviene su questo campo, non sui parametri.
    """
    tenant_id: str
    ifc_guid: str       # GUID IFC univoco, stabile tra export (es. "2L$Pj4Y6P8Q9H...")
    category: str       # Categoria Revit (es. "Structural Foundations")
    family: str         # Nome famiglia Revit (es. "IDG_SF_STL_Segment1")
    model_id: Optional[str] = None   # Assegnato dopo il salvataggio del BimModel
    type_name: Optional[str] = None  # SymbolName nel JSON (es. "Fondazione_500x500")
    level: Optional[str] = None      # Livello architettonico (es. "-1", "Piano Terra")
    parameters: dict = field(default_factory=dict)  # Tutti i parametri Revit come dict
    id: Optional[str] = None         # UUID assegnato dal DB


@dataclass
class BimQuantity:
    """
    Una quantità geometrica di un elemento BIM (volume, lunghezza, area, ecc.).
    Corrisponde a una riga in bim.bim_quantity.

    Priorità nell'estrazione:
        "CutLength" ha priorità su "Length" perché per travi inclinate e diagonali
        CutLength è la lunghezza reale dell'elemento (tagliato a misura), mentre
        Length è la lunghezza del profilo grezzo prima del taglio.
    """
    tenant_id: str
    quantity_type: str     # Es: "Volume", "CutLength", "Area", "Weight"
    value: float
    unit_of_measure: str   # Es: "m³", "m", "m²", "kg"
    element_id: Optional[str] = None   # Assegnato dopo il salvataggio del BimElement
    # Riferimento all'ifc_guid del padre (usato internamente prima di avere l'element_id)
    _ifc_guid: Optional[str] = field(default=None, repr=False)


# =============================================================================
# Tabelle schema bim: WBS (Work Breakdown Structure)
# Definite qui come dataclass per completezza del domain model.
# Il parser bim-parser-v1 NON crea WBS — sono create da MS-02/MS-03.
# Incluse perché fanno parte del dominio bim in v3.0.
# =============================================================================

@dataclass
class ConstructionPhase:
    """Macro-fase costruttiva (es. 'Strutture', 'Finiture'). Schema: bim."""
    tenant_id: str
    code: str           # Es: "STR", "FIN"
    name: str           # Es: "Strutture in acciaio"
    sequence_order: int = 1
    id: Optional[str] = None


@dataclass
class WorkActivity:
    """Lavorazione specifica (es. 'Getto CLS platea'). Schema: bim."""
    tenant_id: str
    phase_id: str       # FK a bim.construction_phase
    code: str           # Es: "CLS-GET"
    name: str
    description: Optional[str] = None
    unit_of_measure: Optional[str] = None
    id: Optional[str] = None


@dataclass
class ElementActivity:
    """Link elemento BIM ↔ lavorazione con peso SAL. Schema: bim."""
    tenant_id: str
    element_id: str     # FK a bim.bim_element
    activity_id: str    # FK a bim.work_activity
    weight_factor: float = 1.0   # 0.0-1.0: contributo % al SAL
    id: Optional[str] = None
