# Esempio completo -- Schema ER esteso (v1.2)

## BIM · Produzione · Qualità · SAL · Computo

Questo documento aggiorna **l'esempio di popolamento** dello schema
Entità‑Relazione alla luce dello **scenario esteso** discusso: -
produzione (MES / OPC UA) - oggetti prodotti (casseri, prefabbricati,
lotti) - qualità (ricette, prove, non conformità) - avanzamento (SAL) e
valorizzazione economica.

Il modello separa chiaramente: - **progetto** (BIM) - **produzione**
(eventi e ordini) - **uso in cantiere** (attività) - **certificazione**
(SAL) - **qualità** (prove e NCR)

------------------------------------------------------------------------

## 1. Scenario di riferimento

-   Opera: Edificio residenziale
-   Fase: Strutture
-   Lavorazione: Getto calcestruzzo platea
-   Oggetti prodotti: Cassero platea; Lotto CLS
-   Fonti: BIM (IFC/JSON), Excel lavorazioni, OPC UA impianto CLS,
    Computo metrico

------------------------------------------------------------------------

## 2. BIM (Progetto)

### 2.1 BIM_MODEL

  ModelId   ProjectCode   Name              AuthoringTool   IFCVersion
  --------- ------------- ----------------- --------------- ------------
  M001      0549-IDG      PPDL -- Levante   Revit           IFC4

### 2.2 BIM_ELEMENT

  -----------------------------------------------------------------------------------------
  ElementId   ModelId    IfcGuid              Category     Family     TypeName   Level
  ----------- ---------- -------------------- ------------ ---------- ---------- ----------
  E_FND_001   M001       2L\$Pj4Y6P8Q9HcZpA   Fondazioni   Plinti     Plinto CLS -1

  -----------------------------------------------------------------------------------------

### 2.3 BIM_QUANTITY

  QuantityId   ElementId   QuantityType   Value   UM
  ------------ ----------- -------------- ------- ----
  Q001         E_FND_001   Volume         3.85    m³
  Q002         E_FND_001   Area           6.20    m²

> Il BIM fornisce **quantità geometriche**, non costi né tempi.

------------------------------------------------------------------------

## 3. Processo (Cosa si fa)

### 3.1 CONSTRUCTION_PHASE

  PhaseId   Code   Name        Order
  --------- ------ ----------- -------
  P01       STR    Strutture   1

### 3.2 WORK_ACTIVITY

  ActivityId   PhaseId   Code      Name
  ------------ --------- --------- ------------------------
  A_CLS_01     P01       CLS-GET   Getto calcestruzzo
  A_CLS_02     P01       CLS-POM   Pompaggio calcestruzzo

### 3.3 MEASUREMENT_RULE

  RuleId   ActivityId   QuantityType   UM   Formula
  -------- ------------ -------------- ---- -----------------------
  R1       A_CLS_01     Volume         m³   Σ BIM_QUANTITY.Volume
  R2       A_CLS_02     Volume         m³   Σ BIM_QUANTITY.Volume

### 3.4 TIME_PROFILE (stima tecnica)

  TimeProfileId   ActivityId   UM   Productivity   TimePerUnit
  --------------- ------------ ---- -------------- -------------
  T1              A_CLS_01     m³   25             0.04

------------------------------------------------------------------------

## 4. Produzione (Cosa si produce)

### 4.1 PRODUCED_ITEM

  ProducedItemId   ItemCode   Description          ItemType      Reusable
  ---------------- ---------- -------------------- ------------- ----------
  PI_CAS_01        CAS-PLT    Cassero platea       Component     Yes
  PI_CLS_01        LOT-CLS    Lotto calcestruzzo   MaterialLot   No

### 4.2 PRODUCTION_ORDER (distinta di commessa)

  -------------------------------------------------------------------------------------------
  ProductionOrderId   ProducedItemId   OrderCode   PlannedStart   PlannedEnd   Status
  ------------------- ---------------- ----------- -------------- ------------ --------------
  PO001               PI_CAS_01        PO-CAS-01   2026-02-08     2026-02-09   Closed

  PO002               PI_CLS_01        PO-CLS-01   2026-02-10     2026-02-10   InProduction
  -------------------------------------------------------------------------------------------

### 4.3 PRODUCTION_ORDER_ITEM

  POItemId   ProductionOrderId   ItemType    Description           Qty   UM
  ---------- ------------------- ----------- --------------------- ----- ----
  POI1       PO001               Component   Pannelli cassero      40    pz
  POI2       PO001               Resource    Squadra carpentieri   2     gg

------------------------------------------------------------------------

## 5. Uso in cantiere

### 5.1 ACTIVITY_ITEM_USAGE

  UsageId   ProducedItemId   ActivityId   QtyUsed   UM    Role
  --------- ---------------- ------------ --------- ----- ----------
  U1        PI_CAS_01        A_CLS_01     1         set   Formwork
  U2        PI_CLS_01        A_CLS_01     3.85      m³    Material

------------------------------------------------------------------------

## 6. Esecuzione e Avanzamento

### 6.1 WORK_PROGRESS

  WorkProgressId   ActivityId   Start              End                Certified
  ---------------- ------------ ------------------ ------------------ -----------
  WP001            A_CLS_01     2026-02-10 08:00   2026-02-10 18:00   Yes

### 6.2 ELEMENT_PROGRESS

  ElementProgressId   WorkProgressId   ElementId   QtyDone   UM
  ------------------- ---------------- ----------- --------- ----
  EP001               WP001            E_FND_001   3.85      m³

------------------------------------------------------------------------

## 7. Produzione reale (eventi)

### 7.1 PRODUCTION_RECORD

  ----------------------------------------------------------------------------------------------------
  ProductionRecordId   ElementProgressId   ProducedQty   UM       Start    End      Source   Quality
  -------------------- ------------------- ------------- -------- -------- -------- -------- ---------
  PR001                EP001               1.40          m³       08:42    09:10    OPCUA    OK

  PR002                EP001               2.45          m³       10:30    12:00    OPCUA    OK
  ----------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

## 8. Tecnologia (come si produce)

### 8.1 MIX_RECIPE

  RecipeId   Code      Class    Version   Status
  ---------- --------- -------- --------- ----------
  R_C25_01   CLS-C25   C25/30   v1        Approved

### 8.2 MIX_RECIPE_COMPONENT

  RecipeId   Material   QtyPerUnit   UM
  ---------- ---------- ------------ -------
  R_C25_01   Cemento    320          kg/m³
  R_C25_01   Sabbia     780          kg/m³
  R_C25_01   Ghiaia     1050         kg/m³
  R_C25_01   Acqua      180          l/m³

------------------------------------------------------------------------

## 9. Qualità

### 9.1 QUALITY_TEST_CERTIFICATE

  -------------------------------------------------------------------------------------------
  CertificateId   WorkProgressId   RecipeId   Test           Result     Unit       Outcome
  --------------- ---------------- ---------- -------------- ---------- ---------- ----------
  QC001           WP001            R_C25_01   Compressione   32.5       MPa        PASS
                                              28gg                                 

  -------------------------------------------------------------------------------------------

### 9.2 NON_CONFORMITY

  NCRId   WorkProgressId   Severity   Description        Status
  ------- ---------------- ---------- ------------------ --------
  NC001   WP001            Minor      Slump borderline   Closed

------------------------------------------------------------------------

## 10. Computo e Valorizzazione

### 10.1 BOQ

  BoqId   Code       Description
  ------- ---------- -------------------------
  B001    CME-0549   Computo metrico Levante

### 10.2 BOQ_ITEM

  BoqItemId   BoqId   Code      Description           UM   UnitPrice
  ----------- ------- --------- --------------------- ---- -----------
  C001        B001    CLS-C25   Calcestruzzo C25/30   m³   145.00

### 10.3 BOQ_ACTIVITY

  BoqActivityId   BoqItemId   ActivityId   Coeff
  --------------- ----------- ------------ -------
  BA001           C001        A_CLS_01     1.0

**Valorizzazione**: `3.85 m³ × 145 € = 558,25 €`

------------------------------------------------------------------------

## 11. Flusso logico finale

    BIM → Quantità
    Produzione → Eventi
    Uso → Attività
    Esecuzione → WORK_PROGRESS
    Qualità → Certificati / NCR
    SAL → ELEMENT_PROGRESS
    Valore → Computo

------------------------------------------------------------------------

## 12. Regole d'oro

-   Si **producono oggetti**, le attività li **usano**
-   La produzione **supporta**, il SAL **certifica**
-   La qualità **valida un'esecuzione nel tempo**
-   Il computo **valorizza solo ciò che è certificato**
